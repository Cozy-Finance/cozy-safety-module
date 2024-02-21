// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {ICozySafetyModuleManager} from "./ICozySafetyModuleManager.sol";
import {ISafetyModule} from "./ISafetyModule.sol";
import {UpdateConfigsCalldataParams, ReservePoolConfig} from "../lib/structs/Configs.sol";
import {Delays} from "../lib/structs/Delays.sol";

interface ISafetyModuleFactory {
  /// @dev Emitted when a new Safety Module is deployed.
  event SafetyModuleDeployed(ISafetyModule safetyModule);

  /// @notice Given the `baseSalt_` compute and return the address that SafetyModule will be deployed to.
  /// @dev SafetyModule addresses are uniquely determined by their salt because the deployer is always the factory,
  /// and the use of minimal proxies means they all have identical bytecode and therefore an identical bytecode hash.
  /// @dev The `baseSalt_` is the user-provided salt, not the final salt after hashing with the chain ID.
  /// @param baseSalt_ The user-provided salt.
  function computeAddress(bytes32 baseSalt_) external view returns (address);

  /// @notice Address of the Cozy Safety Module protocol manager contract.
  function cozySafetyModuleManager() external view returns (ICozySafetyModuleManager);

  /// @notice Deploys a new SafetyModule contract with the specified configuration.
  /// @param owner_ The owner of the SafetyModule.
  /// @param pauser_ The pauser of the SafetyModule.
  /// @param configs_ The configuration for the SafetyModule.
  /// @param baseSalt_ Used to compute the resulting address of the SafetyModule.
  function deploySafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 baseSalt_
  ) external returns (ISafetyModule safetyModule_);

  /// @notice Address of the SafetyModule logic contract used to deploy new SafetyModule minimal proxies.
  function safetyModuleLogic() external view returns (ISafetyModule);

  /// @notice Given the `baseSalt_`, return the salt that will be used for deployment.
  /// @param baseSalt_ The user-provided salt.
  function salt(bytes32 baseSalt_) external view returns (bytes32);
}
