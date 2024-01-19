// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {SafetyModule} from "../../../src/SafetyModule.sol";
import {MathConstants} from "../../../src/lib/MathConstants.sol";
import {TriggerState} from "../../../src/lib/SafetyModuleStates.sol";
import {
  ReservePoolConfig,
  UndrippedRewardPoolConfig,
  UpdateConfigsCalldataParams
} from "../../../src/lib/structs/Configs.sol";
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

/// @dev Base contract for creating new SafetyModule deployment types for
/// invariant tests. Any new SafetyModule deployments should inherit from this,
/// not InvariantTestBase.
abstract contract InvariantBaseDeploy is TestBase, MockDeployer {
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD

  ISafetyModule public safetyModule;
  SafetyModuleHandler public safetyModuleHandler;

  IERC20 public asset = IERC20(address(new MockERC20("Mock Asset", "MOCK", 6)));

  // Deploy with some sane params for default models.
  IDripModel public dripDecayModel = IDripModel(address(new DripModelExponential(9_116_094_774)));

  Delays public delays =
    Delays({unstakeDelay: 2 days, withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

  uint256 public numReservePools;
  uint256 public numRewardPools;
  ITrigger[] public triggers;

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
    bytes4[] memory selectors = new bytes4[](20);
    selectors[0] = SafetyModuleHandler.depositReserveAssets.selector;
    selectors[1] = SafetyModuleHandler.depositReserveAssetsWithExistingActor.selector;
    selectors[2] = SafetyModuleHandler.depositReserveAssetsWithoutTransfer.selector;
    selectors[3] = SafetyModuleHandler.depositReserveAssetsWithoutTransferWithExistingActor.selector;
    selectors[4] = SafetyModuleHandler.depositRewardAssets.selector;
    selectors[5] = SafetyModuleHandler.depositRewardAssetsWithExistingActor.selector;
    selectors[6] = SafetyModuleHandler.depositRewardAssetsWithoutTransfer.selector;
    selectors[7] = SafetyModuleHandler.depositRewardAssetsWithoutTransferWithExistingActor.selector;
    selectors[8] = SafetyModuleHandler.stake.selector;
    selectors[9] = SafetyModuleHandler.stakeWithExistingActor.selector;
    selectors[10] = SafetyModuleHandler.stakeWithoutTransfer.selector;
    selectors[11] = SafetyModuleHandler.stakeWithoutTransferWithExistingActor.selector;
    selectors[12] = SafetyModuleHandler.redeem.selector;
    selectors[13] = SafetyModuleHandler.unstake.selector;
    selectors[14] = SafetyModuleHandler.claimRewards.selector;
    selectors[15] = SafetyModuleHandler.completeRedemption.selector;
    selectors[16] = SafetyModuleHandler.dripFees.selector;
    selectors[17] = SafetyModuleHandler.pause.selector;
    selectors[18] = SafetyModuleHandler.unpause.selector;
    selectors[19] = SafetyModuleHandler.trigger.selector;
    // TODO: This causes tests to fail - something missing from/in redeemUndrippedRewards potentially causing issues.
    // selectors[17] = SafetyModuleHandler.redeemUndrippedRewards.selector;
    return selectors;
  }

  function _initHandler() internal {
    safetyModuleHandler =
      new SafetyModuleHandler(manager, safetyModule, asset, numReservePools, numRewardPools, triggers, block.timestamp);
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

  function _simulateSetTransfer(uint256 amount_) internal {
    deal(address(asset), address(safetyModuleHandler), asset.balanceOf(address(safetyModuleHandler)) + amount_, true);
  }

  function invariant_callSummary() public view {
    safetyModuleHandler.callSummary();
  }
}

abstract contract InvariantTestWithSingleReservePoolAndSingleRewardPool is InvariantBaseDeploy {
  function _initSafetyModule() internal override {
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] =
      ReservePoolConfig({maxSlashPercentage: 0, asset: asset, rewardsPoolsWeight: uint16(MathConstants.ZOC)});

    UndrippedRewardPoolConfig[] memory undrippedRewardPoolConfigs_ = new UndrippedRewardPoolConfig[](1);
    undrippedRewardPoolConfigs_[0] = UndrippedRewardPoolConfig({asset: asset, dripModel: dripDecayModel});

    triggers.push(ITrigger(address(new MockTrigger(TriggerState.ACTIVE))));

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({trigger: triggers[0], payoutHandler: _randomAddress(), exists: true});

    UpdateConfigsCalldataParams memory configs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      undrippedRewardPoolConfigs: undrippedRewardPoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delays
    });

    numReservePools = reservePoolConfigs_.length;
    numRewardPools = undrippedRewardPoolConfigs_.length;
    safetyModule = manager.createSafetyModule(owner, pauser, configs_, _randomBytes32());

    vm.label(address(getReservePool(safetyModule, 0).depositToken), "reservePoolADepositToken");
    vm.label(address(getReservePool(safetyModule, 0).stkToken), "reservePoolAStkToken");
    vm.label(address(getUndrippedRewardPool(safetyModule, 0).depositToken), "rewardPoolADepositToken");
  }
}
