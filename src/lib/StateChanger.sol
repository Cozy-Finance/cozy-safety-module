// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {SafetyModuleState, TriggerState} from "./SafetyModuleStates.sol";
import {IStateChangerEvents} from "../interfaces/IStateChangerEvents.sol";
import {IStateChangerErrors} from "../interfaces/IStateChangerErrors.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {Trigger} from "./structs/Trigger.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {CallerRole, StateTransitionsLib} from "./StateTransitionsLib.sol";

abstract contract StateChanger is SafetyModuleCommon, Governable, IStateChangerEvents, IStateChangerErrors {
  /// @notice Pauses the SafetyModule if it's a valid state transition.
  /// @dev Only the owner or pauser can call this function.
  function pause() external {
    SafetyModuleState currState_ = safetyModuleState;
    if (
      !StateTransitionsLib.isValidStateTransition(
        _getCallerRole(msg.sender), SafetyModuleState.PAUSED, currState_, _nonZeroPendingSlashes()
      )
    ) revert InvalidStateTransition();

    // If transitioning to paused from triggered, any queued config update is reset to prevent config updates from
    // accruing config delay time while triggered, which would result in the possibility of finalizing config updates
    // when the SafetyModule becomes paused, before users have sufficient time to react to the queued update.
    if (currState_ == SafetyModuleState.TRIGGERED) lastConfigUpdate.configUpdateDeadline = 0;

    // Drip fees before pausing, since fees are not dripped while the SafetyModule is paused.
    dripFees();
    safetyModuleState = SafetyModuleState.PAUSED;
    emit SafetyModuleStateUpdated(SafetyModuleState.PAUSED);
  }

  /// @notice Unpauses the SafetyModule if it's a valid state transition.
  /// @dev Only the owner can call this function.
  function unpause() external {
    SafetyModuleState currState_ = safetyModuleState;
    // If number of pending slashes is non-zero, when the safety module is unpaused it will transition to TRIGGERED.
    SafetyModuleState newState_ = _nonZeroPendingSlashes() ? SafetyModuleState.TRIGGERED : SafetyModuleState.ACTIVE;
    if (
      currState_ != SafetyModuleState.PAUSED
        || !StateTransitionsLib.isValidStateTransition(
          _getCallerRole(msg.sender), newState_, currState_, _nonZeroPendingSlashes()
        )
    ) revert InvalidStateTransition();

    safetyModuleState = newState_;
    // Drip fees after unpausing since fees are not dripped while the SafetyModule is paused.
    dripFees();
    emit SafetyModuleStateUpdated(newState_);
  }

  /// @notice Triggers the SafetyModule by referencing one of the triggers configured for this SafetyModule.
  /// @param trigger_ The trigger to reference when triggering the SafetyModule.
  function trigger(ITrigger trigger_) external {
    Trigger memory triggerData_ = triggerData[trigger_];

    if (!triggerData_.exists || trigger_.state() != TriggerState.TRIGGERED || triggerData_.triggered) {
      revert InvalidTrigger();
    }

    // Drip fees before triggering the safety module, since fees are not dripped while the SafetyModule is triggered.
    dripFees();

    // Each trigger has an assigned payout handler that is authorized to slash assets once when the trigger is
    // used to trigger the SafetyModule. Payout handlers can be assigned to multiple triggers, but each trigger
    // can only have one payout handler.
    numPendingSlashes += 1;
    payoutHandlerNumPendingSlashes[triggerData_.payoutHandler] += 1;
    triggerData[trigger_].triggered = true;
    emit Triggered(trigger_);

    // If the SafetyModule is PAUSED, it remains PAUSED and will transition to TRIGGERED when unpaused since
    // now we have `numPendingSlashes` >= 1.
    // If the SafetyModule is TRIGGERED, it remains TRIGGERED since now we have `numPendingSlashes` >= 2.
    // If the SafetyModule is ACTIVE, it needs to be transition to TRIGGERED.
    if (safetyModuleState == SafetyModuleState.ACTIVE) {
      safetyModuleState = SafetyModuleState.TRIGGERED;
      emit SafetyModuleStateUpdated(SafetyModuleState.TRIGGERED);
    }
  }

  /// @notice Returns the role of the caller.
  /// @param who_ The address of the caller.
  function _getCallerRole(address who_) internal view returns (CallerRole) {
    CallerRole role_ = CallerRole.NONE;
    if (who_ == owner) role_ = CallerRole.OWNER;
    else if (who_ == pauser) role_ = CallerRole.PAUSER;
    // If the caller is the Manager itself, authorization for the call is done
    // in the Manager.
    else if (who_ == address(cozySafetyModuleManager)) role_ = CallerRole.MANAGER;
    return role_;
  }

  /// @notice Returns whether the number of pending slashes is non-zero.
  function _nonZeroPendingSlashes() internal view returns (bool) {
    return numPendingSlashes > 0;
  }
}
