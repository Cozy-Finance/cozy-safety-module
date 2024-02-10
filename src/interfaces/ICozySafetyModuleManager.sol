// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {ICozySafetyModuleManagerEvents} from "./ICozySafetyModuleManagerEvents.sol";
import {ISafetyModule} from "./ISafetyModule.sol";
import {IDripModel} from "./IDripModel.sol";
import {UpdateConfigsCalldataParams} from "../lib/structs/Configs.sol";

interface ICozySafetyModuleManager is ICozySafetyModuleManagerEvents {
  /// @notice Deploys a new Safety Module with the provided parameters.
  /// @param owner_ The owner of the safety module.
  /// @param pauser_ The pauser of the safety module.
  /// @param configs_ The configuration for the safety module.
  /// @param salt_ Used to compute the resulting address of the set.
  function createSafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 salt_
  ) external returns (ISafetyModule safetyModule_);

  function isSafetyModule(ISafetyModule safetyModule_) external view returns (bool);

  function getFeeDripModel(ISafetyModule safetyModule_) external view returns (IDripModel);

  /// @notice Number of reserve pools allowed per safety module.
  function allowedReservePools() external view returns (uint8);
}
