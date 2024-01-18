// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../src/interfaces/IReceiptTokenFactory.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
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
import {AssetPool, ReservePool, UndrippedRewardPool} from "../src/lib/structs/Pools.sol";
import {UserRewardsData, ClaimableRewardsData} from "../src/lib/structs/Rewards.sol";
import {RedemptionPreview} from "../src/lib/structs/Redemptions.sol";
import {SafeCastLib} from "../src/lib/SafeCastLib.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockManager} from "./utils/MockManager.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

abstract contract ReedemerUnitTestBase is TestBase {
  using SafeCastLib for uint256;

  IReceiptToken stkToken;
  IReceiptToken depositToken;
  MockManager public mockManager = new MockManager();
  TestableRedeemer component = new TestableRedeemer(IManager(address(mockManager)));
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);

  uint64 internal constant UNSTAKE_DELAY = 15 days;
  uint64 internal constant WITHDRAW_DELAY = 20 days;

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

  function _depositOrStakeAssets(uint16 reservePoolId_, uint256 amount_) internal {
    if (isUnstakeTest) component.mockStakeAssets(reservePoolId_, amount_);
    else component.mockDepositAssets(reservePoolId_, amount_);
  }

  function _redeem(uint16 reservePoolId_, uint256 receiptTokenAmount_, address receiver_, address owner_)
    internal
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_)
  {
    if (isUnstakeTest) return component.unstake(reservePoolId_, receiptTokenAmount_, receiver_, owner_);
    else return component.redeem(reservePoolId_, receiptTokenAmount_, receiver_, owner_);
  }

  function _completeRedeem(uint64 redemptionId_) internal returns (uint256 reserveAssetAmount_) {
    return component.completeRedemption(redemptionId_);
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

  function _setRedemptionDelay(uint64 delay_) internal {
    if (isUnstakeTest) component.mockSetUnstakeDelay(delay_);
    else component.mockSetWithdrawDelay(delay_);
  }

  function _getRedemptionDelay() internal view returns (uint64) {
    (,, uint64 unstakeDelay_, uint64 withdrawDelay_) = component.delays();
    if (isUnstakeTest) return unstakeDelay_;
    else return withdrawDelay_;
  }

  function _mintReceiptToken(uint16 reservePoolId_, address receiver_, uint256 amount_) internal {
    if (isUnstakeTest) component.mockMintStkTokens(reservePoolId_, receiver_, amount_);
    else component.mockMintDepositTokens(reservePoolId_, receiver_, amount_);
  }

  function _getReceiptToken(uint16 reservePoolId_) internal view returns (IERC20) {
    ReservePool memory reservePool_ = component.getReservePool(reservePoolId_);
    if (isUnstakeTest) return reservePool_.stkToken;
    else return reservePool_.depositToken;
  }

  function _setNextDripAmount(uint256 amount_) internal {
    if (isUnstakeTest) component.mockSetNextStakeDripAmount(amount_);
    else component.mockSetNextDepositDripAmount(amount_);
  }

  function _assertReservePoolAccounting(
    uint16 reservePoolId_,
    uint256 poolAssetAmount_,
    uint256 assetsPendingRedemption_
  ) internal {
    ReservePool memory reservePool_ = component.getReservePool(reservePoolId_);
    if (isUnstakeTest) {
      assertEq(reservePool_.pendingUnstakesAmount, assetsPendingRedemption_, "reservePool_.pendingUnstakesAmount");
      assertEq(reservePool_.stakeAmount, poolAssetAmount_, "reservePool_.stakeAmount");
    } else {
      assertEq(reservePool_.pendingWithdrawalsAmount, assetsPendingRedemption_, "reservePool_.pendingWithdrawalsAmount");
      assertEq(reservePool_.depositAmount, poolAssetAmount_, "reservePool_.depositAmount");
    }
  }

  function setUp() public virtual {
    component.mockSetUnstakeDelay(UNSTAKE_DELAY);
    component.mockSetWithdrawDelay(WITHDRAW_DELAY);

    ReceiptToken receiptTokenLogic_ = new ReceiptToken();
    receiptTokenLogic_.initialize(ISafetyModule(address(0)), "", "", 0);
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
        feeAmount: 0,
        pendingUnstakesAmount: 0,
        pendingWithdrawalsAmount: 0,
        rewardsPoolsWeight: 1e4,
        maxSlashPercentage: MathConstants.WAD,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddRewardPool(
      UndrippedRewardPool({
        asset: IERC20(address(mockAsset)),
        amount: 0,
        dripModel: IDripModel(address(0)),
        depositToken: IReceiptToken(address(0)),
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: 0}));

    if (isUnstakeTest) testReceiptToken = stkToken;
    else testReceiptToken = depositToken;
  }
}

abstract contract RedeemerUnitTest is ReedemerUnitTestBase {
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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    emit TestableRedeemerEvents.DripFeesCalled();
    _expectEmit();
    emit RedemptionPending(
      owner_, receiver_, owner_, testReceiptToken, receiptTokenAmount_, reserveAssetAmount_, nextRedemptionId_
    );
    vm.prank(owner_);
    (, uint256 resultReserveAssetAmount_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);
    _assertReservePoolAccounting(0, reserveAssetAmount_, resultReserveAssetAmount_);

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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    emit TestableRedeemerEvents.DripFeesCalled();
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
    uint256 receiptTokensToRedeem_ = receiptTokenAmount_; // Withdraw/unstake 1/4 of all receipt tokens.
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
    _depositOrStakeAssets(0, totalAssets_);

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
        _expectEmit();
        emit TestableRedeemerEvents.DripFeesCalled();
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
    _depositOrStakeAssets(0, totalAssets_);

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
        emit TestableRedeemerEvents.DripFeesCalled();
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
    uint256 previewRedeemedAssets_ = component.previewRedemption(0, receiptTokenAmount_, isUnstakeTest);
    vm.prank(owner_);
    (, uint256 resultRedeemedAssets_) = _redeem(0, receiptTokenAmount_, receiver_, owner_);
    assertEq(previewRedeemedAssets_, resultRedeemedAssets_, "redeemed assets");
    assertEq(previewRedeemedAssets_, reserveAssetAmount_ * 3 / 4);
  }

  function test_previewRedemption_roundsDownToZero() external {
    address owner_ = _randomAddress();
    uint256 reserveAssetAmount_ = 1;
    uint256 receiptTokenAmount_ = 3;
    _depositOrStake(0, owner_, reserveAssetAmount_, receiptTokenAmount_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    component.previewRedemption(0, 2, isUnstakeTest);
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
}

contract UnstakeUnitTest is RedeemerUnitTest {
  using CozyMath for uint256;
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  // Emitted when rewards are claimed.
  event ClaimedRewards(
    uint16 indexed reservePoolId,
    IERC20 indexed rewardAsset_,
    uint256 amount_,
    address indexed owner_,
    address receiver_
  );

  function setUp() public override {
    isUnstakeTest = true;
    super.setUp();
  }

  function test_redeem_withRewardsClaim() external {
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

    uint256 rewardsClaimAmountToReceive_ = 1e6;
    component.mockSetNextRewardClaimAmount(rewardsClaimAmountToReceive_);

    _expectEmit();
    emit TestableRedeemerEvents.MockClaimedRewards();
    _expectEmit();
    emit Transfer(owner_, address(0), receiptTokenAmountToRedeem_);
    _expectEmit();
    emit RedemptionPending(
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
    // Only rewards assets are received at the first step of redemption.
    assertEq(mockAsset.balanceOf(receiver_), rewardsClaimAmountToReceive_, "reserve assets balanceOf");
    _assertReservePoolAccounting(0, reserveAssetAmount_, resultReserveAssetAmount_);
  }
}

contract WithdrawUnitTest is RedeemerUnitTest {
  function setUp() public override {
    isUnstakeTest = false;
    super.setUp();
  }
}

contract RedeemUndrippedRewards is TestBase {
  using SafeCastLib for uint256;

  IReceiptToken depositToken;
  MockManager public mockManager = new MockManager();
  TestableRedeemer component = new TestableRedeemer(IManager(address(mockManager)));
  MockERC20 mockAsset = new MockERC20("Mock Asset", "MOCK", 6);

  /// @dev Emitted when a user redeems undripped rewards.
  event RedeemedUndrippedRewards(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed receiptToken_,
    uint256 receiptTokenAmount_,
    uint256 rewardAssetAmount_
  );

  event Transfer(address indexed from, address indexed to, uint256 amount);

  function _setupDefaultSingleUserFixture(uint16 rewardPoolId_)
    internal
    returns (address owner_, address receiver_, uint256 rewardAssetAmount_, uint256 depositTokenAmount_)
  {
    owner_ = _randomAddress();
    receiver_ = _randomAddress();
    rewardAssetAmount_ = 1e6;
    depositTokenAmount_ = 1e18;
    _deposit(rewardPoolId_, owner_, rewardAssetAmount_, depositTokenAmount_);
  }

  function _deposit(uint16 rewardPoolId_, address owner_, uint256 rewardAssetAmount_, uint256 depositTokenAmount_)
    private
  {
    component.mockRewardsDeposit(rewardPoolId_, owner_, rewardAssetAmount_, depositTokenAmount_);
  }

  function _redeem(uint16 rewardPoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    internal
    returns (uint256 rewardAssetAmount_)
  {
    return component.redeemUndrippedRewards(rewardPoolId_, depositTokenAmount_, receiver_, owner_);
  }

  function _assertRewardPoolAccounting(uint16 reservePoolId_, uint256 poolAssetAmount_) internal {
    UndrippedRewardPool memory rewardPool_ = component.getUndrippedRewardPool(reservePoolId_);
    assertEq(rewardPool_.amount, poolAssetAmount_, "rewardPool_.amount");
  }

  function setUp() public {
    ReceiptToken receiptTokenLogic_ = new ReceiptToken();
    receiptTokenLogic_.initialize(ISafetyModule(address(0)), "", "", 0);
    ReceiptTokenFactory receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(receiptTokenLogic_)), IReceiptToken(address(receiptTokenLogic_)));

    vm.startPrank(address(component));
    depositToken =
      IReceiptToken(address(receiptTokenFactory.deployReceiptToken(0, IReceiptTokenFactory.PoolType.REWARD, 18)));
    vm.stopPrank();

    component.mockAddRewardPool(
      UndrippedRewardPool({
        asset: IERC20(address(mockAsset)),
        amount: 0,
        dripModel: IDripModel(address(0)),
        depositToken: IReceiptToken(address(depositToken)),
        cumulativeDrippedRewards: 0,
        lastDripTime: uint128(block.timestamp)
      })
    );
    component.mockAddAssetPool(IERC20(address(mockAsset)), AssetPool({amount: 0}));
  }

  function test_redeemUndrippedRewards_redeemAll() public {
    (address owner_, address receiver_, uint256 rewardAssetAmount_, uint256 depositTokenAmount_) =
      _setupDefaultSingleUserFixture(0);

    _expectEmit();
    emit Transfer(owner_, address(0), depositTokenAmount_);
    _expectEmit();
    emit RedeemedUndrippedRewards(owner_, receiver_, owner_, depositToken, depositTokenAmount_, rewardAssetAmount_);

    vm.prank(owner_);
    (uint256 resultRewardAssetAmount_) = _redeem(0, depositTokenAmount_, receiver_, owner_);

    assertEq(resultRewardAssetAmount_, rewardAssetAmount_, "reward assets received");
    assertEq(depositToken.balanceOf(owner_), 0, "deposit tokens balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), resultRewardAssetAmount_, "reward assets balanceOf");
    _assertRewardPoolAccounting(0, 0);
  }

  function test_redeemUndrippedRewards_redeemPartial() public {
    (address owner_, address receiver_, uint256 rewardAssetAmount_, uint256 depositTokenAmount_) =
      _setupDefaultSingleUserFixture(0);

    _expectEmit();
    emit Transfer(owner_, address(0), depositTokenAmount_ / 2);
    _expectEmit();
    emit RedeemedUndrippedRewards(
      owner_, receiver_, owner_, depositToken, depositTokenAmount_ / 2, rewardAssetAmount_ / 2
    );

    vm.prank(owner_);
    (uint256 resultRewardAssetAmount_) = _redeem(0, depositTokenAmount_ / 2, receiver_, owner_);

    assertEq(resultRewardAssetAmount_, rewardAssetAmount_ / 2, "reward assets received");
    assertEq(depositToken.balanceOf(owner_), depositTokenAmount_ / 2, "deposit tokens balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), resultRewardAssetAmount_, "reward assets balanceOf");
    _assertRewardPoolAccounting(0, rewardAssetAmount_ / 2);
  }

  function test_redeemUndrippedRewards_withDrip() public {
    (address owner_, address receiver_, uint256 rewardAssetAmount_, uint256 depositTokenAmount_) =
      _setupDefaultSingleUserFixture(0);

    // Drip half of the assets in the undripped reward pool.
    component.mockSetNextRewardsDripAmount(rewardAssetAmount_ / 2);

    _expectEmit();
    emit Transfer(owner_, address(0), depositTokenAmount_ / 2);
    _expectEmit();
    emit RedeemedUndrippedRewards(
      owner_, receiver_, owner_, depositToken, depositTokenAmount_ / 2, rewardAssetAmount_ / 4
    );

    vm.prank(owner_);
    (uint256 resultRewardAssetAmount_) = _redeem(0, depositTokenAmount_ / 2, receiver_, owner_);

    assertEq(resultRewardAssetAmount_, rewardAssetAmount_ / 4, "reward assets received");
    assertEq(depositToken.balanceOf(owner_), depositTokenAmount_ / 2, "deposit tokens balanceOf");
    assertEq(mockAsset.balanceOf(receiver_), resultRewardAssetAmount_, "reward assets balanceOf");
    _assertRewardPoolAccounting(0, rewardAssetAmount_ / 4);
  }

  function test_redeemUndrippedRewards_cannotRedeemIfRoundsDownToZeroAssets() external {
    address owner_ = _randomAddress();
    address receiver_ = _randomAddress();
    uint256 rewardAssetAmount_ = 1;
    uint256 depositTokenAmount_ = 3;
    _deposit(0, owner_, rewardAssetAmount_, depositTokenAmount_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    vm.prank(owner_);
    _redeem(0, 2, receiver_, owner_);
  }

  function test_redeemUndrippedRewards_canRedeemAllInstantly_ThroughAllowance() external {
    (address owner_, address receiver_, uint256 rewardAssetAmount_, uint256 depositTokenAmount_) =
      _setupDefaultSingleUserFixture(0);
    address spender_ = _randomAddress();
    vm.prank(owner_);
    depositToken.approve(spender_, depositTokenAmount_ + 1); // Allowance is 1 extra.

    _expectEmit();
    emit RedeemedUndrippedRewards(spender_, receiver_, owner_, depositToken, depositTokenAmount_, rewardAssetAmount_);

    vm.prank(spender_);
    _redeem(0, depositTokenAmount_, receiver_, owner_);
    assertEq(depositToken.allowance(owner_, spender_), 1, "depositToken allowance"); // Only 1 allowance left because of
      // subtraction.
    _assertRewardPoolAccounting(0, 0);
  }

  function test_redeemUndrippedRewards_cannotRedeem_ThroughAllowance_WithInsufficientAllowance() external {
    (address owner_, address receiver_,, uint256 depositTokenAmount_) = _setupDefaultSingleUserFixture(0);
    address spender_ = _randomAddress();
    vm.prank(owner_);
    depositToken.approve(spender_, depositTokenAmount_ - 1); // Allowance is 1 less.

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(spender_);
    _redeem(0, depositTokenAmount_, receiver_, owner_);
  }

  function test_redeemUndrippedRewards_cannotRedeem_InsufficientDepositTokenBalance() external {
    (address owner_, address receiver_,, uint256 depositTokenAmount_) = _setupDefaultSingleUserFixture(0);

    _expectPanic(PANIC_MATH_UNDEROVERFLOW);
    vm.prank(owner_);
    _redeem(0, depositTokenAmount_ + 1, receiver_, owner_);
  }

  function test_redeemUndrippedRewards_cannotRedeem_InvalidRewardPoolId() external {
    (address owner_, address receiver_,, uint256 depositTokenAmount_) = _setupDefaultSingleUserFixture(0);

    _expectPanic(PANIC_ARRAY_OUT_OF_BOUNDS);
    vm.prank(owner_);
    _redeem(1, depositTokenAmount_, receiver_, owner_);
  }

  function test_redeemUndrippedRewards_previewUndrippedRewardsRedemption_withDrip() external {
    (address owner_, address receiver_, uint256 rewardAssetAmount_, uint256 depositTokenAmount_) =
      _setupDefaultSingleUserFixture(0);

    // Next drip (which occurs on redeem), drip half of the assets in the undripped reward pool.
    vm.warp(100);
    component.mockSetNextRewardsDripAmount(rewardAssetAmount_ / 2);

    uint256 previewRewardAssetAmount_ = component.previewUndrippedRewardsWithdrawal(0, depositTokenAmount_);

    vm.prank(owner_);
    uint256 resultRewardAssetAmount_ = _redeem(0, depositTokenAmount_, receiver_, owner_);

    assertEq(previewRewardAssetAmount_, resultRewardAssetAmount_, "preview reward assets received");
    assertEq(resultRewardAssetAmount_, rewardAssetAmount_ / 2, "reward assets received");
    assertEq(mockAsset.balanceOf(receiver_), resultRewardAssetAmount_, "reward assets balanceOf");
    _assertRewardPoolAccounting(0, rewardAssetAmount_ / 2 - resultRewardAssetAmount_);
  }

  function test_redeemUndrippedRewards_previewUndrippedRewardsRedemption_fullyDripped() external {
    (address owner_, address receiver_, uint256 rewardAssetAmount_, uint256 depositTokenAmount_) =
      _setupDefaultSingleUserFixture(0);

    // Next drip (which occurs on redeem), drip half of the assets in the undripped reward pool.
    vm.warp(100);
    component.mockSetNextRewardsDripAmount(rewardAssetAmount_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    component.previewUndrippedRewardsWithdrawal(0, depositTokenAmount_);

    vm.prank(owner_);
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    _redeem(0, depositTokenAmount_, receiver_, owner_);
  }

  function test_redeemUndrippedRewards_previewUndrippedRewardsRedemption_roundsDownToZero() external {
    address owner_ = _randomAddress();
    uint256 reserveAssetAmount_ = 1;
    uint256 receiptTokenAmount_ = 3;
    _deposit(0, owner_, reserveAssetAmount_, receiptTokenAmount_);

    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    component.previewUndrippedRewardsWithdrawal(0, 2);
  }
}

interface TestableRedeemerEvents {
  event MockClaimedRewards();
  event DripFeesCalled();
}

contract TestableRedeemer is Redeemer, TestableRedeemerEvents {
  using SafeCastLib for uint256;

  enum DripType {
    REWARDS,
    DEPOSITS,
    STAKES
  }

  uint256 internal mockNextRewardsDripAmount;
  uint256 internal mockNextDepositDripAmount;
  uint256 internal mockNextStakeDripAmount;
  DripType internal mockNextDripType;
  uint256 internal mockNextRewardClaimAmount;

  constructor(IManager manager_) {
    cozyManager = manager_;
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

  function mockRewardsDeposit(
    uint16 rewardPoolId_,
    address depositor_,
    uint256 rewardAssetAmountDeposited_,
    uint256 depositTokenAmount_
  ) external {
    mockDepositRewardAssets(rewardPoolId_, rewardAssetAmountDeposited_);
    mockMintRewardDepositTokens(rewardPoolId_, depositor_, depositTokenAmount_);
  }

  function mockDepositAssets(uint16 reservePoolId_, uint256 reserveAssetAmountDeposited_) public {
    if (reserveAssetAmountDeposited_ > 0) {
      ReservePool storage reservePool_ = reservePools[reservePoolId_];
      MockERC20(address(reservePool_.asset)).mint(address(this), reserveAssetAmountDeposited_);
      reservePool_.depositAmount += reserveAssetAmountDeposited_;
      assetPools[reservePool_.asset].amount += reserveAssetAmountDeposited_;
    }
  }

  function mockDepositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmountDeposited_) public {
    if (rewardAssetAmountDeposited_ > 0) {
      UndrippedRewardPool storage rewardPool_ = undrippedRewardPools[rewardPoolId_];
      MockERC20(address(rewardPool_.asset)).mint(address(this), rewardAssetAmountDeposited_);
      rewardPool_.amount += rewardAssetAmountDeposited_;
      assetPools[rewardPool_.asset].amount += rewardAssetAmountDeposited_;
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

  function mockMintRewardDepositTokens(uint16 rewardPoolId_, address depositor_, uint256 depositTokenAmount_) public {
    if (depositTokenAmount_ > 0) {
      MockERC20(address(undrippedRewardPools[rewardPoolId_].depositToken)).mint(depositor_, depositTokenAmount_);
    }
  }

  // -------- Mock setters --------
  function mockSetNextDepositDripAmount(uint256 nextDripAmount_) external {
    mockNextDepositDripAmount = nextDripAmount_;
    mockNextDripType = DripType.DEPOSITS;
  }

  function mockSetNextStakeDripAmount(uint256 nextDripAmount_) external {
    mockNextStakeDripAmount = nextDripAmount_;
    mockNextDripType = DripType.STAKES;
  }

  function mockSetNextRewardsDripAmount(uint256 nextDripAmount_) external {
    mockNextRewardsDripAmount = nextDripAmount_;
    mockNextDripType = DripType.REWARDS;
  }

  function mockSetNextRewardClaimAmount(uint256 nextRewardClaimAmount_) external {
    mockNextRewardClaimAmount = nextRewardClaimAmount_;
  }

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) public {
    reservePools.push(reservePool_);
  }

  function mockAddRewardPool(UndrippedRewardPool memory rewardPool_) external {
    undrippedRewardPools.push(rewardPool_);
  }

  function mockAddAssetPool(IERC20 asset_, AssetPool memory assetPool_) external {
    assetPools[asset_] = assetPool_;
  }

  function mockSetUnstakeDelay(uint64 unstakeDelay_) external {
    delays.unstakeDelay = unstakeDelay_;
  }

  function mockSetWithdrawDelay(uint64 withdrawDelay_) external {
    delays.withdrawDelay = withdrawDelay_;
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

  function getUndrippedRewardPool(uint16 rewardPoolId_) external view returns (UndrippedRewardPool memory) {
    return undrippedRewardPools[rewardPoolId_];
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
    _updateWithdrawalsAfterTrigger(reservePoolId_, reservePools[reservePoolId_], oldAmount_, slashAmount_);
  }

  function updateUnstakesAfterTrigger(uint16 reservePoolId_, uint256 oldStakeAmount_, uint256 slashAmount_) external {
    _updateUnstakesAfterTrigger(reservePoolId_, reservePools[reservePoolId_], oldStakeAmount_, slashAmount_);
  }

  // -------- Overridden common abstract functions --------

  function claimRewards(uint16, /* reservePoolId_ */ address receiver_) public override {
    MockERC20 rewardAsset_ = MockERC20(address(undrippedRewardPools[0].asset));
    rewardAsset_.mint(receiver_, mockNextRewardClaimAmount);
    emit MockClaimedRewards();
  }

  // Mock drip of rewards based on mocked next amount.
  function dripRewards() public override {
    UndrippedRewardPool storage undrippedRewardPool_ = undrippedRewardPools[0];
    uint256 totalDrippedRewards_ = mockNextRewardsDripAmount;

    if (totalDrippedRewards_ > 0) undrippedRewardPool_.amount -= totalDrippedRewards_;

    undrippedRewardPool_.lastDripTime = uint128(block.timestamp);
  }

  function dripFees() public override {
    if (mockNextDripType == DripType.REWARDS) {
      emit DripFeesCalled();
      return;
    }

    ReservePool storage reservePool_ = reservePools[0];
    if (mockNextDripType == DripType.DEPOSITS) reservePool_.depositAmount -= mockNextDepositDripAmount;
    else reservePool_.stakeAmount -= mockNextStakeDripAmount;

    reservePool_.lastFeesDripTime = uint128(block.timestamp);
  }

  function _dripRewardPool(UndrippedRewardPool storage undrippedRewardPool_) internal override {
    uint256 totalDrippedRewards_ = mockNextRewardsDripAmount;
    if (totalDrippedRewards_ > 0) undrippedRewardPool_.amount -= totalDrippedRewards_;
    undrippedRewardPool_.lastDripTime = uint128(block.timestamp);
  }

  function _dripFeesFromReservePool(ReservePool storage reservePool_, IDripModel /* dripModel_*/ ) internal override {
    if (mockNextDripType == DripType.REWARDS) {
      emit DripFeesCalled();
      return;
    }

    if (mockNextDripType == DripType.DEPOSITS) reservePool_.depositAmount -= mockNextDepositDripAmount;
    else reservePool_.stakeAmount -= mockNextStakeDripAmount;

    reservePool_.lastFeesDripTime = uint128(block.timestamp);
  }

  function _getNextDripAmount(
    uint256, /* totalBaseAmount_ */
    IDripModel, /* dripModel_ */
    uint256 lastDripTime_,
    uint256 /* deltaT_ */
  ) internal view override returns (uint256) {
    if (mockNextDripType == DripType.REWARDS) {
      return block.timestamp - lastDripTime_ == 0 ? 0 : mockNextRewardsDripAmount;
    } else if (mockNextDripType == DripType.DEPOSITS) {
      return block.timestamp == lastDripTime_ ? 0 : mockNextDepositDripAmount;
    } else {
      return block.timestamp == lastDripTime_ ? 0 : mockNextStakeDripAmount;
    }
  }

  function _computeNextDripAmount(uint256, /* totalBaseAmount_ */ uint256 /* dripFactor_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _assertValidDepositBalance(
    IERC20, /* token_ */
    uint256, /* tokenPoolBalance_ */
    uint256 /* depositAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _updateUserRewards(
    uint256, /* userStkTokenBalance */
    mapping(uint16 => ClaimableRewardsData) storage, /* claimableRewardsIndices_ */
    UserRewardsData[] storage /* userRewards_ */
  ) internal view override {
    __readStub__();
  }

  function _applyPendingDrippedRewards(
    ReservePool storage, /* reservePool_ */
    mapping(uint16 => ClaimableRewardsData) storage /* claimableRewards_ */
  ) internal view override {
    __readStub__();
  }

  function _dripAndResetCumulativeRewardsValues(
    ReservePool[] storage, /* reservePools_ */
    UndrippedRewardPool[] storage /* undrippedRewardPools_ */
  ) internal view override {
    __readStub__();
  }
}
