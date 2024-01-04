// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ConfiguratorLib} from "./ConfiguratorLib.sol";
import {Governable} from "./Governable.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {Delays} from "./structs/Delays.sol";
import {
  ConfigUpdateMetadata,
  ReservePoolConfig,
  UndrippedRewardPoolConfig,
  UpdateConfigsCalldataParams
} from "./structs/Configs.sol";
import {TriggerConfig} from "./structs/Trigger.sol";

abstract contract Configurator is SafetyModuleCommon, Governable {
  ConfigUpdateMetadata public lastConfigUpdate;

  /// @notice Signal an update to the safety module configs. Existing queued updates are overwritten.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - undrippedRewardPoolConfigs: The array of new undripped reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function updateConfigs(UpdateConfigsCalldataParams calldata configUpdates_) external onlyOwner {
    ConfiguratorLib.updateConfigs(
      lastConfigUpdate, reservePools, undrippedRewardPools, triggerData, delays, configUpdates_
    );
  }

  /// @notice Execute queued updates to the safety module configs.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - undrippedRewardPoolConfigs: The array of new undripped reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function finalizeUpdateConfigs(UpdateConfigsCalldataParams calldata configUpdates_) external {
    ConfiguratorLib.finalizeUpdateConfigs(
      lastConfigUpdate,
      safetyModuleState,
      reservePools,
      undrippedRewardPools,
      triggerData,
      delays,
      stkTokenToReservePoolIds,
      receiptTokenFactory,
      configUpdates_
    );
  }
}
