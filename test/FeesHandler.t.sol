// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {RewardsHandler} from "../src/lib/RewardsHandler.sol";
import {FeesHandler} from "../src/lib/FeesHandler.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {SafeCastLib} from "../src/lib/SafeCastLib.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {Ownable} from "../src/lib/Ownable.sol";
import {AssetPool, ReservePool} from "../src/lib/structs/Pools.sol";
import {UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {IdLookup} from "../src/lib/structs/Pools.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

contract FeesHandlerUnitTest is TestBase {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  MockDripModel mockFeesDripModel;
  MockManager public mockManager = new MockManager();
  TestableFeesHandler component = new TestableFeesHandler(IManager(address(mockManager)));

  uint256 constant DEFAULT_FEES_DRIP_RATE = 0.05e18;
  uint256 constant DEFAULT_NUM_RESERVE_POOLS = 5;

  event ClaimedFees(IERC20 indexed reserveAsset_, uint256 feeAmount_, address indexed owner_);

  function setUp() public {
    mockFeesDripModel = new MockDripModel(DEFAULT_FEES_DRIP_RATE);
    mockManager.setFeeDripModel(IDripModel(address(mockFeesDripModel)));
    component.mockSetLastDripTime(block.timestamp);
  }

  function _setUpReservePools(uint256 numReservePools_) internal {
    for (uint16 i = 0; i < numReservePools_; i++) {
      MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);

      uint256 stakeAmount_ = _randomUint256() % 500_000_000;
      uint256 depositAmount_ = _randomUint256() % 500_000_000;
      uint256 pendingUnstakesAmount_ = _randomUint256() % 500_000_000;
      uint256 pendingWithdrawalsAmount_ = _randomUint256() % 500_000_000;
      pendingUnstakesAmount_ = bound(pendingUnstakesAmount_, 0, stakeAmount_);
      pendingWithdrawalsAmount_ = bound(pendingWithdrawalsAmount_, 0, depositAmount_);

      ReservePool memory reservePool_ = ReservePool({
        asset: IERC20(address(mockAsset_)),
        stkToken: IReceiptToken(address(0)),
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingUnstakesAmount: pendingUnstakesAmount_,
        pendingWithdrawalsAmount: pendingWithdrawalsAmount_,
        feeAmount: 0,
        rewardsPoolsWeight: (MathConstants.ZOC / numReservePools_).safeCastTo16()
      });
      component.mockAddReservePool(reservePool_);
      component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: stakeAmount_ + depositAmount_}));
      mockAsset_.mint(address(component), stakeAmount_ + depositAmount_);
    }
  }

  function _setUpDefault() internal {
    _setUpReservePools(DEFAULT_NUM_RESERVE_POOLS);
  }

  function _setUpConcrete() internal {
    skip(10);

    // Set-up two reserve pools.
    MockERC20 mockAsset1_ = new MockERC20("Mock Asset", "MOCK", 6);
    ReservePool memory reservePool1_ = ReservePool({
      asset: IERC20(address(mockAsset1_)),
      stkToken: IReceiptToken(address(0)),
      depositToken: IReceiptToken(address(0)),
      stakeAmount: 100e6,
      depositAmount: 50e6,
      pendingUnstakesAmount: 100e6,
      pendingWithdrawalsAmount: 25e6,
      feeAmount: 0,
      rewardsPoolsWeight: 0.1e4 // 10% weight
    });
    component.mockAddReservePool(reservePool1_);
    component.mockAddAssetPool(IERC20(address(mockAsset1_)), AssetPool({amount: 150e6}));
    mockAsset1_.mint(address(component), 150e6);

    MockERC20 mockAsset2_ = new MockERC20("Mock Asset", "MOCK", 6);
    ReservePool memory reservePool2_ = ReservePool({
      asset: IERC20(address(mockAsset2_)),
      stkToken: IReceiptToken(address(0)),
      depositToken: IReceiptToken(address(0)),
      stakeAmount: 200e6,
      depositAmount: 20e6,
      pendingUnstakesAmount: 10e6,
      pendingWithdrawalsAmount: 0,
      feeAmount: 0,
      rewardsPoolsWeight: 0.9e4 // 90% weight
    });
    component.mockAddReservePool(reservePool2_);
    component.mockAddAssetPool(IERC20(address(mockAsset2_)), AssetPool({amount: 220e6}));
    mockAsset2_.mint(address(component), 220e6);
  }

  function _calculateExpectedDripQuantity(uint256 poolAmount_, uint256 dripFactor_) internal pure returns (uint256) {
    return poolAmount_.mulWadDown(dripFactor_);
  }
}

contract FeesHandlerDripUnitTest is FeesHandlerUnitTest {
  using FixedPointMathLib for uint256;

  function testFuzz_noDripIfSafetyModuleIsPaused(uint64 timeElapsed_) public {
    _setUpDefault();
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    timeElapsed_ = uint64(bound(timeElapsed_, 0, type(uint64).max - component.getLastDripTime()));
    skip(timeElapsed_);

    ReservePool[] memory initialReservePools_ = component.getReservePools();
    component.dripFees();
    assertEq(component.getReservePools(), initialReservePools_);
  }

  function testFuzz_noDripIfSafetyModuleIsTriggered(uint64 timeElapsed_) public {
    _setUpDefault();
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);
    timeElapsed_ = uint64(bound(timeElapsed_, 0, type(uint64).max - component.getLastDripTime()));
    skip(timeElapsed_);

    ReservePool[] memory initialReservePools_ = component.getReservePools();
    component.dripFees();
    assertEq(component.getReservePools(), initialReservePools_);
  }

  function test_noDripIfNoTimeElapsed() public {
    _setUpDefault();
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    ReservePool[] memory initialReservePools_ = component.getReservePools();
    component.dripFees();
    assertEq(component.getReservePools(), initialReservePools_);
  }

  function test_feesDripConcrete() public {
    _setUpConcrete();

    ReservePool[] memory expectedReservePools_ = new ReservePool[](2);
    ReservePool[] memory concreteReservePools_ = component.getReservePools();
    {
      ReservePool memory expectedPool1_;
      expectedPool1_.asset = concreteReservePools_[0].asset;
      expectedPool1_.stkToken = concreteReservePools_[0].stkToken;
      expectedPool1_.depositToken = concreteReservePools_[0].depositToken;
      // drippedFromStakeAmount = (stakeAmount - pendingUnstakesAmount) * dripRate = 0e6 * 0.05 = 0e6
      // drippedFromDepositAmount = (depositAmount - pendingWithdrawalsAmount) * dripRate = 25e6 * 0.05 = 1.25e6
      expectedPool1_.stakeAmount = 100e6; // stakeAmount = originalStakeAmount - drippedFromStakeAmount
      expectedPool1_.depositAmount = 48.75e6; // depositAmount = originalDepositAmount - drippedFromDepositAmount
      expectedPool1_.feeAmount = 1.25e6; // drippedFromStakeAmount + drippedFromDepositAmount
      expectedPool1_.pendingUnstakesAmount = concreteReservePools_[0].pendingUnstakesAmount;
      expectedPool1_.pendingWithdrawalsAmount = concreteReservePools_[0].pendingWithdrawalsAmount;
      expectedPool1_.rewardsPoolsWeight = concreteReservePools_[0].rewardsPoolsWeight;
      expectedReservePools_[0] = expectedPool1_;
    }
    {
      ReservePool memory expectedPool2_;
      expectedPool2_.asset = concreteReservePools_[1].asset;
      expectedPool2_.stkToken = concreteReservePools_[1].stkToken;
      expectedPool2_.depositToken = concreteReservePools_[1].depositToken;
      // drippedFromStakeAmount = (stakeAmount - pendingUnstakesAmount) * dripRate = 190e6 * 0.05 = 9.5e6
      // drippedFromDepositAmount = (depositAmount - pendingWithdrawalsAmount) * dripRate = 20e6 * 0.05 = 1e6
      expectedPool2_.stakeAmount = 190.5e6; // stakeAmount = originalStakeAmount - drippedFromStakeAmount
      expectedPool2_.depositAmount = 19e6; // depositAmount = originalDepositAmount - drippedFromDepositAmount
      expectedPool2_.feeAmount = 10.5e6; // drippedFromStakeAmount + drippedFromDepositAmount
      expectedPool2_.pendingUnstakesAmount = concreteReservePools_[1].pendingUnstakesAmount;
      expectedPool2_.pendingWithdrawalsAmount = concreteReservePools_[1].pendingWithdrawalsAmount;
      expectedPool2_.rewardsPoolsWeight = concreteReservePools_[1].rewardsPoolsWeight;
      expectedReservePools_[1] = expectedPool2_;
    }

    component.dripFees();
    assertEq(component.getReservePools(), expectedReservePools_);
    assertEq(component.getLastDripTime(), block.timestamp);
  }

  function testFuzz_feesDrip(uint64 timeElapsed_) public {
    _setUpDefault();

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);
    timeElapsed_ = uint64(bound(timeElapsed_, 1, type(uint64).max - component.getLastDripTime()));
    skip(timeElapsed_);

    uint256 dripRate_ = _randomUint256() % MathConstants.WAD;
    MockDripModel model_ = new MockDripModel(dripRate_);
    mockManager.setFeeDripModel(IDripModel(address(model_)));

    ReservePool[] memory expectedReservePools_ = component.getReservePools();
    uint256 numReservePools_ = expectedReservePools_.length;
    for (uint16 i = 0; i < numReservePools_; i++) {
      ReservePool memory expectedReservePool_ = expectedReservePools_[i];
      uint256 drippedFromStakeAmount_ = _calculateExpectedDripQuantity(
        expectedReservePool_.stakeAmount - expectedReservePool_.pendingUnstakesAmount, dripRate_
      );
      uint256 drippedFromDepositAmount_ = _calculateExpectedDripQuantity(
        expectedReservePool_.depositAmount - expectedReservePool_.pendingWithdrawalsAmount, dripRate_
      );

      expectedReservePool_.stakeAmount -= drippedFromStakeAmount_;
      expectedReservePool_.depositAmount -= drippedFromDepositAmount_;
      expectedReservePool_.feeAmount += drippedFromStakeAmount_ + drippedFromDepositAmount_;

      expectedReservePools_[i] = expectedReservePool_;
    }

    component.dripFees();
    assertEq(component.getReservePools(), expectedReservePools_);
    assertEq(component.getLastDripTime(), block.timestamp);
  }

  function testFuzz_ZeroFeesDrip(uint64 timeElapsed_) public {
    _setUpDefault();

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);
    timeElapsed_ = uint64(bound(timeElapsed_, 1, type(uint64).max - component.getLastDripTime()));
    skip(timeElapsed_);

    // Set drip rate to 0.
    MockDripModel model_ = new MockDripModel(0);
    mockManager.setFeeDripModel(IDripModel(address(model_)));

    ReservePool[] memory expectedReservePools_ = component.getReservePools();
    component.dripFees();
    // No fees should be dripped, so all accounting should be the same.
    assertEq(component.getReservePools(), expectedReservePools_);
    assertEq(component.getLastDripTime(), block.timestamp);
  }
}

contract FeesHandlerClaimUnitTest is FeesHandlerUnitTest {
  using FixedPointMathLib for uint256;

  function test_claimFeesConcrete() public {
    _setUpConcrete();

    // Drip fees once and skip some time, so we will drip again on the next call of `claimFees`.
    component.dripFees();
    skip(99);

    // First fee drip for reservePools[0]:
    // drippedFromStakeAmount = (stakeAmount - pendingUnstakesAmount) * dripRate = 0e6 * 0.05 = 0e6
    // drippedFromDepositAmount = (depositAmount - pendingWithdrawalsAmount) * dripRate = 25e6 * 0.05 = 1.25e6

    // First fee drip for reservePools[1]:
    // drippedFromStakeAmount = (stakeAmount - pendingUnstakesAmount) * dripRate = 190e6 * 0.05 = 9.5e6
    // drippedFromDepositAmount = (depositAmount - pendingWithdrawalsAmount) * dripRate = 20e6 * 0.05 = 1e6

    // Second fee drip for reservePools[0]:
    // drippedFromStakeAmount = (stakeAmount - pendingUnstakesAmount) * dripRate = 0e6 * 0.05 = 0e6
    // drippedFromDepositAmount = (depositAmount - pendingWithdrawalsAmount) * dripRate = 23.75e6 * 0.05 = 1.1875e6

    // Second fee drip for reservePools[1]:
    // drippedFromStakeAmount = (stakeAmount - pendingUnstakesAmount) * dripRate = 180.5e6 * 0.05 = 9.025e6
    // drippedFromDepositAmount = (depositAmount - pendingWithdrawalsAmount) * dripRate = 19e6 * 0.05 = 0.95e6

    IERC20 asset1_ = IERC20(address(component.getReservePool(0).asset));
    IERC20 asset2_ = IERC20(address(component.getReservePool(1).asset));

    // Set-up owner and expected events.
    address owner_ = _randomAddress();
    _expectEmit();
    emit ClaimedFees(asset1_, 1.25e6 + 1.1875e6, owner_);
    _expectEmit();
    emit ClaimedFees(asset2_, 10.5e6 + 9.975e6, owner_);

    // Claim fees the second time.
    vm.startPrank(address(mockManager));
    component.claimFees(owner_);
    vm.stopPrank();

    // Get reserve pools after claim.
    ReservePool[] memory reservePools_ = component.getReservePools();

    // `owner_` is transferred fee amounts from both fee drips
    assertEq(asset1_.balanceOf(owner_), 1.25e6 + 1.1875e6);
    assertEq(asset2_.balanceOf(owner_), 10.5e6 + 9.975e6);

    // Fee pools are emptied.
    assertEq(reservePools_[0].feeAmount, 0);
    assertEq(reservePools_[1].feeAmount, 0);

    // Stake and deposit amounts are correct.
    assertEq(reservePools_[0].stakeAmount, 100e6); // stakeAmount - totalStakeFeesDripped = 100e6 - 0e6 - 0e6
    assertEq(reservePools_[0].depositAmount, 47_562_500); // depositAmount - totalDepositFeesDripped = 50e6 - 1.25e6 -
      // 1.1875e6
    assertEq(reservePools_[1].stakeAmount, 181_475_000); // stakeAmount - totalStakeFeesDripped = 200e6 - 9.5e6 -
      // 9.025e6
    assertEq(reservePools_[1].depositAmount, 18_050_000); // depositAmount - totalDepositFeesDripped = 20e6 - 1e6 -
      // 0.95e6

    // Asset pools are updated.
    assertEq(component.getAssetPool(asset1_).amount, 150e6 - 1.25e6 - 1.1875e6);
    assertEq(component.getAssetPool(asset2_).amount, 220e6 - 10.5e6 - 9.975e6);
  }

  function testFuzz_claimFees(uint64 timeElapsed_) public {
    _setUpDefault();

    skip(timeElapsed_);
    ReservePool[] memory oldReservePools_ = component.getReservePools();

    address owner_ = _randomAddress();
    vm.startPrank(address(mockManager));
    component.claimFees(owner_);
    vm.stopPrank();

    ReservePool[] memory newReservePools_ = component.getReservePools();
    for (uint16 i = 0; i < newReservePools_.length; i++) {
      IERC20 asset_ = newReservePools_[i].asset;
      assertLe(newReservePools_[i].stakeAmount, oldReservePools_[i].stakeAmount);
      assertLe(newReservePools_[i].depositAmount, oldReservePools_[i].depositAmount);
      assertEq(newReservePools_[i].pendingUnstakesAmount, oldReservePools_[i].pendingUnstakesAmount);
      assertEq(newReservePools_[i].pendingWithdrawalsAmount, oldReservePools_[i].pendingWithdrawalsAmount);
      assertEq(newReservePools_[i].feeAmount, 0);
      // New fees transferred to owner are equal to the difference in the stake and deposit amount pools.
      uint256 newFeesTransferred_ = oldReservePools_[i].stakeAmount - newReservePools_[i].stakeAmount
        + oldReservePools_[i].depositAmount - newReservePools_[i].depositAmount;
      assertEq(asset_.balanceOf(owner_), oldReservePools_[i].feeAmount + newFeesTransferred_);
    }
  }

  function test_claimFeesWithNewReserveAssets() public {
    _setUpConcrete();

    // Add new reserve pool.
    MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
    ReservePool memory reservePool_ = ReservePool({
      asset: IERC20(address(mockAsset_)),
      stkToken: IReceiptToken(address(0)),
      depositToken: IReceiptToken(address(0)),
      stakeAmount: 10_000,
      depositAmount: 10_000,
      pendingUnstakesAmount: 9000,
      pendingWithdrawalsAmount: 10_000,
      feeAmount: 50,
      rewardsPoolsWeight: 0
    });
    component.mockAddReservePool(reservePool_);
    component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: 10_000 + 10_000 + 50}));
    mockAsset_.mint(address(component), 10_000 + 10_000 + 50);

    address owner_ = _randomAddress();
    vm.startPrank(address(mockManager));
    component.claimFees(owner_);
    vm.stopPrank();

    // Make sure owner received rewards from new reserve asset pool.
    // totalExistingFeeAmount = 50
    // newDrippedDepositFees = (stakeAmount - pendingUnstakesAmount) * dripRate = (10_000 - 9_000) * 0.05
    // newDrippedStakeFees = (depositAmount - pendingWithdrawalsAmount) * dripRate = (10_000 - 10_000) * 0.05
    // totalNewFeeAmount = newDrippedStakeFees + newDrippedDepositFees = 50
    // totalFeeAmount = totalExistingFeeAmount + totalNewFeeAmount = 50 + 50
    assertEq(mockAsset_.balanceOf(owner_), 100);

    // Make sure reserve pools reflects the new reserve pool.
    ReservePool[] memory reservePools_ = component.getReservePools();
    assertEq(address(reservePools_[2].asset), address(mockAsset_));
    assertEq(reservePools_[2].stakeAmount, 9950); // stakeAmount - feeAmount = 10_000 - 50
    assertEq(reservePools_[2].depositAmount, 10_000); // depositAmount - feeAmount = 10_000 - 0
    assertEq(reservePools_[2].pendingUnstakesAmount, 9000);
    assertEq(reservePools_[2].pendingWithdrawalsAmount, 10_000);
    assertEq(reservePools_[2].feeAmount, 0);
  }

  function test_claimFeesTwice() public {
    _setUpDefault();

    // Someone claims fees.
    address owner_ = _randomAddress();
    vm.startPrank(address(mockManager));
    component.claimFees(owner_);
    ReservePool[] memory oldReservePools_ = component.getReservePools();
    vm.stopPrank();

    // Someone claims fees again, with no time elapsed.
    address newOwner_ = _randomAddress();
    vm.startPrank(address(mockManager));
    component.claimFees(owner_);
    ReservePool[] memory newReservePools_ = component.getReservePools();
    vm.stopPrank();

    // Reserve pools are unchanged.
    assertEq(oldReservePools_, newReservePools_);
    // New owner receives no reserve assets.
    for (uint16 i = 0; i < newReservePools_.length; i++) {
      assertEq(newReservePools_[i].asset.balanceOf(newOwner_), 0);
    }
  }

  function testFuzz_RevertOnNonManagerCall(address caller_, address owner_) public {
    _setUpDefault();
    vm.assume(caller_ != address(mockManager));

    vm.prank(caller_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    component.claimFees(owner_);
  }
}

contract TestableFeesHandler is RewardsHandler, Depositor, FeesHandler {
  constructor(IManager manager_) {
    cozyManager = manager_;
  }

  // -------- Mock setters --------
  function mockSetLastDripTime(uint256 lastDripTime_) external {
    dripTimes.lastFeesDripTime = uint128(lastDripTime_);
  }

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) external {
    reservePools.push(reservePool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  // -------- Mock getters --------
  function getReservePools() external view returns (ReservePool[] memory) {
    return reservePools;
  }

  function getLastDripTime() external view returns (uint256) {
    return dripTimes.lastFeesDripTime;
  }

  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  // -------- Overridden abstract function placeholders --------
  function _updateUnstakesAfterTrigger(
    uint16, /* reservePoolId_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint16, /* reservePoolId_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override {
    __readStub__();
  }
}
