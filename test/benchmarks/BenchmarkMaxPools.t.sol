// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {TriggerState} from "../../src/lib/SafetyModuleStates.sol";
import {UpdateConfigsCalldataParams, ReservePoolConfig} from "../../src/lib/structs/Configs.sol";
import {Delays} from "../../src/lib/structs/Delays.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {TriggerConfig} from "../../src/lib/structs/Trigger.sol";
import {Slash} from "../../src/lib/structs/Slash.sol";
import {SafetyModule} from "../../src/SafetyModule.sol";
import {IDripModel} from "../../src/interfaces/IDripModel.sol";
import {ITrigger} from "../../src/interfaces/ITrigger.sol";
import {ISafetyModule} from "../../src/interfaces/ISafetyModule.sol";
import {MockDeployProtocol} from "../utils/MockDeployProtocol.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {MockTrigger} from "../utils/MockTrigger.sol";
import {console2} from "forge-std/console2.sol";

abstract contract BenchmarkMaxPools is MockDeployProtocol {
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD
  uint256 internal constant DEFAULT_SKIP_DAYS = 10;
  Delays DEFAULT_DELAYS = Delays({withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

  SafetyModule safetyModule;
  MockTrigger trigger;
  uint16 numReserveAssets;
  address self = address(this);
  address payoutHandler = _randomAddress();

  function setUp() public virtual override {
    super.setUp();

    _createSafetyModule(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: _createReservePools(numReserveAssets),
        triggerConfigUpdates: _createTriggerConfig(),
        delaysConfig: DEFAULT_DELAYS
      })
    );

    _initializeReservePools();

    skip(DEFAULT_SKIP_DAYS);
  }

  function _createSafetyModule(UpdateConfigsCalldataParams memory updateConfigs_) internal {
    safetyModule = SafetyModule(address(manager.createSafetyModule(self, self, updateConfigs_, _randomBytes32())));
  }

  function _createReservePools(uint16 numPools) internal returns (ReservePoolConfig[] memory) {
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](numPools);
    for (uint256 i = 0; i < numPools; i++) {
      reservePoolConfigs_[i] = ReservePoolConfig({
        maxSlashPercentage: MathConstants.WAD,
        asset: IERC20(address(new MockERC20("Mock Reserve Asset", "cozyRes", 18)))
      });
    }
    return reservePoolConfigs_;
  }

  function _createTriggerConfig() internal returns (TriggerConfig[] memory) {
    trigger = new MockTrigger(TriggerState.ACTIVE);
    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({trigger: ITrigger(address(trigger)), payoutHandler: payoutHandler, exists: true});
    return triggerConfig_;
  }

  function _initializeReservePools() internal {
    for (uint16 i = 0; i < numReserveAssets; i++) {
      (, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture();
      _depositReserveAssets(i, reserveAssetAmount_, receiver_);
    }
  }

  function _randomSingleActionFixture() internal view returns (uint16, uint256, address) {
    return (_randomUint16() % numReserveAssets, _randomUint256() % 999_999_999_999_999, _randomAddress());
  }

  function _setUpDepositReserveAssets(uint16 reservePoolId_) internal {
    ReservePool memory reservePool_ = getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_);
    deal(address(reservePool_.asset), address(safetyModule), type(uint256).max);
  }

  function _depositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    _setUpDepositReserveAssets(reservePoolId_);
    safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function _setUpRedeem(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    internal
    returns (uint256 depositReceiptTokenAmount_)
  {
    _depositReserveAssets(reservePoolId_, reserveAssetAmount_, receiver_);

    depositReceiptTokenAmount_ = safetyModule.convertToReceiptTokenAmount(reservePoolId_, reserveAssetAmount_);
    vm.startPrank(receiver_);
    getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_).depositReceiptToken.approve(
      address(safetyModule), depositReceiptTokenAmount_
    );
    vm.stopPrank();
  }

  function _setUpConfigUpdate() internal returns (UpdateConfigsCalldataParams memory updateConfigs_) {
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](numReserveAssets + 1);

    for (uint256 i = 0; i < numReserveAssets + 1; i++) {
      IERC20 asset_ = i < numReserveAssets
        ? getReservePool(ISafetyModule(address(safetyModule)), i).asset
        : IERC20(address(new MockERC20("Mock Reserve Asset", "cozyRes", 18)));
      reservePoolConfigs_[i] = ReservePoolConfig({maxSlashPercentage: MathConstants.WAD / 2, asset: asset_});
    }

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](0);
    Delays memory delaysConfig_ = getDelays(ISafetyModule(address(safetyModule)));

    updateConfigs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delaysConfig_
    });
  }

  function test_createSafetyModule() public {
    UpdateConfigsCalldataParams memory updateConfigs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: _createReservePools(numReserveAssets),
      triggerConfigUpdates: _createTriggerConfig(),
      delaysConfig: DEFAULT_DELAYS
    });

    uint256 gasInitial_ = gasleft();
    _createSafetyModule(updateConfigs_);
    console2.log("Gas used for createSafetyModule: %s", gasInitial_ - gasleft());
  }

  function test_depositReserveAssets() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture();
    _setUpDepositReserveAssets(reservePoolId_);

    uint256 gasInitial_ = gasleft();
    safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
    console2.log("Gas used for depositReserveAssetsWithoutTransfer: %s", gasInitial_ - gasleft());
  }

  function test_redeem() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture();
    uint256 depositReceiptTokenAmount_ = _setUpRedeem(reservePoolId_, reserveAssetAmount_, receiver_);

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    safetyModule.redeem(reservePoolId_, depositReceiptTokenAmount_, receiver_, receiver_);
    console2.log("Gas used for redeem: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_completeRedemption() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture();
    uint256 depositReceiptTokenAmount_ = _setUpRedeem(reservePoolId_, reserveAssetAmount_, receiver_);

    vm.startPrank(receiver_);
    (uint64 redemptionId_,) = safetyModule.redeem(reservePoolId_, depositReceiptTokenAmount_, receiver_, receiver_);
    vm.stopPrank();

    (,, uint64 withdrawDelay_) = safetyModule.delays();
    skip(withdrawDelay_);

    uint256 gasInitial_ = gasleft();
    safetyModule.completeRedemption(redemptionId_);
    console2.log("Gas used for completeRedemption: %s", gasInitial_ - gasleft());
  }

  function test_pause() public {
    vm.startPrank(owner);
    uint256 gasInitial_ = gasleft();
    safetyModule.pause();
    console2.log("Gas used for pause: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_unpause() public {
    vm.startPrank(owner);
    safetyModule.pause();

    uint256 gasInitial_ = gasleft();
    safetyModule.unpause();
    console2.log("Gas used for unpause: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_trigger() public {
    trigger.mockState(TriggerState.TRIGGERED);

    uint256 gasInitial_ = gasleft();
    safetyModule.trigger(ITrigger(address(trigger)));
    console2.log("Gas used for trigger: %s", gasInitial_ - gasleft());
  }

  function test_slash() public {
    trigger.mockState(TriggerState.TRIGGERED);
    safetyModule.trigger(ITrigger(address(trigger)));
    Slash[] memory slashes_ = new Slash[](numReserveAssets);
    for (uint256 i = 0; i < numReserveAssets; i++) {
      slashes_[i] = Slash({reservePoolId: uint16(i), amount: 0});
    }

    vm.startPrank(payoutHandler);
    uint256 gasInitial_ = gasleft();
    safetyModule.slash(slashes_, _randomAddress());
    console2.log("Gas used for slash: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_dripFees() public {
    skip(_randomUint64());

    uint256 gasInitial_ = gasleft();
    safetyModule.dripFees();
    console2.log("Gas used for dripFees: %s", gasInitial_ - gasleft());
  }

  function test_updateConfigs() public {
    UpdateConfigsCalldataParams memory updateConfigs_ = _setUpConfigUpdate();

    vm.startPrank(owner);
    uint256 gasInitial_ = gasleft();
    safetyModule.updateConfigs(updateConfigs_);
    console2.log("Gas used for updateConfigs: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_finalizeUpdateConfigs() public {
    UpdateConfigsCalldataParams memory updateConfigs_ = _setUpConfigUpdate();

    vm.startPrank(owner);
    safetyModule.updateConfigs(updateConfigs_);
    vm.stopPrank();

    (uint64 configUpdateDelay_,,) = safetyModule.delays();
    skip(configUpdateDelay_);

    uint256 gasInitial_ = gasleft();
    safetyModule.finalizeUpdateConfigs(updateConfigs_);
    console2.log("Gas used for finalizeUpdateConfigs: %s", gasInitial_ - gasleft());
  }
}

contract BenchmarkMaxPools_30Reserve is BenchmarkMaxPools {
  function setUp() public override {
    numReserveAssets = 30;
    super.setUp();
  }
}
