// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ReceiptToken} from "../src/ReceiptToken.sol";
import {ReceiptTokenFactory} from "../src/ReceiptTokenFactory.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {SafetyModuleFactory} from "../src/SafetyModuleFactory.sol";
import {StkToken} from "../src/StkToken.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {
  ReservePoolConfig, UndrippedRewardPoolConfig, UpdateConfigsCalldataParams
} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {ReservePool, UndrippedRewardPool} from "../src/lib/structs/Pools.sol";
import {TriggerConfig} from "../src/lib/structs/Trigger.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../src/interfaces/IReceiptTokenFactory.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";
import {TestBase} from "./utils/TestBase.sol";

contract SafetyModuleFactoryTest is TestBase {
  SafetyModule safetyModuleLogic;
  SafetyModuleFactory safetyModuleFactory;

  ReceiptToken depositTokenLogic;
  StkToken stkTokenLogic;
  IReceiptTokenFactory receiptTokenFactory;

  IManager mockManager = IManager(_randomAddress());

  function setUp() public {
    depositTokenLogic = new ReceiptToken();
    stkTokenLogic = new StkToken();

    depositTokenLogic.initialize(ISafetyModule(address(0)), "", "", 0);
    stkTokenLogic.initialize(ISafetyModule(address(0)), "", "", 0);

    receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(depositTokenLogic)), IReceiptToken(address(stkTokenLogic)));

    safetyModuleLogic = new SafetyModule(mockManager, receiptTokenFactory);
    safetyModuleLogic.initialize(
      address(0),
      address(0),
      UpdateConfigsCalldataParams({
        reservePoolConfigs: new ReservePoolConfig[](0),
        undrippedRewardPoolConfigs: new UndrippedRewardPoolConfig[](0),
        triggerConfigUpdates: new TriggerConfig[](0),
        delaysConfig: Delays({configUpdateDelay: 0, configUpdateGracePeriod: 0, unstakeDelay: 0, withdrawDelay: 0})
      })
    );

    safetyModuleFactory = new SafetyModuleFactory(mockManager, ISafetyModule(address(safetyModuleLogic)));
  }

  function test_deploySafetyModuleFactory() public {
    assertEq(address(safetyModuleFactory.cozyManager()), address(mockManager));
    assertEq(address(safetyModuleFactory.safetyModuleLogic()), address(safetyModuleLogic));
  }

  function test_RevertDeploySafetyModuleFactoryZeroAddressParams() public {
    vm.expectRevert(SafetyModuleFactory.InvalidAddress.selector);
    new SafetyModuleFactory(mockManager, ISafetyModule(address(0)));

    vm.expectRevert(SafetyModuleFactory.InvalidAddress.selector);
    new SafetyModuleFactory(IManager(address(0)), ISafetyModule(address(safetyModuleLogic)));

    vm.expectRevert(SafetyModuleFactory.InvalidAddress.selector);
    new SafetyModuleFactory(IManager(address(0)), ISafetyModule(address(0)));
  }

  function test_deploySafetyModule1() public {
    address owner_ = _randomAddress();
    address pauser_ = _randomAddress();
    IERC20 asset_ = IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6)));

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] =
      ReservePoolConfig({maxSlashPercentage: 0, asset: asset_, rewardsPoolsWeight: uint16(MathConstants.ZOC)});

    UndrippedRewardPoolConfig[] memory undrippedRewardPoolConfigs_ = new UndrippedRewardPoolConfig[](1);
    undrippedRewardPoolConfigs_[0] =
      UndrippedRewardPoolConfig({asset: asset_, dripModel: IDripModel(address(_randomAddress()))});

    Delays memory delaysConfig_ =
      Delays({unstakeDelay: 2 days, withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({
      trigger: ITrigger(address(new MockTrigger(TriggerState.ACTIVE))),
      payoutHandler: _randomAddress(),
      exists: true
    });

    UpdateConfigsCalldataParams memory configs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      undrippedRewardPoolConfigs: undrippedRewardPoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delaysConfig_
    });

    bytes32 baseSalt_ = _randomBytes32();

    address computedSafetyModuleAddress_ = safetyModuleFactory.computeAddress(baseSalt_);

    vm.prank(address(mockManager));
    ISafetyModule safetyModule_ = safetyModuleFactory.deploySafetyModule(owner_, pauser_, configs_, baseSalt_);
    assertEq(address(safetyModule_), computedSafetyModuleAddress_);
    assertEq(address(safetyModule_.cozyManager()), address(mockManager));
    assertEq(address(safetyModule_.receiptTokenFactory()), address(receiptTokenFactory));
    assertEq(address(safetyModule_.owner()), owner_);
    assertEq(address(safetyModule_.pauser()), pauser_);

    // Loosely validate config applied.
    ReservePool memory reservePool_ = getReservePool(safetyModule_, 0);
    assertEq(address(reservePool_.asset), address(asset_));
    assertEq(reservePool_.rewardsPoolsWeight, uint16(MathConstants.ZOC));

    UndrippedRewardPool memory undrippedRewardPool_ = getUndrippedRewardPool(safetyModule_, 0);
    assertEq(address(undrippedRewardPool_.asset), address(asset_));
    assertEq(address(undrippedRewardPool_.dripModel), address(undrippedRewardPoolConfigs_[0].dripModel));
  }
}
