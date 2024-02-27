// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafetyModuleState, TriggerState} from "./SafetyModuleStates.sol";
import {IConfiguratorErrors} from "../interfaces/IConfiguratorErrors.sol";
import {IConfiguratorEvents} from "../interfaces/IConfiguratorEvents.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {ICozySafetyModuleManager} from "../interfaces/ICozySafetyModuleManager.sol";
import {ReservePool} from "./structs/Pools.sol";
import {Delays} from "./structs/Delays.sol";
import {ConfigUpdateMetadata, ReservePoolConfig, UpdateConfigsCalldataParams} from "./structs/Configs.sol";
import {TriggerConfig, Trigger} from "./structs/Trigger.sol";

library ConfiguratorLib {
  error InvalidTimestamp();

  /// @notice Signal an update to the SafetyModule configs. Existing queued updates are overwritten.
  /// @param lastConfigUpdate_ Metadata about the most recently queued configuration update.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param triggerData_ The mapping of trigger to trigger data.
  /// @param delays_ The existing delays config.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  /// @param manager_ The Cozy Safety Module protocol Manager.
  function updateConfigs(
    ConfigUpdateMetadata storage lastConfigUpdate_,
    ReservePool[] storage reservePools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    UpdateConfigsCalldataParams calldata configUpdates_,
    ICozySafetyModuleManager manager_
  ) internal {
    if (!isValidUpdate(reservePools_, triggerData_, configUpdates_, manager_)) {
      revert IConfiguratorErrors.InvalidConfiguration();
    }

    // Hash stored to ensure only queued updates can be applied.
    lastConfigUpdate_.queuedConfigUpdateHash = keccak256(
      abi.encode(configUpdates_.reservePoolConfigs, configUpdates_.triggerConfigUpdates, configUpdates_.delaysConfig)
    );

    uint64 configUpdateTime_ = uint64(block.timestamp) + delays_.configUpdateDelay;
    uint64 configUpdateDeadline_ = configUpdateTime_ + delays_.configUpdateGracePeriod;
    emit IConfiguratorEvents.ConfigUpdatesQueued(
      configUpdates_.reservePoolConfigs,
      configUpdates_.triggerConfigUpdates,
      configUpdates_.delaysConfig,
      configUpdateTime_,
      configUpdateDeadline_
    );

    lastConfigUpdate_.configUpdateTime = configUpdateTime_;
    lastConfigUpdate_.configUpdateDeadline = configUpdateDeadline_;
  }

  /// @notice Execute queued updates to SafetyModule configs.
  /// @param lastConfigUpdate_ Metadata about the most recently queued configuration update.
  /// @param safetyModuleState_ The state of the SafetyModule.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param triggerData_ The mapping of trigger to trigger data.
  /// @param delays_ The existing delays config.
  /// @param receiptTokenFactory_ The ReceiptToken factory.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function finalizeUpdateConfigs(
    ConfigUpdateMetadata storage lastConfigUpdate_,
    SafetyModuleState safetyModuleState_,
    ReservePool[] storage reservePools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    IReceiptTokenFactory receiptTokenFactory_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) internal {
    if (safetyModuleState_ == SafetyModuleState.TRIGGERED) revert ICommonErrors.InvalidState();
    if (block.timestamp < lastConfigUpdate_.configUpdateTime) revert InvalidTimestamp();
    if (block.timestamp > lastConfigUpdate_.configUpdateDeadline) revert InvalidTimestamp();

    // Ensure the queued config update hash matches the provided config updates.
    if (
      keccak256(
        abi.encode(configUpdates_.reservePoolConfigs, configUpdates_.triggerConfigUpdates, configUpdates_.delaysConfig)
      ) != lastConfigUpdate_.queuedConfigUpdateHash
    ) revert IConfiguratorErrors.InvalidConfiguration();

    // Reset the config update hash.
    lastConfigUpdate_.queuedConfigUpdateHash = 0;
    applyConfigUpdates(reservePools_, triggerData_, delays_, receiptTokenFactory_, configUpdates_);
  }

  /// @notice Returns true if the provided configs are valid for the SafetyModule, false otherwise.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param triggerData_ The mapping of trigger to trigger data.
  /// @param configUpdates_ The new configs.
  /// @param manager_ The Cozy Safety Module protocol Manager.
  function isValidUpdate(
    ReservePool[] storage reservePools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    UpdateConfigsCalldataParams calldata configUpdates_,
    ICozySafetyModuleManager manager_
  ) internal view returns (bool) {
    // Generic validation of the configuration parameters.
    if (
      !isValidConfiguration(
        configUpdates_.reservePoolConfigs, configUpdates_.delaysConfig, manager_.allowedReservePools()
      )
    ) return false;

    // Validate number of reserve pools. It is only possible to add new pools, not remove existing ones.
    uint256 numExistingReservePools_ = reservePools_.length;
    if (configUpdates_.reservePoolConfigs.length < numExistingReservePools_) return false;

    // Validate existing reserve pools.
    for (uint8 i = 0; i < numExistingReservePools_; i++) {
      // Existing reserve pools cannot have their asset updated.
      if (reservePools_[i].asset != configUpdates_.reservePoolConfigs[i].asset) return false;
    }

    // Validate trigger config.
    for (uint16 i = 0; i < configUpdates_.triggerConfigUpdates.length; i++) {
      // Triggers that have successfully called trigger() on the safety module cannot be updated.
      if (triggerData_[configUpdates_.triggerConfigUpdates[i].trigger].triggered) return false;
    }

    return true;
  }

  /// @notice Returns true if the provided configs are generically valid, false otherwise.
  /// @dev Does not include SafetyModule-specific checks, e.g. checks based on existing reserve pools.
  function isValidConfiguration(
    ReservePoolConfig[] calldata reservePoolConfigs_,
    Delays calldata delaysConfig_,
    uint8 maxReservePools_
  ) internal pure returns (bool) {
    // Validate number of reserve pools.
    if (reservePoolConfigs_.length > maxReservePools_) return false;

    // Validate delays.
    if (delaysConfig_.configUpdateDelay <= delaysConfig_.withdrawDelay) return false;

    // Validate max slash percentages.
    for (uint8 i = 0; i < reservePoolConfigs_.length; i++) {
      if (reservePoolConfigs_[i].maxSlashPercentage > MathConstants.ZOC) return false;
    }

    return true;
  }

  /// @notice Apply queued updates to SafetyModule config.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param triggerData_ The mapping of trigger to trigger data.
  /// @param delays_ The existing delays config.
  /// @param receiptTokenFactory_ The ReceiptToken factory.
  /// @param configUpdates_ The new configs.
  function applyConfigUpdates(
    ReservePool[] storage reservePools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    IReceiptTokenFactory receiptTokenFactory_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) public {
    // Update existing reserve pool maxSlashPercentages. Reserve pool assets cannot be updated.
    uint8 numExistingReservePools_ = uint8(reservePools_.length);
    for (uint8 i = 0; i < numExistingReservePools_; i++) {
      reservePools_[i].maxSlashPercentage = configUpdates_.reservePoolConfigs[i].maxSlashPercentage;
    }

    // Initialize new reserve pools.
    for (uint8 i = numExistingReservePools_; i < configUpdates_.reservePoolConfigs.length; i++) {
      initializeReservePool(reservePools_, receiptTokenFactory_, configUpdates_.reservePoolConfigs[i], i);
    }

    // Update trigger configs.
    for (uint256 i = 0; i < configUpdates_.triggerConfigUpdates.length; i++) {
      // Triggers that have successfully called trigger() on the Safety cannot be updated.
      // The trigger must also not be in a triggered state.
      if (
        triggerData_[configUpdates_.triggerConfigUpdates[i].trigger].triggered
          || configUpdates_.triggerConfigUpdates[i].trigger.state() == TriggerState.TRIGGERED
      ) revert IConfiguratorErrors.InvalidConfiguration();
      triggerData_[configUpdates_.triggerConfigUpdates[i].trigger] = Trigger({
        exists: configUpdates_.triggerConfigUpdates[i].exists,
        payoutHandler: configUpdates_.triggerConfigUpdates[i].payoutHandler,
        triggered: false
      });
    }

    // Update delays.
    delays_.configUpdateDelay = configUpdates_.delaysConfig.configUpdateDelay;
    delays_.configUpdateGracePeriod = configUpdates_.delaysConfig.configUpdateGracePeriod;
    delays_.withdrawDelay = configUpdates_.delaysConfig.withdrawDelay;

    emit IConfiguratorEvents.ConfigUpdatesFinalized(
      configUpdates_.reservePoolConfigs, configUpdates_.triggerConfigUpdates, configUpdates_.delaysConfig
    );
  }

  /// @notice Initializes a new reserve pool when it is added to the SafetyModule.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param receiptTokenFactory_ The ReceiptToken factory.
  /// @param reservePoolConfig_ The new reserve pool config.
  /// @param reservePoolId_ The ID of the new reserve pool.
  function initializeReservePool(
    ReservePool[] storage reservePools_,
    IReceiptTokenFactory receiptTokenFactory_,
    ReservePoolConfig calldata reservePoolConfig_,
    uint8 reservePoolId_
  ) internal {
    IReceiptToken reserveDepositReceiptToken_ = receiptTokenFactory_.deployReceiptToken(
      reservePoolId_, IReceiptTokenFactory.PoolType.RESERVE, reservePoolConfig_.asset.decimals()
    );

    reservePools_.push(
      ReservePool({
        asset: reservePoolConfig_.asset,
        depositReceiptToken: reserveDepositReceiptToken_,
        depositAmount: 0,
        pendingWithdrawalsAmount: 0,
        feeAmount: 0,
        maxSlashPercentage: reservePoolConfig_.maxSlashPercentage,
        lastFeesDripTime: uint128(block.timestamp)
      })
    );

    emit IConfiguratorEvents.ReservePoolCreated(reservePoolId_, reservePoolConfig_.asset, reserveDepositReceiptToken_);
  }
}
