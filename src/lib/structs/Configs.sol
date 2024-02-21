// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {Delays} from "./Delays.sol";
import {TriggerConfig} from "./Trigger.sol";

/// @notice Configuration for a reserve pool.
struct ReservePoolConfig {
  // The maximum percentage of the reserve pool assets that can be slashed in a single transaction, represented as a
  // ZOC. If multiple slashes occur, they compound, and the final reserve pool amount can be less than
  // (1 - maxSlashPercentage)% following all the slashes.
  uint256 maxSlashPercentage;
  // The underlying asset of the reserve pool.
  IERC20 asset;
}

/// @notice Metadata for a configuration update.
struct ConfigUpdateMetadata {
  // A hash representing queued `ReservePoolConfig[]`, TriggerConfig[], and `Delays` updates. This hash is
  // used to prove that the params used when applying config updates are identical to the queued updates.
  // This strategy is used instead of storing non-hashed `ReservePoolConfig[]`, `TriggerConfig[] and
  // `Delays` for gas optimization and to avoid dynamic array manipulation. This hash is set to bytes32(0) when there is
  // no config update queued.
  bytes32 queuedConfigUpdateHash;
  // Earliest timestamp at which finalizeUpdateConfigs can be called to apply config updates queued by updateConfigs.
  uint64 configUpdateTime;
  // The latest timestamp after configUpdateTime at which finalizeUpdateConfigs can be called to apply config
  // updates queued by updateConfigs. After this timestamp, the queued config updates expire and can no longer be
  // applied.
  uint64 configUpdateDeadline;
}

/// @notice Parameters for configuration updates.
struct UpdateConfigsCalldataParams {
  // The new reserve pool configs.
  ReservePoolConfig[] reservePoolConfigs;
  // The new trigger configs.
  TriggerConfig[] triggerConfigUpdates;
  // The new delays config.
  Delays delaysConfig;
}
