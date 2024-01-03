// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IRedemptionErrors} from "../interfaces/IRedemptionErrors.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";
import {AssetPool, ReservePool, UndrippedRewardPool} from "./structs/Pools.sol";
import {MathConstants} from "./MathConstants.sol";
import {PendingRedemptionAccISFs, Redemption, RedemptionPreview} from "./structs/Redemptions.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {CozyMath} from "./CozyMath.sol";
import {RedemptionLib} from "./RedemptionLib.sol";
import {SafeCastLib} from "./SafeCastLib.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";

abstract contract Redeemer is SafetyModuleCommon, IRedemptionErrors {
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;
  using CozyMath for uint256;

  /// @notice List of accumulated inverse scaling factors for redemption, with the last value being the latest,
  ///         on a reward pool basis.
  /// @dev Every time there is a trigger, a scaling factor is retroactively applied to every pending
  ///      redemption equiv to:
  ///        x = 1 - slashedAmount / reservePool.depositAmount (or stakeAmount for unstakes)
  ///      The last value of this array (a) will be updated to be a = a * 1 / x (scaled by WAD).
  ///      Because x will always be <= 1, the accumulated scaling factor will always INCREASE by a factor of 1/x
  ///      and can run out of usable bits (see RedemptionLib.MAX_SAFE_ACCUM_INV_SCALING_FACTOR_VALUE).
  ///      This can even happen after a single trigger if 100% of pool is consumed because 1/0 = INF.
  ///      If this happens, a new entry (1.0) is appended to the end of this array and the next trigger
  ///      will accumulate on that value.
  mapping(uint16 reservePoolId_ => PendingRedemptionAccISFs reservePoolPendingRedemptionAccISFs) internal
    pendingRedemptionAccISFs;

  /// @notice ID of next redemption.
  uint64 internal redemptionIdCounter;
  mapping(uint256 => Redemption) public redemptions;

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

  /// @dev Emitted when a user redeems undripped rewards.
  event RedeemedUndrippedRewards(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    IReceiptToken indexed depositToken_,
    uint256 depositTokenAmount_,
    uint256 rewardAssetAmount_
  );

  /// @notice Redeem by burning `depositTokenAmount_` of `reservePoolId_` reserve pool deposit tokens and sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeem(uint16 reservePoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_)
  {
    dripFees();
    (redemptionId_, reserveAssetAmount_) = _redeem(reservePoolId_, false, depositTokenAmount_, receiver_, owner_);
  }

  /// @notice Redeem by burning `stkTokenAmount_` of `reservePoolId_` reserve pool stake tokens and sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`. Also claims any outstanding rewards
  /// and sends them to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its stake tokens.
  function unstake(uint16 reservePoolId_, uint256 stkTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_)
  {
    dripFees();
    (redemptionId_, reserveAssetAmount_) = _redeem(reservePoolId_, true, stkTokenAmount_, receiver_, owner_);
    claimRewards(reservePoolId_, receiver_);
  }

  /// @notice Redeem by burning `depositTokenAmount_` of `rewardPoolId_` reward pool deposit tokens and sending
  /// `rewardAssetAmount_` of `rewardPoolId_` reward pool assets to `receiver_`. Reward pool assets can only be redeemed
  /// if they have not been dripped yet.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeemUndrippedRewards(uint16 rewardPoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    external
    returns (uint256 rewardAssetAmount_)
  {
    dripRewards();

    UndrippedRewardPool storage undrippedRewardPool_ = undrippedRewardPools[rewardPoolId_];
    IReceiptToken depositToken_ = undrippedRewardPool_.depositToken;
    uint256 lastDripTime_ = dripTimes.lastRewardsDripTime;

    rewardAssetAmount_ = _previewRedemption(
      depositToken_,
      depositTokenAmount_,
      undrippedRewardPool_.dripModel,
      undrippedRewardPool_.amount,
      lastDripTime_,
      block.timestamp - lastDripTime_
    );

    depositToken_.burn(msg.sender, owner_, depositTokenAmount_);
    undrippedRewardPool_.amount -= rewardAssetAmount_;
    undrippedRewardPool_.asset.safeTransfer(receiver_, rewardAssetAmount_);

    emit RedeemedUndrippedRewards(msg.sender, receiver_, owner_, depositToken_, depositTokenAmount_, rewardAssetAmount_);
  }

  /// @notice Completes the redemption request for the specified redemption ID.
  function completeRedemption(uint64 redemptionId_) public returns (uint256 reserveAssetAmount_) {
    Redemption memory redemption_ = redemptions[redemptionId_];
    delete redemptions[redemptionId_];
    return _completeRedemption(redemptionId_, redemption_);
  }

  /// @notice Completes the unstake request for the specified redemption ID.
  function completeUnstake(uint64 redemptionId_) external returns (uint256 reserveAssetAmount_) {
    return completeRedemption(redemptionId_);
  }

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their redemption (i.e. view the number
  /// of reserve assets received) at the current block, given current on-chain conditions.
  function previewQueuedRedemption(uint64 redemptionId_)
    public
    view
    returns (RedemptionPreview memory redemptionPreview_)
  {
    Redemption memory redemption_ = redemptions[redemptionId_];
    redemptionPreview_ = RedemptionPreview({
      delayRemaining: _getRedemptionDelayTimeRemaining(redemption_.queueTime, redemption_.delay).safeCastTo40(),
      receiptToken: redemption_.receiptToken,
      receiptTokenAmount: redemption_.receiptTokenAmount,
      reserveAssetAmount: _computeFinalReserveAssetsRedeemed(
        redemption_.reservePoolId,
        redemption_.assetAmount,
        redemption_.queuedAccISF,
        redemption_.queuedAccISFsLength,
        redemption_.isUnstake
        ),
      owner: redemption_.owner,
      receiver: redemption_.receiver
    });
  }

  function previewReserveAssetsRedemption(uint16 rewardPoolId_, uint256 receiptTokenAmount_, bool isUnstake_)
    external
    view
    returns (uint256 reserveAssetAmount_)
  {
    ReservePool storage reservePool_ = reservePools[rewardPoolId_];
    IDripModel feeDripModel_ = cozyManager.getFeeDripModel(ISafetyModule(address(this)));
    uint256 lastDripTime_ = dripTimes.lastFeesDripTime;

    reserveAssetAmount_ = _previewRedemption(
      isUnstake_ ? reservePool_.stkToken : reservePool_.depositToken,
      receiptTokenAmount_,
      feeDripModel_,
      isUnstake_ ? reservePool_.stakeAmount : reservePool_.depositAmount,
      lastDripTime_,
      block.timestamp - lastDripTime_
    );
  }

  function previewUndrippedRewardsRedemption(uint16 rewardPoolId_, uint256 depositTokenAmount_)
    external
    view
    returns (uint256 rewardAssetAmount_)
  {
    UndrippedRewardPool storage undrippedRewardPool_ = undrippedRewardPools[rewardPoolId_];
    uint256 lastDripTime_ = dripTimes.lastRewardsDripTime;

    rewardAssetAmount_ = _previewRedemption(
      undrippedRewardPool_.depositToken,
      depositTokenAmount_,
      undrippedRewardPool_.dripModel,
      undrippedRewardPool_.amount,
      lastDripTime_,
      block.timestamp - lastDripTime_
    );
  }

  function _previewRedemption(
    IReceiptToken receiptToken_,
    uint256 receiptTokenAmount_,
    IDripModel dripModel_,
    uint256 totalPoolAmount_,
    uint256 lastDripTime_,
    uint256 deltaT_
  ) internal view returns (uint256 assetAmount_) {
    uint256 nextTotalPoolAmount_ =
      totalPoolAmount_ - _getNextDripAmount(totalPoolAmount_, dripModel_, lastDripTime_, deltaT_);

    assetAmount_ = nextTotalPoolAmount_ == 0
      ? 0
      : SafetyModuleCalculationsLib.convertToAssetAmount(
        receiptTokenAmount_, receiptToken_.totalSupply(), nextTotalPoolAmount_
      );
    if (assetAmount_ == 0) revert RoundsToZero(); // Check for rounding error since we round down in conversion.
  }

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their unstake (i.e. view the number
  /// of reserve assets received) at the current block, given current on-chain conditions.
  function previewQueuedUnstake(uint64 unstakeId_) external view returns (RedemptionPreview memory unstakePreview_) {
    return previewQueuedRedemption(unstakeId_);
  }

  /// @notice Redeem by burning `receiptTokenAmount_` of `receiptToken_` and sending `reserveAssetAmount_` to
  /// `receiver_`. `receiptToken` can be the token received from either staking or depositing into the Safety Module.
  /// @dev Assumes that user has approved the SafetyModule to spend its receipt tokens.
  function _redeem(
    uint16 reservePoolId_,
    bool isUnstake_,
    uint256 receiptTokenAmount_,
    address receiver_,
    address owner_
  ) internal returns (uint64 redemptionId_, uint256 reserveAssetAmount_) {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IReceiptToken receiptToken_ = isUnstake_ ? reservePool_.stkToken : reservePool_.depositToken;

    reserveAssetAmount_ = SafetyModuleCalculationsLib.convertToAssetAmount(
      receiptTokenAmount_,
      receiptToken_.totalSupply(),
      isUnstake_ ? reservePool_.stakeAmount : reservePool_.depositAmount
    );
    if (reserveAssetAmount_ == 0) revert RoundsToZero(); // Check for rounding error since we round down in conversion.

    redemptionId_ = _queueRedemption(
      owner_,
      receiver_,
      reservePool_,
      receiptToken_,
      receiptTokenAmount_,
      reserveAssetAmount_,
      reservePoolId_,
      isUnstake_
    );
  }

  /// @dev Logic to queue a redemption.
  function _queueRedemption(
    address owner_,
    address receiver_,
    ReservePool storage reservePool_,
    IReceiptToken receiptToken_,
    uint256 receiptTokenAmount_,
    uint256 reserveAssetAmount_,
    uint16 reservePoolId_,
    bool isUnstake_
  ) internal returns (uint64 redemptionId_) {
    SafetyModuleState safetyModuleState_ = safetyModuleState;
    if (safetyModuleState_ == SafetyModuleState.TRIGGERED) revert InvalidState();
    receiptToken_.burn(msg.sender, owner_, receiptTokenAmount_);

    redemptionId_ = redemptionIdCounter;
    unchecked {
      // Increments can never realistically overflow. Even with a uint64, you'd need to have 1000 redemptions per
      // second for 584,542,046 years.
      redemptionIdCounter = redemptionId_ + 1;
      if (isUnstake_) reservePool_.pendingUnstakesAmount += reserveAssetAmount_;
      else reservePool_.pendingWithdrawalsAmount += reserveAssetAmount_;
    }

    uint256[] storage reservePoolPendingAccISFs = isUnstake_
      ? pendingRedemptionAccISFs[reservePoolId_].unstakes
      : pendingRedemptionAccISFs[reservePoolId_].withdrawals;
    uint256 numScalingFactors_ = reservePoolPendingAccISFs.length;
    Redemption memory redemption_ = Redemption({
      reservePoolId: reservePoolId_,
      receiptToken: receiptToken_,
      receiptTokenAmount: receiptTokenAmount_.safeCastTo216(),
      assetAmount: reserveAssetAmount_.safeCastTo128(),
      owner: owner_,
      receiver: receiver_,
      queueTime: uint40(block.timestamp),
      delay: safetyModuleState_ == SafetyModuleState.PAUSED
        ? 0
        : isUnstake_ ? uint40(delays.unstakeDelay) : uint40(delays.withdrawDelay),
      queuedAccISFsLength: uint32(numScalingFactors_),
      queuedAccISF: numScalingFactors_ == 0 ? MathConstants.WAD : reservePoolPendingAccISFs[numScalingFactors_ - 1],
      isUnstake: isUnstake_
    });

    if (redemption_.delay == 0) {
      _completeRedemption(redemptionId_, redemption_);
    } else {
      redemptions[redemptionId_] = redemption_;
      emit RedemptionPending(
        msg.sender, receiver_, owner_, receiptToken_, receiptTokenAmount_, reserveAssetAmount_, redemptionId_
      );
    }
  }

  /// @dev Logic to complete a redemption.
  function _completeRedemption(uint64 redemptionId_, Redemption memory redemption_)
    internal
    returns (uint128 reserveAssetAmountRedeemed_)
  {
    if (redemption_.owner == address(0)) revert RedemptionNotFound();

    // If the safety module is paused, redemptions can occur instantly.
    {
      if (_getRedemptionDelayTimeRemaining(redemption_.queueTime, redemption_.delay) != 0) revert DelayNotElapsed();
    }

    ReservePool storage reservePool_ = reservePools[redemption_.reservePoolId];
    IERC20 reserveAsset_ = reservePool_.asset;

    // Compute the final reserve assets to redemptions, which can be scaled down if triggers have occurred
    // since the redemption was queued.
    reserveAssetAmountRedeemed_ = _computeFinalReserveAssetsRedeemed(
      redemption_.reservePoolId,
      redemption_.assetAmount,
      redemption_.queuedAccISF,
      redemption_.queuedAccISFsLength,
      redemption_.isUnstake
    );
    if (reserveAssetAmountRedeemed_ != 0) {
      if (redemption_.isUnstake) {
        reservePool_.stakeAmount -= reserveAssetAmountRedeemed_;
        reservePool_.pendingUnstakesAmount -= reserveAssetAmountRedeemed_;
      } else {
        reservePool_.depositAmount -= reserveAssetAmountRedeemed_;
        reservePool_.pendingWithdrawalsAmount -= reserveAssetAmountRedeemed_;
      }
      assetPools[reserveAsset_].amount -= reserveAssetAmountRedeemed_;
      reserveAsset_.safeTransfer(redemption_.receiver, reserveAssetAmountRedeemed_);
    }

    emit Redeemed(
      msg.sender,
      redemption_.receiver,
      redemption_.owner,
      redemption_.receiptToken,
      redemption_.receiptTokenAmount,
      reserveAssetAmountRedeemed_,
      redemptionId_
    );
  }

  /// @inheritdoc SafetyModuleCommon
  function _updateWithdrawalsAfterTrigger(uint16 reservePoolId_, uint256 oldDepositAmount_, uint256 slashAmount_)
    internal
    override
  {
    uint256[] storage reservePoolPendingRedemptionsAccISFs = pendingRedemptionAccISFs[reservePoolId_].withdrawals;
    RedemptionLib.updateRedemptionsAfterTrigger(oldDepositAmount_, slashAmount_, reservePoolPendingRedemptionsAccISFs);
  }

  /// @inheritdoc SafetyModuleCommon
  function _updateUnstakesAfterTrigger(uint16 reservePoolId_, uint256 oldStakeAmount_, uint256 slashAmount_)
    internal
    override
  {
    uint256[] storage reservePoolPendingUnstakesAccISFs = pendingRedemptionAccISFs[reservePoolId_].unstakes;
    RedemptionLib.updateRedemptionsAfterTrigger(oldStakeAmount_, slashAmount_, reservePoolPendingUnstakesAccISFs);
  }

  /// @dev Returns the amount of time remaining before a queued redemption can be completed.
  function _getRedemptionDelayTimeRemaining(uint40 queueTime_, uint256 delay_) internal view returns (uint256) {
    return RedemptionLib.getRedemptionDelayTimeRemaining(safetyModuleState, queueTime_, delay_, block.timestamp);
  }

  /// @dev Returns the amount of tokens to be redeemed, which may be less than the amount saved when the redemption
  /// was queued if the tokens are used in a payout for a trigger since then.
  function _computeFinalReserveAssetsRedeemed(
    uint16 reservePoolId_,
    uint128 queuedReserveAssetAmount_,
    uint256 queuedAccISF_,
    uint32 queuedAccISFLength_,
    bool isUnstake_
  ) internal view returns (uint128) {
    uint256[] storage reservePoolPendingAccISFs_ = isUnstake_
      ? pendingRedemptionAccISFs[reservePoolId_].unstakes
      : pendingRedemptionAccISFs[reservePoolId_].withdrawals;
    return RedemptionLib.computeFinalReserveAssetsRedeemed(
      reservePoolPendingAccISFs_, queuedReserveAssetAmount_, queuedAccISF_, queuedAccISFLength_
    );
  }
}
