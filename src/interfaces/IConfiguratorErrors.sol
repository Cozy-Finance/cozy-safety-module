// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface IConfiguratorErrors {
  /// @dev Thrown when an update's configuration does not meet all requirements.
  error InvalidConfiguration();
}
