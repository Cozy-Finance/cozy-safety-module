// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ConfiguratorLib} from "./ConfiguratorLib.sol";
import {Governable} from "./Governable.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {Delays} from "./structs/Delays.sol";
import {ReservePool, RewardPool} from "./structs/Pools.sol";
import {ClaimableRewardsData} from "./structs/Rewards.sol";
import {
  ConfigUpdateMetadata, ReservePoolConfig, RewardPoolConfig, UpdateConfigsCalldataParams
} from "./structs/Configs.sol";
import {TriggerConfig} from "./structs/Trigger.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {ISafetyModule} from "../interfaces/ISafetyModule.sol";

abstract contract Configurator is SafetyModuleCommon, Governable {
  ConfigUpdateMetadata public lastConfigUpdate;

  /// @notice Signal an update to the safety module configs. Existing queued updates are overwritten.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - rewardPoolConfigs: The array of new reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function updateConfigs(UpdateConfigsCalldataParams calldata configUpdates_) external onlyOwner {
    ConfiguratorLib.updateConfigs(
      lastConfigUpdate, reservePools, rewardPools, triggerData, delays, configUpdates_, cozyManager
    );
  }

  /// @notice Execute queued updates to the safety module configs.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - rewardPoolConfigs: The array of new reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function finalizeUpdateConfigs(UpdateConfigsCalldataParams calldata configUpdates_) external {
    // A config update may change the rewards weights, which breaks the invariants that we use to do claimable rewards
    // accounting. It may no longer hold that:
    //    claimableRewards[reservePool][rewardPool].cumulativeClaimedRewards <=
    //        rewardPools[rewardPool].cumulativeDrippedRewards*reservePools[reservePool].rewardsPoolsWeight
    // So, before finalizing, we drip rewards, update claimable reward indices and reset the cumulative rewards values
    // to 0.
    ReservePool[] storage reservePools_ = reservePools;
    RewardPool[] storage rewardPools_ = rewardPools;
    _dripAndResetCumulativeRewardsValues(reservePools_, rewardPools_);

    ConfiguratorLib.finalizeUpdateConfigs(
      lastConfigUpdate,
      safetyModuleState,
      reservePools_,
      rewardPools_,
      triggerData,
      delays,
      stkTokenToReservePoolIds,
      receiptTokenFactory,
      configUpdates_
    );
  }
}
