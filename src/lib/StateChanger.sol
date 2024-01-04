// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IStateChangerEvents} from "../interfaces/IStateChangerEvents.sol";
import {IStateChangerErrors} from "../interfaces/IStateChangerErrors.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {Trigger} from "./structs/Trigger.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {Governable} from "./Governable.sol";
import {SafetyModuleState, TriggerState} from "./SafetyModuleStates.sol";
import {CallerRole, StateTransitionsLib} from "./StateTransitionsLib.sol";

abstract contract StateChanger is SafetyModuleCommon, Governable, IStateChangerEvents, IStateChangerErrors {
  /// @dev Pauses the safety module if it's a valid state transition.
  function pause() external {
    SafetyModuleState currState_ = safetyModuleState;
    if (
      !StateTransitionsLib.isValidStateTransition(
        _getCallerRole(msg.sender), SafetyModuleState.PAUSED, currState_, _nonZeroPendingSlashes()
      )
    ) revert InvalidStateTransition();

    // Drip rewards and fees before pausing.
    dripRewards();
    dripFees();
    safetyModuleState = SafetyModuleState.PAUSED;
    emit SafetyModuleStateUpdated(SafetyModuleState.PAUSED);
  }

  /// @dev Unpauses the safety module if it's a valid state transition.
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
    // Drip rewards and fees after unpausing.
    dripRewards();
    dripFees();
    emit SafetyModuleStateUpdated(newState_);
  }

  /// @notice Triggers the safety module by referencing one of the triggers configured for this safety module.
  function trigger(ITrigger trigger_) external {
    Trigger memory triggerData_ = triggerData[trigger_];

    if (!triggerData_.exists || trigger_.state() != TriggerState.TRIGGERED || triggerData_.triggered) {
      revert InvalidTrigger();
    }

    // Drip rewards and fees before triggering the safety module.
    dripRewards();
    dripFees();

    // Each trigger has an assigned payout handler that is authorized to slash assets once when the trigger is
    // triggered. Payout handlers can be assigned to multiple triggers, but each trigger can only have one payout
    // handler.
    numPendingSlashes += 1;
    payoutHandlerNumPendingSlashes[triggerData_.payoutHandler] += 1;
    triggerData[trigger_].triggered = true;
    emit Triggered(trigger_);

    // If the safety module is PAUSED, it remains PAUSED and will transition to TRIGGERED when unpaused since
    // now we have `numPendingSlashes` >= 1.
    // If the safety module is TRIGGERED, it remains TRIGGERED since now we have `numPendingSlashes` >= 2.
    // If the safety module is ACTIVE, it needs to be transition to TRIGGERED.
    if (safetyModuleState == SafetyModuleState.ACTIVE) {
      safetyModuleState = SafetyModuleState.TRIGGERED;
      emit SafetyModuleStateUpdated(SafetyModuleState.TRIGGERED);
    }
  }

  function _getCallerRole(address who_) internal view returns (CallerRole) {
    CallerRole role_ = CallerRole.NONE;
    if (who_ == owner) role_ = CallerRole.OWNER;
    else if (who_ == pauser) role_ = CallerRole.PAUSER;
    // If the caller is the Manager itself, authorization for the call is done
    // in the Manager.
    else if (who_ == address(cozyManager)) role_ = CallerRole.MANAGER;
    return role_;
  }

  function _nonZeroPendingSlashes() internal view returns (bool) {
    return numPendingSlashes > 0;
  }
}
