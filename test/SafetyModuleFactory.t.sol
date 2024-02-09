// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {SafetyModuleFactory} from "../src/SafetyModuleFactory.sol";
import {TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {ReservePoolConfig, UpdateConfigsCalldataParams} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {ReservePool} from "../src/lib/structs/Pools.sol";
import {TriggerConfig} from "../src/lib/structs/Trigger.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ICozySafetyModuleManager} from "../src/interfaces/ICozySafetyModuleManager.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";
import {TestBase} from "./utils/TestBase.sol";

contract SafetyModuleFactoryTest is TestBase {
  SafetyModule safetyModuleLogic;
  SafetyModuleFactory safetyModuleFactory;

  ReceiptToken depositReceiptTokenLogic;
  ReceiptToken stkReceiptTokenLogic;
  IReceiptTokenFactory receiptTokenFactory;

  ICozySafetyModuleManager mockManager = ICozySafetyModuleManager(_randomAddress());

  /// @dev Emitted when a new Safety Module is deployed.
  event SafetyModuleDeployed(ISafetyModule safetyModule);

  function setUp() public {
    depositReceiptTokenLogic = new ReceiptToken();
    stkReceiptTokenLogic = new ReceiptToken();

    depositReceiptTokenLogic.initialize(address(0), "", "", 0);
    stkReceiptTokenLogic.initialize(address(0), "", "", 0);

    receiptTokenFactory = new ReceiptTokenFactory(
      IReceiptToken(address(depositReceiptTokenLogic)), IReceiptToken(address(stkReceiptTokenLogic))
    );

    safetyModuleLogic = new SafetyModule(mockManager, receiptTokenFactory);
    safetyModuleLogic.initialize(
      address(0),
      address(0),
      UpdateConfigsCalldataParams({
        reservePoolConfigs: new ReservePoolConfig[](0),
        triggerConfigUpdates: new TriggerConfig[](0),
        delaysConfig: Delays({configUpdateDelay: 0, configUpdateGracePeriod: 0, withdrawDelay: 0})
      })
    );

    safetyModuleFactory = new SafetyModuleFactory(mockManager, ISafetyModule(address(safetyModuleLogic)));
  }

  function test_deploySafetyModuleFactory() public {
    assertEq(address(safetyModuleFactory.cozySafetyModuleManager()), address(mockManager));
    assertEq(address(safetyModuleFactory.safetyModuleLogic()), address(safetyModuleLogic));
  }

  function test_RevertDeploySafetyModuleFactoryZeroAddressParams() public {
    vm.expectRevert(SafetyModuleFactory.InvalidAddress.selector);
    new SafetyModuleFactory(mockManager, ISafetyModule(address(0)));

    vm.expectRevert(SafetyModuleFactory.InvalidAddress.selector);
    new SafetyModuleFactory(ICozySafetyModuleManager(address(0)), ISafetyModule(address(safetyModuleLogic)));

    vm.expectRevert(SafetyModuleFactory.InvalidAddress.selector);
    new SafetyModuleFactory(ICozySafetyModuleManager(address(0)), ISafetyModule(address(0)));
  }

  function test_deploySafetyModule() public {
    address owner_ = _randomAddress();
    address pauser_ = _randomAddress();
    IERC20 asset_ = IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6)));

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = ReservePoolConfig({maxSlashPercentage: 0, asset: asset_});

    Delays memory delaysConfig_ =
      Delays({withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({
      trigger: ITrigger(address(new MockTrigger(TriggerState.ACTIVE))),
      payoutHandler: _randomAddress(),
      exists: true
    });

    UpdateConfigsCalldataParams memory configs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delaysConfig_
    });

    bytes32 baseSalt_ = _randomBytes32();

    address computedSafetyModuleAddress_ = safetyModuleFactory.computeAddress(baseSalt_);

    _expectEmit();
    emit SafetyModuleDeployed(ISafetyModule(computedSafetyModuleAddress_));
    vm.prank(address(mockManager));
    ISafetyModule safetyModule_ = safetyModuleFactory.deploySafetyModule(owner_, pauser_, configs_, baseSalt_);
    assertEq(address(safetyModule_), computedSafetyModuleAddress_);
    assertEq(address(safetyModule_.cozySafetyModuleManager()), address(mockManager));
    assertEq(address(safetyModule_.receiptTokenFactory()), address(receiptTokenFactory));
    assertEq(address(safetyModule_.owner()), owner_);
    assertEq(address(safetyModule_.pauser()), pauser_);

    // Loosely validate config applied.
    ReservePool memory reservePool_ = getReservePool(safetyModule_, 0);
    assertEq(address(reservePool_.asset), address(asset_));

    // Cannot call initialize again on the safety module.
    vm.expectRevert(SafetyModule.Initialized.selector);
    safetyModule_.initialize(owner_, pauser_, configs_);
  }

  function test_revertDeploySafetyModuleNotManager() public {
    address caller_ = _randomAddress();

    address owner_ = _randomAddress();
    address pauser_ = _randomAddress();
    IERC20 asset_ = IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6)));

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = ReservePoolConfig({maxSlashPercentage: 0, asset: asset_});

    Delays memory delaysConfig_ =
      Delays({withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({
      trigger: ITrigger(address(new MockTrigger(TriggerState.ACTIVE))),
      payoutHandler: _randomAddress(),
      exists: true
    });

    UpdateConfigsCalldataParams memory configs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delaysConfig_
    });

    bytes32 baseSalt_ = _randomBytes32();

    vm.expectRevert(SafetyModuleFactory.Unauthorized.selector);
    vm.prank(caller_);
    safetyModuleFactory.deploySafetyModule(owner_, pauser_, configs_, baseSalt_);
  }
}
