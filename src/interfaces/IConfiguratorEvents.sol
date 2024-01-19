// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {ReservePoolConfig, RewardPoolConfig} from "../lib/structs/Configs.sol";
import {Delays} from "../lib/structs/Delays.sol";
import {TriggerConfig} from "../lib/structs/Trigger.sol";

interface IConfiguratorEvents {
  /// @dev Emitted when a safety module owner queues a new configuration.
  event ConfigUpdatesQueued(
    ReservePoolConfig[] reservePoolConfigs,
    RewardPoolConfig[] undrippedRewardPoolConfigs,
    TriggerConfig[] triggerConfigUpdates,
    Delays delaysConfig,
    uint256 updateTime,
    uint256 updateDeadline
  );

  /// @dev Emitted when a safety module's queued configuration updates are applied.
  event ConfigUpdatesFinalized(
    ReservePoolConfig[] reservePoolConfigs,
    RewardPoolConfig[] undrippedRewardPoolConfigs,
    TriggerConfig[] triggerConfigUpdates,
    Delays delaysConfig
  );

  /// @notice Emitted when a reserve pool is created.
  event ReservePoolCreated(
    uint16 indexed reservePoolId, address reserveAssetAddress, address stkTokenAddress, address depositTokenAddress
  );

  /// @notice Emitted when an undripped reward pool is created.
  event RewardPoolCreated(
    uint16 indexed undrippedRewardPoolId, address rewardAssetAddress, address depositTokenAddress
  );
}
