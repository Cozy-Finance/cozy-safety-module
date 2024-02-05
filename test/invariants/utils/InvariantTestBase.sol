// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {SafetyModule} from "../../../src/SafetyModule.sol";
import {MathConstants} from "../../../src/lib/MathConstants.sol";
import {TriggerState} from "../../../src/lib/SafetyModuleStates.sol";
import {ReservePoolConfig, UpdateConfigsCalldataParams} from "../../../src/lib/structs/Configs.sol";
import {Delays} from "../../../src/lib/structs/Delays.sol";
import {TriggerConfig} from "../../../src/lib/structs/Trigger.sol";
import {IDripModel} from "../../../src/interfaces/IDripModel.sol";
import {IERC20} from "../../../src/interfaces/IERC20.sol";
import {ISafetyModule} from "../../../src/interfaces/ISafetyModule.sol";
import {ITrigger} from "../../../src/interfaces/ITrigger.sol";
import {SafetyModuleHandler} from "../handlers/SafetyModuleHandler.sol";
import {MockDeployer} from "../../utils/MockDeployProtocol.sol";
import {MockERC20} from "../../utils/MockERC20.sol";
import {MockTrigger} from "../../utils/MockTrigger.sol";
import {TestBase} from "../../utils/TestBase.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @dev Base contract for creating new SafetyModule deployment types for
/// invariant tests. Any new SafetyModule deployments should inherit from this,
/// not InvariantTestBase.
abstract contract InvariantBaseDeploy is TestBase, MockDeployer {
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD

  ISafetyModule public safetyModule;
  SafetyModuleHandler public safetyModuleHandler;

  Delays public delays = Delays({withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

  uint256 public numReservePools;
  ITrigger[] public triggers;
  IERC20[] public assets;

  function _initSafetyModule() internal virtual;
}

/// @dev Base contract for creating new invariant test suites.
/// If necessary, child contracts should override _fuzzedSelectors
/// and _initHandler to set custom handlers and selectors.
abstract contract InvariantTestBase is InvariantBaseDeploy {
  function setUp() public {
    deployMockProtocol();

    _initSafetyModule();
    _initHandler();
  }

  function _fuzzedSelectors() internal pure virtual returns (bytes4[] memory) {
    bytes4[] memory selectors = new bytes4[](11);
    selectors[0] = SafetyModuleHandler.depositReserveAssets.selector;
    selectors[1] = SafetyModuleHandler.depositReserveAssetsWithExistingActor.selector;
    selectors[2] = SafetyModuleHandler.depositReserveAssetsWithoutTransfer.selector;
    selectors[3] = SafetyModuleHandler.depositReserveAssetsWithoutTransferWithExistingActor.selector;
    selectors[4] = SafetyModuleHandler.redeem.selector;
    selectors[5] = SafetyModuleHandler.completeRedemption.selector;
    selectors[6] = SafetyModuleHandler.dripFees.selector;
    selectors[7] = SafetyModuleHandler.pause.selector;
    selectors[8] = SafetyModuleHandler.unpause.selector;
    selectors[9] = SafetyModuleHandler.trigger.selector;
    selectors[10] = SafetyModuleHandler.slash.selector;
    return selectors;
  }

  function _initHandler() internal {
    safetyModuleHandler = new SafetyModuleHandler(manager, safetyModule, numReservePools, triggers, block.timestamp);
    targetSelector(FuzzSelector({addr: address(safetyModuleHandler), selectors: _fuzzedSelectors()}));
    targetContract(address(safetyModuleHandler));
  }

  modifier syncCurrentTimestamp(SafetyModuleHandler safetyModuleHandler_) {
    vm.warp(safetyModuleHandler.currentTimestamp());
    _;
  }

  /// @dev Some invariant tests might modify the safety module to put pools in a temporarily terminal state
  /// (like triggering a safety module), thus we might want to only run some invariants with some probability.
  modifier randomlyCall(uint256 callPercentageZoc_) {
    if (_randomUint256InRange(0, MathConstants.ZOC) >= callPercentageZoc_) return;
    _;
  }

  function invariant_callSummary() public view {
    safetyModuleHandler.callSummary();
  }
}

abstract contract InvariantTestWithSingleReservePool is InvariantBaseDeploy {
  function _initSafetyModule() internal override {
    IERC20 asset_ = IERC20(address(new MockERC20("Mock Asset", "MOCK", 6)));
    assets.push(asset_);

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = ReservePoolConfig({maxSlashPercentage: 0.5e18, asset: asset_});

    triggers.push(ITrigger(address(new MockTrigger(TriggerState.ACTIVE))));

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({trigger: triggers[0], payoutHandler: _randomAddress(), exists: true});

    UpdateConfigsCalldataParams memory configs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delays
    });

    numReservePools = reservePoolConfigs_.length;
    safetyModule = manager.createSafetyModule(owner, pauser, configs_, _randomBytes32());

    vm.label(address(getReservePool(safetyModule, 0).depositReceiptToken), "reservePool0DepositReceiptToken");
  }
}

abstract contract InvariantTestWithMultipleReservePools is InvariantBaseDeploy {
  uint16 internal constant MAX_RESERVE_POOLS = 10;

  function _initSafetyModule() internal override {
    uint256 numReservePools_ = _randomUint256InRange(1, MAX_RESERVE_POOLS);

    // Create some unique assets to use for the pools. We want to make sure the invariant tests cover the case where the
    // same asset is used for multiple reserve pools.
    uint256 uniqueNumAssets_ = _randomUint256InRange(1, numReservePools_);
    for (uint256 i_; i_ < uniqueNumAssets_; i_++) {
      assets.push(IERC20(address(new MockERC20("Mock Asset", "MOCK", 6))));
    }

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](numReservePools_);
    for (uint256 i_; i_ < numReservePools_; i_++) {
      reservePoolConfigs_[i_] = ReservePoolConfig({
        maxSlashPercentage: _randomUint256InRange(1, MathConstants.WAD),
        asset: assets[_randomUint256InRange(0, uniqueNumAssets_ - 1)]
      });
    }

    triggers.push(ITrigger(address(new MockTrigger(TriggerState.ACTIVE))));

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({trigger: triggers[0], payoutHandler: _randomAddress(), exists: true});

    UpdateConfigsCalldataParams memory configs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delays
    });

    numReservePools = reservePoolConfigs_.length;
    safetyModule = manager.createSafetyModule(owner, pauser, configs_, _randomBytes32());

    for (uint256 i_; i_ < numReservePools_; i_++) {
      vm.label(
        address(getReservePool(safetyModule, i_).depositReceiptToken),
        string.concat("reservePool", Strings.toString(i_), "DepositReceiptToken")
      );
    }
  }
}
