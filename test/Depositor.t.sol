// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafetyModuleState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IDepositorErrors} from "../src/interfaces/IDepositorErrors.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {Depositor} from "../src/lib/Depositor.sol";
import {AssetPool, ReservePool} from "../src/lib/structs/Pools.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

contract DepositorUnitTest is TestBase {
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);
  MockERC20 mockReserveDepositReceiptToken = new MockERC20("Mock Cozy Deposit Token", "cozyDep", 6);
  TestableDepositor component = new TestableDepositor();

  /// @dev Emitted when a user deposits.
  event Deposited(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed depositReceiptToken_,
    uint256 assetAmount_,
    uint256 depositReceiptTokenAmount_
  );

  uint256 initialSafetyModuleBal = 50e18;

  function setUp() public {
    ReservePool memory initialReservePool_ = ReservePool({
      asset: IERC20(address(mockAsset)),
      depositReceiptToken: IReceiptToken(address(mockReserveDepositReceiptToken)),
      depositAmount: 50e18,
      pendingWithdrawalsAmount: 0,
      feeAmount: 0,
      maxSlashPercentage: MathConstants.WAD,
      lastFeesDripTime: uint128(block.timestamp)
    });
    AssetPool memory initialAssetPool_ = AssetPool({amount: initialSafetyModuleBal});
    component.mockAddReservePool(initialReservePool_);
    component.mockAddAssetPool(IERC20(address(mockAsset)), initialAssetPool_);
    deal(address(mockAsset), address(component), initialSafetyModuleBal);
  }

  function _deposit(
    bool withoutTransfer_,
    uint16 poolId_,
    uint256 amountToDeposit_,
    address receiver_,
    address depositor_
  ) internal returns (uint256 depositReceiptTokenAmount_) {
    if (withoutTransfer_) {
      depositReceiptTokenAmount_ = component.depositReserveAssetsWithoutTransfer(poolId_, amountToDeposit_, receiver_);
    } else {
      depositReceiptTokenAmount_ = component.depositReserveAssets(poolId_, amountToDeposit_, receiver_, depositor_);
    }
  }

  function test_depositReserve_DepositReceiptTokensAndStorageUpdates() external {
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

    // `depositReceiptToken.totalSupply() == 0`, so should be minted 1-1 with reserve assets deposited.
    uint256 expectedDepositReceiptTokenAmount_ = 10e18;
    _expectEmit();
    emit Deposited(
      depositor_,
      receiver_,
      IReceiptToken(address(mockReserveDepositReceiptToken)),
      amountToDeposit_,
      expectedDepositReceiptTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    assertEq(depositReceiptTokenAmount_, expectedDepositReceiptTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 10e18
    assertEq(finalReservePool_.depositAmount, 60e18);
    // 50e18 + 10e18
    assertEq(finalAssetPool_.amount, 60e18);
    assertEq(mockAsset.balanceOf(address(component)), 60e18 + initialSafetyModuleBal);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockReserveDepositReceiptToken.balanceOf(receiver_), expectedDepositReceiptTokenAmount_);
  }

  function test_depositReserve_DepositReceiptTokensAndStorageUpdatesNonZeroSupply() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 20e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), initialSafetyModuleBal);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Mint/burn some depositReceiptTokens.
    uint256 initialDepositReceiptTokenSupply_ = 50e18;
    mockReserveDepositReceiptToken.mint(address(0), initialDepositReceiptTokenSupply_);
    // Approve safety module to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    // `depositReceiptToken.totalSupply() == 50e18`, so we have (20e18 / 50e18) * 50e18 = 20e18.
    uint256 expectedDepositReceiptTokenAmount_ = 20e18;
    _expectEmit();
    emit Deposited(
      depositor_,
      receiver_,
      IReceiptToken(address(mockReserveDepositReceiptToken)),
      amountToDeposit_,
      expectedDepositReceiptTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(false, 0, amountToDeposit_, receiver_, depositor_);

    assertEq(depositReceiptTokenAmount_, expectedDepositReceiptTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));

    // 50e18 + 20e18
    assertEq(finalReservePool_.depositAmount, 70e18);
    // 50e18 + 20e18
    assertEq(finalAssetPool_.amount, 70e18);
    assertEq(mockAsset.balanceOf(address(component)), 70e18 + initialSafetyModuleBal);
    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockReserveDepositReceiptToken.balanceOf(receiver_), expectedDepositReceiptTokenAmount_);
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
    // Mint/burn some depositReceiptTokens.
    uint256 initialDepositReceiptTokenSupply_ = 50e18;
    mockReserveDepositReceiptToken.mint(address(0), initialDepositReceiptTokenSupply_);
    // Approve safety module to spend asset.
    vm.prank(depositor_);
    mockAsset.approve(address(component), amountToDeposit_);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(depositor_);
    _deposit(false, 0, amountToDeposit_, receiver_, depositor_);
  }

  function test_depositReserve_RevertOutOfBoundsReservePoolId() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    vm.prank(depositor_);
    _deposit(false, 1, 10e18, receiver_, depositor_);
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
    _deposit(false, 0, amountToDeposit_, receiver_, depositor_);
  }

  function test_depositReserveAssetsWithoutTransfer_DepositReceiptTokensAndStorageUpdates() external {
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

    // `depositReceiptToken.totalSupply() == 0`, so should be minted 1-1 with reserve assets deposited.
    uint256 expectedDepositReceiptTokenAmount_ = 10e18;
    _expectEmit();
    emit Deposited(
      depositor_,
      receiver_,
      IReceiptToken(address(mockReserveDepositReceiptToken)),
      amountToDeposit_,
      expectedDepositReceiptTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(true, 0, amountToDeposit_, receiver_, receiver_);

    assertEq(depositReceiptTokenAmount_, expectedDepositReceiptTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 10e18
    assertEq(finalReservePool_.depositAmount, 60e18);
    // 50e18 + 10e18
    assertEq(finalAssetPool_.amount, 60e18);
    assertEq(mockAsset.balanceOf(address(component)), 60e18 + initialSafetyModuleBal);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockReserveDepositReceiptToken.balanceOf(receiver_), expectedDepositReceiptTokenAmount_);
  }

  function test_depositReserveAssetsWithoutTransfer_DepositReceiptTokensAndStorageUpdatesNonZeroSupply() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint128 amountToDeposit_ = 20e18;

    // Mint initial asset balance for safety module.
    mockAsset.mint(address(component), initialSafetyModuleBal);
    // Mint initial balance for depositor.
    mockAsset.mint(depositor_, amountToDeposit_);
    // Mint/burn some depositReceiptTokens.
    uint256 initialDepositReceiptTokenSupply_ = 50e18;
    mockReserveDepositReceiptToken.mint(address(0), initialDepositReceiptTokenSupply_);
    // Transfer to safety module.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    // `depositReceiptToken.totalSupply() == 50e18`, so we have (20e18 / 50e18) * 50e18 = 20e18.
    uint256 expectedDepositReceiptTokenAmount_ = 20e18;
    _expectEmit();
    emit Deposited(
      depositor_,
      receiver_,
      IReceiptToken(address(mockReserveDepositReceiptToken)),
      amountToDeposit_,
      expectedDepositReceiptTokenAmount_
    );

    vm.prank(depositor_);
    uint256 depositReceiptTokenAmount_ = _deposit(true, 0, amountToDeposit_, receiver_, receiver_);

    assertEq(depositReceiptTokenAmount_, expectedDepositReceiptTokenAmount_);

    ReservePool memory finalReservePool_ = component.getReservePool(0);
    AssetPool memory finalAssetPool_ = component.getAssetPool(IERC20(address(mockAsset)));
    // 50e18 + 20e18
    assertEq(finalReservePool_.depositAmount, 70e18);
    // 50e18 + 20e18
    assertEq(finalAssetPool_.amount, 70e18);
    assertEq(mockAsset.balanceOf(address(component)), 70e18 + initialSafetyModuleBal);

    assertEq(mockAsset.balanceOf(depositor_), 0);
    assertEq(mockReserveDepositReceiptToken.balanceOf(receiver_), expectedDepositReceiptTokenAmount_);
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
    // Mint/burn some depositReceiptTokens.
    uint256 initialDepositReceiptTokenSupply_ = 50e18;
    mockReserveDepositReceiptToken.mint(address(0), initialDepositReceiptTokenSupply_);
    // Transfer to safety module.
    vm.prank(depositor_);
    mockAsset.transfer(address(component), amountToDeposit_);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_, receiver_, receiver_);
  }

  function test_depositReserveAssetsWithoutTransfer_RevertOutOfBoundsReservePoolId() external {
    address receiver_ = _randomAddress();

    _expectPanic(INDEX_OUT_OF_BOUNDS);
    _deposit(true, 1, 10e18, receiver_, receiver_);
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
    _deposit(true, 0, amountToDeposit_, receiver_, address(0));
  }

  function test_deposit_RevertZeroShares() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToDeposit_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(depositor_);
    _deposit(true, 0, amountToDeposit_, receiver_, address(0));
  }

  function test_depositWithoutTransfer_RevertZeroShares() external {
    address depositor_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 amountToDeposit_ = 0;

    // 0 assets should give 0 shares.
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(depositor_);
    _deposit(false, 0, amountToDeposit_, receiver_, address(0));
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

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
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

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 /* lastDripTime_ */ )
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

  function _dripFeesFromReservePool(ReservePool storage, /*reservePool_*/ IDripModel /*dripModel_*/ )
    internal
    view
    override
  {
    __readStub__();
  }
}
