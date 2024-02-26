// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ICozySafetyModuleManager} from "../../interfaces/ICozySafetyModuleManager.sol";
import {ISafetyModule} from "../../interfaces/ISafetyModule.sol";

contract CozyRouterCommon {
  /// @notice The Cozy Safety Module Manager address.
  ICozySafetyModuleManager public immutable manager;

  /// @dev Thrown when an invalid address is passed as a parameter.
  error InvalidAddress();

  constructor(ICozySafetyModuleManager manager_) {
    manager = manager_;
  }

  function _assertIsValidSafetyModule(address safetyModule_) internal view {
    if (!manager.isSafetyModule(ISafetyModule(safetyModule_))) revert InvalidAddress();
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
