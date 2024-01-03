// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {ITrigger} from "../interfaces/ITrigger.sol";
import {SafetyModuleState} from "../lib/SafetyModuleStates.sol";

interface IStateChangerEvents {
  /// @notice Emitted when the Safety Module changes state.
  event SafetyModuleStateUpdated(SafetyModuleState indexed updatedTo_);

  // Emitted when the safety module is triggered.
  event Triggered(ITrigger indexed trigger);
}
