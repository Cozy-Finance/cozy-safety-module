// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {IERC20} from "../interfaces/IERC20.sol";
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
  function slash(Slash[] memory slashes_, address receiver_) external {
    // If the payout handler is invalid, the default numPendingSlashes state is also 0.
    if (payoutHandlerNumPendingSlashes[msg.sender] == 0) revert Ownable.Unauthorized();
    if (safetyModuleState != SafetyModuleState.TRIGGERED) revert InvalidState();

    // Once all slashes are processed from each of the triggered trigger's assigned payout handlers, the safety module
    // is returned to the ACTIVE state.
    numPendingSlashes -= 1;
    payoutHandlerNumPendingSlashes[msg.sender] -= 1;
    if (numPendingSlashes == 0) {
      safetyModuleState = SafetyModuleState.ACTIVE;
      emit IStateChangerEvents.SafetyModuleStateUpdated(SafetyModuleState.ACTIVE);
    }

    // Create a bitmap to track which reserve pools have already been slashed.
    uint256 alreadySlashed_ = 0;

    for (uint16 i = 0; i < slashes_.length; i++) {
      alreadySlashed_ = _updateAlreadySlashed(alreadySlashed_, slashes_[i].reservePoolId);

      Slash memory slash_ = slashes_[i];
      ReservePool storage reservePool_ = reservePools[slash_.reservePoolId];
      IERC20 reserveAsset_ = reservePool_.asset;

      // Slash reserve pool assets
      if (slash_.amount > 0) {
        uint256 reservePoolDepositAmount_ = reservePool_.depositAmount;
        uint256 slashPercentage_ = _computeSlashPercentage(slash_.amount, reservePoolDepositAmount_);
        if (slashPercentage_ > reservePool_.maxSlashPercentage) {
          revert ExceedsMaxSlashPercentage(slash_.reservePoolId, slashPercentage_);
        }

        reservePool_.pendingWithdrawalsAmount =
          _updateWithdrawalsAfterTrigger(slash_.reservePoolId, reservePool_, reservePoolDepositAmount_, slash_.amount);
        reservePool_.depositAmount -= slash_.amount;
        assetPools[reserveAsset_].amount -= slash_.amount;
      }

      // Transfer the slashed assets to the receiver.
      reserveAsset_.safeTransfer(receiver_, slash_.amount);
      emit Slashed(msg.sender, receiver_, slash_.reservePoolId, slash_.amount);
    }
  }

  function _computeSlashPercentage(uint256 slashAmount_, uint256 totalReservePoolAmount_)
    internal
    pure
    returns (uint256)
  {
    // Round up, in favor of depositors.
    return slashAmount_.divWadUp(totalReservePoolAmount_);
  }

  function _updateAlreadySlashed(uint256 alreadySlashed_, uint16 poolId_) internal pure returns (uint256) {
    if ((alreadySlashed_ & (1 << poolId_)) != 0) revert AlreadySlashed(poolId_);
    return alreadySlashed_ | (1 << poolId_);
  }
}
