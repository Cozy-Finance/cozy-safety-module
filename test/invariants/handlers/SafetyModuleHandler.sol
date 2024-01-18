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

  mapping(address actor_ => uint256 actorReserveDepositCount_) public ghost_actorReserveDepositCount;

  // -------- Structs --------

  struct GhostReservePool {
    uint256 totalAssetAmount;
    uint256 depositAssetAmount;
    uint256 depositSharesAmount;
    uint256 stakeAssetAmount;
    uint256 stakeSharesAmount;
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

    ghost_actorReserveDepositCount[currentActor] += 1;

    return currentActor;
  }

  function depositReserveAssetsWithExistingActor(uint256 assetAmount_)
    public
    virtual
    useActorWithReseveDeposits(_randomUint256())
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

    ghost_actorReserveDepositCount[currentActor] += 1;

    return currentActor;
  }

  // ----------------------------------
  // -------- Helper functions --------
  // ----------------------------------

  function depositReserveAssetsWithoutCountingCall(uint256 assets_) external returns (address) {
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
    console2.log("deposit", calls["depositReserveAssets"]);
    console2.log("-------------------");
    console2.log("Invalid calls:");
    console2.log("");
    console2.log("depositReserveAssets", invalidCalls["depositReserveAssets"]);
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
    _;
  }

  modifier useActorWithRewardDeposits(uint256 seed_) {
    currentActor = actorsWithRewardDeposits.rand(seed_);
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
