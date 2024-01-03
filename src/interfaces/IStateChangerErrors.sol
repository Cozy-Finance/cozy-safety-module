// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IStateChangerErrors {
  /// @dev Thrown when the trigger is not allowed to trigger the safety module.
  error InvalidTrigger();
}
