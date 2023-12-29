// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IConfiguratorErrors {
  /// @dev Thrown when an update's configuration does not meet all requirements.
  error InvalidConfiguration();
}
