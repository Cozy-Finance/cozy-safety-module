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

  function computeAddress(bytes32 baseSalt_) external view returns (address);

  function deploySafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 baseSalt_
  ) external returns (ISafetyModule safetyModule_);

  function cozySafetyModuleManager() external view returns (ICozySafetyModuleManager);

  function salt(bytes32 baseSalt_) external view returns (bytes32);

  function safetyModuleLogic() external view returns (ISafetyModule);
}
