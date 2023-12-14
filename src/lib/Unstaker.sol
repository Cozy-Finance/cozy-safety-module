// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IStkToken} from "../interfaces/IStkToken.sol";
import {IUnstakerErrors} from "../interfaces/IUnstakerErrors.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {MathConstants} from "./MathConstants.sol";
import {Unstake, UnstakePreview} from "./structs/Unstakes.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {CozyMath} from "./CozyMath.sol";
import {SafeCastLib} from "./SafeCastLib.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {UnstakerLib} from "./UnstakerLib.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";

abstract contract Unstaker is SafetyModuleCommon, IUnstakerErrors {
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;
  using CozyMath for uint256;

  /// @notice List of accumulated inverse scaling factors for unstaking, with the last value being the latest,
  ///         on a reward pool basis.
  /// @dev Every time there is a trigger, a scaling factor is retroactively applied to every pending
  ///      unstake equiv to:
  ///        x = 1 - slashedAmount / reservePool.stakeAmount
  ///      The last value of this array (a) will be updated to be a = a * 1 / x (scaled by WAD).
  ///      Because x will always be <= 1, the accumulated scaling factor will always INCREASE by a factor of 1/x
  ///      and can run out of usable bits (see UnstakingLib.MAX_SAFE_ACCUM_INV_SCALING_FACTOR_VALUE).
  ///      This can even happen after a single trigger if 100% of pool is consumed because 1/0 = INF.
  ///      If this happens, a new entry (1.0) is appended to the end of this array and the next trigger
  ///      will accumulate on that value.
  mapping(uint16 reservePoolId_ => uint256[] reservePoolPendingUnstakesAccISFs) internal pendingUnstakesAccISFs;
  /// @notice ID of next unstake.
  uint64 internal unstakeIdCounter;
  mapping(uint256 => Unstake) public unstakes;

  /// @dev Emitted when a user unstakes.
  event Unstaked(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint256 stkTokenAmount_,
    uint256 reserveAssetAmount_,
    uint64 unstakeId_
  );

  /// @dev Emitted when a user queues an unstake.
  event UnstakePending(
    address caller_,
    address indexed receiver_,
    address indexed owner_,
    uint256 stkTokenAmount_,
    uint256 reserveAssetAmount_,
    uint64 unstakeId_
  );

  /// @notice Unstake by burning `stkTokenAmount_` stkTokens and sending `reserveAssetAmount_` to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its stkTokens.
  function unstake(uint16 reservePoolId_, uint256 stkTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 unstakeId_, uint256 reserveAssetAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];

    reserveAssetAmount_ = SafetyModuleCalculationsLib.convertToReserveAssetAmount(
      stkTokenAmount_, reservePool_.stkToken.totalSupply(), reservePool_.stakeAmount
    );
    if (reserveAssetAmount_ == 0) revert RoundsToZero(); // Check for rounding error since we round down in conversion.

    unstakeId_ = _queueUnstake(owner_, receiver_, stkTokenAmount_, reserveAssetAmount_, reservePool_, reservePoolId_);
    // TODO: Add claim rewards logic.
  }

  /// @notice Completes the unstake request for the specified unstake ID.
  function completeUnstake(uint64 unstakeId_) external returns (uint256 reserveAssetAmount_) {
    Unstake memory unstake_ = unstakes[unstakeId_];
    delete unstakes[unstakeId_];
    return _completeUnstake(unstakeId_, unstake_);
  }

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their unstake (i.e. view the number
  /// of reserve assets received) at the current block, given current on-chain conditions.
  function previewUnstake(uint64 unstakeId_) external view returns (UnstakePreview memory unstakePreview_) {
    Unstake memory unstake_ = unstakes[unstakeId_];
    unstakePreview_ = UnstakePreview({
      delayRemaining: _getUnstakeDelayTimeRemaining(unstake_.queueTime, unstake_.delay).safeCastTo40(),
      stkTokenAmount: unstake_.stkTokenAmount,
      reserveAssetAmount: _computeFinalReserveAssetsUnstaked(
        unstake_.reservePoolId, unstake_.reserveAssetAmount, unstake_.queuedAccISF, unstake_.queuedAccISFsLength
        ),
      owner: unstake_.owner,
      receiver: unstake_.receiver
    });
  }

  /// @dev Logic to queue an unstake.
  function _queueUnstake(
    address owner_,
    address receiver_,
    uint256 stkTokenAmount_,
    uint256 reserveAssetAmount_,
    ReservePool storage reservePool_,
    uint16 reservePoolId_
  ) internal returns (uint64 unstakeId_) {
    SafetyModuleState safetyModuleState_ = safetyModuleState;
    if (safetyModuleState_ == SafetyModuleState.TRIGGERED) revert InvalidState();
    reservePool_.stkToken.burn(msg.sender, owner_, stkTokenAmount_);

    unstakeId_ = unstakeIdCounter;
    unchecked {
      // Increments can never realistically overflow. Even with a uint64, you'd need to have 1000 unstakes per
      // second for 584,542,046 years.
      unstakeIdCounter = unstakeId_ + 1;
    }

    uint256[] storage reservePoolPendingUnstakesAccISFs = pendingUnstakesAccISFs[reservePoolId_];
    uint256 numScalingFactors_ = reservePoolPendingUnstakesAccISFs.length;
    Unstake memory unstake_ = Unstake({
      reservePoolId: reservePoolId_,
      stkTokenAmount: stkTokenAmount_.safeCastTo216(),
      reserveAssetAmount: reserveAssetAmount_.safeCastTo128(),
      owner: owner_,
      receiver: receiver_,
      queueTime: uint40(block.timestamp),
      delay: safetyModuleState_ == SafetyModuleState.PAUSED ? 0 : uint40(unstakeDelay),
      queuedAccISFsLength: uint32(numScalingFactors_),
      queuedAccISF: numScalingFactors_ == 0
        ? MathConstants.WAD
        : reservePoolPendingUnstakesAccISFs[numScalingFactors_ - 1]
    });

    if (unstake_.delay == 0) {
      _completeUnstake(unstakeId_, unstake_);
    } else {
      unstakes[unstakeId_] = unstake_;
      emit UnstakePending(msg.sender, receiver_, owner_, stkTokenAmount_, reserveAssetAmount_, unstakeId_);
    }
  }

  /// @dev Logic to complete an unstake.
  function _completeUnstake(uint64 unstakeId_, Unstake memory unstake_)
    internal
    returns (uint128 reserveAssetAmountUnstaked_)
  {
    if (unstake_.owner == address(0)) revert UnstakeNotFound();

    // If the safety module is paused, unstakes can occur instantly.
    {
      if (_getUnstakeDelayTimeRemaining(unstake_.queueTime, unstake_.delay) != 0) revert DelayNotElapsed();
    }

    ReservePool storage reservePool_ = reservePools[unstake_.reservePoolId];
    IERC20 reserveAsset_ = reservePool_.asset;

    // Compute the final reserve assets to unstake, which can be scaled down if triggers have occurred
    // since the unstake was queued.
    reserveAssetAmountUnstaked_ = _computeFinalReserveAssetsUnstaked(
      unstake_.reservePoolId, unstake_.reserveAssetAmount, unstake_.queuedAccISF, unstake_.queuedAccISFsLength
    );
    if (reserveAssetAmountUnstaked_ != 0) {
      reservePool_.stakeAmount -= reserveAssetAmountUnstaked_;
      assetPools[reserveAsset_].amount -= reserveAssetAmountUnstaked_;
      reserveAsset_.safeTransfer(unstake_.receiver, reserveAssetAmountUnstaked_);
    }

    emit Unstaked(
      msg.sender, unstake_.receiver, unstake_.owner, unstake_.stkTokenAmount, reserveAssetAmountUnstaked_, unstakeId_
    );
  }

  /// @inheritdoc SafetyModuleCommon
  function _updateUnstakesAfterTrigger(uint16 reservePoolId_, uint128 oldStakeAmount_, uint128 slashAmount_)
    internal
    override
  {
    uint256[] storage reservePoolPendingUnstakesAccISFs = pendingUnstakesAccISFs[reservePoolId_];
    UnstakerLib.updateUnstakesAfterTrigger(oldStakeAmount_, slashAmount_, reservePoolPendingUnstakesAccISFs);
  }

  /// @dev Returns the amount of time remaining before a queued unstake can be completed.
  function _getUnstakeDelayTimeRemaining(uint40 queueTime_, uint256 delay_) internal view returns (uint256) {
    return UnstakerLib.getUnstakeDelayTimeRemaining(safetyModuleState, queueTime_, delay_, block.timestamp);
  }

  /// @dev Returns the amount of tokens to be unstaked, which may be less than the amount saved when the unstake
  /// was queued if the tokens are used in a payout for a trigger since then.
  function _computeFinalReserveAssetsUnstaked(
    uint16 reservePoolId_,
    uint128 queuedReserveAssetAmount_,
    uint256 queuedAccISF_,
    uint32 queuedAccISFLength_
  ) internal view returns (uint128) {
    uint256[] storage reservePoolPendingUnstakesAccISFs_ = pendingUnstakesAccISFs[reservePoolId_];
    return UnstakerLib.computeFinalReserveAssetsUnstaked(
      reservePoolPendingUnstakesAccISFs_, queuedReserveAssetAmount_, queuedAccISF_, queuedAccISFLength_
    );
  }
}
