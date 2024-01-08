// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface ICommonErrors {
  /// @dev Thrown if the current set or market state does not allow the requested action to be performed.
  error InvalidState();

  /// @dev Thrown when a requested state transition is not allowed.
  error InvalidStateTransition();

  /// @dev Thrown if the request action is not allowed because zero units would be transferred, burned, minted, etc.
  error RoundsToZero();

  /// @dev Thrown when a drip model returns an invalid drip factor.
  error InvalidDripFactor();
}
