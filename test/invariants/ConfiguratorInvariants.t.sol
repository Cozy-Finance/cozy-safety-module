// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {ConfiguratorLib} from "../../src/lib/ConfiguratorLib.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {Trigger} from "../../src/lib/structs/Trigger.sol";
import {ConfigUpdateMetadata, UpdateConfigsCalldataParams, ReservePoolConfig} from "../../src/lib/structs/Configs.sol";
import {TriggerConfig} from "../../src/lib/structs/Trigger.sol";
import {Delays} from "../../src/lib/structs/Delays.sol";
import {TriggerState} from "../../src/lib/SafetyModuleStates.sol";
import {ITrigger} from "../../src/interfaces/ITrigger.sol";
import {IStateChangerErrors} from "../../src/interfaces/IStateChangerErrors.sol";
import {ICozySafetyModuleManager} from "../../src/interfaces/ICozySafetyModuleManager.sol";
import {IConfiguratorErrors} from "../../src/interfaces/IConfiguratorErrors.sol";
import {MockTrigger} from "../utils/MockTrigger.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract ConfiguratorInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  function invariant_updateConfigsUpdatesLastConfigUpdate() public syncCurrentTimestamp(safetyModuleHandler) {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();
    ConfigUpdateMetadata memory expectedConfigUpdateMetadata_ = ConfigUpdateMetadata({
      queuedConfigUpdateHash: keccak256(
        abi.encode(updatedConfig_.reservePoolConfigs, updatedConfig_.triggerConfigUpdates, updatedConfig_.delaysConfig)
        ),
      configUpdateTime: uint64(block.timestamp + safetyModule.delays().configUpdateDelay),
      configUpdateDeadline: uint64(
        block.timestamp + safetyModule.delays().configUpdateDelay + safetyModule.delays().configUpdateGracePeriod
        )
    });

    vm.prank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);

    ConfigUpdateMetadata memory actualConfigUpdateMetadata_ = safetyModule.lastConfigUpdate();
    require(
      actualConfigUpdateMetadata_.queuedConfigUpdateHash == expectedConfigUpdateMetadata_.queuedConfigUpdateHash,
      "Queued config update hash does not match expected hash."
    );
    require(
      actualConfigUpdateMetadata_.configUpdateTime == expectedConfigUpdateMetadata_.configUpdateTime,
      "Config update time does not match expected time."
    );
    require(
      actualConfigUpdateMetadata_.configUpdateDeadline == expectedConfigUpdateMetadata_.configUpdateDeadline,
      "Config update deadline does not match expected deadline."
    );
  }

  function invariant_updateConfigRevertsForNonOwner() public syncCurrentTimestamp(safetyModuleHandler) {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory currentConfig_ = _copyCurrentConfig();

    address nonOwner_ = _randomAddress();
    vm.assume(safetyModule.owner() != nonOwner_);

    vm.prank(nonOwner_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    safetyModule.updateConfigs(currentConfig_);
  }

  function invariant_updateConfigRevertsTooManyReservePools() public syncCurrentTimestamp(safetyModuleHandler) {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory currentConfig_ = _copyCurrentConfig();

    ICozySafetyModuleManager manager_ = safetyModule.cozySafetyModuleManager();
    uint8 allowedReservePools_ = manager_.allowedReservePools();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](allowedReservePools_ + 1);
    for (uint256 i = 0; i < numReservePools; i++) {
      reservePoolConfigs_[i] = currentConfig_.reservePoolConfigs[i];
    }
    for (uint256 i = numReservePools; i < allowedReservePools_ + 1; i++) {
      reservePoolConfigs_[i] = ReservePoolConfig({
        maxSlashPercentage: _randomUint256InRange(0, MathConstants.ZOC),
        asset: assets[_randomUint256() % assets.length]
      });
    }
    UpdateConfigsCalldataParams memory updatedConfig_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: currentConfig_.triggerConfigUpdates,
      delaysConfig: currentConfig_.delaysConfig
    });

    vm.prank(safetyModule.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    safetyModule.updateConfigs(updatedConfig_);
  }

  function invariant_updateConfigRevertsInvalidConfigUpdateDelay() public syncCurrentTimestamp(safetyModuleHandler) {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory currentConfig_ = _copyCurrentConfig();

    Delays memory delaysConfig_ = _generateValidDelays();
    delaysConfig_.configUpdateDelay = uint64(bound(_randomUint256(), 0, delaysConfig_.withdrawDelay));

    UpdateConfigsCalldataParams memory updatedConfig_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: currentConfig_.reservePoolConfigs,
      triggerConfigUpdates: currentConfig_.triggerConfigUpdates,
      delaysConfig: delaysConfig_
    });

    vm.prank(safetyModule.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    safetyModule.updateConfigs(updatedConfig_);
  }

  function invariant_updateConfigRevertsInvalidMaxSlashPercentage() public syncCurrentTimestamp(safetyModuleHandler) {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _copyCurrentConfig();
    ReservePoolConfig[] memory updatedReservePoolConfigs_ = updatedConfig_.reservePoolConfigs;
    updatedReservePoolConfigs_[_randomUint256() % (updatedReservePoolConfigs_.length)].maxSlashPercentage =
      MathConstants.ZOC + 1;
    updatedConfig_.reservePoolConfigs = updatedReservePoolConfigs_;

    vm.prank(safetyModule.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    safetyModule.updateConfigs(updatedConfig_);
  }

  function invariant_updateConfigRevertsRemovesExistingReservePool() public syncCurrentTimestamp(safetyModuleHandler) {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _copyCurrentConfig();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](numReservePools - 1);
    for (uint8 i = 0; i < numReservePools - 1; i++) {
      reservePoolConfigs_[i] = updatedConfig_.reservePoolConfigs[i];
    }
    updatedConfig_.reservePoolConfigs = reservePoolConfigs_;

    vm.prank(safetyModule.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    safetyModule.updateConfigs(updatedConfig_);
  }

  function invariant_updateConfigRevertsChangesExistingReservePoolAsset()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _copyCurrentConfig();
    ReservePoolConfig[] memory updatedReservePoolConfigs_ = updatedConfig_.reservePoolConfigs;
    updatedReservePoolConfigs_[_randomUint256() % updatedReservePoolConfigs_.length].asset = IERC20(address(0xBEEF));
    updatedConfig_.reservePoolConfigs = updatedReservePoolConfigs_;

    vm.prank(safetyModule.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    safetyModule.updateConfigs(updatedConfig_);
  }

  function invariant_updateConfigRevertsUpdatesTriggeredTrigger() public syncCurrentTimestamp(safetyModuleHandler) {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    ITrigger[] memory triggeredTriggers_ = safetyModuleHandler.getTriggeredTriggers();
    if (triggeredTriggers_.length == 0) return;
    ITrigger triggeredTrigger_ = triggeredTriggers_[_randomUint256() % triggeredTriggers_.length];

    UpdateConfigsCalldataParams memory updatedConfig_ = _copyCurrentConfig();
    TriggerConfig[] memory updatedTriggerConfigs_ = new TriggerConfig[](updatedConfig_.triggerConfigUpdates.length + 1);
    for (uint8 i = 0; i < updatedConfig_.triggerConfigUpdates.length; i++) {
      updatedTriggerConfigs_[i] = updatedConfig_.triggerConfigUpdates[i];
    }
    updatedTriggerConfigs_[updatedConfig_.triggerConfigUpdates.length] = TriggerConfig({
      trigger: triggeredTrigger_,
      payoutHandler: safetyModule.triggerData(triggeredTrigger_).payoutHandler,
      exists: safetyModule.triggerData(triggeredTrigger_).exists
    });
    updatedConfig_.triggerConfigUpdates = updatedTriggerConfigs_;

    vm.prank(safetyModule.owner());
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    safetyModule.updateConfigs(updatedConfig_);
  }

  function invariant_finalizeUpdateConfigsSucceeds() public syncCurrentTimestamp(safetyModuleHandler) {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();

    vm.startPrank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);
    vm.stopPrank();
    vm.warp(safetyModule.lastConfigUpdate().configUpdateTime);

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      vm.startPrank(_randomAddress());
      safetyModule.finalizeUpdateConfigs(updatedConfig_);
      vm.stopPrank();

      // Delay config updates applied.
      Delays memory delays_ = safetyModule.delays();
      assertEq(delays_.configUpdateDelay, updatedConfig_.delaysConfig.configUpdateDelay);
      assertEq(delays_.configUpdateGracePeriod, updatedConfig_.delaysConfig.configUpdateGracePeriod);
      assertEq(delays_.withdrawDelay, updatedConfig_.delaysConfig.withdrawDelay);

      // Reserve pool config updates applied.
      for (uint8 i = 0; i < updatedConfig_.reservePoolConfigs.length; i++) {
        ReservePool memory reservePool_ = safetyModule.reservePools(i);
        _assertReservePoolUpdatesApplied(reservePool_, updatedConfig_.reservePoolConfigs[i]);
      }

      // Trigger config updates applied.
      for (uint8 i = 0; i < updatedConfig_.triggerConfigUpdates.length; i++) {
        Trigger memory triggerData_ = safetyModule.triggerData(updatedConfig_.triggerConfigUpdates[i].trigger);
        assertEq(triggerData_.exists, updatedConfig_.triggerConfigUpdates[i].exists);
        assertEq(triggerData_.payoutHandler, updatedConfig_.triggerConfigUpdates[i].payoutHandler);
      }

      // Last config update metadata updated.
      ConfigUpdateMetadata memory lastConfigUpdate_ = safetyModule.lastConfigUpdate();
      assertEq(lastConfigUpdate_.queuedConfigUpdateHash, bytes32(0));
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.startPrank(_randomAddress());
      safetyModule.finalizeUpdateConfigs(updatedConfig_);
      vm.stopPrank();
    }
  }

  function invariant_finalizeUpdateConfigsRevertsBeforeConfigUpdateTime()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();

    vm.startPrank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);
    vm.stopPrank();
    vm.warp(safetyModule.lastConfigUpdate().configUpdateTime - 1);

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      vm.expectRevert(ConfiguratorLib.InvalidTimestamp.selector);
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
    }

    vm.prank(_randomAddress());
    safetyModule.finalizeUpdateConfigs(updatedConfig_);
  }

  function invariant_finalizeUpdateConfigsRevertsAfterConfigUpdateDeadline()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();

    vm.startPrank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);
    vm.stopPrank();
    vm.warp(safetyModule.lastConfigUpdate().configUpdateDeadline + 1);

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      vm.expectRevert(ConfiguratorLib.InvalidTimestamp.selector);
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
    }

    vm.prank(_randomAddress());
    safetyModule.finalizeUpdateConfigs(updatedConfig_);
  }

  function invariant_finalizeUpdateConfigsRevertsQueuedConfigUpdateHashReservePoolConfigMismatch()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();

    vm.startPrank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);
    vm.stopPrank();
    vm.warp(safetyModule.lastConfigUpdate().configUpdateTime);

    UpdateConfigsCalldataParams memory incorrectConfig_ = updatedConfig_;
    ReservePoolConfig[] memory reservePoolConfigs_ = updatedConfig_.reservePoolConfigs;
    incorrectConfig_.reservePoolConfigs[_randomUint256() % reservePoolConfigs_.length].maxSlashPercentage += 1;

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
    }

    vm.prank(_randomAddress());
    safetyModule.finalizeUpdateConfigs(incorrectConfig_);
  }

  function invariant_finalizeUpdateConfigsRevertsQueuedConfigUpdateHashDelayConfigMismatch()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();

    vm.startPrank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);
    vm.stopPrank();
    vm.warp(safetyModule.lastConfigUpdate().configUpdateTime);

    UpdateConfigsCalldataParams memory incorrectConfig_ = updatedConfig_;
    incorrectConfig_.delaysConfig.configUpdateGracePeriod += 1;

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
    }

    vm.prank(_randomAddress());
    safetyModule.finalizeUpdateConfigs(incorrectConfig_);
  }

  function invariant_finalizeUpdateConfigsRevertsQueuedConfigUpdateHashTriggerConfigMismatch()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();

    vm.startPrank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);
    vm.stopPrank();
    vm.warp(safetyModule.lastConfigUpdate().configUpdateTime);

    UpdateConfigsCalldataParams memory incorrectConfig_ = updatedConfig_;
    TriggerConfig[] memory triggerConfigs_ = new TriggerConfig[](1);
    triggerConfigs_[0] = TriggerConfig({
      trigger: ITrigger(_randomAddress()),
      payoutHandler: _randomAddress(),
      exists: _randomUint8() % 2 == 0
    });
    incorrectConfig_.triggerConfigUpdates = triggerConfigs_;

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
    }

    vm.prank(_randomAddress());
    safetyModule.finalizeUpdateConfigs(incorrectConfig_);
  }

  function invariant_finalizeUpdateConfigsRevertsQueuedConfigUpdateTriggerAlreadyTriggered()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();
    if (updatedConfig_.triggerConfigUpdates.length == 0) return;

    vm.startPrank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);
    vm.stopPrank();
    vm.warp(safetyModule.lastConfigUpdate().configUpdateTime);

    TriggerConfig[] memory triggerConfigs_ = updatedConfig_.triggerConfigUpdates;
    MockTrigger(address(triggerConfigs_[_randomUint256() % triggerConfigs_.length].trigger)).mockState(
      TriggerState.TRIGGERED
    );

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
    }

    vm.prank(_randomAddress());
    safetyModule.finalizeUpdateConfigs(updatedConfig_);
  }

  function invariant_finalizeUpdateConfigsRevertsQueuedConfigUpdateTriggerAlreadyTriggeredSafetyModule()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Cannot update configs if the safety module is triggered.
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();

    TriggerConfig[] memory triggerConfigs_ = updatedConfig_.triggerConfigUpdates;
    uint256 untriggeredTriggerIndex_ = 0;
    for (untriggeredTriggerIndex_; untriggeredTriggerIndex_ < triggerConfigs_.length; untriggeredTriggerIndex_++) {
      TriggerConfig memory triggerConfig_ = triggerConfigs_[untriggeredTriggerIndex_];
      if (!safetyModule.triggerData(triggerConfig_.trigger).triggered) break;
    }
    if (untriggeredTriggerIndex_ == triggerConfigs_.length) return;

    vm.startPrank(safetyModule.owner());
    safetyModule.updateConfigs(updatedConfig_);
    vm.stopPrank();
    vm.warp(safetyModule.lastConfigUpdate().configUpdateTime);

    MockTrigger(address(triggerConfigs_[untriggeredTriggerIndex_].trigger)).mockState(TriggerState.TRIGGERED);
    safetyModule.trigger(triggerConfigs_[untriggeredTriggerIndex_].trigger);

    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) {
      vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
    }

    vm.prank(_randomAddress());
    safetyModule.finalizeUpdateConfigs(updatedConfig_);
  }

  function invariant_cannotQueueConfigUpdatesIfTriggered() public syncCurrentTimestamp(safetyModuleHandler) {
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      UpdateConfigsCalldataParams memory updatedConfig_ = _createValidConfigUpdate();
      vm.prank(safetyModule.owner());
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      safetyModule.updateConfigs(updatedConfig_);
    }
  }

  function invariant_queuedConfigUpdatesAreResetWhenSafetyModulePaused()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) return;

    vm.prank(safetyModule.owner());
    safetyModule.pause();

    ConfigUpdateMetadata memory lastConfigUpdate_ = safetyModule.lastConfigUpdate();
    require(
      lastConfigUpdate_.queuedConfigUpdateHash == bytes32(0),
      "Invariant Violated: Queued config update hash must be reset to zero when the SafetyModule transitions to paused from triggered."
    );
  }

  function _createValidConfigUpdate() internal view returns (UpdateConfigsCalldataParams memory) {
    UpdateConfigsCalldataParams memory currentConfig_ = _copyCurrentConfig();

    // Foundry invariant tests seem to revert at some random point into a run when you try to deploy new reserve deposit
    // receipt tokens or new triggers, so these tests do not add new reserve pools or triggers. Those cases are checked
    // in unit tests.
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](currentConfig_.reservePoolConfigs.length);
    for (uint8 i = 0; i < currentConfig_.reservePoolConfigs.length; i++) {
      // We cannot update the asset of the copied current config, since it will cause a revert.
      reservePoolConfigs_[i] = ReservePoolConfig({
        maxSlashPercentage: _randomUint256InRange(0, MathConstants.ZOC),
        asset: currentConfig_.reservePoolConfigs[i].asset
      });
    }

    TriggerConfig[] memory triggerConfigs_ = new TriggerConfig[](currentConfig_.triggerConfigUpdates.length);
    for (uint8 i = 0; i < currentConfig_.triggerConfigUpdates.length; i++) {
      triggerConfigs_[i] = TriggerConfig({
        trigger: currentConfig_.triggerConfigUpdates[i].trigger,
        payoutHandler: _randomAddress(),
        exists: _randomUint8() % 2 == 0
      });
    }

    return UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfigs_,
      delaysConfig: _generateValidDelays()
    });
  }

  function _copyCurrentConfig() internal view returns (UpdateConfigsCalldataParams memory) {
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](numReservePools);
    for (uint8 i = 0; i < numReservePools; i++) {
      ReservePool memory reservePool_ = safetyModule.reservePools(i);
      reservePoolConfigs_[i] =
        ReservePoolConfig({maxSlashPercentage: reservePool_.maxSlashPercentage, asset: reservePool_.asset});
    }

    ITrigger[] memory triggers_ = safetyModuleHandler.getTriggers();
    ITrigger[] memory triggeredTriggers_ = safetyModuleHandler.getTriggeredTriggers();
    TriggerConfig[] memory triggerConfigs_ = new TriggerConfig[](triggers_.length - triggeredTriggers_.length);
    uint8 untriggeredTriggersCount_ = 0;
    for (uint8 i = 0; i < triggers_.length; i++) {
      Trigger memory triggerData_ = safetyModule.triggerData(triggers_[i]);
      // We have to exclude triggered triggers from the config update since they cannot be updated and will cause a
      // revert.
      if (!triggerData_.triggered) {
        triggerConfigs_[untriggeredTriggersCount_] =
          TriggerConfig({trigger: triggers_[i], payoutHandler: triggerData_.payoutHandler, exists: triggerData_.exists});
        untriggeredTriggersCount_++;
      }
    }

    return UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfigs_,
      delaysConfig: safetyModule.delays()
    });
  }

  function _generateValidReservePoolConfig() internal view returns (ReservePoolConfig memory) {
    return ReservePoolConfig({
      maxSlashPercentage: _randomUint256InRange(0, MathConstants.ZOC),
      asset: assets[_randomUint8() % assets.length]
    });
  }

  function _generateValidTriggerConfig() internal returns (TriggerConfig memory) {
    return TriggerConfig({
      trigger: ITrigger(address(new MockTrigger(TriggerState.ACTIVE))),
      payoutHandler: _randomAddress(),
      exists: _randomUint8() % 2 == 0
    });
  }

  function _generateValidDelays() internal view returns (Delays memory) {
    uint64 withdrawDelay_ = _randomUint64();
    uint64 configUpdateGracePeriod_ = _randomUint64();
    uint64 configUpdateDelay_ = uint64(bound(_randomUint256(), withdrawDelay_, type(uint64).max));
    return Delays({
      withdrawDelay: withdrawDelay_,
      configUpdateDelay: configUpdateDelay_,
      configUpdateGracePeriod: configUpdateGracePeriod_
    });
  }

  function _assertReservePoolUpdatesApplied(
    ReservePool memory reservePool_,
    ReservePoolConfig memory reservePoolConfig_
  ) private {
    assertEq(address(reservePool_.asset), address(reservePoolConfig_.asset));
    assertEq(reservePool_.maxSlashPercentage, reservePoolConfig_.maxSlashPercentage);
  }
}

contract ConfiguratorInvariantsWithStateTransitionsSingleReservePool is
  ConfiguratorInvariantsWithStateTransitions,
  InvariantTestWithSingleReservePool
{}

contract ConfiguratorInvariantsWithStateTransitionsMultipleReservePools is
  ConfiguratorInvariantsWithStateTransitions,
  InvariantTestWithMultipleReservePools
{}
