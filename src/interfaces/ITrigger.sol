// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {TriggerState} from "../lib/SafetyModuleStates.sol";

/**
 * @dev The minimal functions a trigger must implement to work with SafetyModules.
 */
interface ITrigger {
  /// @notice The current trigger state.
  function state() external returns (TriggerState);
}
