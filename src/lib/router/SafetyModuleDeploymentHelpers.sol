// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {UpdateConfigsCalldataParams} from "../structs/Configs.sol";
import {ISafetyModule} from "../../interfaces/ISafetyModule.sol";
import {IMetadataRegistry} from "../../interfaces/IMetadataRegistry.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";

abstract contract SafetyModuleDeploymentHelpers is CozyRouterCommon {
  /// @notice Deploys a new Cozy Safety Module.
  function deploySafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 salt_
  ) external payable returns (ISafetyModule safetyModule_) {
    safetyModule_ =
      safetyModuleCozyManager.createSafetyModule(owner_, pauser_, configs_, computeSalt(msg.sender, salt_));
  }

  /// @notice Update metadata for a safety module.
  /// @dev `msg.sender` must be the owner of the safety module.
  /// @param metadataRegistry_ The address of the metadata registry.
  /// @param safetyModule_ The address of the safety module.
  /// @param metadata_ The new metadata for the safety module.
  function updateSafetyModuleMetadata(
    IMetadataRegistry metadataRegistry_,
    address safetyModule_,
    IMetadataRegistry.Metadata calldata metadata_
  ) external payable {
    metadataRegistry_.updateSafetyModuleMetadata(safetyModule_, metadata_, msg.sender);
  }
}
