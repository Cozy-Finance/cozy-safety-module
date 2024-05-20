// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {ICozyManager} from "cozy-safety-module-rewards-manager/interfaces/ICozyManager.sol";
import {ICozySafetyModuleManager} from "../../interfaces/ICozySafetyModuleManager.sol";
import {ISafetyModule} from "../../interfaces/ISafetyModule.sol";

contract CozyRouterCommon {
  /// @notice The Cozy Safety Module Manager address.
  ICozySafetyModuleManager public immutable safetyModuleCozyManager;

  /// @dev Thrown when an invalid address is passed as a parameter.
  error InvalidAddress();

  constructor(ICozySafetyModuleManager safetyModuleCozyManager_) {
    safetyModuleCozyManager = safetyModuleCozyManager_;
  }

  /// @notice Given a `caller_` and `baseSalt_`, return the salt used to compute the address of a deployed contract
  /// using a deployment helper function on this `CozyRouter`.
  /// @param caller_ The caller of the deployment helper function on this `CozyRouter`.
  /// @param baseSalt_ Used to compute the deployment salt.
  function computeSalt(address caller_, bytes32 baseSalt_) public pure returns (bytes32) {
    // To avoid front-running of factory deploys using a salt, msg.sender is used to compute the deploy salt.
    return keccak256(abi.encodePacked(baseSalt_, caller_));
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
