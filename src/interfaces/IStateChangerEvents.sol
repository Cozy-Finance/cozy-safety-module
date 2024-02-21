// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {SafetyModuleState} from "../lib/SafetyModuleStates.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";

interface IStateChangerEvents {
  /// @notice Emitted when the SafetyModule changes state.
  event SafetyModuleStateUpdated(SafetyModuleState indexed updatedTo_);

  // Emitted when the SafetyModule is triggered.
  event Triggered(ITrigger indexed trigger);
}
