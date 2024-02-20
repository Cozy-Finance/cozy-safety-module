// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafeCastLib} from "cozy-safety-module-shared/lib/SafeCastLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {CozyMath} from "./CozyMath.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {ReservePool} from "./structs/Pools.sol";

/**
 * @notice Read-only logic for redemptions.
 */
library RedemptionLib {
  using CozyMath for uint256;
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  // Accumulator values are 1/x in WAD, where x is a scaling factor. This is the smallest
  // accumulator value (inverse scaling factor) that is not 1/0 (infinity). Any value greater than this
  // will scale any assets to zero.
  // 1e18/1e-18 => 1e18 * 1e18 / 1 => WAD ** 2 (1e36)
  // SUB_INF_INV_SCALING_FACTOR = 1_000_000_000_000_000_000_000_000_000_000_000_000;
  // Adding 1 to SUB_INF_INV_SCALING_FACTOR will turn to zero when inverted,
  // so this value is effectively an inverted zero scaling factor (infinity).
  uint256 internal constant INF_INV_SCALING_FACTOR = 1_000_000_000_000_000_000_000_000_000_000_000_001;
  // This is the maximum value an accumulator value can hold. Any more and it could overflow
  // during calculations. This value should not overflow a uint256 when multiplied by 1 WAD.
  // Equiv to uint256.max / WAD
  // MAX_SAFE_ACCUM_INV_SCALING_FACTOR_VALUE =
  //   115_792_089_237_316_195_423_570_985_008_687_907_853_269_984_665_640_564_039_457;
  // When a new accumulator value exceeds this threshold, a new entry should be used.
  // When this value is multiplied by INF_INV_SCALING_FACTOR, it should be <= MAX_SAFE_ACCUM_INV_SCALING_FACTOR_VALUE
  // Equiv to MAX_SAFE_ACCUM_INV_SCALING_FACTOR_VALUE.mulWadUp / ((INF_INV_SCALING_FACTOR + WAD-1) / WAD)
  uint256 internal constant NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD =
    115_792_089_237_316_195_307_778_895_771_371_712_545_491;
  // The maximum value an accumulator should ever actually hold, if everything is working correctly.
  // Equiv to: NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD.mulWadUp(INF_INV_SCALING_FACTOR);
  // Should be <= MAX_SAFE_ACCUM_INV_SCALING_FACTOR_VALUE
  // Equiv to (NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD * INF_INV_SCALING_FACTOR + WAD-1) / WAD
  uint256 internal constant MAX_ACCUM_INV_SCALING_FACTOR_VALUE =
    115_792_089_237_316_195_307_778_895_771_371_712_661_283_089_237_316_195_307_779;

  // @dev Compute the tokens settled by a pending redemption, which will be scaled (down) by the accumulated
  // scaling factors of triggers that happened after it was queued.
  function computeFinalReserveAssetsRedeemed(
    uint256[] storage accISFs_,
    uint128 queuedReserveAssetAmount_,
    uint256 queuedAccISF_,
    uint32 queuedAccISFsLength_
  ) internal view returns (uint128 reserveAssetAmountRedeemed_) {
    // If a trigger occurs after the redemption was queued, the tokens returned will need to be scaled down
    // by a factor equivalent to how much was taken out relative to the usable reserve assets
    // (which includes pending redemptions):
    //    factor = 1 - slashedAmount / reservePool.amount
    // The values of `accISFs_` are the product of the inverse of this scaling factor
    // after each trigger, with the last one being the most recent. We cache the latest scaling factor at queue time
    // and can divide the current scaling factor by the cached value to isolate the scaling that needs to
    // be applied to the queued assets to redeem.
    uint256 invScalingFactor_ = MathConstants.WAD;
    if (queuedAccISFsLength_ != 0) {
      // Get the current scaling factor at the index of the last scaling factor we queued at.
      uint256 currentScalingFactorAtQueueIndex_ = accISFs_[queuedAccISFsLength_ - 1];
      // Divide/factor out the scaling factor we queued at. If this value hasn't changed then scaling
      // will come out to 1.0.
      // Note that we round UP here because these are inverse scaling factors (larger -> less assets).
      invScalingFactor_ = currentScalingFactorAtQueueIndex_.divWadUp(queuedAccISF_);
    }
    // The queuedAccISF_ and queuedAccISFsLength_ are the last value of accISFs_ and the length of
    // that array when the redemption was queued. If the array has had more entries added to it since
    // then, we need to scale our factor with each of those as well, to account for the effects of
    // ALL triggers since we queued.
    uint256 ScalingFactorsLength_ = accISFs_.length;
    // Note that the maximum length accISFs_ can be is the number of markets in the set, and probably only
    // if every market triggered a 100% collateral loss, since anything less would likely be compressed into
    // the previous accumulator entry. Even then, we break early if we accumulate >= a factor that
    // scales assets to 0 so, in practice, this loop will only iterate once or twice.
    for (uint256 i = queuedAccISFsLength_; i < ScalingFactorsLength_; i++) {
      // If the scaling factor is large enough, the resulting assets will come out to essentially zero
      // anyway, so we can stop early.
      if (invScalingFactor_ >= INF_INV_SCALING_FACTOR) break;
      // Note that we round UP here because these are inverse scaling factors (larger -> less assets).
      invScalingFactor_ = invScalingFactor_.mulWadUp(accISFs_[i]);
    }
    // This accumulated value is actually the inverse of the true scaling factor, so we need to invert it first.
    // We need to do this step separately from the next to minimize rounding errors.
    uint256 scalingFactor_ =
      invScalingFactor_ >= INF_INV_SCALING_FACTOR ? 0 : MathConstants.WAD.divWadDown(invScalingFactor_);
    // Now we can just scale the queued tokens by this scaling factor to get the final tokens redeemed.
    reserveAssetAmountRedeemed_ = scalingFactor_.mulWadDown(queuedReserveAssetAmount_).safeCastTo128();
  }

  /// @dev Prepares pending redemptions to have their exchange rates adjusted after a trigger.
  function updateRedemptionsAfterTrigger(
    uint256 pendingRedemptionsAmount_,
    uint256 redemptionAmount_,
    uint256 slashAmount_,
    uint256[] storage pendingAccISFs_
  ) internal returns (uint256) {
    uint256 numScalingFactors_ = pendingAccISFs_.length;
    uint256 currAccISF_ = numScalingFactors_ == 0 ? MathConstants.WAD : pendingAccISFs_[numScalingFactors_ - 1];
    (uint256 newAssetsPendingRedemption_, uint256 accISF_) = computeNewPendingRedemptionsAccumulatedScalingFactor(
      currAccISF_, pendingRedemptionsAmount_, redemptionAmount_, slashAmount_
    );
    if (numScalingFactors_ == 0) {
      // First trigger for this safety module. Create an accumulator entry.
      pendingAccISFs_.push(accISF_);
    } else {
      // Update the last accumulator entry.
      pendingAccISFs_[numScalingFactors_ - 1] = accISF_;
    }
    if (accISF_ > NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD) {
      // The new entry is very large and cannot be safely combined with the next trigger, so append
      // a new 1.0 entry for next time.
      pendingAccISFs_.push(MathConstants.WAD);
    }
    return newAssetsPendingRedemption_;
  }

  // @dev Compute the scaled tokens pending redemptions and accumulated inverse scaling factor
  // as a result of a trigger.
  function computeNewPendingRedemptionsAccumulatedScalingFactor(
    uint256 currAccISF_,
    uint256 oldAssetsPendingRedemption_,
    uint256 oldPoolAmount_,
    uint256 slashAmount_
  ) internal pure returns (uint256 newAssetsPendingRedemption_, uint256 newAccISF_) {
    // The incoming accumulator should be less than the threshold to use a new one.
    assert(currAccISF_ <= NEW_ACCUM_INV_SCALING_FACTOR_THRESHOLD);
    // The incoming accumulator should be >= 1.0 because it starts at 1.0 and
    // should only ever increase (or stay the same). This is because scalingFactor will always <= 1.0 and
    // we accumulate *= 1/scalingFactor.
    assert(currAccISF_ >= MathConstants.WAD);
    uint256 scalingFactor_ = computeNextPendingRedemptionsScalingFactorForTrigger(oldPoolAmount_, slashAmount_);
    // Computed scaling factor as a result of this trigger should be <= 1.0.
    assert(scalingFactor_ <= MathConstants.WAD);
    newAssetsPendingRedemption_ = oldAssetsPendingRedemption_.mulWadDown(scalingFactor_);
    // The accumulator is actually the products of the inverse of each scaling factor.
    uint256 invScalingFactor_ =
      scalingFactor_ == 0 ? INF_INV_SCALING_FACTOR : MathConstants.WAD.divWadUp(scalingFactor_);
    newAccISF_ = invScalingFactor_.mulWadUp(currAccISF_);
    assert(newAccISF_ <= MAX_ACCUM_INV_SCALING_FACTOR_VALUE);
  }

  function computeNextPendingRedemptionsScalingFactorForTrigger(uint256 oldPoolAmount_, uint256 slashAmount_)
    internal
    pure
    returns (uint256 scalingFactor_)
  {
    // Because the slash amount will be removed from the redemption amount, the value of all
    // redeemed tokens will be scaled (down) by:
    //      scalingFactor = 1 - slashAmount_ / oldPoolAmount_
    if (slashAmount_ > oldPoolAmount_) return 0;
    if (oldPoolAmount_ == 0) return 0;
    return MathConstants.WAD - slashAmount_.divWadUp(oldPoolAmount_);
  }

  /// @dev Gets the amount of time remaining that must elapse before a queued redemption can be completed.
  function getRedemptionDelayTimeRemaining(
    SafetyModuleState safetyModuleState_,
    uint256 redemptionQueueTime_,
    uint256 redemptionDelay_,
    uint256 now_
  ) internal pure returns (uint256) {
    // Redemptions can occur immediately when the safety module is paused.
    return safetyModuleState_ == SafetyModuleState.PAUSED
      ? 0
      : redemptionDelay_.differenceOrZero(now_ - redemptionQueueTime_);
  }
}
