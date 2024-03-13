// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {TimelockController} from "openzeppelin-contracts/contracts/governance/TimelockController.sol";
import {TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {UpdateConfigsCalldataParams, ReservePoolConfig} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {ReservePool} from "../src/lib/structs/Pools.sol";
import {TriggerConfig} from "../src/lib/structs/Trigger.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {IConfiguratorEvents} from "../src/interfaces/IConfiguratorEvents.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";

// TimelockController sanity tests.
contract TimelockControllerTest is MockDeployProtocol {
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD
  uint256 internal constant DEFAULT_SKIP_DAYS = 10;
  Delays DEFAULT_DELAYS = Delays({withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});
  uint256 TIMELOCK_DELAY = 3 days;

  SafetyModule safetyModule;
  MockTrigger trigger;
  uint8 numReserveAssets = 3;
  address self = address(this);
  address payoutHandler = _randomAddress();

  address[] proposers = [address(0xBEEF)];
  address[] executors = [address(0xC0FFEE), address(0xBEEF)];
  TimelockController timelock;

  function setUp() public virtual override {
    super.setUp();

    timelock = new TimelockController(TIMELOCK_DELAY, proposers, executors, address(0));

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](3);
    for (uint256 i = 0; i < 3; i++) {
      reservePoolConfigs_[i] = ReservePoolConfig({
        maxSlashPercentage: MathConstants.ZOC,
        asset: IERC20(address(new MockERC20("Mock Reserve Asset", "cozyRes", 18)))
      });
    }

    trigger = new MockTrigger(TriggerState.ACTIVE);
    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({trigger: ITrigger(address(trigger)), payoutHandler: payoutHandler, exists: true});

    safetyModule = SafetyModule(
      address(
        manager.createSafetyModule(
          address(timelock),
          self,
          UpdateConfigsCalldataParams({
            reservePoolConfigs: reservePoolConfigs_,
            triggerConfigUpdates: triggerConfig_,
            delaysConfig: DEFAULT_DELAYS
          }),
          _randomBytes32()
        )
      )
    );

    skip(DEFAULT_SKIP_DAYS);
  }

  function _setUpConfigUpdate() internal returns (UpdateConfigsCalldataParams memory updateConfigs_) {
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](numReserveAssets + 1);

    for (uint8 i = 0; i < numReserveAssets + 1; i++) {
      IERC20 asset_ = i < numReserveAssets
        ? getReservePool(ISafetyModule(address(safetyModule)), i).asset
        : IERC20(address(new MockERC20("Mock Reserve Asset", "cozyRes", 18)));
      reservePoolConfigs_[i] = ReservePoolConfig({maxSlashPercentage: MathConstants.ZOC / 2, asset: asset_});
    }

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](0);
    Delays memory delaysConfig_ = getDelays(ISafetyModule(address(safetyModule)));

    updateConfigs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delaysConfig_
    });
  }

  function test_updateConfigsThroughTimelock() public {
    UpdateConfigsCalldataParams memory updateConfigs_ = _setUpConfigUpdate();

    bytes32 salt_ = _randomBytes32();
    bytes memory payload_ = abi.encodeWithSelector(safetyModule.updateConfigs.selector, updateConfigs_);

    // Cannot schedule a change without the proposer's signature.
    vm.expectRevert();
    vm.prank(_randomAddress());
    timelock.schedule(address(safetyModule), 0, payload_, 0, salt_, TIMELOCK_DELAY);

    vm.prank(proposers[0]);
    timelock.schedule(address(safetyModule), 0, payload_, 0, salt_, TIMELOCK_DELAY);

    // Fast-forward an amount of time less than the delay specified.
    skip(bound(_randomUint256(), 0, TIMELOCK_DELAY - 1));

    // Unable to execute the change before the delay.
    vm.expectRevert();
    vm.prank(executors[0]);
    timelock.execute(address(safetyModule), 0, payload_, 0, salt_);

    // Fast-forward amount of time required.
    skip(TIMELOCK_DELAY);

    // Cannot execute the change without the executor's signature.
    vm.expectRevert();
    vm.prank(_randomAddress());
    timelock.execute(address(safetyModule), 0, payload_, 0, salt_);

    // The executor of the timelock is able to execute the changes after the delay.
    uint256 updateTime_ = block.timestamp + DEFAULT_DELAYS.configUpdateDelay;
    uint256 updateDeadline_ = updateTime_ + DEFAULT_DELAYS.configUpdateGracePeriod;
    _expectEmit();
    emit IConfiguratorEvents.ConfigUpdatesQueued(
      updateConfigs_.reservePoolConfigs,
      updateConfigs_.triggerConfigUpdates,
      updateConfigs_.delaysConfig,
      updateTime_,
      updateDeadline_
    );
    vm.prank(executors[0]);
    timelock.execute(address(safetyModule), 0, payload_, 0, salt_);
  }
}
