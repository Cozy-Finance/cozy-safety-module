// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {ISlashHandlerErrors} from "../interfaces/ISlashHandlerErrors.sol";
import {ISlashHandlerEvents} from "../interfaces/ISlashHandlerEvents.sol";
import {IStateChangerEvents} from "../interfaces/IStateChangerEvents.sol";
import {Slash} from "./structs/Slash.sol";
import {Trigger} from "./structs/Trigger.sol";
import {ReservePool} from "./structs/Pools.sol";

abstract contract SlashHandler is SafetyModuleCommon, ISlashHandlerErrors, ISlashHandlerEvents {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;

  /// @notice Slashes the reserve pools, sends the assets to the receiver, and returns the safety module to the ACTIVE
  /// state if there are no payout handlers that still need to slash assets. Note: Payout handlers can call this
  /// function once for each triggered trigger that has it assigned as its payout handler.
  /// @param slashes_ The slashes to execute.
  /// @param receiver_ The address to receive the slashed assets.
  function slash(Slash[] memory slashes_, address receiver_) external {
    // If the payout handler is invalid, the default numPendingSlashes state is also 0.
    if (payoutHandlerNumPendingSlashes[msg.sender] == 0) revert Ownable.Unauthorized();
    if (safetyModuleState != SafetyModuleState.TRIGGERED) revert InvalidState();

    // Once all slashes are processed from each of the triggered trigger's assigned payout handlers, the safety module
    // is returned to the ACTIVE state.
    numPendingSlashes -= 1;
    payoutHandlerNumPendingSlashes[msg.sender] -= 1;
    if (numPendingSlashes == 0) {
      // If transitioning to triggered from active, any queued config update is reset to prevent config updates
      // from accruing config delay time while triggered, which would result in the possibility of finalizing config
      // updates when the SafetyModule returns to active, before users have sufficient time to react to the queued
      // update.
      lastConfigUpdate.queuedConfigUpdateHash = bytes32(0);

      safetyModuleState = SafetyModuleState.ACTIVE;
      emit IStateChangerEvents.SafetyModuleStateUpdated(SafetyModuleState.ACTIVE);
    }

    // Create a bitmap to track which reserve pools have already been slashed during execution of the following loop.
    uint256 alreadySlashed_ = 0;
    for (uint16 i = 0; i < slashes_.length; i++) {
      alreadySlashed_ = _updateAlreadySlashed(alreadySlashed_, slashes_[i].reservePoolId);

      Slash memory slash_ = slashes_[i];
      ReservePool storage reservePool_ = reservePools[slash_.reservePoolId];
      IERC20 reserveAsset_ = reservePool_.asset;
      uint256 reservePoolDepositAmount_ = reservePool_.depositAmount;

      // Slash reserve pool assets.
      if (slash_.amount > 0 && reservePoolDepositAmount_ > 0) {
        uint256 slashPercentage_ = _computeSlashPercentage(slash_.amount, reservePoolDepositAmount_);
        if (slashPercentage_ > reservePool_.maxSlashPercentage) {
          revert ExceedsMaxSlashPercentage(slash_.reservePoolId, slashPercentage_);
        }

        reservePool_.pendingWithdrawalsAmount =
          _updateWithdrawalsAfterTrigger(slash_.reservePoolId, reservePool_, reservePoolDepositAmount_, slash_.amount);
        reservePool_.depositAmount -= slash_.amount;
        assetPools[reserveAsset_].amount -= slash_.amount;

        // Transfer the slashed assets to the specified receiver.
        reserveAsset_.safeTransfer(receiver_, slash_.amount);
        emit Slashed(msg.sender, receiver_, slash_.reservePoolId, slash_.amount);
      }
    }
  }

  /// @notice Returns the maximum amount of assets that can be slashed from the specified reserve pool.
  /// @param reservePoolId_ The ID of the reserve pool to get the maximum slashable amount for.
  function getMaxSlashableReservePoolAmount(uint8 reservePoolId_)
    external
    view
    returns (uint256 slashableReservePoolAmount_)
  {
    return reservePools[reservePoolId_].depositAmount.mulDivDown(
      reservePools[reservePoolId_].maxSlashPercentage, MathConstants.ZOC
    );
  }

  /// @notice Returns the percentage corresponding to the amount of assets to be slashed from the reserve pool.
  /// @param slashAmount_ The amount of assets to be slashed.
  /// @param totalReservePoolAmount_ The total amount of assets in the reserve pool.
  function _computeSlashPercentage(uint256 slashAmount_, uint256 totalReservePoolAmount_)
    internal
    pure
    returns (uint256)
  {
    // Round up, in favor of depositors.
    return slashAmount_.mulDivUp(MathConstants.ZOC, totalReservePoolAmount_);
  }

  /// @notice Updates the bitmap used to track which reserve pools have already been slashed.
  /// @param alreadySlashed_ The bitmap to update.
  /// @param poolId_ The ID of the reserve pool to update the bitmap for.
  function _updateAlreadySlashed(uint256 alreadySlashed_, uint8 poolId_) internal pure returns (uint256) {
    // Using the left shift here is valid because poolId_ < allowedReservePools <= 255.
    if ((alreadySlashed_ & (1 << poolId_)) != 0) revert AlreadySlashed(poolId_);
    return alreadySlashed_ | (1 << poolId_);
  }
}
