// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {console2} from "forge-std/console2.sol";
import {Manager} from "../../../src/Manager.sol";
import {SafetyModule} from "../../../src/SafetyModule.sol";
import {SafetyModuleState} from "../../../src/lib/SafetyModuleStates.sol";
import {IERC20} from "../../../src/interfaces/IERC20.sol";
import {ISafetyModule} from "../../../src/interfaces/ISafetyModule.sol";
import {AddressSet, AddressSetLib} from "../utils/AddressSet.sol";
import {TestBase} from "../../utils/TestBase.sol";

contract SafetyModuleHandler is TestBase {
  using AddressSetLib for AddressSet;

  uint64 constant SECONDS_IN_A_YEAR = 365 * 24 * 60 * 60;

  address pauser;
  address owner;

  Manager public manager;
  ISafetyModule public safetyModule;

  IERC20 public asset;

  uint256 numReservePools;
  uint256 numRewardPools;

  mapping(string => uint256) public calls;
  mapping(string => uint256) public invalidCalls;

  address internal currentActor;

  AddressSet internal actors;

  AddressSet internal actorsWithReserveDeposits;

  AddressSet internal actorsWithRewardDeposits;

  AddressSet internal actorsWithStakes;

  uint16 public currentReservePoolId;

  uint16 public currentRewardPoolId;

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

  // -------- Structs --------

  struct GhostReservePool {
    uint256 totalAssetAmount;
    uint256 depositAssetAmount;
    uint256 depositSharesAmount;
    uint256 stakeAssetAmount;
    uint256 stakeSharesAmount;
    uint256 depositRedeemAssetAmount;
    uint256 depositRedeemSharesAmount;
    uint256 stakeRedeemAssetAmount;
    uint256 stakeRedeemSharesAmount;
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

    vm.label(address(safetyModule), "safetyModule");
  }

  // --------------------------------------
  // -------- Functions under test --------
  // --------------------------------------

  function depositReserveAssets(uint256 assetAmount_)
    public
    virtual
    createActor
    createActorWithReserveDeposits
    useValidReservePoolId(_randomUint256())
    countCall("depositReserveAssets")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["depositReserveAssets"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.depositReserveAssets(currentReservePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].depositAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositSharesAmount += shares_;

    ghost_actorReserveDepositCount[currentActor][currentReservePoolId] += 1;

    return currentActor;
  }

  function depositReserveAssetsWithExistingActor(uint256 assetAmount_)
    public
    virtual
    useActor(_randomUint256())
    useValidReservePoolId(_randomUint256())
    countCall("depositReserveAssetsWithExistingActor")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["depositReserveAssetsWithExistingActor"] += 1;
      return currentActor;
    }
    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.depositReserveAssets(currentReservePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].depositAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositSharesAmount += shares_;

    ghost_actorReserveDepositCount[currentActor][currentReservePoolId] += 1;

    return currentActor;
  }

  function depositReserveAssetsWithoutTransfer(uint256 assetAmount_)
    public
    virtual
    createActor
    createActorWithReserveDeposits
    useValidReservePoolId(_randomUint256())
    countCall("depositReserveAssetsWithoutTransfer")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["depositReserveAssetsWithoutTransfer"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.prank(currentActor);
    uint256 shares_ = safetyModule.depositReserveAssetsWithoutTransfer(currentReservePoolId, assetAmount_, currentActor);

    ghost_reservePoolCumulative[currentReservePoolId].depositAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositSharesAmount += shares_;

    ghost_actorReserveDepositCount[currentActor][currentReservePoolId] += 1;

    return currentActor;
  }

  function depositReserveAssetsWithoutTransferWithExistingActor(uint256 assetAmount_)
    public
    virtual
    useActor(_randomUint256())
    useValidReservePoolId(_randomUint256())
    countCall("depositReserveAssetsWithoutTransferWithExistingActor")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["depositReserveAssetsWithoutTransferWithExistingActor"] += 1;
      return currentActor;
    }
    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.prank(currentActor);
    uint256 shares_ = safetyModule.depositReserveAssets(currentReservePoolId, assetAmount_, currentActor, currentActor);

    ghost_reservePoolCumulative[currentReservePoolId].depositAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositSharesAmount += shares_;

    ghost_actorReserveDepositCount[currentActor][currentReservePoolId] += 1;

    return currentActor;
  }

  function depositRewardAssets(uint256 assetAmount_)
    public
    virtual
    createActor
    createActorWithRewardDeposits
    useValidRewardPoolId(_randomUint256())
    countCall("depositRewardAssets")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["depositRewardAssets"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.depositRewardAssets(currentRewardPoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;

    return currentActor;
  }

  function depositRewardAssetsWithExistingActor(uint256 assetAmount_)
    public
    virtual
    useActor(_randomUint256())
    useValidRewardPoolId(_randomUint256())
    countCall("depositRewardAssetsWithExistingActor")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["depositRewardAssetsWithExistingActor"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.depositRewardAssets(currentRewardPoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;

    return currentActor;
  }

  function depositRewardAssetsWithoutTransfer(uint256 assetAmount_)
    public
    virtual
    createActor
    createActorWithRewardDeposits
    useValidRewardPoolId(_randomUint256())
    countCall("depositRewardAssetsWithoutTransfer")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["depositRewardAssetsWithoutTransfer"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.prank(currentActor);
    uint256 shares_ = safetyModule.depositRewardAssets(currentRewardPoolId, assetAmount_, currentActor, currentActor);

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;

    return currentActor;
  }

  function depositRewardAssetsWithoutTransferWithExistingActor(uint256 assetAmount_)
    public
    virtual
    useActor(_randomUint256())
    useValidRewardPoolId(_randomUint256())
    countCall("depositRewardAssetsWithoutTransferWithExistingActor")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["depositRewardAssetsWithoutTransferWithExistingActor"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.prank(currentActor);
    uint256 shares_ = safetyModule.depositRewardAssets(currentRewardPoolId, assetAmount_, currentActor, currentActor);

    ghost_rewardPoolCumulative[currentRewardPoolId].totalAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentRewardPoolId].depositSharesAmount += shares_;

    ghost_actorRewardDepositCount[currentActor][currentRewardPoolId] += 1;

    return currentActor;
  }

  function stake(uint256 assetAmount_)
    public
    virtual
    createActor
    createActorWithStakes
    useValidReservePoolId(_randomUint256())
    countCall("stake")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["stake"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.stake(currentReservePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].stakeAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].stakeSharesAmount += shares_;

    ghost_actorStakeCount[currentActor][currentReservePoolId] += 1;

    return currentActor;
  }

  function stakeWithExistingActor(uint256 assetAmount_)
    public
    virtual
    useActor(_randomUint256())
    useValidReservePoolId(_randomUint256())
    countCall("stakeWithExistingActor")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["stakeWithExistingActor"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    deal(address(asset), currentActor, asset.balanceOf(currentActor) + assetAmount_, true);

    vm.startPrank(currentActor);
    asset.approve(address(safetyModule), assetAmount_);
    uint256 shares_ = safetyModule.stake(currentReservePoolId, assetAmount_, currentActor, currentActor);
    vm.stopPrank();

    ghost_reservePoolCumulative[currentReservePoolId].stakeAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].stakeSharesAmount += shares_;

    ghost_actorStakeCount[currentActor][currentReservePoolId] += 1;

    return currentActor;
  }

  function stakeWithoutTransfer(uint256 assetAmount_)
    public
    virtual
    createActor
    createActorWithStakes
    useValidReservePoolId(_randomUint256())
    countCall("stakeWithoutTransfer")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["stakeWithoutTransfer"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.prank(currentActor);
    uint256 shares_ = safetyModule.stakeWithoutTransfer(currentReservePoolId, assetAmount_, currentActor);

    ghost_reservePoolCumulative[currentReservePoolId].stakeAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].stakeSharesAmount += shares_;

    ghost_actorStakeCount[currentActor][currentReservePoolId] += 1;

    return currentActor;
  }

  function stakeWithoutTransferWithExistingActor(uint256 assetAmount_)
    public
    virtual
    useActor(_randomUint256())
    useValidReservePoolId(_randomUint256())
    countCall("stakeWithoutTransferWithExistingActor")
    advanceTime(_randomUint256())
    returns (address actor_)
  {
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      invalidCalls["stakeWithoutTransferWithExistingActor"] += 1;
      return currentActor;
    }

    assetAmount_ = uint80(bound(assetAmount_, 0.0001e6, type(uint80).max));
    _simulateTransferToSafetyModule(assetAmount_);

    vm.prank(currentActor);
    uint256 shares_ = safetyModule.stakeWithoutTransfer(currentReservePoolId, assetAmount_, currentActor);

    ghost_reservePoolCumulative[currentReservePoolId].stakeAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].totalAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].stakeSharesAmount += shares_;

    ghost_actorStakeCount[currentActor][currentReservePoolId] += 1;

    return currentActor;
  }

  function redeem(uint256 depositTokenRedeemAmount_, address receiver_, uint256 actorSeed_)
    public
    virtual
    useActorWithReseveDeposits(actorSeed_)
    countCall("redeem")
    advanceTime(_randomUint256())
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

    ghost_reservePoolCumulative[currentReservePoolId].depositRedeemAssetAmount += assetAmount_;
    ghost_reservePoolCumulative[currentReservePoolId].depositRedeemSharesAmount += depositTokenRedeemAmount_;
    ghost_redemptions.push(GhostRedemption(redemptionId_, assetAmount_, depositTokenRedeemAmount_, false));
  }

  function redeemUndrippedRewards(uint256 depositTokenRedeemAmount_, address receiver_, uint256 actorSeed_)
    public
    virtual
    useActorWithRewardDeposits(actorSeed_)
    countCall("redeemUndrippedRewards")
    advanceTime(_randomUint256())
  {
    IERC20 depositToken_ = getUndrippedRewardPool(safetyModule, currentRewardPoolId).depositToken;
    uint256 actorDepositTokenBalance_ = depositToken_.balanceOf(currentActor);
    if (actorDepositTokenBalance_ == 0 || safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      invalidCalls["redeemUndrippedRewards"] += 1;
      return;
    }

    depositTokenRedeemAmount_ = bound(depositTokenRedeemAmount_, 1, actorDepositTokenBalance_);
    vm.startPrank(currentActor);
    depositToken_.approve(address(safetyModule), depositTokenRedeemAmount_);
    uint256 assetAmount_ =
      safetyModule.redeemUndrippedRewards(currentReservePoolId, depositTokenRedeemAmount_, receiver_, currentActor);

    ghost_rewardPoolCumulative[currentReservePoolId].redeemAssetAmount += assetAmount_;
    ghost_rewardPoolCumulative[currentReservePoolId].redeemSharesAmount += depositTokenRedeemAmount_;
  }

  // ----------------------------------
  // -------- Helper functions --------
  // ----------------------------------

  function depositReserveAssetsWithExistingActorWithoutCountingCall(uint256 assets_) external returns (address) {
    address actor_ = depositReserveAssetsWithExistingActor(assets_);
    calls["depositReserveAssetsWithExistingActor"] -= 1; // depositWithExistingActor increments by 1.

    return actor_;
  }

  function callSummary() public view virtual {
    console2.log("Call summary:");
    console2.log("-------------------");
    console2.log("Total Calls: ", totalCalls);
    console2.log("Total Time Advanced: ", totalTimeAdvanced);
    console2.log("-------------------");
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
    console2.log("-------------------");
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
        if (addr_ == address(getUndrippedRewardPool(ISafetyModule(address(safetyModule)), j).depositToken)) {
          return _randomAddress();
        }
      }
    }
    return addr_;
  }

  // ----------------------------------
  // -------- Helper modifiers --------
  // ----------------------------------

  modifier advanceTime(uint256 byAmount_) {
    vm.warp(currentTimestamp);
    byAmount_ = uint64(bound(byAmount_, 1, SECONDS_IN_A_YEAR));
    skip(byAmount_);
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

  modifier useActor(uint256 actorIndexSeed_) {
    currentActor = actors.rand(actorIndexSeed_);
    _;
  }

  modifier useActorWithReseveDeposits(uint256 seed_) {
    currentActor = actorsWithReserveDeposits.rand(seed_);
    // TODO: Determine which reserve pool to use in a smarter manner to better support redeem calls.
    currentReservePoolId = uint16(bound(seed_, 0, numReservePools - 1));
    _;
  }

  modifier useActorWithRewardDeposits(uint256 seed_) {
    currentActor = actorsWithRewardDeposits.rand(seed_);
    // TODO: Determine which reserve pool to use in a smarter manner to better support redeem calls.
    currentRewardPoolId = uint16(bound(seed_, 0, numRewardPools - 1));
    _;
  }

  modifier useActorWithStakes(uint256 seed_) {
    currentActor = actorsWithStakes.rand(seed_);
    _;
  }

  modifier warpToCurrentTimestamp() {
    vm.warp(currentTimestamp);
    _;
  }
}
