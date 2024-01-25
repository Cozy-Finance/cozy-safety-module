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
import {AssetPool, ReservePool, RewardPool} from "../src/lib/structs/Pools.sol";
import {UserRewardsData, ClaimableRewardsData} from "../src/lib/structs/Rewards.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

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
  event Deposited(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed depositToken_,
    uint256 amount_,
    uint256 depositTokenAmount_
  );

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
      pendingUnstakesAmount: 0,
      pendingWithdrawalsAmount: 0,
      feeAmount: 0,
      rewardsPoolsWeight: 1e4,
      maxSlashPercentage: MathConstants.WAD,
      lastFeesDripTime: uint128(block.timestamp)
    });
    RewardPool memory initialRewardPool_ = RewardPool({
      asset: IERC20(address(mockAsset)),
      depositToken: IReceiptToken(address(mockRewardPoolDepositToken)),
      dripModel: IDripModel(address(0)),
      undrippedRewards: 50e18,
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });
    AssetPool memory initialAssetPool_ = AssetPool({amount: initialSafetyModuleBal});
    component.mockAddReservePool(initialReservePool_);
    component.mockAddRewardPool(initialRewardPool_);
    component.mockAddAssetPool(IERC20(address(mockAsset)), initialAssetPool_);
    deal(address(mockAsset), address(component), initialSafetyModuleBal);
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
    emit Deposited(
      depositor_, receiver_, IReceiptToken(address(mockDepositToken)), amountToDeposit_, expectedDepositTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositTokenAmount_ = _deposit(depositType, false, 0, amountToDeposit_, receiver_, depositor_);

    assertEq(depositTokenAmount_, expectedDepositTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
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
      assertEq(finalRewardPool_.undrippedRewards, 60e18);
    } else {
      // No change
      assertEq(finalRewardPool_.undrippedRewards, 50e18);
    }
    // 200e18 + 10e18
    assertEq(finalAssetPool_.amount, 210e18);
    assertEq(mockAsset.balanceOf(address(component)), 210e18 + initialSafetyModuleBal);

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
    emit Deposited(
      depositor_, receiver_, IReceiptToken(address(mockDepositToken)), amountToDeposit_, expectedDepositTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositTokenAmount_ = _deposit(depositType, false, 0, amountToDeposit_, receiver_, depositor_);

    assertEq(depositTokenAmount_, expectedDepositTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
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
      assertEq(finalRewardPool_.undrippedRewards, 70e18);
    } else {
      // No change
      assertEq(finalRewardPool_.undrippedRewards, 50e18);
    }
    // 200e18 + 20e18
    assertEq(finalAssetPool_.amount, 220e18);
    assertEq(mockAsset.balanceOf(address(component)), 220e18 + initialSafetyModuleBal);
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
    emit Deposited(
      depositor_, receiver_, IReceiptToken(address(mockDepositToken)), amountToDeposit_, expectedDepositTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositTokenAmount_ = _deposit(depositType, true, 0, amountToDeposit_, receiver_, receiver_);

    assertEq(depositTokenAmount_, expectedDepositTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
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
      assertEq(finalRewardPool_.undrippedRewards, 60e18);
    } else {
      // No change
      assertEq(finalRewardPool_.undrippedRewards, 50e18);
    }
    // 200e18 + 10e18
    assertEq(finalAssetPool_.amount, 210e18);
    assertEq(mockAsset.balanceOf(address(component)), 210e18 + initialSafetyModuleBal);

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
    emit Deposited(
      depositor_, receiver_, IReceiptToken(address(mockDepositToken)), amountToDeposit_, expectedDepositTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositTokenAmount_ = _deposit(depositType, true, 0, amountToDeposit_, receiver_, receiver_);

    assertEq(depositTokenAmount_, expectedDepositTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    RewardPool memory finalRewardPool_ = component.getRewardPool(0);
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
      assertEq(finalRewardPool_.undrippedRewards, 70e18);
    } else {
      // No change
      assertEq(finalRewardPool_.undrippedRewards, 50e18);
    }
    // 200e18 + 20e18
    assertEq(finalAssetPool_.amount, 220e18);
    assertEq(mockAsset.balanceOf(address(component)), 220e18 + initialSafetyModuleBal);

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
    amountToDeposit_ = bound(amountToDeposit_, 1, type(uint128).max);
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint insufficient assets for depositor.
    mockAsset.mint(depositor_, amountToDeposit_ - 1);
    // Transfer to safety module.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_ - 1);

    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    vm.prank(depositor_);
    _deposit(depositType, true, 0, amountToDeposit_, receiver_, address(0));
  }

  function test_deposit_RevertZeroShares() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToDeposit_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(depositor_);
    _deposit(depositType, true, 0, amountToDeposit_, receiver_, address(0));
  }

  function test_depositWithoutTransfer_RevertZeroShares() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToDeposit_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(depositor_);
    _deposit(depositType, false, 0, amountToDeposit_, receiver_, address(0));
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

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  // -------- Mock getters --------
  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getRewardPool(uint16 rewardPoolid_) external view returns (RewardPool memory) {
    return rewardPools[rewardPoolid_];
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

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 /* lastDripTime_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _computeNextDripAmount(uint256, /* totalBaseAmount_ */ uint256 /* dripFactor_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint16, /* reservePoolId_ */
    ReservePool storage, /* reservePool_ */
    uint256, /* oldAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _updateUnstakesAfterTrigger(
    uint16, /* reservePoolId_ */
    ReservePool storage, /* reservePool_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _updateUserRewards(
    uint256, /*userStkTokenBalance_*/
    mapping(uint16 => ClaimableRewardsData) storage, /*claimableRewards_*/
    UserRewardsData[] storage /*userRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _dripRewardPool(RewardPool storage /*rewardPool_*/ ) internal view override {
    __readStub__();
  }

  function _dripAndApplyPendingDrippedRewards(
    ReservePool storage, /*reservePool_*/
    mapping(uint16 => ClaimableRewardsData) storage /*claimableRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _dripFeesFromReservePool(ReservePool storage, /*reservePool_*/ IDripModel /*dripModel_*/ )
    internal
    view
    override
  {
    __readStub__();
  }

  function _dripAndResetCumulativeRewardsValues(
    ReservePool[] storage, /*reservePools_*/
    RewardPool[] storage /*rewardPools_*/
  ) internal view override {
    __readStub__();
  }
}
