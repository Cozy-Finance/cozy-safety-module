// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IUnstakerErrors {
  /// @dev Thrown when attempting to complete an unstake that doesn't exist.
  error UnstakeNotFound();

  /// @dev Thrown when unstaked delay has not elapsed.
  error DelayNotElapsed();
}
