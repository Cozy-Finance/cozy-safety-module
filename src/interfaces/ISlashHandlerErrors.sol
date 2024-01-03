// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface ISlashHandlerErrors {
  /// @dev Thrown when there are insufficient assets in a reserve pool to slash.
  error InsufficientReserveAssets(uint16 reservePoolId_);
}
