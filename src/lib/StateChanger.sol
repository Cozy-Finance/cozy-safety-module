// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IStateChangerEvents} from "../interfaces/IStateChangerEvents.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {Governable} from "./Governable.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {CallerRole, StateTransitionsLib} from "./StateTransitionsLib.sol";

abstract contract StateChanger is SafetyModuleCommon, Governable, IStateChangerEvents {
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

  /// @dev Unpauses the safety module is it's a valid state transition.
  function unpause() external {
    SafetyModuleState currState_ = safetyModuleState;
    // If number of pending slashes is non-zero, when the set is unpaused it will transition to TRIGGERED.
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
