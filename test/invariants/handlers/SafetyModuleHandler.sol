// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {console2} from "forge-std/console2.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {CozySafetyModuleManager} from "../../../src/CozySafetyModuleManager.sol";
import {SafetyModule} from "../../../src/SafetyModule.sol";
import {SafetyModuleState, TriggerState} from "../../../src/lib/SafetyModuleStates.sol";
import {ReservePool} from "../../../src/lib/structs/Pools.sol";
import {RedemptionPreview} from "../../../src/lib/structs/Redemptions.sol";
import {Slash} from "../../../src/lib/structs/Slash.sol";
import {Trigger} from "../../../src/lib/structs/Trigger.sol";
import {ISafetyModule} from "../../../src/interfaces/ISafetyModule.sol";
import {ITrigger} from "../../../src/interfaces/ITrigger.sol";
import {MockTrigger} from "../../utils/MockTrigger.sol";
import {TestBase} from "../../utils/TestBase.sol";

contract SafetyModuleHandler is TestBase {
  using FixedPointMathLib for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;

  uint64 constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;

  address public constant DEFAULT_ADDRESS = address(0xc0ffee);

  address pauser;
  address owner;

  CozySafetyModuleManager public manager;
  ISafetyModule public safetyModule;

  uint256 numReservePools;

  ITrigger[] public triggers;
  ITrigger[] public triggeredTriggers; // Triggers that have triggered the safety module.

  mapping(string => uint256) public calls;
  mapping(string => uint256) public invalidCalls;

  address internal currentActor;

  EnumerableSet.AddressSet internal actors;

  EnumerableSet.AddressSet internal actorsWithReserveDeposits;

  uint8 public currentReservePoolId;

  address public currentPayoutHandler;

  ITrigger public currentTrigger;

  uint256 public currentTimestamp;

  uint256 totalTimeAdvanced;

  uint256 public totalCalls;

  // -------- Ghost Variables --------

  mapping(uint8 reservePoolId_ => GhostReservePool reservePool_) public ghost_reservePoolCumulative;

  mapping(address actor_ => mapping(uint8 reservePoolId_ => uint256 actorReserveDepositCount_)) public
    ghost_actorReserveDepositCount;

  GhostRedemption[] public ghost_redemptions;

  // -------- Structs --------

  struct GhostReservePool {
    uint256 depositAssetAmount;
    uint256 depositSharesAmount;
    uint256 depositRedeemAssetAmount;
    uint256 depositRedeemSharesAmount;
  }

  struct GhostRedemption {
    uint64 id;
    uint256 assetAmount;
    uint256 receiptTokenAmount;
    bool completed;
  }

  // -------- Constructor --------

  constructor(
    CozySafetyModuleManager manager_,
    ISafetyModule safetyModule_,
    uint256 numReservePools_,
    ITrigger[] memory triggers_,
    uint256 currentTimestamp_
  ) {
    safetyModule = safetyModule_;
    manager = manager_;
    numReservePools = numReservePools_;
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

  function redeem(uint256 depositReceiptTokenRedeemAmount_, address receiver_, uint256 seed_)
    public
    virtual
    useActorWithReseveDeposits(seed_)
    countCall("redeem")
    advanceTime(seed_)
  {
    IERC20 depositReceiptToken_ = getReservePool(safetyModule, currentReservePoolId).depositReceiptToken;
    uint256 actorDepositReceiptTokenBalance_ = depositReceiptToken_.balanceOf(currentActor);
    if (actorDepositReceiptTokenBalance_ == 0 || safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      invalidCalls["redeem"] += 1;
      return;
    }

    depositReceiptTokenRedeemAmount_ = bound(depositReceiptTokenRedeemAmount_, 1, actorDepositReceiptTokenBalance_);
    vm.startPrank(currentActor);
    depositReceiptToken_.approve(address(safetyModule), depositReceiptTokenRedeemAmount_);
    (uint64 redemptionId_, uint256 assetAmount_) =
      safetyModule.redeem(currentReservePoolId, depositReceiptTokenRedeemAmount_, receiver_, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].depositRedeemAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositRedeemSharesAmount += depositReceiptTokenRedeemAmount_;
    ghost_redemptions.push(GhostRedemption(redemptionId_, assetAmount_, depositReceiptTokenRedeemAmount_, false));
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

  function dripFeesFromReservePool(address caller_, uint256 seed_)
    public
    virtual
    countCall("dripFeesFromReservePool")
    advanceTime(seed_)
  {
    vm.startPrank(caller_);
    safetyModule.dripFeesFromReservePool(currentReservePoolId);
    vm.stopPrank();
  }

  function claimFees(address owner_, uint256 seed_) public virtual countCall("claimFees") advanceTime(seed_) {
    vm.prank(address(manager));
    safetyModule.claimFees(owner_);
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

  function slash(uint256 seed_) public virtual useValidPayoutHandler(seed_) countCall("slash") advanceTime(seed_) {
    if (safetyModule.numPendingSlashes() == 0 || safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      invalidCalls["slash"] += 1;
      return;
    }

    Slash[] memory slashes_ = new Slash[](numReservePools);
    for (uint8 i = 0; i < numReservePools; i++) {
      ReservePool memory reservePool_ = getReservePool(safetyModule, i);

      uint256 depositAmountToSlash_ = reservePool_.depositAmount > 0
        ? bound(seed_, 0, reservePool_.depositAmount.mulWadUp(reservePool_.maxSlashPercentage))
        : 0;

      slashes_[i] = Slash({reservePoolId: i, amount: depositAmountToSlash_});
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

  function depositReserveAssetsWithExistingActorWithoutCountingCall(
    uint8 reservePoolId_,
    uint256 assets_,
    address actor_
  ) external returns (address) {
    uint256 invalidCallsBefore_ = invalidCalls["depositReserveAssetsWithExistingActor"];

    currentReservePoolId = reservePoolId_;
    currentActor = actor_;

    _depositReserveAssets(assets_, "depositReserveAssetsWithExistingActor");

    // _depositReserveAssets increments invalidCalls by 1 if the safety module is paused.
    if (invalidCallsBefore_ < invalidCalls["depositReserveAssetsWithExistingActor"]) {
      invalidCalls["depositReserveAssetsWithExistingActor"] -= 1;
    }

    return currentActor;
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
    console2.log("redeem", calls["redeem"]);
    console2.log("completeRedemption", calls["completeRedemption"]);
    console2.log("dripFees", calls["dripFees"]);
    console2.log("dripFeesFromReservePool", calls["dripFeesFromReservePool"]);
    console2.log("claimFees", calls["claimFees"]);
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
    console2.log("redeem", invalidCalls["redeem"]);
    console2.log("completeRedemption", invalidCalls["completeRedemption"]);
    console2.log("dripFees", invalidCalls["dripFees"]);
    console2.log("pause", invalidCalls["pause"]);
    console2.log("unpause", invalidCalls["unpause"]);
    console2.log("trigger", invalidCalls["trigger"]);
    console2.log("slash", invalidCalls["slash"]);
  }

  function boundDepositAssetAmount(uint256 assetAmount_) public pure returns (uint256) {
    return bound(assetAmount_, 0.0001e6, type(uint72).max);
  }

  function pickValidReservePoolId(uint256 seed_) public view returns (uint8) {
    return uint8(bound(seed_, 0, numReservePools - 1));
  }

  function getTriggeredTriggers() public view returns (ITrigger[] memory) {
    return triggeredTriggers;
  }

  function getTriggers() public view returns (ITrigger[] memory) {
    return triggers;
  }

  function pickActor(uint256 seed_) public view returns (address) {
    uint256 numActors_ = actors.length();
    return numActors_ == 0 ? DEFAULT_ADDRESS : actors.at(seed_ % numActors_);
  }

  function pickValidTrigger(uint256 seed_) public view returns (ITrigger) {
    uint256 initIndex_ = seed_ % triggers.length;
    uint256 indicesVisited_ = 0;

    // Iterate through triggers to find the first trigger that has not yet triggered the safety module,
    // if there is one.
    for (uint256 i = initIndex_; indicesVisited_ < triggers.length; i = (i + 1) % triggers.length) {
      if (!safetyModule.triggerData(triggers[i]).triggered) return triggers[i];
      indicesVisited_++;
    }

    // If no valid trigger is found, return a default address.
    return ITrigger(DEFAULT_ADDRESS);
  }

  function pickActorWithReserveDeposits(uint256 seed_) public view returns (address) {
    uint256 numActorsWithReserveDeposits_ = actorsWithReserveDeposits.length();
    return numActorsWithReserveDeposits_ == 0
      ? DEFAULT_ADDRESS
      : actorsWithReserveDeposits.at(seed_ % numActorsWithReserveDeposits_);
  }

  function pickReservePoolIdForActorWithReserveDeposits(uint256 seed_, address actor_) public view returns (uint8) {
    uint8 initIndex_ = uint8(_randomUint256FromSeed(seed_) % numReservePools);
    uint8 indicesVisited_ = 0;

    // Iterate through reserve pools to find the first pool with a positive reserve deposit count for the current actor
    for (uint8 i = initIndex_; indicesVisited_ < numReservePools; i = uint8((i + 1) % numReservePools)) {
      if (ghost_actorReserveDepositCount[actor_][i] > 0) return i;
      indicesVisited_++;
    }

    // If no reserve pool with a reward deposit count was found, return the random initial index.
    return initIndex_;
  }

  function _depositReserveAssets(uint256 assetAmount_, string memory callName_) internal {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls[callName_] += 1;
      return;
    }
    assetAmount_ = boundDepositAssetAmount(assetAmount_);
    IERC20 asset_ = getReservePool(safetyModule, currentReservePoolId).asset;
    deal(address(asset_), currentActor, asset_.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset_.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.depositReserveAssets(currentReservePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].depositAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositSharesAmount += shares_;

    ghost_actorReserveDepositCount[currentActor][currentReservePoolId] += 1;
  }

  function _depositReserveAssetsWithoutTransfer(uint256 assetAmount_, string memory callName_) internal {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls[callName_] += 1;
      return;
    }

    assetAmount_ = boundDepositAssetAmount(assetAmount_);
    IERC20 asset_ = getReservePool(safetyModule, currentReservePoolId).asset;
    _simulateTransferToSafetyModule(asset_, assetAmount_);

    vm.startPrank(currentActor);
    uint256 shares_ = safetyModule.depositReserveAssetsWithoutTransfer(currentReservePoolId, assetAmount_, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].depositAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositSharesAmount += shares_;

    ghost_actorReserveDepositCount[currentActor][currentReservePoolId] += 1;
  }

  function _simulateTransferToSafetyModule(IERC20 asset_, uint256 assets_) internal {
    // Simulate transfer of assets to the safety module.
    deal(address(asset_), address(safetyModule), asset_.balanceOf(address(safetyModule)) + assets_, true);
  }

  function _createValidRandomAddress(address addr_) internal view returns (address) {
    if (addr_ == address(safetyModule)) return _randomAddress();
    for (uint256 i = 0; i < numReservePools; i++) {
      if (addr_ == address(getReservePool(ISafetyModule(address(safetyModule)), i).depositReceiptToken)) {
        return _randomAddress();
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

  modifier countCall(string memory key_) {
    totalCalls++;
    calls[key_]++;
    _;
  }

  modifier useValidReservePoolId(uint256 seed_) {
    currentReservePoolId = pickValidReservePoolId(seed_);
    _;
  }

  modifier useValidTrigger(uint256 seed_) {
    ITrigger trigger_ = pickValidTrigger(seed_);
    currentTrigger = trigger_;
    _;
  }

  modifier useValidPayoutHandler(uint256 seed_) {
    uint256 initIndex_ = seed_ % triggeredTriggers.length;
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
    currentActor = pickActor(actorIndexSeed_);
    _;
  }

  modifier useActorWithReseveDeposits(uint256 seed_) {
    currentActor = pickActorWithReserveDeposits(seed_);
    currentReservePoolId = pickReservePoolIdForActorWithReserveDeposits(seed_, currentActor);
    _;
  }

  modifier warpToCurrentTimestamp() {
    vm.warp(currentTimestamp);
    _;
  }
}
