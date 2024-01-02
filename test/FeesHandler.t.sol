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
import {Staker} from "../src/lib/Staker.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {SafeCastLib} from "../src/lib/SafeCastLib.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {Ownable} from "../src/lib/Ownable.sol";
import {AssetPool, ReservePool, UndrippedRewardPool} from "../src/lib/structs/Pools.sol";
import {UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {IdLookup} from "../src/lib/structs/Pools.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockStkToken} from "./utils/MockStkToken.sol";
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
  uint256 constant DEFAULT_REWARDS_DRIP_RATE = 0.01e18;
  uint256 constant DEFAULT_NUM_RESERVE_POOLS = 5;

  event ClaimedFees(IERC20 indexed reserveAsset_, uint256 feeAmount_, address indexed owner_);

  function setUp() public {
    mockFeesDripModel = new MockDripModel(DEFAULT_FEES_DRIP_RATE);
    mockManager.setFeeDripModel(IDripModel(address(mockFeesDripModel)));
    component.mockSetLastDripTime(block.timestamp);
  }

  function _setUpReservePools(uint256 numReservePools_) internal {
    for (uint16 i = 0; i < numReservePools_; i++) {
      IReceiptToken stkToken_ =
        IReceiptToken(address(new MockStkToken("Mock Cozy  stkToken", "cozyStk", 6, ISafetyModule(address(component)))));
      MockERC20 mockAsset_ = new MockERC20("Mock Asset", "MOCK", 6);
      uint256 stakeAmount_ = _randomUint256() % 500_000_000;
      uint256 depositAmount_ = _randomUint256() % 500_000_000;
      uint256 pendingRedemptionsAmount_ = _randomUint256() % 500_000_000;
      pendingRedemptionsAmount_ = bound(pendingRedemptionsAmount_, 0, stakeAmount_ + depositAmount_);
      ReservePool memory reservePool_ = ReservePool({
        asset: IERC20(address(mockAsset_)),
        stkToken: stkToken_,
        depositToken: IReceiptToken(address(0)),
        stakeAmount: stakeAmount_,
        depositAmount: depositAmount_,
        pendingRedemptionsAmount: pendingRedemptionsAmount_,
        feeAmount: 0,
        rewardsPoolsWeight: (MathConstants.ZOC / numReservePools_).safeCastTo16()
      });
      component.mockRegisterStkToken(i, stkToken_);
      component.mockAddReservePool(reservePool_);

      // Mint safety module stakeAmount + depositAmount + pendingRedemptionsAmount.
      mockAsset_.mint(address(component), stakeAmount_ + depositAmount_ + pendingRedemptionsAmount_);
      component.mockAddAssetPool(
        IERC20(address(mockAsset_)), AssetPool({amount: stakeAmount_ + depositAmount_ + pendingRedemptionsAmount_})
      );

      // Mint stkTokens and send to zero address to floor supply.
      stkToken_.mint(address(0), _randomUint256() % 500_000_000);
    }
  }

  function _setUpDefault() internal {
    _setUpReservePools(DEFAULT_NUM_RESERVE_POOLS);
  }

  function _setUpConcrete() internal {
    skip(10);

    // Set-up two reserve pools.
    IReceiptToken stkToken1_ =
      IReceiptToken(address(new MockStkToken("Mock Cozy  stkToken", "cozyStk", 6, ISafetyModule(address(component)))));
    component.mockRegisterStkToken(0, stkToken1_);

    MockERC20 mockAsset1_ = new MockERC20("Mock Asset", "MOCK", 6);
    ReservePool memory reservePool1_ = ReservePool({
      asset: IERC20(address(mockAsset1_)),
      stkToken: stkToken1_,
      depositToken: IReceiptToken(address(0)),
      stakeAmount: 100e6,
      depositAmount: 50e6,
      pendingRedemptionsAmount: 100e6,
      feeAmount: 0,
      rewardsPoolsWeight: 0.1e4 // 10% weight
    });
    stkToken1_.mint(address(0), 0.1e18);
    component.mockAddReservePool(reservePool1_);
    mockAsset1_.mint(address(component), 250e6);
    component.mockAddAssetPool(IERC20(address(mockAsset1_)), AssetPool({amount: 250e6}));

    IReceiptToken stkToken2_ =
      IReceiptToken(address(new MockStkToken("Mock Cozy  stkToken", "cozyStk", 6, ISafetyModule(address(component)))));
    component.mockRegisterStkToken(1, stkToken2_);

    MockERC20 mockAsset2_ = new MockERC20("Mock Asset", "MOCK", 6);
    ReservePool memory reservePool2_ = ReservePool({
      asset: IERC20(address(mockAsset2_)),
      stkToken: stkToken2_,
      depositToken: IReceiptToken(address(0)),
      stakeAmount: 200e6,
      depositAmount: 20e6,
      pendingRedemptionsAmount: 10e6,
      feeAmount: 0,
      rewardsPoolsWeight: 0.9e4 // 90% weight
    });
    stkToken2_.mint(address(0), 10);
    component.mockAddReservePool(reservePool2_);
    mockAsset2_.mint(address(component), 230e6);
    component.mockAddAssetPool(IERC20(address(mockAsset2_)), AssetPool({amount: 230e6}));
  }

  function _calculateExpectedDripQuantity(uint256 poolAmount_, uint256 dripFactor_) internal pure returns (uint256) {
    return poolAmount_.mulWadDown(dripFactor_);
  }
}

contract FeesHandlerDripUnitTest is FeesHandlerUnitTest {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  function testFuzz_noDripIfSafetyModuleIsPaused(uint64 timeElapsed_) public {
    _setUpDefault();
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
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

  function testFuzz_getFeeAllocation(uint256 totalDrippedFees_, uint256 stakeAmount_, uint256 depositAmount_) public {
    stakeAmount_ = bound(stakeAmount_, 0, type(uint128).max);
    depositAmount_ = bound(depositAmount_, 0, type(uint128).max);
    totalDrippedFees_ = bound(totalDrippedFees_, 0, stakeAmount_ + depositAmount_); // totalDrippedFees_ <= stakeAmount
      // + depositAmount - pendingRedemptionsAmount

    (uint256 drippedFromStakeAmount_, uint256 drippedFromDepositAmount_) =
      component.getFeeAllocation(totalDrippedFees_, stakeAmount_, depositAmount_);

    assertGe(stakeAmount_ - drippedFromStakeAmount_, 0);
    assertGe(depositAmount_ - drippedFromDepositAmount_, 0);
    assertLe(drippedFromStakeAmount_ + drippedFromDepositAmount_, totalDrippedFees_);
  }

  function testFuzz_getFeeAllocationZeroReserves(uint256 totalDrippedFees_) public {
    (uint256 drippedFromStakeAmount_, uint256 drippedFromDepositAmount_) =
      component.getFeeAllocation(totalDrippedFees_, 0, 0);

    assertEq(drippedFromStakeAmount_, 0);
    assertEq(drippedFromDepositAmount_, 0);
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
      // totalBaseAmount = stakeAmount + depositAmount - pendingRedemptionsAmount = 100e6 + 50e6 - 100e6 = 50e6
      // totalFeeAmount = totalBaseAmount * dripRate = 50e6 * 0.05 = 2.5e6
      // stakeRatio = originalStakeAmount / totalAmount = 100e6 / 150e6 = 2/3
      expectedPool1_.stakeAmount = 98_333_334; // stakeAmount = originalStakeAmount - totalFeeAmount * stakeRatio
      expectedPool1_.depositAmount = 49_166_666; // depositAmount = originalDepositAmount - totalFeeAmount * (1 -
        // stakeRatio)
      expectedPool1_.feeAmount = 2.5e6; // totalFeeAmount
      expectedPool1_.pendingRedemptionsAmount = concreteReservePools_[0].pendingRedemptionsAmount;
      expectedPool1_.rewardsPoolsWeight = concreteReservePools_[0].rewardsPoolsWeight;
      expectedReservePools_[0] = expectedPool1_;
    }
    {
      ReservePool memory expectedPool2_;
      expectedPool2_.asset = concreteReservePools_[1].asset;
      expectedPool2_.stkToken = concreteReservePools_[1].stkToken;
      expectedPool2_.depositToken = concreteReservePools_[1].depositToken;
      // totalBaseAmount = stakeAmount + depositAmount - pendingRedemptionsAmount = 200e6 + 20e6 - 10e6 = 210e6
      // totalFeeAmount = totalBaseAmount * dripRate = 210e6 * 0.05 = 10.5e6
      // stakeRatio = originalStakeAmount / totalAmount = 200e6 / 220e6 = 10/11
      expectedPool2_.stakeAmount = 190_454_546; // stakeAmount = originalStakeAmount - totalFeeAmount * stakeRatio
      expectedPool2_.depositAmount = 19_045_454; // depositAmount = originalDepositAmount - totalFeeAmount * (1 -
        // stakeRatio)
      expectedPool2_.feeAmount = 10.5e6; // totalFeeAmount
      expectedPool2_.pendingRedemptionsAmount = concreteReservePools_[1].pendingRedemptionsAmount;
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
      // Set up test cases.
      ReservePool memory expectedReservePool_ = expectedReservePools_[i];
      uint256 totalBaseAmount_ = expectedReservePool_.stakeAmount + expectedReservePool_.depositAmount
        - expectedReservePool_.pendingRedemptionsAmount;
      uint256 totalDrippedFees_ = _calculateExpectedDripQuantity(totalBaseAmount_, dripRate_);
      (uint256 drippedFromStakeAmount_, uint256 drippedFromDepositAmount_) = component.getFeeAllocation(
        totalDrippedFees_, expectedReservePool_.stakeAmount, expectedReservePool_.depositAmount
      );

      expectedReservePool_.stakeAmount -= drippedFromStakeAmount_;
      expectedReservePool_.depositAmount -= drippedFromDepositAmount_;
      expectedReservePool_.feeAmount += drippedFromStakeAmount_ + drippedFromDepositAmount_;

      expectedReservePools_[i] = expectedReservePool_;
    }

    component.dripFees();
    assertEq(component.getLastDripTime(), block.timestamp);
    assertEq(component.getReservePools(), expectedReservePools_);
  }
}

contract FeesHandlerClaimUnitTest is FeesHandlerUnitTest {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  function test_claimFeesConcrete() public {
    _setUpConcrete();

    // Drip fees once and skip some time, so it will drip again on the next fees claim.
    component.dripFees();
    skip(1000);

    // In the first drip, for reservePool[0]:
    //  totalBaseAmount = stakeAmount + depositAmount - pendingRedemptionsAmount = 100e6 + 50e6 - 100e6 = 50e6
    //  totalFeeAmount = totalBaseAmount * dripRate = 50e6 * 0.05 = 2.5e6
    //  stakeRatio = originalStakeAmount / totalAmount = 100e6 / 150e6 = 2/3

    // In the first drip, for reservePool[1]:
    //  totalBaseAmount = stakeAmount + depositAmount - pendingRedemptionsAmount = 200e6 + 20e6 - 10e6 = 210e6
    //  totalFeeAmount = totalBaseAmount * dripRate = 210e6 * 0.05 = 10.5e6
    //  stakeRatio = originalStakeAmount / totalAmount = 200e6 / 220e6 = 10/11

    // In the second drip, for reservePool[0]:
    //  totalBaseAmount = stakeAmount + depositAmount - pendingRedemptionsAmount = 98_333_334 + 49_166_666 - 100e6 =
    // 47.5e6
    //  totalFeeAmount = totalBaseAmount * dripRate = 47.5e6 * 0.05 = 2.375e6
    //  stakeRatio = originalStakeAmount / totalAmount = 98_333_334 / 147_500_000 = 0.66666666712

    // In the second drip, for reservePool[1]:
    //  totalBaseAmount = stakeAmount + depositAmount - pendingRedemptionsAmount = 190_454_546 + 19_045_454 - 10e6 =
    // 199.5e6
    //  totalFeeAmount = totalBaseAmount * dripRate = 199.5e6 * 0.05 = 9.975e6
    //  stakeRatio = originalStakeAmount / totalAmount = 190_454_546 / 209.5e6 = 0.9090909117

    // Get reserve pools.
    ReservePool[] memory initialReservePools_ = component.getReservePools();
    IERC20 asset1_ = IERC20(address(initialReservePools_[0].asset));
    IERC20 asset2_ = IERC20(address(initialReservePools_[1].asset));

    // Set-up owner and expected events.
    address owner_ = _randomAddress();
    _expectEmit();
    emit ClaimedFees(asset1_, 2.5e6 + 2.375e6, owner_);
    _expectEmit();
    emit ClaimedFees(asset2_, 10.5e6 + 9.975e6, owner_);

    vm.startPrank(address(mockManager));
    component.claimFees(owner_);
    vm.stopPrank();

    // Get reserve pools after claim.
    ReservePool[] memory reservePools_ = component.getReservePools();

    // `owner_` is transferred fee amounts from both fee drips
    assertEq(asset1_.balanceOf(owner_), 2.5e6 + 2.375e6);
    assertEq(asset2_.balanceOf(owner_), 10.5e6 + 9.975e6);

    // Fee pools are emptied.
    assertEq(reservePools_[0].feeAmount, 0);
    assertEq(reservePools_[1].feeAmount, 0);

    // Fee pools are emptied.
    assertEq(reservePools_[0].stakeAmount, 96_750_001); // stakeAmount - feeAmount * stakeRatio = 98_333_334 - 2.375e6 *
      // 0.66666666712
    assertEq(reservePools_[0].depositAmount, 48_374_999); // depositAmount - feeAmount * (1 - stakeRatio) = 49_166_666 -
      // 2.375e6 * (1 - 0.66666666712)
    assertEq(reservePools_[1].stakeAmount, 181_386_365); // stakeAmount - feeAmount * stakeRatio = 190_454_546 - 9.975e6
      // * 9090909117
    assertEq(reservePools_[1].depositAmount, 18_138_635); // depositAmount - feeAmount * (1 - stakeRatio) = 19_045_454 -
      // 9.975e6 * (1 - 0.9090909117)

    // Asset pools are updated. Initially, assetPool[asset1_].amount = 250e6 and assetPool[asset2_].amount = 230e6.
    assertEq(component.getAssetPool(asset1_).amount, 250e6 - 2.5e6 - 2.375e6);
    assertEq(component.getAssetPool(asset2_).amount, 230e6 - 10.5e6 - 9.975e6);
  }

  function testFuzz_claimFees(uint64 timeElapsed_) public {
    _setUpDefault();

    skip(timeElapsed_);
    ReservePool[] memory oldReservePools_ = component.getReservePools();

    // User claims rewards.
    address owner_ = _randomAddress();
    vm.startPrank(address(mockManager));
    component.claimFees(owner_);
    vm.stopPrank();

    // Check receiver balances and user rewards data.
    ReservePool[] memory newReservePools_ = component.getReservePools();
    for (uint16 i = 0; i < newReservePools_.length; i++) {
      IERC20 asset_ = newReservePools_[i].asset;
      assertLe(newReservePools_[i].stakeAmount, oldReservePools_[i].stakeAmount);
      assertLe(newReservePools_[i].depositAmount, oldReservePools_[i].depositAmount);
      assertEq(newReservePools_[i].pendingRedemptionsAmount, oldReservePools_[i].pendingRedemptionsAmount);
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
      pendingRedemptionsAmount: 19_000,
      feeAmount: 50,
      rewardsPoolsWeight: 0
    });
    component.mockAddReservePool(reservePool_);
    mockAsset_.mint(address(component), 10_000 + 10_000 + 50);
    component.mockAddAssetPool(IERC20(address(mockAsset_)), AssetPool({amount: 10_000 + 10_000 + 50}));

    address owner_ = _randomAddress();
    vm.startPrank(address(mockManager));
    component.claimFees(owner_);
    vm.stopPrank();

    // Make sure owner received rewards from new reserve asset pool.
    // totalNewFeeAmountFromNewPool = 50; // (stakeAmount + depositAmount - pendingRedemptionsAmount) * dripRate =
    // (10_000 + 10_000 - 19_000) * 0.05
    // totalFeeAmount = totalNewFeeAmountFromNewPool + totalExistinFeeAmount = 50 + 50
    assertEq(mockAsset_.balanceOf(owner_), 100);

    // Make sure reserve pools reflects the new reserve pool.
    ReservePool[] memory reservePools_ = component.getReservePools();
    assertEq(address(reservePools_[2].asset), address(mockAsset_));
    assertEq(reservePools_[2].stakeAmount, 9975); // stakeAmount - feeAmount * stakeRatio = 10_000 - 50 * 0.5
    assertEq(reservePools_[2].depositAmount, 9975);
    assertEq(reservePools_[2].pendingRedemptionsAmount, 19_000);
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
    lastFeesDripTime = lastDripTime_;
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

  function mockRegisterStkToken(uint16 reservePoolId_, IReceiptToken stkToken_) external {
    stkTokenToReservePoolIds[stkToken_] = IdLookup({index: reservePoolId_, exists: true});
  }

  // -------- Mock getters --------
  function getReservePools() external view returns (ReservePool[] memory) {
    return reservePools;
  }

  function getLastDripTime() external view returns (uint256) {
    return lastFeesDripTime;
  }

  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  // -------- Exposed internal functions --------
  function getFeeAllocation(uint256 totalDrippedFees_, uint256 stakeAmount_, uint256 depositAmount_)
    external
    pure
    returns (uint256 drippedFromStakeAmount_, uint256 drippedFromDepositAmount_)
  {
    return _getFeeAllocation(totalDrippedFees_, stakeAmount_, depositAmount_);
  }

  // -------- Overridden abstract function placeholders --------
  function _updateUnstakesAfterTrigger(
    uint16, /* reservePoolId_ */
    uint128, /* oldStakeAmount_ */
    uint128 /* slashAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint16, /* reservePoolId_ */
    uint128, /* oldStakeAmount_ */
    uint128 /* slashAmount_ */
  ) internal view override {
    __readStub__();
  }
}
