// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IRedemptionErrors {
  /// @dev Thrown when attempting to complete an redemption that doesn't exist.
  error RedemptionNotFound();

  /// @dev Thrown when redemption delay has not elapsed.
  error DelayNotElapsed();
}
