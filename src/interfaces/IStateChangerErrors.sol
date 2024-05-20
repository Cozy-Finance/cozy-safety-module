// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IStateChangerErrors {
  /// @dev Thrown when the trigger is not allowed to trigger the SafetyModule.
  error InvalidTrigger();
}
