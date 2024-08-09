// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IRedemptionErrors} from "../interfaces/IRedemptionErrors.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";
import {AssetPool, ReservePool} from "./structs/Pools.sol";
import {Redemption, RedemptionPreview} from "./structs/Redemptions.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {CozyMath} from "./CozyMath.sol";
import {RedemptionLib} from "./RedemptionLib.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";

abstract contract Redeemer is SafetyModuleCommon, IRedemptionErrors {
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;
  using CozyMath for uint256;

  /// @notice List of accumulated inverse scaling factors for redemption, with the last value being the latest,
  ///         on a reserve pool basis.
  /// @dev Every time there is a trigger, a scaling factor is retroactively applied to every pending
  ///      redemption equiv to:
  ///        x = 1 - slashedAmount / reservePool.depositAmount
  ///      The last value of this array (a) will be updated to be a = a * 1 / x (scaled by WAD).
  ///      Because x will always be <= 1, the accumulated scaling factor will always INCREASE by a factor of 1/x
  ///      and can run out of usable bits (see RedemptionLib.MAX_SAFE_ACCUM_INV_SCALING_FACTOR_VALUE).
  ///      This can even happen after a single trigger if 100% of pool is consumed because 1/0 = INF.
  ///      If this happens, a new entry (1.0) is appended to the end of this array and the next trigger
  ///      will accumulate on that value.
  mapping(uint8 reservePoolId_ => uint256[] reservePoolPendingRedemptionAccISFs) internal pendingRedemptionAccISFs;

  /// @notice ID of next redemption.
  uint64 internal redemptionIdCounter;
  mapping(uint256 => Redemption) public redemptions;

  /// @dev Emitted when a user redeems.
  event Redeemed(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint8 indexed reservePoolId_,
    IReceiptToken receiptToken_,
    uint256 receiptTokenAmount_,
    uint256 reserveAssetAmount_,
    uint64 redemptionId_
  );

  /// @dev Emitted when a user queues an redemption.
  event RedemptionPending(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint8 indexed reservePoolId_,
    IReceiptToken receiptToken_,
    uint256 receiptTokenAmount_,
    uint256 reserveAssetAmount_,
    uint64 redemptionId_
  );

  /// @notice Queues a redemption by burning `depositReceiptTokenAmount_` of `reservePoolId_` reserve pool deposit
  /// tokens.
  /// When the redemption is completed, `reserveAssetAmount_` of `reservePoolId_` reserve pool assets will be sent
  /// to `receiver_` if the reserve pool's assets are not slashed. If the SafetyModule is paused, the redemption
  /// will be completed instantly.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  /// @param reservePoolId_ The ID of the reserve pool to redeem from.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to redeem.
  /// @param receiver_ The address to receive the reserve assets.
  /// @param owner_ The address that owns the deposit receipt tokens.
  function redeem(uint8 reservePoolId_, uint256 depositReceiptTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_)
  {
    SafetyModuleState safetyModuleState_ = safetyModuleState;
    if (safetyModuleState_ == SafetyModuleState.TRIGGERED) revert InvalidState();

    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    if (safetyModuleState_ == SafetyModuleState.ACTIVE) {
      _dripFeesFromReservePool(reservePool_, cozySafetyModuleManager.getFeeDripModel(ISafetyModule(address(this))));
    }

    IReceiptToken receiptToken_ = reservePool_.depositReceiptToken;
    {
      // Fees were dripped already in this function if the SafetyModule is active, so we don't need to accomodate for
      // next fee drip amount here.
      uint256 assetsAvailableForRedemption_ = reservePool_.depositAmount - reservePool_.pendingWithdrawalsAmount;
      if (assetsAvailableForRedemption_ == 0) revert NoAssetsToRedeem();

      // Fees were dripped already in this function if the SafetyModule is active, so we can use the
      // SafetyModuleCalculationsLib directly. Fees do not drip while the SafetyModule is not active.
      reserveAssetAmount_ = SafetyModuleCalculationsLib.convertToAssetAmount(
        depositReceiptTokenAmount_, receiptToken_.totalSupply(), assetsAvailableForRedemption_
      );
      if (reserveAssetAmount_ == 0) revert RoundsToZero(); // Check for rounding error since we round down in
        // conversion.
    }

    redemptionId_ = _queueRedemption(
      owner_,
      receiver_,
      reservePool_,
      receiptToken_,
      depositReceiptTokenAmount_,
      reserveAssetAmount_,
      reservePoolId_,
      safetyModuleState_
    );
  }

  /// @notice Completes the redemption request for the specified redemption ID.
  /// @param redemptionId_ The ID of the redemption to complete.
  function completeRedemption(uint64 redemptionId_) external returns (uint256 reserveAssetAmount_) {
    Redemption memory redemption_ = redemptions[redemptionId_];
    delete redemptions[redemptionId_];
    return _completeRedemption(redemptionId_, redemption_);
  }

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their redemption (i.e. view the number
  /// of reserve assets received) at the current block, given current on-chain conditions.
  /// @param reservePoolId_ The ID of the reserve pool to redeem from.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to redeem.
  function previewRedemption(uint8 reservePoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_)
  {
    if (safetyModuleState == SafetyModuleState.TRIGGERED) revert InvalidState();
    return convertToReserveAssetAmount(reservePoolId_, depositReceiptTokenAmount_);
  }

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their queued redemption (i.e. view the
  /// number of reserve assets received) at the current block, given current on-chain conditions.
  /// @param redemptionId_ The ID of the redemption to preview.
  function previewQueuedRedemption(uint64 redemptionId_)
    external
    view
    returns (RedemptionPreview memory redemptionPreview_)
  {
    Redemption memory redemption_ = redemptions[redemptionId_];
    redemptionPreview_ = RedemptionPreview({
      delayRemaining: _getRedemptionDelayTimeRemaining(redemption_.queueTime, redemption_.delay).safeCastTo40(),
      receiptToken: redemption_.receiptToken,
      receiptTokenAmount: redemption_.receiptTokenAmount,
      reserveAssetAmount: _computeFinalReserveAssetsRedeemed(
        redemption_.reservePoolId, redemption_.assetAmount, redemption_.queuedAccISF, redemption_.queuedAccISFsLength
      ),
      owner: redemption_.owner,
      receiver: redemption_.receiver
    });
  }

  /// @notice Logic to queue a redemption.
  /// @param owner_ The owner of the deposit receipt tokens.
  /// @param receiver_ The address to receive the reserve assets.
  /// @param reservePool_ The reserve pool to redeem from.
  /// @param depositReceiptToken_ The deposit receipt token being redeemed.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to redeem.
  /// @param reserveAssetAmount_ The amount of reserve assets to redeem.
  /// @param reservePoolId_ The ID of the reserve pool to redeem from.
  /// @param safetyModuleState_ The current state of the SafetyModule.
  function _queueRedemption(
    address owner_,
    address receiver_,
    ReservePool storage reservePool_,
    IReceiptToken depositReceiptToken_,
    uint256 depositReceiptTokenAmount_,
    uint256 reserveAssetAmount_,
    uint8 reservePoolId_,
    SafetyModuleState safetyModuleState_
  ) internal returns (uint64 redemptionId_) {
    depositReceiptToken_.burn(msg.sender, owner_, depositReceiptTokenAmount_);

    redemptionId_ = redemptionIdCounter;
    unchecked {
      // Increments can never realistically overflow. Even with a uint64, you'd need to have 1000 redemptions per
      // second for 584,542,046 years.
      redemptionIdCounter = redemptionId_ + 1;
      reservePool_.pendingWithdrawalsAmount += reserveAssetAmount_;
    }

    uint256[] storage reservePoolPendingAccISFs = pendingRedemptionAccISFs[reservePoolId_];
    uint256 numScalingFactors_ = reservePoolPendingAccISFs.length;
    Redemption memory redemption_ = Redemption({
      reservePoolId: reservePoolId_,
      receiptToken: depositReceiptToken_,
      receiptTokenAmount: depositReceiptTokenAmount_.safeCastTo216(),
      assetAmount: reserveAssetAmount_.safeCastTo128(),
      owner: owner_,
      receiver: receiver_,
      queueTime: uint40(block.timestamp),
      // If the safety module is paused, redemptions can occur instantly.
      delay: safetyModuleState_ == SafetyModuleState.PAUSED ? 0 : uint40(delays.withdrawDelay),
      queuedAccISFsLength: uint32(numScalingFactors_),
      // If there are no scaling factors, the last scaling factor is 1.0.
      queuedAccISF: numScalingFactors_ == 0 ? MathConstants.WAD : reservePoolPendingAccISFs[numScalingFactors_ - 1]
    });

    if (redemption_.delay == 0) {
      _completeRedemption(redemptionId_, redemption_);
    } else {
      redemptions[redemptionId_] = redemption_;
      emit RedemptionPending(
        msg.sender,
        receiver_,
        owner_,
        reservePoolId_,
        depositReceiptToken_,
        depositReceiptTokenAmount_,
        reserveAssetAmount_,
        redemptionId_
      );
    }
  }

  /// @notice Logic to complete a redemption.
  /// @param redemptionId_ The ID of the redemption to complete.
  /// @param redemption_ The Redemption struct for the redemption to complete.
  function _completeRedemption(uint64 redemptionId_, Redemption memory redemption_)
    internal
    returns (uint128 reserveAssetAmountRedeemed_)
  {
    if (safetyModuleState == SafetyModuleState.TRIGGERED) revert InvalidState();
    if (redemption_.owner == address(0)) revert RedemptionNotFound();
    {
      if (_getRedemptionDelayTimeRemaining(redemption_.queueTime, redemption_.delay) != 0) revert DelayNotElapsed();
    }

    ReservePool storage reservePool_ = reservePools[redemption_.reservePoolId];
    IERC20 reserveAsset_ = reservePool_.asset;

    // Compute the final reserve assets to redemptions, which can be scaled down if triggers and slashes have occurred
    // since the redemption was queued.
    reserveAssetAmountRedeemed_ = _computeFinalReserveAssetsRedeemed(
      redemption_.reservePoolId, redemption_.assetAmount, redemption_.queuedAccISF, redemption_.queuedAccISFsLength
    );
    if (reserveAssetAmountRedeemed_ != 0) {
      reservePool_.depositAmount -= reserveAssetAmountRedeemed_;
      reservePool_.pendingWithdrawalsAmount -= reserveAssetAmountRedeemed_;
      assetPools[reserveAsset_].amount -= reserveAssetAmountRedeemed_;
      reserveAsset_.safeTransfer(redemption_.receiver, reserveAssetAmountRedeemed_);
    }

    emit Redeemed(
      msg.sender,
      redemption_.receiver,
      redemption_.owner,
      redemption_.reservePoolId,
      redemption_.receiptToken,
      redemption_.receiptTokenAmount,
      reserveAssetAmountRedeemed_,
      redemptionId_
    );
  }

  /// @inheritdoc SafetyModuleCommon
  function _updateWithdrawalsAfterTrigger(
    uint8 reservePoolId_,
    ReservePool storage reservePool_,
    uint256 oldDepositAmount_,
    uint256 slashAmount_
  ) internal override returns (uint256 newPendingWithdrawalsAmount_) {
    uint256[] storage reservePoolPendingRedemptionsAccISFs = pendingRedemptionAccISFs[reservePoolId_];
    newPendingWithdrawalsAmount_ = RedemptionLib.updateRedemptionsAfterTrigger(
      reservePool_.pendingWithdrawalsAmount, oldDepositAmount_, slashAmount_, reservePoolPendingRedemptionsAccISFs
    );
  }

  /// @notice Returns the amount of time remaining before a queued redemption can be completed.
  /// @param queueTime_ The time at which the redemption was queued.
  /// @param delay_ The delay for the redemption.
  function _getRedemptionDelayTimeRemaining(uint40 queueTime_, uint256 delay_) internal view returns (uint256) {
    return RedemptionLib.getRedemptionDelayTimeRemaining(safetyModuleState, queueTime_, delay_, block.timestamp);
  }

  /// @notice Returns the amount of assets to be redeemed, which may be less than the amount saved when the redemption
  /// was queued if the assets are used in a payout for a trigger since then.
  /// @param reservePoolId_ The ID of the reserve pool to redeem from.
  /// @param queuedReserveAssetAmount_ The amount of reserve assets to redeem when the redemption was queued.
  /// @param queuedAccISF_ The last pendingRedemptionAccISFs value at queue time.
  /// @param queuedAccISFLength_ The length of pendingRedemptionAccISFs at queue time.
  function _computeFinalReserveAssetsRedeemed(
    uint8 reservePoolId_,
    uint128 queuedReserveAssetAmount_,
    uint256 queuedAccISF_,
    uint32 queuedAccISFLength_
  ) internal view returns (uint128) {
    uint256[] storage reservePoolPendingAccISFs_ = pendingRedemptionAccISFs[reservePoolId_];
    return RedemptionLib.computeFinalReserveAssetsRedeemed(
      reservePoolPendingAccISFs_, queuedReserveAssetAmount_, queuedAccISF_, queuedAccISFLength_
    );
  }
}
