// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ConfiguratorLib} from "./ConfiguratorLib.sol";
import {Governable} from "./Governable.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {Delays} from "./structs/Delays.sol";
import {ConfigUpdateMetadata} from "./structs/Configs.sol";
import {ReservePoolConfig, UndrippedRewardPoolConfig} from "./structs/Configs.sol";

abstract contract Configurator is SafetyModuleCommon, Governable {
  ConfigUpdateMetadata public lastConfigUpdate;

  /// @notice Signal an update to the safety module configs. Existing queued updates are overwritten.
  /// @param reservePoolConfigs_ The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// @param undrippedRewardPoolConfigs_ The array of new undripped reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// @param delaysConfig_ The new delays config.
  function updateConfigs(
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) external onlyOwner {
    ConfiguratorLib.updateConfigs(
      lastConfigUpdate,
      reservePools,
      undrippedRewardPools,
      delays,
      reservePoolConfigs_,
      undrippedRewardPoolConfigs_,
      delaysConfig_
    );
  }

  /// @notice Execute queued updates to the safety module configs.
  /// @param reservePoolConfigs_ The array of new reserve pool configs. Must be identical to the queued reserve pool
  /// config updates.
  /// @param undrippedRewardPoolConfigs_ The array of new undripped reward pool configs. Must be identical to the queued
  /// undripped reward pool config updates.
  /// @param delaysConfig_ The new delays config. Must be identical to the queued delays config update.
  function finalizeUpdateConfigs(
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) external {
    ConfiguratorLib.finalizeUpdateConfigs(
      lastConfigUpdate,
      safetyModuleState,
      reservePools,
      undrippedRewardPools,
      delays,
      stkTokenToReservePoolIds,
      receiptTokenFactory,
      reservePoolConfigs_,
      undrippedRewardPoolConfigs_,
      delaysConfig_
    );
  }
}
