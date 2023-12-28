// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../src/interfaces/IReceiptTokenFactory.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IRedemptionErrors} from "../src/interfaces/IRedemptionErrors.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {CozyMath} from "../src/lib/CozyMath.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {Redeemer} from "../src/lib/Redeemer.sol";
import {RedemptionLib} from "../src/lib/RedemptionLib.sol";
import {ReceiptToken} from "../src/ReceiptToken.sol";
import {ReceiptTokenFactory} from "../src/ReceiptTokenFactory.sol";
import {SafetyModuleState} from "../src/lib/SafetyModuleStates.sol";
import {ReservePool} from "../src/lib/structs/Pools.sol";
import {AssetPool} from "../src/lib/structs/Pools.sol";
import {UserRewardsData} from "../src/lib/structs/Rewards.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

abstract contract RedeemerUnitTest is TestBase {
  using CozyMath for uint256;
  using FixedPointMathLib for uint256;

  IReceiptToken stkToken;
  IReceiptToken depositToken;
  MockManager public mockManager = new MockManager();
  TestableRedeemer component = new TestableRedeemer(IManager(address(mockManager)));
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);

  uint128 internal constant UNSTAKE_DELAY = 15 days;
  uint128 internal constant WITHDRAW_DELAY = 20 days;

  bool isUnstakeTest;
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
    if (isUnstakeTest) _stake(reservePoolId_, owner_, reserveAssetAmount_, receiptTokenAmount_);
    else _deposit(reservePoolId_, owner_, reserveAssetAmount_, receiptTokenAmount_);
  }

  function _stake(uint16 reservePoolId_, address staker_, uint256 reserveAssetAmountStaked_, uint256 stkTokenAmount_)
    private
  {
    component.mockStake(reservePoolId_, staker_, reserveAssetAmountStaked_, stkTokenAmount_);
  }

  function _deposit(uint16 reservePoolId_, address owner_, uint256 reserveAssetAmount_, uint256 depositTokenAmount_)
    private
  {
    component.mockDeposit(reservePoolId_, owner_, reserveAssetAmount_, depositTokenAmount_);
  }

  function _depositOrStake(
    uint16 reservePoolId_,
    address owner_,
    uint256 reserveAssetAmount_,
    uint256 receiptTokenAmount_
  ) internal {
    if (isUnstakeTest) _stake(reservePoolId_, owner_, reserveAssetAmount_, receiptTokenAmount_);
    else _deposit(reservePoolId_, owner_, reserveAssetAmount_, receiptTokenAmount_);
  }

  function _redeem(uint16 reservePoolId_, uint256 receiptTokenAmount_, address receiver_, address owner_)
    internal
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_)
  {
    if (isUnstakeTest) return component.unstake(reservePoolId_, receiptTokenAmount_, receiver_, owner_);
    else return component.redeem(reservePoolId_, receiptTokenAmount_, receiver_, owner_);
  }

  function _completeRedeem(uint64 redemptionId_) internal returns (uint256 reserveAssetAmount_) {
    if (isUnstakeTest) return component.completeUnstake(redemptionId_);
    else return component.completeRedemption(redemptionId_);
  }

  function _updateRedemptionsAfterTrigger(uint16 reservePoolId_, uint256 oldReservePoolAmount_, uint256 slashAmount_)
    internal
  {
    if (isUnstakeTest) component.updateUnstakesAfterTrigger(reservePoolId_, oldReservePoolAmount_, slashAmount_);
    else component.updateWithdrawalsAfterTrigger(reservePoolId_, oldReservePoolAmount_, slashAmount_);
  }

  function _getPendingAccISFs(uint16 reservePoolId_) internal view returns (uint256[] memory) {
    if (isUnstakeTest) return component.getPendingUnstakesAccISFs(reservePoolId_);
    else return component.getPendingWithdrawalsAccISFs(reservePoolId_);
  }

  function _setRedemptionDelay(uint128 delay_) internal {
    if (isUnstakeTest) component.mockSetUnstakeDelay(delay_);
    else component.mockSetWithdrawDelay(delay_);
  }

  function _getRedemptionDelay() internal view returns (uint128) {
    if (isUnstakeTest) return component.unstakeDelay();
    else return component.withdrawDelay();
  }

  function setUp() public virtual {
    component.mockSetUnstakeDelay(UNSTAKE_DELAY);
    component.mockSetWithdrawDelay(WITHDRAW_DELAY);

    ReceiptToken receiptTokenLogic_ = new ReceiptToken(IManager(address(mockManager)));
    receiptTokenLogic_.initialize(ISafetyModule(address(0)), 0);
    ReceiptTokenFactory receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(receiptTokenLogic_)), IReceiptToken(address(receiptTokenLogic_)));

    vm.startPrank(address(component));
    stkToken =
      IReceiptToken(address(receiptTokenFactory.deployReceiptToken(0, IReceiptTokenFactory.PoolType.STAKE, 18)));
    depositToken =
      IReceiptToken(address(receiptTokenFactory.deployReceiptToken(0, IReceiptTokenFactory.PoolType.RESERVE, 18)));
    vm.stopPrank();

    component.mockAddReservePool(
      ReservePool({
        asset: IERC20(address(mockAsset)),
        stkToken: IReceiptToken(address(stkToken)),
        depositToken: IReceiptToken(address(depositToken)),
        stakeAmount: 0,
        depositAmount: 0,
        rewardsPoolsWeight: 1e4
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: 0}));

    if (isUnstakeTest) testReceiptToken = stkToken;
    else testReceiptToken = depositToken;
  }

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
    _redeem(0, receiptTokenAmount_, receiver_, owner_);
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

    // Stake/Deposit some extra that belongs to someone else.
    _depositOrStake(0, _randomAddress(), 1e6, 1e18);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(owner_);
    _redeem(0, receiptTokenAmount_ + 1, receiver_, owner_);
  }

  function test_redeem_cannotRedeemIfRoundsDownToZeroAssets() external {
    address owner_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 reserveAssetAmount_ = 1;
    uint256 receiptTokenAmount_ = 3;
    _depositOrStake(0, owner_, reserveAssetAmount_, receiptTokenAmount_);

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
    _redeem(0, receiptTokenAmount_, receiver_, owner_);
    assertEq(testReceiptToken.allowance(owner_, spender_), 1, "receiptToken allowance"); // Only 1 allowance left
      // because
      // of subtraction.
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
    _redeem(0, receiptTokenAmount_, receiver_, owner_);

    // New deposit/stake.
    _depositOrStake(0, _randomAddress(), 1e6, 1e18);

    skip(_getRedemptionDelay());
    // Complete.
    _expectEmit();
    emit Redeemed(
      address(this), receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    _completeRedeem(nextRedemptionId_);

    assertEq(testReceiptToken.balanceOf(owner_), 0, "receiptToken balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), reserveAssetAmount_, "assets balanceOf");
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
    _redeem(0, receiptTokenAmount_, receiver_, owner_);

    skip(_getRedemptionDelay());
    // Complete.
    _completeRedeem(nextRedemptionId_);
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
    uint256 receiptTokensToRedeem_ = receiptTokenAmount_; // Withdraw/unstake 1/4 of all receipt tokens.
    uint256 oldReservePoolAmount_ = reserveAssetAmount_;
    uint256 slashAmount_ = oldReservePoolAmount_ / 10; // Slash 1/10 of the reserve pool.

    // Queue.
    vm.prank(owner_);
    (, uint256 queueResultReserveAssetAmount_) = _redeem(0, receiptTokensToRedeem_, receiver_, owner_);
    assertEq(
      queueResultReserveAssetAmount_,
      receiptTokensToRedeem_.mulDivDown(reserveAssetAmount_, receiptTokenAmount_),
      "resultReserveAssetAmount"
    );

    // Trigger, taking 10% of the reserve pool.
    _updateRedemptionsAfterTrigger(0, oldReservePoolAmount_, slashAmount_);

    skip(_getRedemptionDelay());
    uint256 resultReserveAssetAmount_ = _completeRedeem(nextRedemptionId_);
    // receiptTokens are now worth 90% of what they were before the trigger.
    assertEq(resultReserveAssetAmount_, queueResultReserveAssetAmount_ * 9 / 10 - 1, "reserve assets received");
    assertEq(testReceiptToken.balanceOf(owner_), 0, "receiptToken balanceOf");
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
    if (isUnstakeTest) component.mockSetLastUnstakesAccISF(0, acc_);
    else component.mockSetLastWithdrawalsAccISF(0, acc_);
    _updateRedemptionsAfterTrigger(0, oldReservePoolAmount_, slashAmount_);

    uint256 scale_;
    if (oldReservePoolAmount_ >= slashAmount_ && oldReservePoolAmount_ != 0) {
      scale_ = MathConstants.WAD - slashAmount_.divWadDown(oldReservePoolAmount_);
    }
    uint256[] memory accs_ = _getPendingAccISFs(0);
    if (accs_[0] > RedemptionLib.NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD) assertEq(accs_.length, 2, "accs_.length");
    else assertEq(accs_.length, 1, "accs_.length");
    if (scale_ != 0) assertEq(accs_[0], acc_.mulWadUp(MathConstants.WAD.divWadUp(scale_)), "accs_[0]");
    else assertEq(accs_[0], acc_.mulWadUp(RedemptionLib.INF_INV_SCALING_FACTOR), "accs_[0]");
  }
}

contract UnstakeUnitTest is RedeemerUnitTest {
  function setUp() public override {
    isUnstakeTest = true;
    super.setUp();
  }
}

contract WithdrawUnitTest is RedeemerUnitTest {
  function setUp() public override {
    isUnstakeTest = false;
    super.setUp();
  }
}

contract TestableRedeemer is Redeemer {
  MockManager public immutable mockManager;

  constructor(IManager manager_) {
    mockManager = MockManager(address(manager_));
  }

  function mockStake(uint16 reservePoolId_, address staker_, uint256 reserveAssetAmountStaked_, uint256 stkTokenAmount_)
    external
  {
    mockStakeAssets(reservePoolId_, reserveAssetAmountStaked_);
    mockMintStkTokens(reservePoolId_, staker_, stkTokenAmount_);
  }

  function mockDeposit(
    uint16 reservePoolId_,
    address depositor_,
    uint256 reserveAssetAmountDeposited_,
    uint256 depositTokenAmount_
  ) external {
    mockDepositAssets(reservePoolId_, reserveAssetAmountDeposited_);
    mockMintDepositTokens(reservePoolId_, depositor_, depositTokenAmount_);
  }

  function mockStakeAssets(uint16 reservePoolId_, uint256 reserveAssetAmountStaked_) public {
    if (reserveAssetAmountStaked_ > 0) {
      ReservePool storage reservePool_ = reservePools[reservePoolId_];
      MockERC20(address(reservePool_.asset)).mint(address(this), reserveAssetAmountStaked_);
      reservePool_.stakeAmount += reserveAssetAmountStaked_;
      assetPools[reservePool_.asset].amount += reserveAssetAmountStaked_;
    }
  }

  function mockDepositAssets(uint16 reservePoolId_, uint256 reserveAssetAmountDeposited_) public {
    if (reserveAssetAmountDeposited_ > 0) {
      ReservePool storage reservePool_ = reservePools[reservePoolId_];
      MockERC20(address(reservePool_.asset)).mint(address(this), reserveAssetAmountDeposited_);
      reservePool_.depositAmount += reserveAssetAmountDeposited_;
      assetPools[reservePool_.asset].amount += reserveAssetAmountDeposited_;
    }
  }

  function mockMintStkTokens(uint16 reservePoolId_, address staker_, uint256 stkTokenAmount_) public {
    if (stkTokenAmount_ > 0) MockERC20(address(reservePools[reservePoolId_].stkToken)).mint(staker_, stkTokenAmount_);
  }

  function mockMintDepositTokens(uint16 reservePoolId_, address depositor_, uint256 depositTokenAmount_) public {
    if (depositTokenAmount_ > 0) {
      MockERC20(address(reservePools[reservePoolId_].depositToken)).mint(depositor_, depositTokenAmount_);
    }
  }

  // -------- Mock setters --------

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) public {
    reservePools.push(reservePool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockSetUnstakeDelay(uint128 unstakeDelay_) external {
    unstakeDelay = unstakeDelay_;
  }

  function mockSetWithdrawDelay(uint128 withdrawDelay_) external {
    withdrawDelay = withdrawDelay_;
  }

  function mockSetLastUnstakesAccISF(uint16 reservePoolId_, uint256 acc_) external {
    uint256[] storage pendingUnstakesAccISFs_ = pendingRedemptionAccISFs[reservePoolId_].unstakes;
    if (pendingUnstakesAccISFs_.length == 0) pendingUnstakesAccISFs_.push(acc_);
    else pendingUnstakesAccISFs_[pendingUnstakesAccISFs_.length - 1] = acc_;
  }

  function mockSetLastWithdrawalsAccISF(uint16 reservePoolId_, uint256 acc_) external {
    uint256[] storage pendingWithdrawalsAccISFs_ = pendingRedemptionAccISFs[reservePoolId_].withdrawals;
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

  function getPendingUnstakesAccISFs(uint16 reservePoolId_) external view returns (uint256[] memory) {
    return pendingRedemptionAccISFs[reservePoolId_].unstakes;
  }

  function getPendingWithdrawalsAccISFs(uint16 reservePoolId_) external view returns (uint256[] memory) {
    return pendingRedemptionAccISFs[reservePoolId_].withdrawals;
  }

  // -------- Exposed internals --------

  function updateWithdrawalsAfterTrigger(uint16 reservePoolId_, uint256 oldAmount_, uint256 slashAmount_) external {
    _updateWithdrawalsAfterTrigger(reservePoolId_, uint128(oldAmount_), uint128(slashAmount_));
  }

  function updateUnstakesAfterTrigger(uint16 reservePoolId_, uint256 oldStakeAmount_, uint256 slashAmount_) external {
    _updateUnstakesAfterTrigger(reservePoolId_, uint128(oldStakeAmount_), uint128(slashAmount_));
  }

  function _assertValidDepositBalance(
    IERC20, /* token_ */
    uint256, /* tokenPoolBalance_ */
    uint256 /* depositAmount_ */
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
