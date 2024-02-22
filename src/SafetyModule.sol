// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {ICozySafetyModuleManager} from "./interfaces/ICozySafetyModuleManager.sol";
import {UpdateConfigsCalldataParams} from "./lib/structs/Configs.sol";
import {Configurator} from "./lib/Configurator.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";
import {Depositor} from "./lib/Depositor.sol";
import {Redeemer} from "./lib/Redeemer.sol";
import {SlashHandler} from "./lib/SlashHandler.sol";
import {SafetyModuleBaseStorage} from "./lib/SafetyModuleBaseStorage.sol";
import {SafetyModuleInspector} from "./lib/SafetyModuleInspector.sol";
import {FeesHandler} from "./lib/FeesHandler.sol";
import {StateChanger} from "./lib/StateChanger.sol";

contract SafetyModule is
  SafetyModuleBaseStorage,
  SafetyModuleInspector,
  Configurator,
  Depositor,
  Redeemer,
  SlashHandler,
  FeesHandler,
  StateChanger
{
  /// @dev Thrown if the contract is already initialized.
  error Initialized();

  /// @param cozySafetyModuleManager_ The Cozy Safety Module protocol manager.
  /// @param receiptTokenFactory_ The Cozy Safety Module protocol ReceiptTokenFactory.
  constructor(ICozySafetyModuleManager cozySafetyModuleManager_, IReceiptTokenFactory receiptTokenFactory_) {
    _assertAddressNotZero(address(cozySafetyModuleManager_));
    _assertAddressNotZero(address(receiptTokenFactory_));
    cozySafetyModuleManager = cozySafetyModuleManager_;
    receiptTokenFactory = receiptTokenFactory_;
  }

  /// @notice Initializes the SafetyModule with the specified parameters.
  /// @dev Replaces the constructor for minimal proxies.
  /// @param owner_ The SafetyModule owner.
  /// @param pauser_ The SafetyModule pauser.
  /// @param configs_ The SafetyModule configuration parameters. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  function initialize(address owner_, address pauser_, UpdateConfigsCalldataParams calldata configs_) external {
    if (initialized) revert Initialized();

    // Safety Modules are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the logic
    // contract. When the set is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);
    
    initialized = true;
    ConfiguratorLib.applyConfigUpdates(reservePools, triggerData, delays, receiptTokenFactory, configs_);
  }
}
