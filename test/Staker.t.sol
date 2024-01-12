// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "../src/interfaces/IERC20.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IDepositorErrors} from "../src/interfaces/IDepositorErrors.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {Staker} from "../src/lib/Staker.sol";
import {RewardsHandler} from "../src/lib/RewardsHandler.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {AssetPool, ReservePool} from "../src/lib/structs/Pools.sol";
import {UndrippedRewardPool} from "../src/lib/structs/Pools.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

contract StakerUnitTest is TestBase {
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);
  MockERC20 mockStkToken = new MockERC20("Mock Cozy Stake Token", "cozyStk", 6);
  MockERC20 mockDepositToken = new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6);
  TestableStaker component = new TestableStaker();

  event Staked(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed stkToken_,
    uint256 amount_,
    uint256 stkTokenAmount_
  );

  function setUp() public {
    ReservePool memory initialReservePool_ = ReservePool({
      asset: IERC20(address(mockAsset)),
      stkToken: IReceiptToken(address(mockStkToken)),
      depositToken: IReceiptToken(address(mockDepositToken)),
      stakeAmount: 100e18,
      depositAmount: 99e18,
      pendingUnstakesAmount: 0,
      pendingWithdrawalsAmount: 0,
      feeAmount: 0,
      rewardsPoolsWeight: 1e4,
      maxSlashPercentage: MathConstants.WAD
    });
    AssetPool memory initialAssetPool_ = AssetPool({amount: 150e18});
    component.mockAddReservePool(initialReservePool_);
    component.mockAddAssetPool(IERC20(address(mockAsset)), initialAssetPool_);
    component.mockAddUndrippedRewardPool(IERC20(address(mockAsset)));
  }

  function test_stake_StkTokensAndStorageUpdates() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockAsset.mint(staker_, amountToStake_);
    // Approve safety module to spend asset.
    vm.prank(staker_);
    mockAsset.approve(address(component), amountToStake_);

    // `stkToken.totalSupply() == 0`, so should be minted 1-1 with reserve assets staked.
    uint256 expectedStkTokenAmount_ = 20e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountToStake_, expectedStkTokenAmount_);

    vm.prank(staker_);
    uint256 stkTokenAmount_ = component.stake(0, amountToStake_, receiver_, staker_);

    assertEq(stkTokenAmount_, expectedStkTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 100e18 + 20e18
    assertEq(finalReservePool_.stakeAmount, 120e18);
    // No change
    assertEq(finalReservePool_.depositAmount, 99e18);
    // 150e18 + 20e18
    assertEq(finalAssetPool_.amount, 170e18);
    assertEq(mockAsset.balanceOf(address(component)), 170e18);

    assertEq(mockAsset.balanceOf(staker_), 0);
    assertEq(mockStkToken.balanceOf(receiver_), expectedStkTokenAmount_);
  }

  function test_stake_StkTokensAndStorageUpdatesNonZeroSupply() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockAsset.mint(staker_, amountToStake_);
    // Mint/burn some stkTokens.
    uint256 initialStkTokenSupply_ = 50e18;
    mockStkToken.mint(address(0), initialStkTokenSupply_);
    // Approve safety module to spend asset.
    vm.prank(staker_);
    mockAsset.approve(address(component), amountToStake_);

    // `stkToken.totalSupply() == 50e18`, so we have (20e18 / 100e18) * 50e18 = 10e18.
    uint256 expectedStkTokenAmount_ = 10e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountToStake_, expectedStkTokenAmount_);

    vm.prank(staker_);
    uint256 stkTokenAmount_ = component.stake(0, amountToStake_, receiver_, staker_);

    assertEq(stkTokenAmount_, expectedStkTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 100e18 + 20e18
    assertEq(finalReservePool_.stakeAmount, 120e18);
    // 150e18 + 20e18
    assertEq(finalAssetPool_.amount, 170e18);
    assertEq(mockAsset.balanceOf(address(component)), 170e18);

    assertEq(mockAsset.balanceOf(staker_), 0);
    assertEq(mockStkToken.balanceOf(receiver_), expectedStkTokenAmount_);
  }

  function testFuzz_stake_RevertSafetyModulePaused(uint256 amountToStake_) external {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockAsset.mint(staker_, amountToStake_);
    // Mint/burn some stkTokens.
    uint256 initialStkTokenSupply_ = 50e18;
    mockStkToken.mint(address(0), initialStkTokenSupply_);
    // Approve safety module to spend asset.
    vm.prank(staker_);
    mockAsset.approve(address(component), amountToStake_);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);
  }

  function test_stake_RevertOutOfBoundsReservePoolId() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    vm.prank(staker_);
    component.stake(1, 10e18, receiver_, staker_);
  }

  function testFuzz_stake_RevertInsufficientAssetsAvailable(uint256 amountToStake_) external {
    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint insufficient assets for staker.
    mockAsset.mint(staker_, amountToStake_ - 1);
    // Approve safety module to spend asset.
    vm.prank(staker_);
    mockAsset.approve(address(component), amountToStake_);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(staker_);
    component.stake(0, amountToStake_, receiver_, staker_);
  }

  function test_stakeWithoutTransfer_StkTokensAndStorageUpdates() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockAsset.mint(staker_, amountToStake_);
    // Transfer to safety module.
    vm.prank(staker_);
    mockAsset.transfer(address(component), amountToStake_);

    // `stkToken.totalSupply() == 0`, so should be minted 1-1 with reserve assets staked.
    uint256 expectedStkTokenAmount_ = 20e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountToStake_, expectedStkTokenAmount_);

    vm.prank(staker_);
    uint256 stkTokenAmount_ = component.stakeWithoutTransfer(0, amountToStake_, receiver_);

    assertEq(stkTokenAmount_, expectedStkTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 100e18 + 20e18
    assertEq(finalReservePool_.stakeAmount, 120e18);
    // No change
    assertEq(finalReservePool_.depositAmount, 99e18);
    // 150e18 + 20e18
    assertEq(finalAssetPool_.amount, 170e18);
    assertEq(mockAsset.balanceOf(address(component)), 170e18);

    assertEq(mockAsset.balanceOf(staker_), 0);
    assertEq(mockStkToken.balanceOf(receiver_), expectedStkTokenAmount_);
  }

  function test_stakeWithoutTransfer_StkTokensAndStorageUpdatesNonZeroSupply() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToStake_ = 20e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockAsset.mint(staker_, amountToStake_);
    // Mint/burn some stkTokens.
    uint256 initialStkTokenSupply_ = 50e18;
    mockStkToken.mint(address(0), initialStkTokenSupply_);
    // Transfer to safety module.
    vm.prank(staker_);
    mockAsset.transfer(address(component), amountToStake_);

    // `stkToken.totalSupply() == 50e18`, so we have (20e18 / 100e18) * 50e18 = 10e18.
    uint256 expectedStkTokenAmount_ = 10e18;
    _expectEmit();
    emit Staked(staker_, receiver_, IReceiptToken(address(mockStkToken)), amountToStake_, expectedStkTokenAmount_);

    vm.prank(staker_);
    uint256 stkTokenAmount_ = component.stakeWithoutTransfer(0, amountToStake_, receiver_);

    assertEq(stkTokenAmount_, expectedStkTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 100e18 + 20e18
    assertEq(finalReservePool_.stakeAmount, 120e18);
    // No change
    assertEq(finalReservePool_.depositAmount, 99e18);
    // 150e18 + 20e18
    assertEq(finalAssetPool_.amount, 170e18);
    assertEq(mockAsset.balanceOf(address(component)), 170e18);

    assertEq(mockAsset.balanceOf(staker_), 0);
    assertEq(mockStkToken.balanceOf(receiver_), expectedStkTokenAmount_);
  }

  function testFuzz_stakeWithoutTransfer_RevertSafetyModulePaused(uint256 amountToStake_) external {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);

    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint initial balance for staker.
    mockAsset.mint(staker_, amountToStake_);
    // Mint/burn some stkTokens.
    uint256 initialStkTokenSupply_ = 50e18;
    mockStkToken.mint(address(0), initialStkTokenSupply_);
    // Transfer to safety module.
    vm.prank(staker_);
    mockAsset.transfer(address(component), amountToStake_);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);
  }

  function test_stakeWithoutTransfer_RevertOutOfBoundsReservePoolId() external {
    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    component.stakeWithoutTransfer(1, 10e18, receiver_);
  }

  function testFuzz_stakeWithoutTransfer_RevertInsufficientAssetsAvailable(uint256 amountToStake_) external {
    amountToStake_ = bound(amountToStake_, 1, type(uint216).max);

    component.mockSetSafetyModuleState(SafetyModuleState.ACTIVE);

    address staker_ = _randomAddress();
    address receiver_ = _randomAddress();

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), 150e18);
    // Mint assets for staker.
    mockAsset.mint(staker_, amountToStake_);
    // Transfer insufficient assets to safety module.
    vm.prank(staker_);
    mockAsset.transfer(address(component), amountToStake_ - 1);

    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    vm.prank(staker_);
    component.stakeWithoutTransfer(0, amountToStake_, receiver_);
  }
}

contract TestableStaker is Staker, Depositor, RewardsHandler {
  // -------- Mock setters --------
  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) external {
    reservePools.push(reservePool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockAddUndrippedRewardPool(IERC20 rewardAsset_) external {
    undrippedRewardPools.push(
      UndrippedRewardPool({
        asset: rewardAsset_,
        dripModel: IDripModel(address(new MockDripModel(1e18))),
        amount: 0,
        depositToken: IReceiptToken(address(new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6)))
      })
    );
  }

  // -------- Mock getters --------
  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  // -------- Overridden abstract function placeholders --------
  function dripFees() public view override {
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
}
