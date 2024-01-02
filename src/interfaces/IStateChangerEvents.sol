// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {SafetyModuleState} from "../lib/SafetyModuleStates.sol";

interface IStateChangerEvents {
  /// @notice Emitted when the Safety Module changes state.
  event SafetyModuleStateUpdated(SafetyModuleState indexed updatedTo_);
}
