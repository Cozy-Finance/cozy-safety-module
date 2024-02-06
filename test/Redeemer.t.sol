// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IRedemptionErrors} from "../src/interfaces/IRedemptionErrors.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {CozyMath} from "../src/lib/CozyMath.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {Redeemer} from "../src/lib/Redeemer.sol";
import {RedemptionLib} from "../src/lib/RedemptionLib.sol";
import {AssetPool, ReservePool} from "../src/lib/structs/Pools.sol";
import {RedemptionPreview} from "../src/lib/structs/Redemptions.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "./utils/Stub.sol";

abstract contract ReedemerUnitTestBase is TestBase {
  using SafeCastLib for uint256;

  IReceiptToken stkReceiptToken;
  IReceiptToken depositReceiptToken;
  MockManager public mockManager = new MockManager();
  TestableRedeemer component = new TestableRedeemer(IManager(address(mockManager)));
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);

  uint64 internal constant WITHDRAW_DELAY = 20 days;

  IReceiptToken testReceiptToken;

  /// @dev Emitted when a user redeems.
  event Redeemed(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed receiptToken_,
    uint256 receiptTokenAmount_,
    uint256 reserveAssetAmount_,
    uint64 redemptionId_
  );

  /// @dev Emitted when a user queues an redemption.
  event RedemptionPending(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed receiptToken_,
    uint256 receiptTokenAmount_,
    uint256 reserveAssetAmount_,
    uint64 redemptionId_
  );

  event Transfer(address indexed from, address indexed to, uint256 amount);

  function _setupDefaultSingleUserFixture(uint16 reservePoolId_)
    internal
    returns (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    )
  {
    owner_ = _randomAddress();
    receiver_ = _randomAddress();
    reserveAssetAmount_ = 1e6;
    receiptTokenAmount_ = 1e18;
    nextRedemptionId_ = component.getRedemptionIdCounter();
    _deposit(reservePoolId_, owner_, reserveAssetAmount_, receiptTokenAmount_);
  }

  function _deposit(
    uint16 reservePoolId_,
    address owner_,
    uint256 reserveAssetAmount_,
    uint256 depositReceiptTokenAmount_
  ) internal {
    component.mockDeposit(reservePoolId_, owner_, reserveAssetAmount_, depositReceiptTokenAmount_);
  }

  function _depositAssets(uint16 reservePoolId_, uint256 amount_) internal {
    component.mockDepositAssets(reservePoolId_, amount_);
  }

  function _redeem(uint16 reservePoolId_, uint256 receiptTokenAmount_, address receiver_, address owner_)
    internal
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_)
  {
    return component.redeem(reservePoolId_, receiptTokenAmount_, receiver_, owner_);
  }

  function _completeRedeem(uint64 redemptionId_) internal returns (uint256 reserveAssetAmount_) {
    return component.completeRedemption(redemptionId_);
  }

  function _updateRedemptionsAfterTrigger(uint16 reservePoolId_, uint256 oldReservePoolAmount_, uint256 slashAmount_)
    internal
  {
    component.updateWithdrawalsAfterTrigger(reservePoolId_, oldReservePoolAmount_, slashAmount_);
  }

  function _getPendingAccISFs(uint16 reservePoolId_) internal view returns (uint256[] memory) {
    return component.getPendingWithdrawalsAccISFs(reservePoolId_);
  }

  function _setRedemptionDelay(uint64 delay_) internal {
    component.mockSetWithdrawDelay(delay_);
  }

  function _getRedemptionDelay() internal view returns (uint64) {
    (,, uint64 withdrawDelay_) = component.delays();
    return withdrawDelay_;
  }

  function _mintReceiptToken(uint16 reservePoolId_, address receiver_, uint256 amount_) internal {
    component.mockMintDepositReceiptTokens(reservePoolId_, receiver_, amount_);
  }

  function _getReceiptToken(uint16 reservePoolId_) internal view returns (IERC20) {
    ReservePool memory reservePool_ = component.getReservePool(reservePoolId_);
    return reservePool_.depositReceiptToken;
  }

  function _setNextDripAmount(uint256 amount_) internal {
    component.mockSetNextDepositDripAmount(amount_);
  }

  function _assertReservePoolAccounting(
    uint16 reservePoolId_,
    uint256 poolAssetAmount_,
    uint256 assetsPendingRedemption_
  ) internal {
    ReservePool memory reservePool_ = component.getReservePool(reservePoolId_);
    assertEq(reservePool_.pendingWithdrawalsAmount, assetsPendingRedemption_, "reservePool_.pendingWithdrawalsAmount");
    assertEq(reservePool_.depositAmount, poolAssetAmount_, "reservePool_.depositAmount");
  }

  function setUp() public virtual {
    component.mockSetWithdrawDelay(WITHDRAW_DELAY);

    ReceiptToken receiptTokenLogic_ = new ReceiptToken();
    receiptTokenLogic_.initialize(address(0), "", "", 0);
    ReceiptTokenFactory receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(receiptTokenLogic_)), IReceiptToken(address(receiptTokenLogic_)));

    vm.startPrank(address(component));
    stkReceiptToken =
      IReceiptToken(address(receiptTokenFactory.deployReceiptToken(0, IReceiptTokenFactory.PoolType.STAKE, 18)));
    depositReceiptToken =
      IReceiptToken(address(receiptTokenFactory.deployReceiptToken(0, IReceiptTokenFactory.PoolType.RESERVE, 18)));
    vm.stopPrank();

    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        depositReceiptToken: IReceiptToken(address(depositReceiptToken)),
        depositAmount: 0,
        feeAmount: 0,
        pendingWithdrawalsAmount: 0,
        maxSlashPercentage: MathConstants.ZOC,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: 0}));

    testReceiptToken = depositReceiptToken;
  }
}

contract RedeemerUnitTest is ReedemerUnitTestBase {
  using CozyMath for uint256;
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  function test_redeem_canRedeemAllInstantly_whenRedemptionDelayIsZero() external {
    _setRedemptionDelay(0);

    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    _expectEmit();
    emit Transfer(owner_, address(0), receiptTokenAmount_);
    _expectEmit();
    emit Redeemed(
      owner_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );

    vm.prank(owner_);
    (uint64 resultRedemptionId_, uint256 resultReserveAssetAmount_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);

    assertEq(resultRedemptionId_, nextRedemptionId_, "redemptionId");
    assertEq(resultReserveAssetAmount_, reserveAssetAmount_, "reserve assets received");
    assertEq(testReceiptToken.balanceOf(owner_), 0, "receipt tokens balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), resultReserveAssetAmount_, "reserve assets balanceOf");
    assertEq(component.getRedemptionIdCounter(), 1, "redemptionidCounter");
    _assertReservePoolAccounting(0, reserveAssetAmount_ - resultReserveAssetAmount_, 0);
  }

  function test_redeem_canRedeemAllInstantly_whenSafetyModuleIsPaused() external {
    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    _expectEmit();
    emit Redeemed(
      owner_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    vm.prank(owner_);
    (, uint256 resultReserveAssetAmount_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);

    _assertReservePoolAccounting(0, reserveAssetAmount_ - resultReserveAssetAmount_, 0);
  }

  function test_redeem_canRedeemPartialInstantly() external {
    _setRedemptionDelay(0);

    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    uint256 receiptTokenAmountToRedeem_ = receiptTokenAmount_ / 2 - 1;
    uint256 reserveAssetsToReceive_ =
      uint256(reserveAssetAmount_).mulDivDown(receiptTokenAmountToRedeem_, receiptTokenAmount_);

    _expectEmit();
    emit Transfer(owner_, address(0), receiptTokenAmountToRedeem_);
    _expectEmit();
    emit Redeemed(
      owner_,
      receiver_,
      owner_,
      testReceiptToken,
      receiptTokenAmountToRedeem_,
      reserveAssetsToReceive_,
      nextRedemptionId_
    );

    vm.prank(owner_);
    (uint64 resultRedemptionId_, uint256 resultReserveAssetAmount_) =
      _redeem(0, receiptTokenAmountToRedeem_, receiver_, owner_);

    assertEq(resultRedemptionId_, nextRedemptionId_, "redemptionId");
    assertEq(resultReserveAssetAmount_, reserveAssetsToReceive_, "reserve assets received");
    assertEq(testReceiptToken.balanceOf(owner_), receiptTokenAmount_ - receiptTokenAmountToRedeem_, "shares balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetsToReceive_, "reserve assets balanceOf");
    assertEq(component.getRedemptionIdCounter(), 1, "redemptionidCounter");
    _assertReservePoolAccounting(0, reserveAssetAmount_ - resultReserveAssetAmount_, 0);
  }

  function test_redeem_canRedeemTotalInstantlyInTwoRedeems() external {
    _setRedemptionDelay(0);

    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    uint256 receiptTokenAmountToRedeem_ = receiptTokenAmount_ / 2 - 1;
    uint256 reserveAssetsToReceive_ =
      uint256(reserveAssetAmount_).mulDivDown(receiptTokenAmountToRedeem_, receiptTokenAmount_);

    _expectEmit();
    emit Transfer(owner_, address(0), receiptTokenAmountToRedeem_);
    _expectEmit();
    emit Redeemed(
      owner_,
      receiver_,
      owner_,
      testReceiptToken,
      receiptTokenAmountToRedeem_,
      reserveAssetsToReceive_,
      nextRedemptionId_
    );

    vm.prank(owner_);
    (uint64 resultRedemptionId_, uint256 resultReserveAssetAmount_) =
      _redeem(0, receiptTokenAmountToRedeem_, receiver_, owner_);

    assertEq(resultRedemptionId_, nextRedemptionId_, "redemptionId");
    assertEq(resultReserveAssetAmount_, reserveAssetsToReceive_, "reserve assets received");
    assertEq(testReceiptToken.balanceOf(owner_), receiptTokenAmount_ - receiptTokenAmountToRedeem_, "shares balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetsToReceive_, "reserve assets balanceOf");
    assertEq(component.getRedemptionIdCounter(), 1, "redemptionIdCounter");
    _assertReservePoolAccounting(0, reserveAssetAmount_ - resultReserveAssetAmount_, 0);

    receiptTokenAmountToRedeem_ = receiptTokenAmount_ - receiptTokenAmountToRedeem_;
    reserveAssetsToReceive_ = reserveAssetAmount_ - reserveAssetsToReceive_;
    nextRedemptionId_ += 1;

    _expectEmit();
    emit Transfer(owner_, address(0), receiptTokenAmountToRedeem_);
    _expectEmit();
    emit Redeemed(
      owner_,
      receiver_,
      owner_,
      testReceiptToken,
      receiptTokenAmountToRedeem_,
      reserveAssetsToReceive_,
      nextRedemptionId_
    );

    vm.prank(owner_);
    (resultRedemptionId_, resultReserveAssetAmount_) = _redeem(0, receiptTokenAmountToRedeem_, receiver_, owner_);

    assertEq(resultRedemptionId_, nextRedemptionId_, "redemptionId");
    assertEq(resultReserveAssetAmount_, reserveAssetsToReceive_, "reserve assets received");
    assertEq(testReceiptToken.balanceOf(owner_), 0, "shares balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetAmount_, "reserve assets balanceOf");
    assertEq(component.getRedemptionIdCounter(), 2, "redemptionIdCounter");
    _assertReservePoolAccounting(0, 0, 0);
  }

  function test_redeem_cannotRedeemIfSafetyModuleTriggered() external {
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);
    (address owner_, address receiver_,, uint256 receiptTokenAmount_,) = _setupDefaultSingleUserFixture(0);

    vm.expectRevert(ICommonErrors.InvalidState.selector);
    vm.prank(owner_);
    _redeem(0, receiptTokenAmount_, receiver_, owner_);
  }

  function test_redeem_cannotRedeemMoreReceiptTokensThanOwned() external {
    (address owner_, address receiver_,, uint256 receiptTokenAmount_,) = _setupDefaultSingleUserFixture(0);

    // Deposit some extra that belongs to someone else.
    _deposit(0, _randomAddress(), 1e6, 1e18);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(owner_);
    _redeem(0, receiptTokenAmount_ + 1, receiver_, owner_);
  }

  function test_redeem_cannotRedeemIfRoundsDownToZeroAssets() external {
    address owner_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 reserveAssetAmount_ = 1;
    uint256 receiptTokenAmount_ = 3;
    _deposit(0, owner_, reserveAssetAmount_, receiptTokenAmount_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(owner_);
    _redeem(0, 2, receiver_, owner_);
  }

  function test_redeem_canRedeemAllInstantly_ThroughAllowance() external {
    _setRedemptionDelay(0);

    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);
    address spender_ = _randomAddress();
    vm.prank(owner_);
    testReceiptToken.approve(spender_, receiptTokenAmount_ + 1); // Allowance is 1 extra.

    _expectEmit();
    emit Redeemed(
      spender_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );

    vm.prank(spender_);
    (, uint256 resultReserveAssetAmount_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);
    assertEq(testReceiptToken.allowance(owner_, spender_), 1, "receiptToken allowance"); // Only 1 allowance left
      // because of subtraction.
    _assertReservePoolAccounting(0, reserveAssetAmount_ - resultReserveAssetAmount_, 0);
  }

  function test_redeem_cannotRedeem_ThroughAllowance_WithInsufficientAllowance() external {
    _setRedemptionDelay(0);

    (address owner_, address receiver_,, uint256 receiptTokenAmount_,) = _setupDefaultSingleUserFixture(0);
    address spender_ = _randomAddress();
    vm.prank(owner_);
    testReceiptToken.approve(spender_, receiptTokenAmount_ - 1); // Allowance is 1 less.

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(spender_);
    _redeem(0, receiptTokenAmount_, receiver_, owner_);
  }

  function test_redeem_canQueueRedeemAll_ThenCompleteAfterDelay() external {
    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit RedemptionPending(
      owner_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    vm.prank(owner_);
    {
      (uint64 resultRedemptionId_, uint256 resultReserveAssetAmount_) =
        _redeem(0, receiptTokenAmount_, receiver_, owner_);
      assertEq(resultRedemptionId_, nextRedemptionId_, "redemptionId");
      assertEq(resultReserveAssetAmount_, reserveAssetAmount_, "reserve assets received");
      _assertReservePoolAccounting(0, reserveAssetAmount_, resultReserveAssetAmount_);
    }

    skip(_getRedemptionDelay());
    // Complete.
    _expectEmit();
    emit Redeemed(
      address(this), receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    _completeRedeem(nextRedemptionId_);

    assertEq(testReceiptToken.balanceOf(owner_), 0, "receiptToken balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetAmount_, "assets balanceOf");
    _assertReservePoolAccounting(0, 0, 0);
  }

  function test_redeem_canQueueRedeemAll_ThenCompleteIfSafetyModuleIsPaused() external {
    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit RedemptionPending(
      owner_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    vm.prank(owner_);
    {
      (uint64 resultRedemptionId_, uint256 resultReserveAssetAmount_) =
        _redeem(0, receiptTokenAmount_, receiver_, owner_);
      assertEq(resultRedemptionId_, nextRedemptionId_, "redemptionId");
      assertEq(resultReserveAssetAmount_, reserveAssetAmount_, "reserve assets received");
      _assertReservePoolAccounting(0, reserveAssetAmount_, resultReserveAssetAmount_);
    }

    component.mockSetSafetyModuleState(SafetyModuleState.PAUSED);
    // Complete.
    _expectEmit();
    emit Redeemed(
      address(this), receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    _completeRedeem(nextRedemptionId_);

    assertEq(testReceiptToken.balanceOf(owner_), 0, "receiptToken balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetAmount_, "assets balanceOf");
    _assertReservePoolAccounting(0, 0, 0);
  }

  function test_redeem_delayedRedeemAll_IsNotAffectedByNewRedeem() external {
    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit RedemptionPending(
      owner_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    vm.prank(owner_);
    (, uint256 resultReserveAssetAmount_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);
    _assertReservePoolAccounting(0, reserveAssetAmount_, resultReserveAssetAmount_);

    // New deposit.
    _deposit(0, _randomAddress(), 1e6, 1e18);

    skip(_getRedemptionDelay());
    // Complete.
    _expectEmit();
    emit Redeemed(
      address(this), receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    _completeRedeem(nextRedemptionId_);

    assertEq(testReceiptToken.balanceOf(owner_), 0, "receiptToken balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetAmount_, "assets balanceOf");
    _assertReservePoolAccounting(0, 1e6, 0);
  }

  function test_redeem_cannotCompleteRedeemBeforeDelayPasses() external {
    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit RedemptionPending(
      owner_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    vm.prank(owner_);
    _redeem(0, receiptTokenAmount_, receiver_, owner_);

    skip(_getRedemptionDelay() - 1);
    // Complete.
    vm.expectRevert(IRedemptionErrors.DelayNotElapsed.selector);
    _completeRedeem(nextRedemptionId_);
  }

  function test_redeem_cannotRedeemInvalidReservePoolId() external {
    (address owner_, address receiver_,, uint256 receiptTokenAmount_,) = _setupDefaultSingleUserFixture(0);

    _expectPanic(PANIC_ARRAY_OUT_OF_BOUNDS);
    vm.prank(owner_);
    _redeem(1, receiptTokenAmount_, receiver_, owner_);
  }

  function test_redeem_cannotRedeemnsufficientReceiptTokenBalance() external {
    (address owner_, address receiver_,, uint256 receiptTokenAmount_,) = _setupDefaultSingleUserFixture(0);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(owner_);
    _redeem(0, receiptTokenAmount_ + 1, receiver_, owner_);
  }

  function test_redeem_cannotCompleteRedeemSameRedemptionIdTwice() external {
    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    // Queue.
    _expectEmit();
    emit RedemptionPending(
      owner_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    vm.prank(owner_);
    (, uint256 resultReserveAssetAmount_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);
    _assertReservePoolAccounting(0, reserveAssetAmount_, resultReserveAssetAmount_);

    skip(_getRedemptionDelay());
    // Complete.
    _completeRedeem(nextRedemptionId_);
    _assertReservePoolAccounting(0, 0, 0);
    vm.expectRevert(IRedemptionErrors.RedemptionNotFound.selector);
    _completeRedeem(nextRedemptionId_);
  }

  function test_redeem_triggerCanReduceExchangeRateForPendingRedeems() external {
    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);
    uint256 receiptTokensToRedeem_ = receiptTokenAmount_; // Withdraw 1/4 of all receipt tokens.
    uint256 oldReservePoolAmount_ = reserveAssetAmount_;

    // Queue.
    vm.prank(owner_);
    (, uint256 queueResultReserveAssetAmount_) = _redeem(0, receiptTokensToRedeem_, receiver_, owner_);
    assertEq(
      queueResultReserveAssetAmount_,
      receiptTokensToRedeem_.mulDivDown(reserveAssetAmount_, receiptTokenAmount_),
      "resultReserveAssetAmount"
    );
    _assertReservePoolAccounting(0, reserveAssetAmount_, queueResultReserveAssetAmount_);

    // Trigger, taking 50% of the reserve pool.
    _updateRedemptionsAfterTrigger(0, oldReservePoolAmount_, oldReservePoolAmount_ / 2);
    // Trigger, taking another 50% of the reserve pool.
    _updateRedemptionsAfterTrigger(0, oldReservePoolAmount_ / 2, oldReservePoolAmount_ / 4);

    skip(_getRedemptionDelay());
    uint256 resultReserveAssetAmount_ = _completeRedeem(nextRedemptionId_);
    // receiptTokens are now worth 25% of what they were before the triggers.
    assertEq(resultReserveAssetAmount_, queueResultReserveAssetAmount_ * 1 / 4, "reserve assets received");
    assertEq(testReceiptToken.balanceOf(owner_), 0, "receiptToken balanceOf");
    // These values should both be 0, but the accounting updates due to the slash taking out assets gets updated in
    // `SlashHandler.slash` not the `Redeemer` contract.
    _assertReservePoolAccounting(0, reserveAssetAmount_ * 3 / 4, queueResultReserveAssetAmount_ * 3 / 4);
  }

  function test_redeem_triggerWhileNoneBeingRedeemed() external {
    uint256 assets_ = 100e18;
    // Trigger, taking 10% out of reserve pool.
    _updateRedemptionsAfterTrigger(0, assets_, assets_ / 10);
  }

  function test_redeem_triggerAddsFirstAccumulatorEntry() external {
    uint256 assets_ = 100e18;
    uint256[] memory accs_ = _getPendingAccISFs(0);
    assertEq(accs_.length, 0, "accs_.length == 0");
    // Trigger, taking 10% out of pool.
    _updateRedemptionsAfterTrigger(0, assets_, assets_ / 10);
    accs_ = _getPendingAccISFs(0);
    assertEq(accs_.length, 1, "accs_.length == 1");
    assertEq(accs_[0], MathConstants.WAD * 10 / 9 + 1, "accs_[0]");
  }

  function test_redeem_triggerCanUpdateLastAccumulatorEntry() external {
    uint256 assets_ = 100e18;
    // Trigger, taking 10% out of pool.
    _updateRedemptionsAfterTrigger(0, assets_, assets_ / 10);
    uint256[] memory accs_ = _getPendingAccISFs(0);
    assertEq(accs_.length, 1, "accs_.length");
    assertEq(accs_[0], MathConstants.WAD.mulDivUp(10, 9), "accs_[0]");

    uint256 firstAcc_ = accs_[0];

    // Trigger, taking 25% out of pool.
    _updateRedemptionsAfterTrigger(0, assets_, assets_ / 4);
    accs_ = _getPendingAccISFs(0);
    assertEq(accs_.length, 1, "accs_.length");
    assertEq(accs_[0], firstAcc_.mulWadUp(MathConstants.WAD.mulDivUp(4, 3)), "accs_[0]");
  }

  function test_redeem_triggerCanAddNewAccumulatorEntry() external {
    uint256 assets_ = 100e18;
    // We should be able to exceed NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD and require a new entry
    // with 2 100% losses.

    // Trigger, taking 100% out of pool.
    _updateRedemptionsAfterTrigger(0, assets_, assets_);
    // Trigger, taking 100% out of pool.
    _updateRedemptionsAfterTrigger(0, assets_, assets_);

    uint256 expectedAcc0_ = RedemptionLib.INF_INV_SCALING_FACTOR.mulWadDown(RedemptionLib.INF_INV_SCALING_FACTOR) + 1;
    uint256[] memory accs_ = _getPendingAccISFs(0);
    assertEq(accs_.length, 2, "accs_.length");
    assertEq(accs_[0], expectedAcc0_, "accs_[0]");
    assertEq(accs_[1], MathConstants.WAD, "accs_[1]");

    // Trigger, taking 33% out of pool.
    _updateRedemptionsAfterTrigger(0, assets_, assets_ * 33 / 100);
    accs_ = _getPendingAccISFs(0);
    assertEq(accs_.length, 2, "accs_.length");
    assertEq(accs_[0], expectedAcc0_, "accs_[0]");
    assertEq(accs_[1], MathConstants.WAD * 100 / 67 + 1, "accs_[1]");
  }

  function testFuzz_redeem_updateRedemptionsAfterTrigger(
    uint256 acc_,
    uint256 oldReservePoolAmount_,
    uint256 slashAmount_,
    uint256 redemptions_
  ) external {
    acc_ = bound(acc_, MathConstants.WAD, RedemptionLib.NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD);
    oldReservePoolAmount_ = bound(oldReservePoolAmount_, 0, type(uint128).max);
    slashAmount_ = bound(slashAmount_, 0, type(uint128).max);
    redemptions_ = bound(redemptions_, 0, type(uint128).max);
    component.mockSetLastWithdrawalsAccISF(0, acc_);
    _updateRedemptionsAfterTrigger(0, oldReservePoolAmount_, slashAmount_);

    uint256 scale_;
    if (oldReservePoolAmount_ >= slashAmount_ && oldReservePoolAmount_ != 0) {
      scale_ = MathConstants.WAD - slashAmount_.divWadUp(oldReservePoolAmount_);
    }
    uint256[] memory accs_ = _getPendingAccISFs(0);
    if (accs_[0] > RedemptionLib.NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD) assertEq(accs_.length, 2, "accs_.length");
    else assertEq(accs_.length, 1, "accs_.length");
    if (scale_ != 0) assertEq(accs_[0], acc_.mulWadUp(MathConstants.WAD.divWadUp(scale_)), "accs_[0]");
    else assertEq(accs_[0], acc_.mulWadUp(RedemptionLib.INF_INV_SCALING_FACTOR), "accs_[0]");
  }

  struct FuzzUserInfo {
    address owner;
    uint216 receiptTokenAmount;
    uint64 redemptionId;
    uint128 assetsRedeemed;
    uint216 receiptTokensRedeemed;
  }

  function testFuzz_multipleRedeemInstantly(uint256) external {
    _setRedemptionDelay(0);

    uint256 numOwners_ = _randomUint256(6) + 2; // 2 to 8 users
    FuzzUserInfo[] memory users_ = new FuzzUserInfo[](numOwners_);
    uint128 totalAssets_ = uint128(_randomUint256(100e6 - numOwners_ * 2) + numOwners_ * 2);
    uint216 totalReceiptTokenAmount_;
    for (uint256 i; i < numOwners_; ++i) {
      users_[i].owner = _randomAddress();
      totalReceiptTokenAmount_ += users_[i].receiptTokenAmount = uint216(_randomUint256(1e18 - 2) + 2);
      _mintReceiptToken(0, users_[i].owner, users_[i].receiptTokenAmount);
      assertEq(_getReceiptToken(0).balanceOf(users_[i].owner), users_[i].receiptTokenAmount, "receipt token balance");
    }
    _depositAssets(0, totalAssets_);

    // Redeem in a random order.
    uint256[] memory idxs_ = _randomIndices(numOwners_);
    for (uint256 i; i < numOwners_; ++i) {
      FuzzUserInfo memory user_ = users_[idxs_[i]];
      // User redeems either half or all their receipt tokens.
      uint216 receiptTokensToRedeem_ =
        _randomUint256() % 2 == 0 ? user_.receiptTokenAmount / 2 : user_.receiptTokenAmount;
      uint128 assetsToRedeem_ =
        uint128(uint256(receiptTokensToRedeem_).mulDivDown(totalAssets_, totalReceiptTokenAmount_));
      totalReceiptTokenAmount_ -= receiptTokensToRedeem_;
      totalAssets_ -= assetsToRedeem_;

      vm.prank(user_.owner);
      {
        if (assetsToRedeem_ == 0) vm.expectRevert(ICommonErrors.RoundsToZero.selector);
        (uint64 redemptionId_, uint256 assetsRedeemed_) = _redeem(0, receiptTokensToRedeem_, user_.owner, user_.owner);
        assertEq(uint256(redemptionId_), i, "redemption id");
        assertEq(assetsRedeemed_, uint256(assetsToRedeem_), "assets redeemed");
      }
      assertEq(
        _getReceiptToken(0).balanceOf(user_.owner),
        user_.receiptTokenAmount - receiptTokensToRedeem_,
        "receipt token balance"
      );
      assertEq(component.getReservePool(0).asset.balanceOf(user_.owner), assetsToRedeem_, "assets balanceOf");
      assertEq(component.getRedemptionIdCounter(), i + 1, "redemptionCounter");
      _assertReservePoolAccounting(0, totalAssets_, 0);
    }
  }

  function testFuzz_multipleDelayedRedeem(uint256) external {
    _setRedemptionDelay(uint64(_randomUint64()));

    uint256 numOwners_ = _randomUint256(6) + 2; // 2 to 8 users
    FuzzUserInfo[] memory users_ = new FuzzUserInfo[](numOwners_);
    uint128 totalAssets_ = uint128(_randomUint256(100e6 - numOwners_ * 2) + numOwners_ * 2);
    uint216 totalReceiptTokenAmount_;
    for (uint256 i; i < numOwners_; ++i) {
      users_[i].owner = _randomAddress();
      totalReceiptTokenAmount_ += users_[i].receiptTokenAmount = uint216(_randomUint256(1e18 - 2) + 2);
      _mintReceiptToken(0, users_[i].owner, users_[i].receiptTokenAmount);
      assertEq(_getReceiptToken(0).balanceOf(users_[i].owner), users_[i].receiptTokenAmount, "receipt token balance");
    }
    _depositAssets(0, totalAssets_);

    // Redeem in a random order.
    uint256[] memory idxs_ = _randomIndices(numOwners_);
    uint128 totalAssetsToRedeem_;
    for (uint256 i; i < numOwners_; ++i) {
      FuzzUserInfo memory user_ = users_[idxs_[i]];
      // User redeems either half or all their receipt tokens.
      user_.receiptTokensRedeemed = _randomUint256() % 2 == 0 ? user_.receiptTokenAmount / 2 : user_.receiptTokenAmount;
      user_.assetsRedeemed = uint128(
        uint256(user_.receiptTokensRedeemed).mulDivDown(totalAssets_ - totalAssetsToRedeem_, totalReceiptTokenAmount_)
      );
      totalAssetsToRedeem_ += user_.assetsRedeemed;
      totalReceiptTokenAmount_ -= user_.receiptTokensRedeemed;
      {
        uint64 nextRedemptionId_ = component.getRedemptionIdCounter();
        _expectEmit();
        emit RedemptionPending(
          user_.owner,
          user_.owner,
          user_.owner,
          IReceiptToken(address(_getReceiptToken(0))),
          uint256(user_.receiptTokensRedeemed),
          uint256(user_.assetsRedeemed),
          nextRedemptionId_
        );
        vm.prank(user_.owner);
        (uint64 redemptionId_, uint256 assetsRedeemed_) =
          _redeem(0, user_.receiptTokensRedeemed, user_.owner, user_.owner);
        assertEq(uint256(redemptionId_), i, "redemption id");
        assertEq(assetsRedeemed_, uint256(user_.assetsRedeemed), "assets redeemed");
        user_.redemptionId = redemptionId_;
      }
      _assertReservePoolAccounting(0, totalAssets_, totalAssetsToRedeem_);
      assertLe(totalAssetsToRedeem_, totalAssets_, "totalAssetsToRedeem_ <= totalAssets");
      assertEq(component.getRedemptionIdCounter(), i + 1, "redemptionCounter");
    }

    skip(_getRedemptionDelay());

    // Complete in a random order.
    idxs_ = _randomIndices(numOwners_);
    for (uint256 i; i < numOwners_; ++i) {
      FuzzUserInfo memory user_ = users_[idxs_[i]];
      _expectEmit();
      emit Redeemed(
        address(this),
        user_.owner,
        user_.owner,
        IReceiptToken(address(_getReceiptToken(0))),
        uint256(user_.receiptTokensRedeemed),
        uint256(user_.assetsRedeemed),
        user_.redemptionId
      );
      _completeRedeem(user_.redemptionId);
      totalAssets_ -= user_.assetsRedeemed;
      totalAssetsToRedeem_ -= user_.assetsRedeemed;
      assertEq(
        _getReceiptToken(0).balanceOf(user_.owner),
        user_.receiptTokenAmount - user_.receiptTokensRedeemed,
        "receipt token balance"
      );
      assertEq(component.getReservePool(0).asset.balanceOf(user_.owner), user_.assetsRedeemed, "reserve asset balance");
      _assertReservePoolAccounting(0, totalAssets_, totalAssetsToRedeem_);
    }
    assertEq(component.getRedemptionIdCounter(), numOwners_, "redemptionCounter");
  }

  function test_previewRedemption() external {
    (address owner_, address receiver_, uint256 reserveAssetAmount_, uint256 receiptTokenAmount_,) =
      _setupDefaultSingleUserFixture(0);

    mockManager.setFeeDripModel(IDripModel(_randomAddress()));
    _setNextDripAmount(reserveAssetAmount_ / 4);

    skip(_randomUint128());

    // Preview and actually redeemed assets match.
    uint256 previewRedeemedAssets_ = component.previewRedemption(0, receiptTokenAmount_);
    vm.prank(owner_);
    (, uint256 resultRedeemedAssets_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);
    assertEq(previewRedeemedAssets_, resultRedeemedAssets_, "redeemed assets");
    assertEq(previewRedeemedAssets_, reserveAssetAmount_ * 3 / 4);
  }

  function test_previewRedemption_roundsDownToZero() external {
    address owner_ = _randomAddress();
    uint256 reserveAssetAmount_ = 1;
    uint256 receiptTokenAmount_ = 3;
    _deposit(0, owner_, reserveAssetAmount_, receiptTokenAmount_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    component.previewRedemption(0, 2);
  }

  function test_previewQueuedRedemption() external {
    (
      address owner_,
      address receiver_,
      uint256 reserveAssetAmount_,
      uint256 receiptTokenAmount_,
      uint64 nextRedemptionId_
    ) = _setupDefaultSingleUserFixture(0);

    // Queue.
    vm.prank(owner_);
    (uint64 resultRedemptionId_, uint256 resultReserveAssetAmount_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);
    // Sanity checks.
    assertEq(resultRedemptionId_, nextRedemptionId_, "redemptionId");
    assertEq(resultReserveAssetAmount_, reserveAssetAmount_, "reserve assets received");

    (RedemptionPreview memory redemptionPreview_) = component.previewQueuedRedemption(resultRedemptionId_);
    assertEq(redemptionPreview_.delayRemaining, _getRedemptionDelay(), "delayRemaining");
    assertEq(redemptionPreview_.receiptTokenAmount, receiptTokenAmount_, "receiptTokenAmount");
    assertEq(redemptionPreview_.reserveAssetAmount, reserveAssetAmount_, "reserveAssetAmount");
    assertEq(address(_getReceiptToken(0)), address(redemptionPreview_.receiptToken), "receiptToken");
    assertEq(redemptionPreview_.owner, owner_, "owner");
    assertEq(redemptionPreview_.receiver, receiver_, "receiver");

    skip(_getRedemptionDelay() / 2);
    // Trigger, taking 50% of the reserve pool.
    _updateRedemptionsAfterTrigger(0, reserveAssetAmount_, reserveAssetAmount_ / 2);
    // Trigger, another 50% of the reserve pool.
    _updateRedemptionsAfterTrigger(0, reserveAssetAmount_ / 2, reserveAssetAmount_ / 4);

    (redemptionPreview_) = component.previewQueuedRedemption(resultRedemptionId_);
    assertEq(redemptionPreview_.delayRemaining, _getRedemptionDelay() / 2, "delayRemaining");
    assertEq(redemptionPreview_.receiptTokenAmount, receiptTokenAmount_, "receiptTokenAmount");
    assertEq(redemptionPreview_.reserveAssetAmount, reserveAssetAmount_ * 1 / 4, "reserveAssetAmount");
    assertEq(address(_getReceiptToken(0)), address(redemptionPreview_.receiptToken), "receiptToken");
    assertEq(redemptionPreview_.owner, owner_, "owner");
    assertEq(redemptionPreview_.receiver, receiver_, "receiver");
  }

  function test_redeem_revertNoAssetsToRedeem() public {
    address ownerA_ = _randomAddress();
    uint256 amount_ = _randomUint256();

    // Reverts with no assets to redeem if there are no assets in the pool.
    vm.expectRevert(IRedemptionErrors.NoAssetsToRedeem.selector);
    vm.prank(ownerA_);
    _redeem(0, amount_, ownerA_, ownerA_);

    (address ownerB_,,, uint256 receiptTokenAmount_,) = _setupDefaultSingleUserFixture(0);
    vm.prank(ownerB_);
    _redeem(0, receiptTokenAmount_, ownerB_, ownerB_);
    // Reverts with no assets to redeem if try to double redeem.
    vm.expectRevert(IRedemptionErrors.NoAssetsToRedeem.selector);
    vm.prank(ownerB_);
    _redeem(0, receiptTokenAmount_, ownerB_, ownerB_);
  }
}

contract TestableRedeemer is Redeemer {
  using SafeCastLib for uint256;

  uint256 internal mockNextDepositDripAmount;

  constructor(IManager manager_) {
    cozyManager = manager_;
  }

  function mockDeposit(
    uint16 reservePoolId_,
    address depositor_,
    uint256 reserveAssetAmountDeposited_,
    uint256 depositReceiptTokenAmount_
  ) external {
    mockDepositAssets(reservePoolId_, reserveAssetAmountDeposited_);
    mockMintDepositReceiptTokens(reservePoolId_, depositor_, depositReceiptTokenAmount_);
  }

  function mockDepositAssets(uint16 reservePoolId_, uint256 reserveAssetAmountDeposited_) public {
    if (reserveAssetAmountDeposited_ > 0) {
      ReservePool storage reservePool_ = reservePools[reservePoolId_];
      MockERC20(address(reservePool_.asset)).mint(address(this), reserveAssetAmountDeposited_);
      reservePool_.depositAmount += reserveAssetAmountDeposited_;
      assetPools[reservePool_.asset].amount += reserveAssetAmountDeposited_;
    }
  }

  function mockMintDepositReceiptTokens(uint16 reservePoolId_, address depositor_, uint256 depositReceiptTokenAmount_)
    public
  {
    if (depositReceiptTokenAmount_ > 0) {
      MockERC20(address(reservePools[reservePoolId_].depositReceiptToken)).mint(depositor_, depositReceiptTokenAmount_);
    }
  }

  // -------- Mock setters --------
  function mockSetNextDepositDripAmount(uint256 nextDripAmount_) external {
    mockNextDepositDripAmount = nextDripAmount_;
  }

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) public {
    reservePools.push(reservePool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockSetWithdrawDelay(uint64 withdrawDelay_) external {
    delays.withdrawDelay = withdrawDelay_;
  }

  function mockSetLastWithdrawalsAccISF(uint16 reservePoolId_, uint256 acc_) external {
    uint256[] storage pendingWithdrawalsAccISFs_ = pendingRedemptionAccISFs[reservePoolId_];
    if (pendingWithdrawalsAccISFs_.length == 0) pendingWithdrawalsAccISFs_.push(acc_);
    else pendingWithdrawalsAccISFs_[pendingWithdrawalsAccISFs_.length - 1] = acc_;
  }

  // -------- Mock getters --------
  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getAssetPool(IERC20 asset_) external view returns (AssetPool memory) {
    return assetPools[asset_];
  }

  function getRedemptionIdCounter() external view returns (uint64) {
    return redemptionIdCounter;
  }

  function getPendingWithdrawalsAccISFs(uint16 reservePoolId_) external view returns (uint256[] memory) {
    return pendingRedemptionAccISFs[reservePoolId_];
  }

  // -------- Exposed internals --------

  function updateWithdrawalsAfterTrigger(uint16 reservePoolId_, uint256 oldAmount_, uint256 slashAmount_) external {
    _updateWithdrawalsAfterTrigger(reservePoolId_, reservePools[reservePoolId_], oldAmount_, slashAmount_);
  }

  // -------- Overridden common abstract functions --------

  function dripFees() public override {
    ReservePool storage reservePool_ = reservePools[0];
    reservePool_.depositAmount -= mockNextDepositDripAmount;
    reservePool_.lastFeesDripTime = uint128(block.timestamp);
  }

  function _dripFeesFromReservePool(ReservePool storage reservePool_, IDripModel /* dripModel_*/ ) internal override {
    reservePool_.depositAmount -= mockNextDepositDripAmount;
    reservePool_.lastFeesDripTime = uint128(block.timestamp);
  }

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 lastDripTime_)
    internal
    view
    override
    returns (uint256)
  {
    return block.timestamp == lastDripTime_ ? 0 : mockNextDepositDripAmount;
  }

  function _assertValidDepositBalance(
    IERC20, /* token_ */
    uint256, /* tokenPoolBalance_ */
    uint256 /* depositAmount_ */
  ) internal view override {
    __readStub__();
  }
}
