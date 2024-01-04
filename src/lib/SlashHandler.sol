// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Ownable} from "./Ownable.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ISlashHandlerErrors} from "../interfaces/ISlashHandlerErrors.sol";
import {PayoutHandler} from "./structs/PayoutHandler.sol";
import {Slash} from "./structs/Slash.sol";
import {Trigger} from "./structs/Trigger.sol";
import {ReservePool} from "./structs/Pools.sol";

abstract contract SlashHandler is SafetyModuleCommon, ISlashHandlerErrors {
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
    if (numPendingSlashes == 0) safetyModuleState = SafetyModuleState.ACTIVE;

    for (uint16 i = 0; i < slashes_.length; i++) {
      Slash memory slash_ = slashes_[i];
      ReservePool storage reservePool_ = reservePools[slash_.reservePoolId];
      IERC20 reserveAsset_ = reservePool_.asset;
      uint256 slashAmountRemaining_ = slash_.amount;

      // 1. Slash deposited assets
      uint256 reservePoolDepositAmount_ = reservePool_.depositAmount;
      _updateWithdrawalsAfterTrigger(slash_.reservePoolId, reservePoolDepositAmount_, slashAmountRemaining_);
      if (reservePoolDepositAmount_ <= slashAmountRemaining_) {
        slashAmountRemaining_ -= reservePoolDepositAmount_;
        reservePool_.depositAmount = 0;
        assetPools[reserveAsset_].amount -= reservePoolDepositAmount_;
      } else {
        reservePool_.depositAmount -= slashAmountRemaining_;
        assetPools[reserveAsset_].amount -= slashAmountRemaining_;
        slashAmountRemaining_ = 0;
      }

      // 2. Slash staked assets
      if (slashAmountRemaining_ > 0) {
        uint256 reservePoolStakeAmount_ = reservePool_.stakeAmount;
        _updateUnstakesAfterTrigger(slash_.reservePoolId, reservePoolStakeAmount_, slashAmountRemaining_);
        if (reservePoolStakeAmount_ < slashAmountRemaining_) {
          // The staked assets are insufficient to cover the remaining slash amount, so the reserve pool is insolvent
          // wrt the slash amount specified.
          revert InsufficientReserveAssets(slash_.reservePoolId);
        } else {
          reservePool_.stakeAmount -= slashAmountRemaining_;
          assetPools[reserveAsset_].amount -= slashAmountRemaining_;
        }
      }

      // Transfer the slashed assets to the receiver.
      reserveAsset_.safeTransfer(receiver_, slash_.amount);
    }
  }
}
