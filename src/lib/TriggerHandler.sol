// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafetyModuleState, TriggerState} from "./SafetyModuleStates.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {ITriggerHandlerErrors} from "../interfaces/ITriggerHandlerErrors.sol";
import {Trigger} from "./structs/Trigger.sol";

abstract contract TriggerHandler is SafetyModuleCommon, ITriggerHandlerErrors {
  // Emitted when the safety module is triggered.
  event Triggered(ITrigger indexed trigger);

  /// @notice Triggers the safety module by referencing one of the triggers configured for this safety module.
  function trigger(ITrigger trigger_) external {
    Trigger memory triggerData_ = triggerData[trigger_];

    if (!triggerData_.exists || trigger_.state() != TriggerState.TRIGGERED || triggerData_.triggered) {
      revert InvalidTrigger();
    }

    // Drip rewards before triggering the safety module, as the safety module cannot drip rewards while triggered.
    dripRewards();

    // Each trigger has an assigned payout handler that is authorized to slash assets once when the trigger is
    // triggered. Payout handlers can be assigned to multiple triggers, but each trigger can only have one payout
    // handler.
    numPendingSlashes += 1;
    payoutHandlerData[triggerData_.payoutHandler].numPendingSlashes += 1;
    triggerData[trigger_].triggered = true;

    // TODO: Use StateChanger validation check function.
    if (safetyModuleState == SafetyModuleState.ACTIVE) {
      safetyModuleState = SafetyModuleState.TRIGGERED;
      emit Triggered(trigger_);
    }
  }
}
