// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {SafetyModuleState, TriggerState} from "cozy-safety-module-shared/lib/SafetyModuleStates.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IConfiguratorErrors} from "../interfaces/IConfiguratorErrors.sol";
import {IConfiguratorEvents} from "../interfaces/IConfiguratorEvents.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {IManager} from "../interfaces/IManager.sol";
import {ReservePool, IdLookup} from "./structs/Pools.sol";
import {Delays} from "./structs/Delays.sol";
import {ConfigUpdateMetadata, ReservePoolConfig, UpdateConfigsCalldataParams} from "./structs/Configs.sol";
import {TriggerConfig, Trigger} from "./structs/Trigger.sol";

library ConfiguratorLib {
  /// @notice Signal an update to the safety module configs. Existing queued updates are overwritten.
  /// @param lastConfigUpdate_ Metadata about the most recently queued configuration update.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param delays_ The existing delays config.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function updateConfigs(
    ConfigUpdateMetadata storage lastConfigUpdate_,
    ReservePool[] storage reservePools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    UpdateConfigsCalldataParams calldata configUpdates_,
    IManager manager_
  ) external {
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

  /// @notice Execute queued updates to safety module configs.
  /// @param lastConfigUpdate_ Metadata about the most recently queued configuration update.
  /// @param safetyModuleState_ The state of the safety module.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param delays_ The existing delays config.
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
  ) external {
    if (safetyModuleState_ == SafetyModuleState.TRIGGERED) revert ICommonErrors.InvalidState();
    if (block.timestamp < lastConfigUpdate_.configUpdateTime) revert ICommonErrors.InvalidStateTransition();
    if (block.timestamp > lastConfigUpdate_.configUpdateDeadline) revert ICommonErrors.InvalidStateTransition();
    if (
      keccak256(
        abi.encode(configUpdates_.reservePoolConfigs, configUpdates_.triggerConfigUpdates, configUpdates_.delaysConfig)
      ) != lastConfigUpdate_.queuedConfigUpdateHash
    ) revert IConfiguratorErrors.InvalidConfiguration();

    // Reset the config update hash.
    lastConfigUpdate_.queuedConfigUpdateHash = 0;
    applyConfigUpdates(reservePools_, triggerData_, delays_, receiptTokenFactory_, configUpdates_);
  }

  /// @notice Returns true if the provided configs are valid for the safety module, false otherwise.
  function isValidUpdate(
    ReservePool[] storage reservePools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    UpdateConfigsCalldataParams calldata configUpdates_,
    IManager manager_
  ) internal view returns (bool) {
    // Validate the configuration parameters.
    if (
      !isValidConfiguration(
        configUpdates_.reservePoolConfigs, configUpdates_.delaysConfig, manager_.allowedReservePools()
      )
    ) return false;

    // Validate number of reserve pools. It is only possible to add new pools, not remove existing ones.
    uint256 numExistingReservePools_ = reservePools_.length;
    if (configUpdates_.reservePoolConfigs.length < numExistingReservePools_) return false;

    // Validate existing reserve pools.
    for (uint16 i = 0; i < numExistingReservePools_; i++) {
      if (reservePools_[i].asset != configUpdates_.reservePoolConfigs[i].asset) return false;
    }

    for (uint16 i = 0; i < configUpdates_.triggerConfigUpdates.length; i++) {
      // Triggers that have successfully called trigger() on the safety module cannot be updated.
      if (triggerData_[configUpdates_.triggerConfigUpdates[i].trigger].triggered) return false;
    }

    return true;
  }

  /// @notice Returns true if the provided configs are generically valid, false otherwise.
  /// @dev Does not include safety module-specific checks, e.g. checks based on existing reserve pools.
  function isValidConfiguration(
    ReservePoolConfig[] calldata reservePoolConfigs_,
    Delays calldata delaysConfig_,
    uint256 maxReservePools_
  ) internal pure returns (bool) {
    // Validate number of reserve pools.
    if (reservePoolConfigs_.length > maxReservePools_) return false;

    // Validate delays.
    if (delaysConfig_.configUpdateDelay <= delaysConfig_.withdrawDelay) return false;

    // Validate max slash percentages.
    for (uint16 i = 0; i < reservePoolConfigs_.length; i++) {
      if (reservePoolConfigs_[i].maxSlashPercentage > MathConstants.WAD) return false;
    }

    return true;
  }

  /// @notice Apply queued updates to safety module config.
  function applyConfigUpdates(
    ReservePool[] storage reservePools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    IReceiptTokenFactory receiptTokenFactory_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) public {
    // Update existing reserve pool maxSlashPercentages. No need to update the reserve pool asset since it cannot
    // change.
    uint256 numExistingReservePools_ = reservePools_.length;
    for (uint256 i = 0; i < numExistingReservePools_; i++) {
      ReservePool storage reservePool_ = reservePools_[i];
      reservePool_.maxSlashPercentage = configUpdates_.reservePoolConfigs[i].maxSlashPercentage;
    }

    // Initialize new reserve pools.
    for (uint256 i = numExistingReservePools_; i < configUpdates_.reservePoolConfigs.length; i++) {
      initializeReservePool(reservePools_, receiptTokenFactory_, configUpdates_.reservePoolConfigs[i]);
    }

    // Update trigger configs.
    for (uint256 i = 0; i < configUpdates_.triggerConfigUpdates.length; i++) {
      // Triggers that have successfully called trigger() on the safety module cannot be updated.
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

  /// @dev Initializes a new reserve pool when it is added to the safety module.
  function initializeReservePool(
    ReservePool[] storage reservePools_,
    IReceiptTokenFactory receiptTokenFactory_,
    ReservePoolConfig calldata reservePoolConfig_
  ) internal {
    uint16 reservePoolId_ = uint16(reservePools_.length);

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
