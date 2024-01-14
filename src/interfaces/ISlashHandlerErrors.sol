// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface ISlashHandlerErrors {
  /// @dev Thrown when the slash percentage exceeds the max slash percentage.
  error ExceedsMaxSlashPercentage(uint16 reservePoolId_, uint256 slashPercentage_);

  /// @dev Thrown when the slash percentage is less than the min slash percentage.
  error AlreadySlashed(uint16 reservePoolId_);
}
