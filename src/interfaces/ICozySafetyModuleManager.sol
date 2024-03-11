// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IOwnable} from "cozy-safety-module-shared/interfaces/IOwnable.sol";
import {ICozySafetyModuleManagerEvents} from "./ICozySafetyModuleManagerEvents.sol";
import {ISafetyModule} from "./ISafetyModule.sol";
import {UpdateConfigsCalldataParams} from "../lib/structs/Configs.sol";

interface ICozySafetyModuleManager is IOwnable, ICozySafetyModuleManagerEvents {
  /// @notice Deploys a new SafetyModule with the provided parameters.
  /// @param owner_ The owner of the SafetyModule.
  /// @param pauser_ The pauser of the SafetyModule.
  /// @param configs_ The configuration for the SafetyModule.
  /// @param salt_ Used to compute the resulting address of the SafetyModule.
  function createSafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 salt_
  ) external returns (ISafetyModule safetyModule_);

  /// @notice For the specified SafetyModule, returns whether it's a valid Cozy Safety Module.
  function isSafetyModule(ISafetyModule safetyModule_) external view returns (bool);

  /// @notice For the specified SafetyModule, returns the drip model used for fee accrual.
  function getFeeDripModel(ISafetyModule safetyModule_) external view returns (IDripModel);

  /// @notice Number of reserve pools allowed per SafetyModule.
  function allowedReservePools() external view returns (uint8);
}
