// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IConfiguratorErrors} from "../interfaces/IConfiguratorErrors.sol";
import {ReservePool, UndrippedRewardPool, IdLookup} from "./structs/Pools.sol";
import {Delays} from "./structs/Delays.sol";
import {ReservePoolConfig, UndrippedRewardPoolConfig} from "./structs/Configs.sol";
import {ConfigUpdateMetadata} from "./structs/Configs.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {MathConstants} from "./MathConstants.sol";
import {SafeCastLib} from "./SafeCastLib.sol";

library ConfiguratorLib {
  using FixedPointMathLib for uint256;
  using SafeCastLib for uint256;

  /// @dev Emitted when a safety module owner queues a new configuration.
  event ConfigUpdatesQueued(
    ReservePoolConfig[] reservePoolConfigs,
    UndrippedRewardPoolConfig[] undrippedRewardPoolConfigs,
    Delays delaysConfig,
    uint256 updateTime,
    uint256 updateDeadline
  );

  /// @dev Emitted when a safety module's queued configuration updates are applied.
  event ConfigUpdatesFinalized(
    ReservePoolConfig[] reservePoolConfigs, UndrippedRewardPoolConfig[] undrippedRewardPoolConfigs, Delays delaysConfig
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
  /// @param reservePoolConfigs_ The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// @param undrippedRewardPoolConfigs_ The array of new undripped reward pool configs, sorted by associated ID. The
  /// array may also include config for new reward pools.
  /// @param delaysConfig_ The new delays config.
  function updateConfigs(
    ConfigUpdateMetadata storage lastConfigUpdate_,
    ReservePool[] storage reservePools_,
    UndrippedRewardPool[] storage undrippedRewardPools_,
    Delays storage delays_,
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) external {
    if (
      !isValidUpdate(
        reservePools_, undrippedRewardPools_, reservePoolConfigs_, undrippedRewardPoolConfigs_, delaysConfig_
      )
    ) revert IConfiguratorErrors.InvalidConfiguration();

    // Hash stored to ensure only queued updates can be applied.
    lastConfigUpdate_.queuedConfigUpdateHash =
      keccak256(abi.encode(reservePoolConfigs_, undrippedRewardPoolConfigs_, delaysConfig_));

    uint64 configUpdateTime_ = uint64(block.timestamp) + delays_.configUpdateDelay;
    uint64 configUpdateDeadline_ = configUpdateTime_ + delays_.configUpdateGracePeriod;
    emit ConfigUpdatesQueued(
      reservePoolConfigs_, undrippedRewardPoolConfigs_, delaysConfig_, configUpdateTime_, configUpdateDeadline_
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
  /// @param receiptTokenFactory_ The address of the receipt token factory.
  /// @param reservePoolConfigs_ The array of new reserve pool configs, sorted by associated ID.
  /// @param undrippedRewardPoolConfigs_ The array of new undripped reward pool configs, sorted by associated ID.
  /// @param delaysConfig_ The new delays config.
  function finalizeUpdateConfigs(
    ConfigUpdateMetadata storage lastConfigUpdate_,
    SafetyModuleState safetyModuleState_,
    ReservePool[] storage reservePools_,
    UndrippedRewardPool[] storage undrippedRewardPools_,
    Delays storage delays_,
    mapping(IReceiptToken => IdLookup) storage stkTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) external {
    if (safetyModuleState_ == SafetyModuleState.TRIGGERED) revert ICommonErrors.InvalidState();
    if (block.timestamp < lastConfigUpdate_.configUpdateTime) revert ICommonErrors.InvalidStateTransition();
    if (block.timestamp > lastConfigUpdate_.configUpdateDeadline) revert ICommonErrors.InvalidStateTransition();
    if (
      keccak256(abi.encode(reservePoolConfigs_, undrippedRewardPoolConfigs_, delaysConfig_))
        != lastConfigUpdate_.queuedConfigUpdateHash
    ) revert IConfiguratorErrors.InvalidConfiguration();

    // Reset the config update hash.
    lastConfigUpdate_.queuedConfigUpdateHash = 0;
    applyConfigUpdates(
      reservePools_,
      undrippedRewardPools_,
      delays_,
      stkTokenToReservePoolIds_,
      receiptTokenFactory_,
      reservePoolConfigs_,
      undrippedRewardPoolConfigs_,
      delaysConfig_
    );
  }

  /// @notice Returns true if the provided configs are valid for the safety module, false otherwise.
  function isValidUpdate(
    ReservePool[] storage reservePools_,
    UndrippedRewardPool[] storage undrippedRewardPools_,
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) internal view returns (bool) {
    // Validate the configuration parameters.
    if (!isValidConfiguration(reservePoolConfigs_, delaysConfig_)) return false;

    // Validate number of reserve and rewards pools. It is only possible to add new pools, not remove existing ones.
    uint256 numExistingReservePools_ = reservePools_.length;
    uint256 numExistingUndrippedRewardPools_ = undrippedRewardPools_.length;
    if (
      reservePoolConfigs_.length < numExistingReservePools_
        || undrippedRewardPoolConfigs_.length < numExistingUndrippedRewardPools_
    ) return false;

    // Validate existing reserve pools.
    for (uint16 i = 0; i < numExistingReservePools_; i++) {
      if (reservePools_[i].asset != reservePoolConfigs_[i].asset) return false;
    }

    // Validate existing undripped reward pools.
    for (uint16 i = 0; i < numExistingUndrippedRewardPools_; i++) {
      if (undrippedRewardPools_[i].asset != undrippedRewardPoolConfigs_[i].asset) return false;
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

    // Validate rewards pools weights.
    uint16 weightSum_ = 0;
    for (uint16 i = 0; i < reservePoolConfigs_.length; i++) {
      weightSum_ += reservePoolConfigs_[i].rewardsPoolsWeight;
    }
    if (weightSum_ != MathConstants.ZOC) return false;
    return true;
  }

  /// @notice Apply queued updates to safety module config.
  function applyConfigUpdates(
    ReservePool[] storage reservePools_,
    UndrippedRewardPool[] storage undrippedRewardPools_,
    Delays storage delays_,
    mapping(IReceiptToken => IdLookup) storage stkTokenToReservePoolIds_,
    IReceiptTokenFactory receiptTokenFactory_,
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) public {
    // Update existing reserve pool weights. No need to update the reserve pool asset since it cannot change.
    uint256 numExistingReservePools_ = reservePools_.length;
    for (uint256 i = 0; i < numExistingReservePools_; i++) {
      reservePools_[i].rewardsPoolsWeight = reservePoolConfigs_[i].rewardsPoolsWeight;
    }

    // Initialize new reserve pools.
    for (uint256 i = numExistingReservePools_; i < reservePoolConfigs_.length; i++) {
      initializeReservePool(reservePools_, stkTokenToReservePoolIds_, receiptTokenFactory_, reservePoolConfigs_[i]);
    }

    // Update existing reward pool drip models. No need to update the reward pool asset since it cannot change.
    uint256 numExistingUndrippedRewardPools_ = undrippedRewardPools_.length;
    for (uint256 i = 0; i < numExistingUndrippedRewardPools_; i++) {
      undrippedRewardPools_[i].dripModel = undrippedRewardPoolConfigs_[i].dripModel;
    }

    // Initialize new reward pools.
    for (uint256 i = numExistingUndrippedRewardPools_; i < undrippedRewardPoolConfigs_.length; i++) {
      initializeUndrippedRewardPool(undrippedRewardPools_, receiptTokenFactory_, undrippedRewardPoolConfigs_[i]);
    }

    // Update delays.
    delays_.configUpdateDelay = delaysConfig_.configUpdateDelay;
    delays_.configUpdateGracePeriod = delaysConfig_.configUpdateGracePeriod;
    delays_.unstakeDelay = delaysConfig_.unstakeDelay;
    delays_.withdrawDelay = delaysConfig_.withdrawDelay;

    emit ConfigUpdatesFinalized(reservePoolConfigs_, undrippedRewardPoolConfigs_, delaysConfig_);
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
        rewardsPoolsWeight: reservePoolConfig_.rewardsPoolsWeight
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
