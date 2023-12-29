// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IDepositorErrors} from "../src/interfaces/IDepositorErrors.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {AssetPool, ReservePool, UndrippedRewardPool} from "../src/lib/structs/Pools.sol";
import {UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

enum DepositType {
  RESERVE,
  REWARDS
}

abstract contract DepositorUnitTest is TestBase {
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);
  MockERC20 mockReserveDepositToken = new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6);
  MockERC20 mockRewardPoolDepositToken = new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6);
  TestableDepositor component = new TestableDepositor();

  /// @dev Emitted when a user stakes.
  event Deposited(address indexed caller_, address indexed receiver_, uint256 amount_, uint256 depositTokenAmount_);

  uint256 initialSafetyModuleBal = 200e18;

  // Test contract specific variables.
  DepositType depositType;
  MockERC20 mockDepositToken;

  function setUp() public {
    ReservePool memory initialReservePool_ = ReservePool({
      asset: IERC20(address(mockAsset)),
      stkToken: IReceiptToken(address(0)),
      depositToken: IReceiptToken(address(mockReserveDepositToken)),
      stakeAmount: 100e18,
      depositAmount: 50e18,
      pendingRedemptionsAmount: 0,
      feeAmount: 0,
      rewardsPoolsWeight: 1e4
    });
    UndrippedRewardPool memory initialUndrippedRewardPool_ = UndrippedRewardPool({
      asset: IERC20(address(mockAsset)),
      depositToken: IReceiptToken(address(mockRewardPoolDepositToken)),
      dripModel: IDripModel(address(0)),
      amount: 50e18
    });
    AssetPool memory initialAssetPool_ = AssetPool({amount: initialSafetyModuleBal});
    component.mockAddReservePool(initialReservePool_);
    component.mockAddUndrippedRewardPool(initialUndrippedRewardPool_);
    component.mockAddAssetPool(IERC20(address(mockAsset)), initialAssetPool_);
  }

  function _deposit(
    DepositType depositType_,
    bool withoutTransfer_,
    uint16 poolId_,
    uint256 amountToDeposit_,
    address receiver_,
    address depositor_
  ) internal returns (uint256 depositTokenAmount_) {
    if (depositType_ == DepositType.RESERVE) {
      if (withoutTransfer_) {
        depositTokenAmount_ = component.depositReserveAssetsWithoutTransfer(poolId_, amountToDeposit_, receiver_);
      } else {
        depositTokenAmount_ = component.depositReserveAssets(poolId_, amountToDeposit_, receiver_, depositor_);
      }
    } else {
      if (withoutTransfer_) {
        depositTokenAmount_ = component.depositRewardAssetsWithoutTransfer(poolId_, amountToDeposit_, receiver_);
      } else {
        depositTokenAmount_ = component.depositRewardAssets(poolId_, amountToDeposit_, receiver_, depositor_);
      }
    }
  }

  function test_depositReserve_DepositTokensAndStorageUpdates() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial asset balance for set.
    mockAsset.mint(address(component), initialSafetyModuleBal);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Approve safety module to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    // `depositToken.totalSupply() == 0`, so should be minted 1-1 with reserve assets deposited.
    uint256 expectedDepositTokenAmount_ = 10e18;
    _expectEmit();
    emit Deposited(depositor_, receiver_, amountToDeposit_, expectedDepositTokenAmount_);

    vm.prank(depositor_);
    uint256 depositTokenAmount_ = _deposit(depositType, false, 0, amountToDeposit_, receiver_, depositor_);

    assertEq(depositTokenAmount_, expectedDepositTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    UndrippedRewardPool memory finalUndrippedRewardPool_ = component.getUndrippedRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // No change
    assertEq(finalReservePool_.stakeAmount, 100e18);
    if (depositType == DepositType.RESERVE) {
      // 50e18 + 10e18
      assertEq(finalReservePool_.depositAmount, 60e18);
    } else {
      // No change
      assertEq(finalReservePool_.depositAmount, 50e18);
    }
    if (depositType == DepositType.REWARDS) {
      // 50e18 + 10e18
      assertEq(finalUndrippedRewardPool_.amount, 60e18);
    } else {
      // No change
      assertEq(finalUndrippedRewardPool_.amount, 50e18);
    }
    // 200e18 + 10e18
    assertEq(finalAssetPool_.amount, 210e18);
    assertEq(mockAsset.balanceOf(address(component)), 210e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockDepositToken.balanceOf(receiver_), expectedDepositTokenAmount_);
  }

  function test_depositReserve_DepositTokensAndStorageUpdatesNonZeroSupply() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 20e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), initialSafetyModuleBal);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Mint/burn some depositTokens.
    uint256 initialDepositTokenSupply_ = 50e18;
    mockDepositToken.mint(address(0), initialDepositTokenSupply_);
    // Approve safety module to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    // `depositToken.totalSupply() == 50e18`, so we have (20e18 / 50e18) * 50e18 = 20e18.
    uint256 expectedDepositTokenAmount_ = 20e18;
    _expectEmit();
    emit Deposited(depositor_, receiver_, amountToDeposit_, expectedDepositTokenAmount_);

    vm.prank(depositor_);
    uint256 depositTokenAmount_ = _deposit(depositType, false, 0, amountToDeposit_, receiver_, depositor_);

    assertEq(depositTokenAmount_, expectedDepositTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    UndrippedRewardPool memory finalUndrippedRewardPool_ = component.getUndrippedRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));

    // No change
    assertEq(finalReservePool_.stakeAmount, 100e18);
    if (depositType == DepositType.RESERVE) {
      // 50e18 + 20e18
      assertEq(finalReservePool_.depositAmount, 70e18);
    } else {
      // No change
      assertEq(finalReservePool_.depositAmount, 50e18);
    }
    if (depositType == DepositType.REWARDS) {
      // 50e18 + 20e18
      assertEq(finalUndrippedRewardPool_.amount, 70e18);
    } else {
      // No change
      assertEq(finalUndrippedRewardPool_.amount, 50e18);
    }
    // 200e18 + 20e18
    assertEq(finalAssetPool_.amount, 220e18);
    assertEq(mockAsset.balanceOf(address(component)), 220e18);
    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockDepositToken.balanceOf(receiver_), expectedDepositTokenAmount_);
  }

  function testFuzz_depositReserve_RevertSafetyModulePaused(uint256 amountToDeposit_) external {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);

    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint216).max);

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Mint/burn some depositTokens.
    uint256 initialDepositTokenSupply_ = 50e18;
    mockDepositToken.mint(address(0), initialDepositTokenSupply_);
    // Approve safety module to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(depositor_);
    _deposit(depositType, false, 0, amountToDeposit_, receiver_, depositor_);
  }

  function test_depositReserve_RevertOutOfBoundsReservePoolId() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    vm.prank(depositor_);
    _deposit(depositType, false, 1, 10e18, receiver_, depositor_);
  }

  function testFuzz_depositReserve_RevertInsufficientAssetsAvailable(uint256 amountToDeposit_) external {
    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint216).max);

    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint insufficient assets for depositor.
    mockAsset.mint(depositor_, amountToDeposit_ - 1);
    // Approve safety module to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(depositor_);
    _deposit(depositType, false, 0, amountToDeposit_, receiver_, depositor_);
  }

  function test_depositReserveAssetsWithoutTransfer_DepositTokensAndStorageUpdates() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 10e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), initialSafetyModuleBal);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Transfer to safety module.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    // `depositToken.totalSupply() == 0`, so should be minted 1-1 with reserve assets deposited.
    uint256 expectedDepositTokenAmount_ = 10e18;
    _expectEmit();
    emit Deposited(depositor_, receiver_, amountToDeposit_, expectedDepositTokenAmount_);

    vm.prank(depositor_);
    uint256 depositTokenAmount_ = _deposit(depositType, true, 0, amountToDeposit_, receiver_, receiver_);

    assertEq(depositTokenAmount_, expectedDepositTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    UndrippedRewardPool memory finalUndrippedRewardPool_ = component.getUndrippedRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // No change
    assertEq(finalReservePool_.stakeAmount, 100e18);
    if (depositType == DepositType.RESERVE) {
      // 50e18 + 10e18
      assertEq(finalReservePool_.depositAmount, 60e18);
    } else {
      // No change
      assertEq(finalReservePool_.depositAmount, 50e18);
    }
    if (depositType == DepositType.REWARDS) {
      // 50e18 + 10e18
      assertEq(finalUndrippedRewardPool_.amount, 60e18);
    } else {
      // No change
      assertEq(finalUndrippedRewardPool_.amount, 50e18);
    }
    // 200e18 + 10e18
    assertEq(finalAssetPool_.amount, 210e18);
    assertEq(mockAsset.balanceOf(address(component)), 210e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockDepositToken.balanceOf(receiver_), expectedDepositTokenAmount_);
  }

  function test_depositReserveAssetsWithoutTransfer_DepositTokensAndStorageUpdatesNonZeroSupply() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 20e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), initialSafetyModuleBal);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Mint/burn some depositTokens.
    uint256 initialDepositTokenSupply_ = 50e18;
    mockDepositToken.mint(address(0), initialDepositTokenSupply_);
    // Transfer to safety module.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    // `depositToken.totalSupply() == 50e18`, so we have (20e18 / 50e18) * 50e18 = 20e18.
    uint256 expectedDepositTokenAmount_ = 20e18;
    _expectEmit();
    emit Deposited(depositor_, receiver_, amountToDeposit_, expectedDepositTokenAmount_);

    vm.prank(depositor_);
    uint256 depositTokenAmount_ = _deposit(depositType, true, 0, amountToDeposit_, receiver_, receiver_);

    assertEq(depositTokenAmount_, expectedDepositTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    UndrippedRewardPool memory finalUndrippedRewardPool_ = component.getUndrippedRewardPool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // No change
    assertEq(finalReservePool_.stakeAmount, 100e18);
    if (depositType == DepositType.RESERVE) {
      // 50e18 + 20e18
      assertEq(finalReservePool_.depositAmount, 70e18);
    } else {
      // No change
      assertEq(finalReservePool_.depositAmount, 50e18);
    }
    if (depositType == DepositType.REWARDS) {
      // 50e18 + 20e18
      assertEq(finalUndrippedRewardPool_.amount, 70e18);
    } else {
      // No change
      assertEq(finalUndrippedRewardPool_.amount, 50e18);
    }
    // 200e18 + 20e18
    assertEq(finalAssetPool_.amount, 220e18);
    assertEq(mockAsset.balanceOf(address(component)), 220e18);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockDepositToken.balanceOf(receiver_), expectedDepositTokenAmount_);
  }

  function testFuzz_depositReserveAssetsWithoutTransfer_RevertSafetyModulePaused(uint256 amountToDeposit_) external {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);

    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint216).max);

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Mint/burn some depositTokens.
    uint256 initialDepositTokenSupply_ = 50e18;
    mockDepositToken.mint(address(0), initialDepositTokenSupply_);
    // Transfer to safety module.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(depositor_);
    _deposit(depositType, true, 0, amountToDeposit_, receiver_, receiver_);
  }

  function test_depositReserveAssetsWithoutTransfer_RevertOutOfBoundsReservePoolId() external {
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    _deposit(depositType, true, 1, 10e18, receiver_, receiver_);
  }

  function testFuzz_depositReserveAssetsWithoutTransfer_RevertInsufficientAssetsAvailable(uint256 amountToDeposit_)
    external
  {
    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint256).max);
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint insufficient assets for depositor.
    mockAsset.mint(depositor_, amountToDeposit_ - 1);
    // Transfer to safety module.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_ - 1);

    if (amountToDeposit_ - 1 < initialSafetyModuleBal) _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    else vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    vm.prank(depositor_);
    _deposit(depositType, true, 0, amountToDeposit_, receiver_, address(0));
  }
}

contract ReservePoolDepositorUnitTest is DepositorUnitTest {
  constructor() {
    depositType = DepositType.RESERVE;
    mockDepositToken = mockReserveDepositToken;
  }
}

contract RewardPoolDepositorUnitTest is DepositorUnitTest {
  constructor() {
    depositType = DepositType.REWARDS;
    mockDepositToken = mockRewardPoolDepositToken;
  }
}

contract TestableDepositor is Depositor {
  // -------- Mock setters --------
  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) external {
    reservePools.push(reservePool_);
  }

  function mockAddUndrippedRewardPool(UndrippedRewardPool memory rewardPool_) external {
    undrippedRewardPools.push(rewardPool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  // -------- Mock getters --------
  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getUndrippedRewardPool(uint16 undrippedRewardPoolId_) external view returns (UndrippedRewardPool memory) {
    return undrippedRewardPools[undrippedRewardPoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  // -------- Overridden abstract function placeholders --------

  function claimRewards(uint16, /* reservePoolId_ */ address /* receiver_ */ ) public view override {
    __readStub__();
  }

  function dripRewards() public view override {
    __readStub__();
  }

  function dripFees() public view override {
    __readStub__();
  }

  function _getNextDripAmount(
    uint256, /* totalBaseAmount_ */
    IDripModel, /* dripModel_ */
    uint256, /* lastDripTime_ */
    uint256 /* deltaT_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint16, /* reservePoolId_ */
    uint128, /* oldAmount_ */
    uint128 /* slashAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _updateUnstakesAfterTrigger(
    uint16, /* reservePoolId_ */
    uint128, /* oldStakeAmount_ */
    uint128 /* slashAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _updateUserRewards(
    uint256 userStkTokenBalance_,
    mapping(uint16 => uint256) storage claimableRewardsIndices_,
    UserRewardsData[] storage userRewards_
  ) internal override {
    __readStub__();
  }
}
