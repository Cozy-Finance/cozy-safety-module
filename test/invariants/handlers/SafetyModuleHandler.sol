// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {console2} from "forge-std/console2.sol";
import {Vm} from "forge-std/Vm.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Manager} from "../../../src/Manager.sol";
import {SafetyModule} from "../../../src/SafetyModule.sol";
import {SafetyModuleState, TriggerState} from "../../../src/lib/SafetyModuleStates.sol";
import {ReservePool, RewardPool} from "../../../src/lib/structs/Pools.sol";
import {RedemptionPreview} from "../../../src/lib/structs/Redemptions.sol";
import {PreviewClaimableRewards, PreviewClaimableRewardsData} from "../../../src/lib/structs/Rewards.sol";
import {Slash} from "../../../src/lib/structs/Slash.sol";
import {Trigger} from "../../../src/lib/structs/Trigger.sol";
import {IERC20} from "../../../src/interfaces/IERC20.sol";
import {ISafetyModule} from "../../../src/interfaces/ISafetyModule.sol";
import {ITrigger} from "../../../src/interfaces/ITrigger.sol";
import {AddressSet, AddressSetLib} from "../utils/AddressSet.sol";
import {MockTrigger} from "../../utils/MockTrigger.sol";
import {TestBase} from "../../utils/TestBase.sol";

contract SafetyModuleHandler is TestBase {
  using FixedPointMathLib for uint256;
  using AddressSetLib for AddressSet;

  uint64 constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;

  address pauser;
  address owner;

  Manager public manager;
  ISafetyModule public safetyModule;

  IERC20 public asset;

  uint256 numReservePools;
  uint256 numRewardPools;

  ITrigger[] public triggers;
  ITrigger[] public triggeredTriggers; // Triggers that have triggered the safety module.

  mapping(string => uint256) public calls;
  mapping(string => uint256) public invalidCalls;

  address internal currentActor;

  AddressSet internal actors;

  AddressSet internal actorsWithReserveDeposits;

  AddressSet internal actorsWithRewardDeposits;

  AddressSet internal actorsWithStakes;

  uint16 public currentReservePoolId;

  uint16 public currentRewardPoolId;

  address public currentPayoutHandler;

  ITrigger public currentTrigger;

  uint256 public currentTimestamp;

  uint256 totalTimeAdvanced;

  uint256 public totalCalls;

  // -------- Ghost Variables --------

  mapping(uint16 reservePoolId_ => GhostReservePool reservePool_) public ghost_reservePoolCumulative;
  mapping(uint16 rewardPoolId_ => GhostRewardPool) public ghost_rewardPoolCumulative;

  mapping(address actor_ => mapping(uint16 reservePoolId_ => uint256 actorStakeCount_)) public ghost_actorStakeCount;
  mapping(address actor_ => mapping(uint16 reservePoolId_ => uint256 actorReserveDepositCount_)) public
    ghost_actorReserveDepositCount;
  mapping(address actor_ => mapping(uint16 rewardPoolId_ => uint256 actorRewardDepositCount_)) public
    ghost_actorRewardDepositCount;

  GhostRedemption[] public ghost_redemptions;

  mapping(IERC20 asset_ => uint256 amount_) public ghost_rewardsClaimed;

  // -------- Structs --------

  struct GhostReservePool {
    uint256 totalAssetAmount;
    uint256 depositAssetAmount;
    uint256 depositSharesAmount;
    uint256 stakeAssetAmount;
    uint256 stakeSharesAmount;
    uint256 depositRedeemAssetAmount;
    uint256 depositRedeemSharesAmount;
    uint256 unstakeAssetAmount;
    uint256 unstakeSharesAmount;
  }

  struct GhostRewardPool {
    uint256 totalAssetAmount;
    uint256 depositSharesAmount;
    uint256 redeemSharesAmount;
    uint256 redeemAssetAmount;
  }

  struct GhostRedemption {
    uint64 id;
    uint256 assetAmount;
    uint256 receiptTokenAmount;
    bool completed;
  }

  // -------- Constructor --------

  constructor(
    Manager manager_,
    ISafetyModule safetyModule_,
    IERC20 asset_,
    uint256 numReservePools_,
    uint256 numRewardPools_,
    ITrigger[] memory triggers_,
    uint256 currentTimestamp_
  ) {
    safetyModule = safetyModule_;
    manager = manager_;
    numReservePools = numReservePools_;
    numRewardPools = numRewardPools_;
    asset = asset_;
    pauser = safetyModule_.pauser();
    owner = safetyModule_.owner();
    currentTimestamp = currentTimestamp_;
    triggers = triggers_;

    vm.label(address(safetyModule), "safetyModule");
  }

  // --------------------------------------
  // -------- Functions under test --------
  // --------------------------------------

  function depositReserveAssets(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithReserveDeposits
    useValidReservePoolId(seed_)
    countCall("depositReserveAssets")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositReserveAssets(assetAmount_, "depositReserveAssets");

    return currentActor;
  }

  function depositReserveAssetsWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidReservePoolId(seed_)
    countCall("depositReserveAssetsWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositReserveAssets(assetAmount_, "depositReserveAssetsWithExistingActor");

    return currentActor;
  }

  function depositReserveAssetsWithoutTransfer(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithReserveDeposits
    useValidReservePoolId(seed_)
    countCall("depositReserveAssetsWithoutTransfer")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositReserveAssetsWithoutTransfer(assetAmount_, "depositReserveAssetsWithoutTransfer");

    return currentActor;
  }

  function depositReserveAssetsWithoutTransferWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidReservePoolId(seed_)
    countCall("depositReserveAssetsWithoutTransferWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositReserveAssetsWithoutTransfer(assetAmount_, "depositReserveAssetsWithoutTransferWithExistingActor");

    return currentActor;
  }

  function depositRewardAssets(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithRewardDeposits
    useValidRewardPoolId(seed_)
    countCall("depositRewardAssets")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositRewardAssets(assetAmount_, "depositRewardAssets");

    return currentActor;
  }

  function depositRewardAssetsWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidRewardPoolId(seed_)
    countCall("depositRewardAssetsWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositRewardAssets(assetAmount_, "depositRewardAssetsWithExistingActor");

    return currentActor;
  }

  function depositRewardAssetsWithoutTransfer(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithRewardDeposits
    useValidRewardPoolId(seed_)
    countCall("depositRewardAssetsWithoutTransfer")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositRewardAssetsWithoutTransfer(assetAmount_, "depositRewardAssetsWithoutTransfer");

    return currentActor;
  }

  function depositRewardAssetsWithoutTransferWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidRewardPoolId(seed_)
    countCall("depositRewardAssetsWithoutTransferWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _depositRewardAssetsWithoutTransfer(assetAmount_, "depositRewardAssetsWithoutTransferWithExistingActor");

    return currentActor;
  }

  function stake(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithStakes
    useValidReservePoolId(seed_)
    countCall("stake")
    advanceTime(seed_)
    returns (address actor_)
  {
    _stake(assetAmount_, "stake");

    return currentActor;
  }

  function stakeWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidReservePoolId(seed_)
    countCall("stakeWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _stake(assetAmount_, "stakeWithExistingActor");

    return currentActor;
  }

  function stakeWithoutTransfer(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    createActor
    createActorWithStakes
    useValidReservePoolId(seed_)
    countCall("stakeWithoutTransfer")
    advanceTime(seed_)
    returns (address actor_)
  {
    _stakeWithoutTransfer(assetAmount_, "stakeWithoutTransfer");

    return currentActor;
  }

  function stakeWithoutTransferWithExistingActor(uint256 assetAmount_, uint256 seed_)
    public
    virtual
    useActor(seed_)
    useValidReservePoolId(seed_)
    countCall("stakeWithoutTransferWithExistingActor")
    advanceTime(seed_)
    returns (address actor_)
  {
    _stakeWithoutTransfer(assetAmount_, "stakeWithoutTransferWithExistingActor");

    return currentActor;
  }

  function redeem(uint256 depositTokenRedeemAmount_, address receiver_, uint256 seed_)
    public
    virtual
    useActorWithReseveDeposits(seed_)
    countCall("redeem")
    advanceTime(seed_)
  {
    IERC20 depositToken_ = getReservePool(safetyModule, currentReservePoolId).depositToken;
    uint256 actorDepositTokenBalance_ = depositToken_.balanceOf(currentActor);
    if (actorDepositTokenBalance_ == 0 || safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      invalidCalls["redeem"] += 1;
      return;
    }

    depositTokenRedeemAmount_ = bound(depositTokenRedeemAmount_, 1, actorDepositTokenBalance_);
    vm.startPrank(currentActor);
    depositToken_.approve(address(safetyModule), depositTokenRedeemAmount_);
    (uint64 redemptionId_, uint256 assetAmount_) =
      safetyModule.redeem(currentReservePoolId, depositTokenRedeemAmount_, receiver_, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].depositRedeemAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositRedeemSharesAmount += depositTokenRedeemAmount_;
    ghost_redemptions.push(GhostRedemption(redemptionId_, assetAmount_, depositTokenRedeemAmount_, false));
  }

  function redeemUndrippedRewards(uint256 depositTokenRedeemAmount_, address receiver_, uint256 seed_)
    public
    virtual
    useActorWithRewardDeposits(seed_)
    countCall("redeemUndrippedRewards")
    advanceTime(seed_)
  {
    IERC20 depositToken_ = getRewardPool(safetyModule, currentRewardPoolId).depositToken;
    uint256 actorDepositTokenBalance_ = depositToken_.balanceOf(currentActor);
    if (actorDepositTokenBalance_ == 0 || safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      invalidCalls["redeemUndrippedRewards"] += 1;
      return;
    }

    depositTokenRedeemAmount_ = bound(depositTokenRedeemAmount_, 1, actorDepositTokenBalance_);
    vm.startPrank(currentActor);
    depositToken_.approve(address(safetyModule), depositTokenRedeemAmount_);
    uint256 assetAmount_ =
      safetyModule.redeemUndrippedRewards(currentRewardPoolId, depositTokenRedeemAmount_, receiver_, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].redeemAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].redeemSharesAmount += depositTokenRedeemAmount_;
  }

  function unstake(uint256 stkTokenUnstakeAmount_, address receiver_, uint256 seed_)
    public
    virtual
    useActorWithStakes(seed_)
    countCall("unstake")
    advanceTime(seed_)
  {
    IERC20 stkToken_ = getReservePool(safetyModule, currentReservePoolId).stkToken;
    uint256 actorStkTokenBalance_ = stkToken_.balanceOf(currentActor);
    if (actorStkTokenBalance_ == 0 || safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      invalidCalls["unstake"] += 1;
      return;
    }

    _incrementRewardsToBeClaimed(currentReservePoolId, currentActor);

    stkTokenUnstakeAmount_ = bound(stkTokenUnstakeAmount_, 1, actorStkTokenBalance_);
    vm.startPrank(currentActor);
    stkToken_.approve(address(safetyModule), stkTokenUnstakeAmount_);
    (uint64 redemptionId_, uint256 assetAmount_) =
      safetyModule.unstake(currentReservePoolId, stkTokenUnstakeAmount_, receiver_, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].unstakeAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].unstakeSharesAmount += stkTokenUnstakeAmount_;
    ghost_redemptions.push(GhostRedemption(redemptionId_, assetAmount_, stkTokenUnstakeAmount_, false));
  }

  function claimRewards(address receiver_, uint256 seed_)
    public
    useActorWithStakes(seed_)
    countCall("claimRewards")
    advanceTime(seed_)
  {
    IERC20 stkToken_ = getReservePool(safetyModule, currentReservePoolId).stkToken;
    uint256 actorStkTokenBalance_ = stkToken_.balanceOf(currentActor);
    if (actorStkTokenBalance_ == 0) {
      invalidCalls["claimRewards"] += 1;
      return;
    }

    _incrementRewardsToBeClaimed(currentReservePoolId, currentActor);

    vm.startPrank(currentActor);
    safetyModule.claimRewards(currentReservePoolId, receiver_);
    vm.stopPrank();
  }

  function _incrementRewardsToBeClaimed(uint16 currentReservePool_, address currentActor_) public {
    uint16[] memory reservePoolIds_ = new uint16[](1);
    reservePoolIds_[0] = currentReservePool_;
    PreviewClaimableRewards[] memory reservePoolClaimableRewards_ =
      safetyModule.previewClaimableRewards(reservePoolIds_, currentActor_);

    for (uint16 j = 0; j < numRewardPools; j++) {
      PreviewClaimableRewardsData memory rewardPoolClaimableRewards_ =
        reservePoolClaimableRewards_[0].claimableRewardsData[j];
      ghost_rewardsClaimed[rewardPoolClaimableRewards_.asset] += rewardPoolClaimableRewards_.amount;
    }
  }

  function completeRedemption(address caller_, uint256 seed_)
    public
    virtual
    countCall("completeRedemption")
    advanceTime(seed_)
  {
    uint64 redemptionId_ = _pickRedemptionId(seed_);
    if (redemptionId_ == type(uint64).max) {
      invalidCalls["completeRedemption"] += 1;
      return;
    }

    RedemptionPreview memory queuedRedemption_ = safetyModule.previewQueuedRedemption(redemptionId_);

    skip(queuedRedemption_.delayRemaining);
    vm.startPrank(caller_);
    safetyModule.completeRedemption(redemptionId_);
    vm.stopPrank();

    ghost_redemptions[redemptionId_].completed = true;
  }

  function dripFees(address caller_, uint256 seed_) public virtual countCall("dripFees") advanceTime(seed_) {
    vm.startPrank(caller_);
    safetyModule.dripFees();
    vm.stopPrank();
  }

  function pause(uint256 seed_) public virtual countCall("pause") advanceTime(seed_) {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["pause"] += 1;
      return;
    }
    vm.prank(pauser);
    safetyModule.pause();
  }

  function unpause(uint256 seed_) public virtual countCall("unpause") advanceTime(seed_) {
    if (safetyModule.safetyModuleState() != SafetyModuleState.PAUSED) {
      invalidCalls["unpause"] += 1;
      return;
    }
    vm.prank(owner);
    safetyModule.unpause();
  }

  function trigger(uint256 seed_) public virtual useValidTrigger(seed_) countCall("trigger") advanceTime(seed_) {
    Trigger memory triggerData_ = safetyModule.triggerData(currentTrigger);
    if (triggerData_.triggered || !triggerData_.exists) {
      invalidCalls["trigger"] += 1;
      return;
    }
    MockTrigger(address(currentTrigger)).mockState(TriggerState.TRIGGERED);
    safetyModule.trigger(currentTrigger);
    triggeredTriggers.push(currentTrigger);

    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      assertEq(safetyModule.safetyModuleState(), SafetyModuleState.PAUSED);
    } else {
      assertEq(safetyModule.safetyModuleState(), SafetyModuleState.TRIGGERED);
    }
  }

  function slash(uint256 seedA_, uint256 seedB_)
    public
    virtual
    useValidPayoutHandler(seedA_)
    countCall("slash")
    advanceTime(seedA_)
  {
    if (safetyModule.numPendingSlashes() == 0 || safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      invalidCalls["slash"] += 1;
      return;
    }

    Slash[] memory slashes_ = new Slash[](numReservePools);
    for (uint16 i = 0; i < numReservePools; i++) {
      ReservePool memory reservePool_ = getReservePool(safetyModule, uint16(i));

      uint256 depositAmountToSlash_ = reservePool_.depositAmount > 0 ? bound(seedA_, 0, reservePool_.depositAmount) : 0;
      uint256 stakeAmountToSlash_ = reservePool_.stakeAmount > 0
        ? bound(seedB_, 0, reservePool_.stakeAmount.mulWadUp(reservePool_.maxSlashPercentage))
        : 0;

      slashes_[i] = Slash({reservePoolId: uint16(i), amount: depositAmountToSlash_ + stakeAmountToSlash_});
    }

    vm.prank(currentPayoutHandler);
    safetyModule.slash(slashes_, _randomAddress());
  }

  // ----------------------------------
  // -------- Helper functions --------
  // ----------------------------------

  function depositReserveAssetsWithExistingActorWithoutCountingCall(uint256 assets_) external returns (address) {
    uint256 invalidCallsBefore_ = invalidCalls["depositReserveAssetsWithExistingActor"];

    address actor_ = depositReserveAssetsWithExistingActor(assets_, _randomUint256());

    calls["depositReserveAssetsWithExistingActor"] -= 1; // depositWithExistingActor increments by 1.
    if (invalidCallsBefore_ < invalidCalls["depositReserveAssetsWithExistingActor"]) {
      invalidCalls["depositReserveAssetsWithExistingActor"] -= 1;
    }

    return actor_;
  }

  function callSummary() public view virtual {
    console2.log("Call summary:");
    console2.log("----------------------------------------------------------------------------");
    console2.log("Total Calls: ", totalCalls);
    console2.log("Total Time Advanced: ", totalTimeAdvanced);
    console2.log("----------------------------------------------------------------------------");
    console2.log("Calls:");
    console2.log("");
    console2.log("depositReserveAssets", calls["depositReserveAssets"]);
    console2.log("depositReserveAssetsWithExistingActor", calls["depositReserveAssetsWithExistingActor"]);
    console2.log("depositReserveAssetsWithoutTransfer", calls["depositReserveAssetsWithoutTransfer"]);
    console2.log(
      "depositReserveAssetsWithoutTransferWithExistingActor",
      calls["depositReserveAssetsWithoutTransferWithExistingActor"]
    );
    console2.log("depositRewardAssets", calls["depositRewardAssets"]);
    console2.log("depositRewardAssetsWithExistingActor", calls["depositRewardAssetsWithExistingActor"]);
    console2.log("depositRewardAssetsWithoutTransfer", calls["depositRewardAssetsWithoutTransfer"]);
    console2.log(
      "depositRewardAssetsWithoutTransferWithExistingActor",
      calls["depositRewardAssetsWithoutTransferWithExistingActor"]
    );
    console2.log("stake", calls["stake"]);
    console2.log("stakeWithExistingActor", calls["stakeWithExistingActor"]);
    console2.log("stakeWithoutTransfer", calls["stakeWithoutTransfer"]);
    console2.log("stakeWithoutTransferWithExistingActor", calls["stakeWithoutTransferWithExistingActor"]);
    console2.log("redeem", calls["redeem"]);
    console2.log("redeemUndrippedRewards", calls["redeemUndrippedRewards"]);
    console2.log("unstake", calls["unstake"]);
    console2.log("claimRewards", calls["claimRewards"]);
    console2.log("completeRedemption", calls["completeRedemption"]);
    console2.log("dripFees", calls["dripFees"]);
    console2.log("pause", calls["pause"]);
    console2.log("unpause", calls["unpause"]);
    console2.log("trigger", calls["trigger"]);
    console2.log("slash", calls["slash"]);
    console2.log("----------------------------------------------------------------------------");
    console2.log("Invalid calls:");
    console2.log("");
    console2.log("depositReserveAssets", invalidCalls["depositReserveAssets"]);
    console2.log("depositReserveAssetsWithExistingActor", invalidCalls["depositReserveAssetsWithExistingActor"]);
    console2.log("depositReserveAssetsWithoutTransfer", invalidCalls["depositReserveAssetsWithoutTransfer"]);
    console2.log(
      "depositReserveAssetsWithoutTransferWithExistingActor",
      invalidCalls["depositReserveAssetsWithoutTransferWithExistingActor"]
    );
    console2.log("depositRewardAssets", invalidCalls["depositRewardAssets"]);
    console2.log("depositRewardAssetsWithExistingActor", invalidCalls["depositRewardAssetsWithExistingActor"]);
    console2.log("depositRewardAssetsWithoutTransfer", invalidCalls["depositRewardAssetsWithoutTransfer"]);
    console2.log(
      "depositRewardAssetsWithoutTransferWithExistingActor",
      invalidCalls["depositRewardAssetsWithoutTransferWithExistingActor"]
    );
    console2.log("stake", invalidCalls["stake"]);
    console2.log("stakeWithExistingActor", invalidCalls["stakeWithExistingActor"]);
    console2.log("stakeWithoutTransfer", invalidCalls["stakeWithoutTransfer"]);
    console2.log("stakeWithoutTransferWithExistingActor", invalidCalls["stakeWithoutTransferWithExistingActor"]);
    console2.log("redeem", invalidCalls["redeem"]);
    console2.log("redeemUndrippedRewards", invalidCalls["redeemUndrippedRewards"]);
    console2.log("unstake", invalidCalls["unstake"]);
    console2.log("claimRewards", invalidCalls["claimRewards"]);
    console2.log("completeRedemption", invalidCalls["completeRedemption"]);
    console2.log("dripFees", invalidCalls["dripFees"]);
    console2.log("pause", invalidCalls["pause"]);
    console2.log("unpause", invalidCalls["unpause"]);
    console2.log("trigger", invalidCalls["trigger"]);
    console2.log("slash", invalidCalls["slash"]);
  }

  function _depositReserveAssets(uint256 assetAmount_, string memory callName_) internal {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls[callName_] += 1;
      return;
    }
    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint72).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.depositReserveAssets(currentReservePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].depositAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositSharesAmount += shares_;

    ghost_actorReserveDepositCount[currentActor][currentReservePoolId] += 1;
  }

  function _depositReserveAssetsWithoutTransfer(uint256 assetAmount_, string memory callName_) internal {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls[callName_] += 1;
      return;
    }

    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint72).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.startPrank(currentActor);
    uint256 shares_ = safetyModule.depositReserveAssetsWithoutTransfer(currentReservePoolId, assetAmount_, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].depositAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositSharesAmount += shares_;

    ghost_actorReserveDepositCount[currentActor][currentReservePoolId] += 1;
  }

  function _depositRewardAssets(uint256 assetAmount_, string memory callName_) internal {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls[callName_] += 1;
      return;
    }

    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint72).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.depositRewardAssets(currentRewardPoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;
  }

  function _depositRewardAssetsWithoutTransfer(uint256 assetAmount_, string memory callName_) internal {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls[callName_] += 1;
      return;
    }

    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint72).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.startPrank(currentActor);
    uint256 shares_ = safetyModule.depositRewardAssetsWithoutTransfer(currentRewardPoolId, assetAmount_, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;
  }

  function _stake(uint256 assetAmount_, string memory callName_) internal {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls[callName_] += 1;
      return;
    }

    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint72).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.stake(currentReservePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].stakeAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].stakeSharesAmount += shares_;

    ghost_actorStakeCount[currentActor][currentReservePoolId] += 1;
  }

  function _stakeWithoutTransfer(uint256 assetAmount_, string memory callName_) internal {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls[callName_] += 1;
      return;
    }

    assetAmount_ = uint72(bound(assetAmount_, 0.0001e6, type(uint72).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.startPrank(currentActor);
    uint256 shares_ = safetyModule.stakeWithoutTransfer(currentReservePoolId, assetAmount_, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].stakeAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].stakeSharesAmount += shares_;

    ghost_actorStakeCount[currentActor][currentReservePoolId] += 1;
  }

  function _simulateTransferToSafetyModule(uint256 assets_) internal {
    // Simulate transfer of assets to the safety module.
    deal(address(asset), address(safetyModule), asset.balanceOf(address(safetyModule)) + assets_, true);
  }

  function _createValidRandomAddress(address addr_) internal view returns (address) {
    if (addr_ == address(safetyModule)) return _randomAddress();
    for (uint256 i = 0; i < numReservePools; i++) {
      for (uint256 j = 0; j < numRewardPools; j++) {
        if (addr_ == address(getReservePool(ISafetyModule(address(safetyModule)), i).depositToken)) {
          return _randomAddress();
        }
        if (addr_ == address(getReservePool(ISafetyModule(address(safetyModule)), i).stkToken)) return _randomAddress();
        if (addr_ == address(getRewardPool(ISafetyModule(address(safetyModule)), j).depositToken)) {
          return _randomAddress();
        }
      }
    }
    return addr_;
  }

  function _pickRedemptionId(uint256 seed_) internal view returns (uint64 redemptionId_) {
    uint16 numRedemptions_ = uint16(ghost_redemptions.length);
    uint16 initIndex_ = uint16(bound(seed_, 0, numRedemptions_));
    uint16 indicesVisited_ = 0;

    for (uint16 i = initIndex_; indicesVisited_ < numRedemptions_; i = uint16((i + 1) % numRedemptions_)) {
      if (!ghost_redemptions[i].completed) return ghost_redemptions[i].id;
      indicesVisited_++;
    }

    // If no uncompleted pending redemption is found, we return type(uint64).max.
    return type(uint64).max;
  }

  // ----------------------------------
  // -------- Helper modifiers --------
  // ----------------------------------

  modifier advanceTime(uint256 byAmount_) {
    vm.warp(currentTimestamp);
    byAmount_ = uint64(bound(byAmount_, 1, SECONDS_IN_A_YEAR));
    skip(byAmount_);
    currentTimestamp += byAmount_;
    totalTimeAdvanced += byAmount_;
    _;
  }

  modifier createActor() {
    address actor_ = _createValidRandomAddress(msg.sender);
    currentActor = actor_;
    actors.add(currentActor);
    _;
  }

  modifier createActorWithReserveDeposits() {
    actorsWithReserveDeposits.add(currentActor);
    _;
  }

  modifier createActorWithRewardDeposits() {
    actorsWithRewardDeposits.add(currentActor);
    _;
  }

  modifier createActorWithStakes() {
    actorsWithStakes.add(currentActor);
    _;
  }

  modifier countCall(string memory key_) {
    totalCalls++;
    calls[key_]++;
    _;
  }

  modifier useValidReservePoolId(uint256 seed_) {
    currentReservePoolId = uint16(bound(seed_, 0, numReservePools - 1));
    _;
  }

  modifier useValidRewardPoolId(uint256 seed_) {
    currentRewardPoolId = uint16(bound(seed_, 0, numRewardPools - 1));
    _;
  }

  modifier useValidTrigger(uint256 seed_) {
    uint256 initIndex_ = bound(seed_, 0, triggers.length - 1);
    uint256 indicesVisited_ = 0;

    // Iterate through triggers to find the first trigger that can has not yet triggered the safety module,
    // if there is one.
    for (uint256 i = initIndex_; indicesVisited_ < triggers.length; i = (i + 1) % triggers.length) {
      if (!safetyModule.triggerData(triggers[i]).triggered) {
        currentTrigger = triggers[i];
        break;
      }
      indicesVisited_++;
    }
    _;
  }

  modifier useValidPayoutHandler(uint256 seed_) {
    uint256 initIndex_ = bound(seed_, 0, triggeredTriggers.length - 1);
    uint256 indicesVisited_ = 0;

    for (uint256 i = initIndex_; indicesVisited_ < triggeredTriggers.length; i = (i + 1) % triggeredTriggers.length) {
      Trigger memory triggerData_ = safetyModule.triggerData(triggeredTriggers[i]);
      if (triggerData_.triggered && safetyModule.payoutHandlerNumPendingSlashes(triggerData_.payoutHandler) > 0) {
        currentPayoutHandler = triggerData_.payoutHandler;
        break;
      }
      indicesVisited_++;
    }
    _;
  }

  modifier useActor(uint256 actorIndexSeed_) {
    currentActor = actors.rand(actorIndexSeed_);
    _;
  }

  modifier useActorWithReseveDeposits(uint256 seed_) {
    currentActor = actorsWithReserveDeposits.rand(seed_);

    uint16 initIndex_ = uint16(bound(seed_, 0, numReservePools));
    uint16 indicesVisited_ = 0;

    // Iterate through reserve pools to find the first pool with a positive reserve deposit count for the current actor
    for (uint16 i = initIndex_; indicesVisited_ < numReservePools; i = uint16((i + 1) % numReservePools)) {
      if (ghost_actorReserveDepositCount[currentActor][i] > 0) {
        currentReservePoolId = i;
        break;
      }
      indicesVisited_++;
    }
    _;
  }

  modifier useActorWithRewardDeposits(uint256 seed_) {
    currentActor = actorsWithRewardDeposits.rand(seed_);

    uint16 initIndex_ = uint16(bound(seed_, 0, numRewardPools));
    uint16 indicesVisited_ = 0;

    // Iterate through reserve pools to find the first pool with a positive reserve deposit count for the current actor
    for (uint16 i = initIndex_; indicesVisited_ < numRewardPools; i = uint16((i + 1) % numRewardPools)) {
      if (ghost_actorRewardDepositCount[currentActor][i] > 0) {
        currentRewardPoolId = i;
        break;
      }
      indicesVisited_++;
    }
    _;
  }

  modifier useActorWithStakes(uint256 seed_) {
    currentActor = actorsWithStakes.rand(seed_);

    uint16 initIndex_ = uint16(bound(seed_, 0, numReservePools));
    uint16 indicesVisited_ = 0;

    // Iterate through reserve pools to find the first pool with a positive reserve deposit count for the current actor
    for (uint16 i = initIndex_; indicesVisited_ < numReservePools; i = uint16((i + 1) % numReservePools)) {
      if (ghost_actorStakeCount[currentActor][i] > 0) {
        currentReservePoolId = i;
        break;
      }
      indicesVisited_++;
    }
    _;
  }

  modifier warpToCurrentTimestamp() {
    vm.warp(currentTimestamp);
    _;
  }
}
