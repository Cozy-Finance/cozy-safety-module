// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IRedemptionErrors {
  /// @dev Thrown when attempting to complete an redemption that doesn't exist.
  error RedemptionNotFound();

  /// @dev Thrown when redemption delay has not elapsed.
  error DelayNotElapsed();

  /// @dev Thrown when attempting to queue a redemption when there are not assets available in the reserve pool.
  error NoAssetsToRedeem();
}
