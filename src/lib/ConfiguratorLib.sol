// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IConfiguratorErrors} from "../interfaces/IConfiguratorErrors.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {ReservePool, UndrippedRewardPool, IdLookup} from "./structs/Pools.sol";
import {Delays} from "./structs/Delays.sol";
import {
  ConfigUpdateMetadata,
  ReservePoolConfig,
  UndrippedRewardPoolConfig,
  UpdateConfigsCalldataParams
} from "./structs/Configs.sol";
import {TriggerConfig, Trigger} from "./structs/Trigger.sol";
import {SafetyModuleState, TriggerState} from "./SafetyModuleStates.sol";
import {MathConstants} from "./MathConstants.sol";
import {SafeCastLib} from "./SafeCastLib.sol";

library ConfiguratorLib {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  /// @dev Emitted when a safety module owner queues a new configuration.
  event ConfigUpdatesQueued(
    ReservePoolConfig[] reservePoolConfigs,
    UndrippedRewardPoolConfig[] undrippedRewardPoolConfigs,
    TriggerConfig[] triggerConfigs,
    Delays delaysConfig,
    uint256 updateTime,
    uint256 updateDeadline
  );

  /// @dev Emitted when a safety module's queued configuration updates are applied.
  event ConfigUpdatesFinalized(
    ReservePoolConfig[] reservePoolConfigs,
    UndrippedRewardPoolConfig[] undrippedRewardPoolConfigs,
    TriggerConfig[] triggerConfigUpdates,
    Delays delaysConfig
  );

  /// @notice Emitted when a reserve pool is created.
  event ReservePoolCreated(
    uint16 indexed reservePoolId, address reserveAssetAddress, address stkTokenAddress, address depositTokenAddress
  );

  /// @notice Emitted when an undripped reward pool is created.
  event UndrippedRewardPoolCreated(
    uint16 indexed undrippedRewardPoolId, address rewardAssetAddress, address depositTokenAddress
  );

  /// @notice Signal an update to the safety module configs. Existing queued updates are overwritten.
  /// @param lastConfigUpdate_ Metadata about the most recently queued configuration update.
  /// @param reservePools_ The array of existing reserve pools.
  /// @param undrippedRewardPools_ The array of existing undripped reward pools.
  /// @param delays_ The existing delays config.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - undrippedRewardPoolConfigs: The array of new undripped reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function updateConfigs(
    ConfigUpdateMetadata storage lastConfigUpdate_,
    ReservePool[] storage reservePools_,
    UndrippedRewardPool[] storage undrippedRewardPools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) external {
    if (!isValidUpdate(reservePools_, undrippedRewardPools_, triggerData_, configUpdates_)) {
      revert IConfiguratorErrors.InvalidConfiguration();
    }

    // Hash stored to ensure only queued updates can be applied.
    lastConfigUpdate_.queuedConfigUpdateHash = keccak256(
      abi.encode(
        configUpdates_.reservePoolConfigs,
        configUpdates_.undrippedRewardPoolConfigs,
        configUpdates_.triggerConfigUpdates,
        configUpdates_.delaysConfig
      )
    );

    uint64 configUpdateTime_ = uint64(block.timestamp) + delays_.configUpdateDelay;
    uint64 configUpdateDeadline_ = configUpdateTime_ + delays_.configUpdateGracePeriod;
    emit ConfigUpdatesQueued(
      configUpdates_.reservePoolConfigs,
      configUpdates_.undrippedRewardPoolConfigs,
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
  /// @param undrippedRewardPools_ The array of existing undripped reward pools.
  /// @param delays_ The existing delays config.
  /// @param stkTokenToReservePoolIds_ The mapping of stktokens to reserve pool IDs.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - undrippedRewardPoolConfigs: The array of new undripped reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function finalizeUpdateConfigs(
    ConfigUpdateMetadata storage lastConfigUpdate_,
    SafetyModuleState safetyModuleState_,
    ReservePool[] storage reservePools_,
    UndrippedRewardPool[] storage undrippedRewardPools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    mapping(IReceiptToken => IdLookup) storage stkTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) external {
    if (safetyModuleState_ == SafetyModuleState.TRIGGERED) revert ICommonErrors.InvalidState();
    if (block.timestamp < lastConfigUpdate_.configUpdateTime) revert ICommonErrors.InvalidStateTransition();
    if (block.timestamp > lastConfigUpdate_.configUpdateDeadline) revert ICommonErrors.InvalidStateTransition();
    if (
      keccak256(
        abi.encode(
          configUpdates_.reservePoolConfigs,
          configUpdates_.undrippedRewardPoolConfigs,
          configUpdates_.triggerConfigUpdates,
          configUpdates_.delaysConfig
        )
      ) != lastConfigUpdate_.queuedConfigUpdateHash
    ) revert IConfiguratorErrors.InvalidConfiguration();

    // Reset the config update hash.
    lastConfigUpdate_.queuedConfigUpdateHash = 0;
    applyConfigUpdates(
      reservePools_,
      undrippedRewardPools_,
      triggerData_,
      delays_,
      stkTokenToReservePoolIds_,
      receiptTokenFactory_,
      configUpdates_
    );
  }

  /// @notice Returns true if the provided configs are valid for the safety module, false otherwise.
  function isValidUpdate(
    ReservePool[] storage reservePools_,
    UndrippedRewardPool[] storage undrippedRewardPools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) internal view returns (bool) {
    // Validate the configuration parameters.
    if (!isValidConfiguration(configUpdates_.reservePoolConfigs, configUpdates_.delaysConfig)) return false;

    // Validate number of reserve and rewards pools. It is only possible to add new pools, not remove existing ones.
    uint256 numExistingReservePools_ = reservePools_.length;
    uint256 numExistingUndrippedRewardPools_ = undrippedRewardPools_.length;
    if (
      configUpdates_.reservePoolConfigs.length < numExistingReservePools_
        || configUpdates_.undrippedRewardPoolConfigs.length < numExistingUndrippedRewardPools_
    ) return false;

    // Validate existing reserve pools.
    for (uint16 i = 0; i < numExistingReservePools_; i++) {
      if (reservePools_[i].asset != configUpdates_.reservePoolConfigs[i].asset) return false;
    }

    // Validate existing undripped reward pools.
    for (uint16 i = 0; i < numExistingUndrippedRewardPools_; i++) {
      if (undrippedRewardPools_[i].asset != configUpdates_.undrippedRewardPoolConfigs[i].asset) return false;
    }

    for (uint16 i = 0; i < configUpdates_.triggerConfigUpdates.length; i++) {
      // Triggers that have successfully called trigger() on the safety module cannot be updated.
      if (triggerData_[configUpdates_.triggerConfigUpdates[i].trigger].triggered) return false;
    }

    return true;
  }

  /// @notice Returns true if the provided configs are generically valid, false otherwise.
  /// @dev Does not include safety module-specific checks, e.g. checks based on existing reserve and reward pools.
  function isValidConfiguration(ReservePoolConfig[] calldata reservePoolConfigs_, Delays calldata delaysConfig_)
    internal
    pure
    returns (bool)
  {
    // Validate delays.
    if (
      delaysConfig_.configUpdateDelay <= delaysConfig_.unstakeDelay
        || delaysConfig_.configUpdateDelay <= delaysConfig_.withdrawDelay
    ) return false;

    // Validate rewards pools weights and max slash percentages.
    uint16 weightSum_ = 0;
    for (uint16 i = 0; i < reservePoolConfigs_.length; i++) {
      weightSum_ += reservePoolConfigs_[i].rewardsPoolsWeight;
      if (reservePoolConfigs_[i].maxSlashPercentage > MathConstants.WAD) return false;
    }
    if (weightSum_ != MathConstants.ZOC) return false;
    return true;
  }

  /// @notice Apply queued updates to safety module config.
  function applyConfigUpdates(
    ReservePool[] storage reservePools_,
    UndrippedRewardPool[] storage undrippedRewardPools_,
    mapping(ITrigger => Trigger) storage triggerData_,
    Delays storage delays_,
    mapping(IReceiptToken => IdLookup) storage stkTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    UpdateConfigsCalldataParams calldata configUpdates_
  ) public {
    // Update existing reserve pool weights. No need to update the reserve pool asset since it cannot change.
    uint256 numExistingReservePools_ = reservePools_.length;
    for (uint256 i = 0; i < numExistingReservePools_; i++) {
      reservePools_[i].rewardsPoolsWeight = configUpdates_.reservePoolConfigs[i].rewardsPoolsWeight;
    }

    // Initialize new reserve pools.
    for (uint256 i = numExistingReservePools_; i < configUpdates_.reservePoolConfigs.length; i++) {
      initializeReservePool(
        reservePools_, stkTokenToReservePoolIds_, receiptTokenFactory_, configUpdates_.reservePoolConfigs[i]
      );
    }

    // Update existing reward pool drip models. No need to update the reward pool asset since it cannot change.
    uint256 numExistingUndrippedRewardPools_ = undrippedRewardPools_.length;
    for (uint256 i = 0; i < numExistingUndrippedRewardPools_; i++) {
      undrippedRewardPools_[i].dripModel = configUpdates_.undrippedRewardPoolConfigs[i].dripModel;
    }

    // Initialize new reward pools.
    for (uint256 i = numExistingUndrippedRewardPools_; i < configUpdates_.undrippedRewardPoolConfigs.length; i++) {
      initializeUndrippedRewardPool(
        undrippedRewardPools_, receiptTokenFactory_, configUpdates_.undrippedRewardPoolConfigs[i]
      );
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
    delays_.unstakeDelay = configUpdates_.delaysConfig.unstakeDelay;
    delays_.withdrawDelay = configUpdates_.delaysConfig.withdrawDelay;

    emit ConfigUpdatesFinalized(
      configUpdates_.reservePoolConfigs,
      configUpdates_.undrippedRewardPoolConfigs,
      configUpdates_.triggerConfigUpdates,
      configUpdates_.delaysConfig
    );
  }

  /// @dev Initializes a new reserve pool when it is added to the safety module.
  function initializeReservePool(
    ReservePool[] storage reservePools_,
    mapping(IReceiptToken stkToken_ => IdLookup reservePoolId_) storage stkTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    ReservePoolConfig calldata reservePoolConfig_
  ) internal {
    uint16 reservePoolId_ = uint16(reservePools_.length);

    IReceiptToken stkToken_ = receiptTokenFactory_.deployReceiptToken(
      reservePoolId_, IReceiptTokenFactory.PoolType.STAKE, reservePoolConfig_.asset.decimals()
    );
    IReceiptToken reserveDepositToken_ = receiptTokenFactory_.deployReceiptToken(
      reservePoolId_, IReceiptTokenFactory.PoolType.RESERVE, reservePoolConfig_.asset.decimals()
    );

    reservePools_.push(
      ReservePool({
        asset: reservePoolConfig_.asset,
        stkToken: stkToken_,
        depositToken: reserveDepositToken_,
        stakeAmount: 0,
        depositAmount: 0,
        pendingUnstakesAmount: 0,
        pendingWithdrawalsAmount: 0,
        feeAmount: 0,
        rewardsPoolsWeight: reservePoolConfig_.rewardsPoolsWeight,
        maxSlashPercentage: reservePoolConfig_.maxSlashPercentage
      })
    );
    stkTokenToReservePoolIds_[stkToken_] = IdLookup({index: reservePoolId_, exists: true});

    emit ReservePoolCreated(
      reservePoolId_, address(reservePoolConfig_.asset), address(stkToken_), address(reserveDepositToken_)
    );
  }

  /// @dev Initializes a new undripped reward pool when it is added to the safety module.
  function initializeUndrippedRewardPool(
    UndrippedRewardPool[] storage undrippedRewardPools_,
    IReceiptTokenFactory receiptTokenFactory_,
    UndrippedRewardPoolConfig calldata undrippedRewardPoolConfig_
  ) internal {
    uint16 undrippedRewardPoolId_ = uint16(undrippedRewardPools_.length);

    IReceiptToken rewardDepositToken_ = receiptTokenFactory_.deployReceiptToken(
      undrippedRewardPoolId_, IReceiptTokenFactory.PoolType.REWARD, undrippedRewardPoolConfig_.asset.decimals()
    );

    undrippedRewardPools_.push(
      UndrippedRewardPool({
        asset: undrippedRewardPoolConfig_.asset,
        amount: 0,
        dripModel: undrippedRewardPoolConfig_.dripModel,
        depositToken: rewardDepositToken_
      })
    );

    emit UndrippedRewardPoolCreated(
      undrippedRewardPoolId_, address(undrippedRewardPoolConfig_.asset), address(rewardDepositToken_)
    );
  }
}
