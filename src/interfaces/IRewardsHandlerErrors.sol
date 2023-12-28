// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IRewardsHandlerErrors {
  /// @dev Thrown when a unauthorized address attempts a user rewards update.
  error UnauthorizedUserRewardsUpdate();
}
