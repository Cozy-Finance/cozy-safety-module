// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface ISlashHandlerErrors {
  /// @dev Thrown when the slash percentage exceeds the max slash percentage allowed for the reserve pool.
  error ExceedsMaxSlashPercentage(uint8 reservePoolId_, uint256 slashPercentage_);

  /// @dev Thrown when the reserve pool has already been slashed.
  error AlreadySlashed(uint8 reservePoolId_);
}
