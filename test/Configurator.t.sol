// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "../src/interfaces/IERC20.sol";
import {ICommonErrors} from "../src/interfaces/ICommonErrors.sol";
import {IConfiguratorErrors} from "../src/interfaces/IConfiguratorErrors.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {IConfiguratorEvents} from "../src/interfaces/IConfiguratorEvents.sol";
import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../src/interfaces/IReceiptTokenFactory.sol";
import {IManager} from "../src/interfaces/IManager.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {Ownable} from "../src/lib/Ownable.sol";
import {ConfiguratorLib} from "../src/lib/ConfiguratorLib.sol";
import {Configurator} from "../src/lib/Configurator.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {SafetyModuleState, TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {ReceiptToken} from "../src/ReceiptToken.sol";
import {ReceiptTokenFactory} from "../src/ReceiptTokenFactory.sol";
import {SafetyModuleBaseStorage} from "../src/lib/SafetyModuleBaseStorage.sol";
import {ReservePool, RewardPool, AssetPool, IdLookup} from "../src/lib/structs/Pools.sol";
import {
  ReservePoolConfig,
  RewardPoolConfig,
  ConfigUpdateMetadata,
  UpdateConfigsCalldataParams
} from "../src/lib/structs/Configs.sol";
import {UserRewardsData, ClaimableRewardsData} from "../src/lib/structs/Rewards.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {TriggerConfig, Trigger} from "../src/lib/structs/Trigger.sol";
import {MockManager} from "./utils/MockManager.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";
import "../src/lib/Stub.sol";

contract ConfiguratorUnitTest is TestBase, IConfiguratorEvents {
  TestableConfigurator component;
  ReservePool reservePool1;
  ReservePool reservePool2;
  RewardPool rewardPool1;
  RewardPool rewardPool2;

  MockManager mockManager = new MockManager();

  uint64 constant DEFAULT_CONFIG_UPDATE_DELAY = 10 days;
  uint64 constant DEFAULT_CONFIG_UPDATE_GRACE_PERIOD = 5 days;

  function setUp() public {
    mockManager.initGovernable(address(0xBEEF), address(0xABCD));
    mockManager.setAllowedReservePools(30);
    mockManager.setAllowedRewardPools(25);

    ReceiptToken receiptTokenLogic_ = new ReceiptToken();
    receiptTokenLogic_.initialize(ISafetyModule(address(0)), "", "", 0);
    ReceiptTokenFactory receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(receiptTokenLogic_)), IReceiptToken(address(receiptTokenLogic_)));

    component = new TestableConfigurator(address(this), IManager(address(mockManager)), receiptTokenFactory);

    component.mockSetDelays(
      Delays({
        unstakeDelay: 1 days,
        withdrawDelay: 1 days,
        configUpdateDelay: DEFAULT_CONFIG_UPDATE_DELAY,
        configUpdateGracePeriod: DEFAULT_CONFIG_UPDATE_GRACE_PERIOD
      })
    );

    reservePool1 = ReservePool({
      asset: IERC20(_randomAddress()),
      stkToken: IReceiptToken(_randomAddress()),
      depositToken: IReceiptToken(_randomAddress()),
      stakeAmount: _randomUint256(),
      depositAmount: _randomUint256(),
      pendingUnstakesAmount: _randomUint256(),
      pendingWithdrawalsAmount: _randomUint256(),
      feeAmount: _randomUint256(),
      rewardsPoolsWeight: uint16(MathConstants.ZOC) / 2,
      maxSlashPercentage: 0.5e18,
      lastFeesDripTime: uint128(block.timestamp)
    });
    reservePool2 = ReservePool({
      asset: IERC20(_randomAddress()),
      stkToken: IReceiptToken(_randomAddress()),
      depositToken: IReceiptToken(_randomAddress()),
      stakeAmount: _randomUint256(),
      depositAmount: _randomUint256(),
      pendingUnstakesAmount: _randomUint256(),
      pendingWithdrawalsAmount: _randomUint256(),
      feeAmount: _randomUint256(),
      rewardsPoolsWeight: uint16(MathConstants.ZOC) / 2,
      maxSlashPercentage: MathConstants.WAD,
      lastFeesDripTime: uint128(block.timestamp)
    });

    rewardPool1 = RewardPool({
      asset: IERC20(_randomAddress()),
      dripModel: IDripModel(_randomAddress()),
      depositToken: IReceiptToken(_randomAddress()),
      undrippedRewards: _randomUint256(),
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });
    rewardPool2 = RewardPool({
      asset: IERC20(_randomAddress()),
      dripModel: IDripModel(_randomAddress()),
      depositToken: IReceiptToken(_randomAddress()),
      undrippedRewards: _randomUint256(),
      cumulativeDrippedRewards: 0,
      lastDripTime: uint128(block.timestamp)
    });
  }

  function _generateValidReservePoolConfig(uint16 weight_, uint256 maxSlashPercentage_)
    private
    returns (ReservePoolConfig memory)
  {
    return ReservePoolConfig({
      asset: IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6))),
      rewardsPoolsWeight: weight_,
      maxSlashPercentage: maxSlashPercentage_
    });
  }

  function _generateValidRewardPoolConfig() private returns (RewardPoolConfig memory) {
    return RewardPoolConfig({
      asset: IERC20(address(new MockERC20("Mock Asset", "cozyMock", 6))),
      dripModel: IDripModel(_randomAddress())
    });
  }

  function _generateValidDelays() private view returns (Delays memory) {
    uint64 unstakeDelay_ = _randomUint64();
    uint64 withdrawDelay_ = _randomUint64();
    uint64 configUpdateGracePeriod_ = _randomUint64();
    uint64 configUpdateDelay_ =
      uint64(bound(_randomUint256(), unstakeDelay_ > withdrawDelay_ ? unstakeDelay_ : withdrawDelay_, type(uint64).max));
    return Delays({
      unstakeDelay: unstakeDelay_,
      withdrawDelay: withdrawDelay_,
      configUpdateDelay: configUpdateDelay_,
      configUpdateGracePeriod: configUpdateGracePeriod_
    });
  }

  function _generateValidTriggerConfig() private returns (TriggerConfig memory) {
    return TriggerConfig({
      trigger: ITrigger(address(new MockTrigger(TriggerState.ACTIVE))),
      payoutHandler: _randomAddress(),
      exists: _randomUint256() % 2 == 0
    });
  }

  function _generateBasicConfigs()
    private
    returns (ReservePoolConfig[] memory, RewardPoolConfig[] memory, TriggerConfig[] memory, Delays memory)
  {
    Delays memory delayConfig_ = _generateValidDelays();
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC), 0.5e18);
    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](1);
    triggerConfigUpdates_[0] = _generateValidTriggerConfig();
    return (reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
  }

  function _getConfigUpdateMetadata(
    ReservePoolConfig[] memory reservePoolConfigs_,
    RewardPoolConfig[] memory rewardPoolConfigs_,
    TriggerConfig[] memory triggerConfigUpdates_,
    Delays memory delaysConfig_
  ) private view returns (ConfigUpdateMetadata memory) {
    uint64 now_ = uint64(block.timestamp);
    uint64 configUpdateTime_ = now_ + DEFAULT_CONFIG_UPDATE_DELAY;
    uint64 configUpdateDeadline_ = configUpdateTime_ + DEFAULT_CONFIG_UPDATE_GRACE_PERIOD;
    return ConfigUpdateMetadata({
      queuedConfigUpdateHash: keccak256(
        abi.encode(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delaysConfig_)
        ),
      configUpdateTime: configUpdateTime_,
      configUpdateDeadline: configUpdateDeadline_
    });
  }

  function _assertReservePoolUpdatesApplied(
    ReservePool memory reservePool_,
    ReservePoolConfig memory reservePoolConfig_
  ) private {
    assertEq(address(reservePool_.asset), address(reservePoolConfig_.asset));
    assertEq(reservePool_.rewardsPoolsWeight, reservePoolConfig_.rewardsPoolsWeight);
    assertEq(reservePool_.maxSlashPercentage, reservePoolConfig_.maxSlashPercentage);
  }

  function _assertRewardPoolUpdatesApplied(RewardPool memory rewardPool_, RewardPoolConfig memory rewardPoolConfig_)
    private
  {
    assertEq(address(rewardPool_.asset), address(rewardPoolConfig_.asset));
    assertEq(address(rewardPool_.dripModel), address(rewardPoolConfig_.dripModel));
  }

  function test_updateConfigs() external {
    Delays memory delaysConfig_ = _generateValidDelays();
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](2);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[1] = _generateValidRewardPoolConfig();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    reservePoolConfigs_[1] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](2);
    triggerConfigUpdates_[0] = _generateValidTriggerConfig();
    triggerConfigUpdates_[1] = _generateValidTriggerConfig();
    uint256 now_ = block.timestamp;

    _expectEmit();
    emit ConfigUpdatesQueued(
      reservePoolConfigs_,
      rewardPoolConfigs_,
      triggerConfigUpdates_,
      delaysConfig_,
      now_ + DEFAULT_CONFIG_UPDATE_DELAY,
      now_ + DEFAULT_CONFIG_UPDATE_DELAY + DEFAULT_CONFIG_UPDATE_GRACE_PERIOD
    );
    component.updateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delaysConfig_
      })
    );

    ConfigUpdateMetadata memory result_ = component.getLastConfigUpdate();
    assertEq(
      result_.queuedConfigUpdateHash,
      keccak256(abi.encode(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delaysConfig_))
    );
    assertEq(result_.configUpdateTime, now_ + DEFAULT_CONFIG_UPDATE_DELAY);
    assertEq(result_.configUpdateDeadline, now_ + DEFAULT_CONFIG_UPDATE_DELAY + DEFAULT_CONFIG_UPDATE_GRACE_PERIOD);
  }

  function test_updateConfigs_revertNonOwner() external {
    Delays memory delaysConfig_ = _generateValidDelays();
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC), MathConstants.WAD);
    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](1);
    triggerConfigUpdates_[0] = _generateValidTriggerConfig();

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    component.updateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delaysConfig_
      })
    );
  }

  function test_isValidConfiguration_TrueValidConfig() external {
    Delays memory delayConfig_ = _generateValidDelays();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    reservePoolConfigs_[1] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](0);

    assertTrue(component.isValidConfiguration(reservePoolConfigs_, rewardPoolConfigs_, delayConfig_));
  }

  function test_isValidConfiguration_FalseInvalidWeightSum() external {
    Delays memory delayConfig_ = _generateValidDelays();

    uint16 weightA_ = _randomUint16();
    uint16 weightB_ = uint16(bound(_randomUint16(), 0, type(uint16).max - weightA_));

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(weightA_, MathConstants.WAD);
    reservePoolConfigs_[1] = _generateValidReservePoolConfig(weightB_, MathConstants.WAD);
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](0);

    assertFalse(component.isValidConfiguration(reservePoolConfigs_, rewardPoolConfigs_, delayConfig_));
  }

  function test_isValidConfiguration_FalseTooManyReservePools() external {
    Delays memory delayConfig_ = _generateValidDelays();

    mockManager.setAllowedReservePools(1);

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    reservePoolConfigs_[1] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](0);

    assertFalse(component.isValidConfiguration(reservePoolConfigs_, rewardPoolConfigs_, delayConfig_));
  }

  function test_isValidConfiguration_FalseTooManyRewardPools() external {
    Delays memory delayConfig_ = _generateValidDelays();

    mockManager.setAllowedRewardPools(1);

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](0);
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](2);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[1] = _generateValidRewardPoolConfig();

    assertFalse(component.isValidConfiguration(reservePoolConfigs_, rewardPoolConfigs_, delayConfig_));
  }

  function test_isValidConfiguration_FalseInvalidConfigUpdateDelay() external {
    Delays memory delayConfig_ = _generateValidDelays();
    delayConfig_.configUpdateDelay = uint64(
      bound(
        _randomUint256(),
        0,
        delayConfig_.unstakeDelay > delayConfig_.withdrawDelay ? delayConfig_.unstakeDelay : delayConfig_.withdrawDelay
      )
    );

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    reservePoolConfigs_[1] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](0);

    assertFalse(component.isValidConfiguration(reservePoolConfigs_, rewardPoolConfigs_, delayConfig_));
  }

  function test_isValidConfiguration_FalseInvalidMaxSlashPercentage() external {
    Delays memory delayConfig_ = _generateValidDelays();

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    ReservePoolConfig memory reservePoolConfig2_ =
      _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    reservePoolConfig2_.maxSlashPercentage = MathConstants.WAD + 1;
    reservePoolConfigs_[1] = reservePoolConfig2_;
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](0);

    assertFalse(component.isValidConfiguration(reservePoolConfigs_, rewardPoolConfigs_, delayConfig_));
  }

  function test_isValidUpdate_IsValidConfiguration() external {
    Delays memory delayConfig_ = _generateValidDelays();

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    reservePoolConfigs_[1] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](2);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[1] = _generateValidRewardPoolConfig();

    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](2);
    triggerConfigUpdates_[0] = _generateValidTriggerConfig();
    triggerConfigUpdates_[1] = _generateValidTriggerConfig();

    assertTrue(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: reservePoolConfigs_,
          rewardPoolConfigs: rewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );

    reservePoolConfigs_[0].rewardsPoolsWeight = 1e4 - 1; // Weight should equal 100%, simulate isValidConfiguration
      // returning false.
    assertFalse(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: reservePoolConfigs_,
          rewardPoolConfigs: rewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );
  }

  function test_isValidUpdate_ExistingReservePoolsChecks() external {
    // Add two existing reserve pools.
    component.mockAddReservePool(reservePool1);
    component.mockAddReservePool(reservePool2);

    // Two possible reserve pool configs.
    ReservePoolConfig memory reservePoolConfig1_ = ReservePoolConfig({
      asset: reservePool1.asset,
      rewardsPoolsWeight: uint16(MathConstants.ZOC),
      maxSlashPercentage: MathConstants.WAD
    });
    ReservePoolConfig memory reservePoolConfig2_ =
      ReservePoolConfig({asset: reservePool2.asset, rewardsPoolsWeight: 0, maxSlashPercentage: MathConstants.WAD});

    // Generate valid new configs for delays and reward pools.
    Delays memory delayConfig_ = _generateValidDelays();
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();

    // Generate valid new configs for triggers.
    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](1);
    triggerConfigUpdates_[0] = _generateValidTriggerConfig();

    // Invalid update because `invalidReservePoolConfigs_.length < numExistingReservePools`.
    ReservePoolConfig[] memory invalidReservePoolConfigs_ = new ReservePoolConfig[](1);
    invalidReservePoolConfigs_[0] = reservePoolConfig1_;
    assertFalse(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: invalidReservePoolConfigs_,
          rewardPoolConfigs: rewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );

    // Invalid update because `reservePool2.address != invalidReservePoolConfigs_[1].address`.
    invalidReservePoolConfigs_ = new ReservePoolConfig[](2);
    invalidReservePoolConfigs_[0] = reservePoolConfig1_;
    invalidReservePoolConfigs_[1] =
      ReservePoolConfig({asset: IERC20(_randomAddress()), rewardsPoolsWeight: 0, maxSlashPercentage: MathConstants.WAD});
    assertFalse(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: invalidReservePoolConfigs_,
          rewardPoolConfigs: rewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );

    // Valid update.
    ReservePoolConfig[] memory validReservePoolConfigs_ = new ReservePoolConfig[](3);
    validReservePoolConfigs_[0] = reservePoolConfig1_;
    validReservePoolConfigs_[1] = reservePoolConfig2_;
    validReservePoolConfigs_[2] = _generateValidReservePoolConfig(0, MathConstants.WAD);
    assertTrue(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: validReservePoolConfigs_,
          rewardPoolConfigs: rewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );
  }

  function test_isValidUpdate_ExistingRewardPoolsChecks() external {
    // Add two existing ls.
    component.mockAddRewardPool(rewardPool1);
    component.mockAddRewardPool(rewardPool2);

    // Two possible l configs.
    RewardPoolConfig memory rewardPoolConfig1_ =
      RewardPoolConfig({asset: rewardPool1.asset, dripModel: IDripModel(_randomAddress())});
    RewardPoolConfig memory rewardPoolConfig2_ =
      RewardPoolConfig({asset: rewardPool2.asset, dripModel: IDripModel(_randomAddress())});

    // Generate valid new configs for delays and reserve pools.
    Delays memory delayConfig_ = _generateValidDelays();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC), MathConstants.WAD);

    // Generate valid new configs for triggers.
    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](1);
    triggerConfigUpdates_[0] = _generateValidTriggerConfig();

    // Invalid update because `invalidRewardPoolConfigs_.length < numExistingRewardPools`.
    RewardPoolConfig[] memory invalidRewardPoolConfigs_ = new RewardPoolConfig[](1);
    invalidRewardPoolConfigs_[0] = rewardPoolConfig1_;
    assertFalse(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: reservePoolConfigs_,
          rewardPoolConfigs: invalidRewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );

    // Invalid update because `rewardPool2.address != invalidRewardPoolConfigs_[1].address`.
    invalidRewardPoolConfigs_ = new RewardPoolConfig[](2);
    invalidRewardPoolConfigs_[0] = rewardPoolConfig1_;
    invalidRewardPoolConfigs_[1] =
      RewardPoolConfig({asset: IERC20(_randomAddress()), dripModel: IDripModel(_randomAddress())});
    assertFalse(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: reservePoolConfigs_,
          rewardPoolConfigs: invalidRewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );

    // Valid update.
    RewardPoolConfig[] memory validRewardPoolConfigs_ = new RewardPoolConfig[](3);
    validRewardPoolConfigs_[0] = rewardPoolConfig1_;
    validRewardPoolConfigs_[1] = rewardPoolConfig2_;
    validRewardPoolConfigs_[2] = _generateValidRewardPoolConfig();
    assertTrue(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: reservePoolConfigs_,
          rewardPoolConfigs: validRewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );
  }

  function test_isValidUpdate_TriggerAlreadyTriggeredSafetyModule() external {
    Delays memory delayConfig_ = _generateValidDelays();

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    reservePoolConfigs_[1] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](2);
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    rewardPoolConfigs_[1] = _generateValidRewardPoolConfig();

    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](1);
    triggerConfigUpdates_[0] = _generateValidTriggerConfig();

    component.mockSetTriggerData(
      triggerConfigUpdates_[0].trigger, Trigger({exists: true, payoutHandler: _randomAddress(), triggered: true})
    );
    assertFalse(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: reservePoolConfigs_,
          rewardPoolConfigs: rewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );

    // Regardless of if the trigger is not being used by the safety module at this point in time.
    component.mockSetTriggerData(
      triggerConfigUpdates_[0].trigger, Trigger({exists: false, payoutHandler: _randomAddress(), triggered: true})
    );
    assertFalse(
      component.isValidUpdate(
        UpdateConfigsCalldataParams({
          reservePoolConfigs: reservePoolConfigs_,
          rewardPoolConfigs: rewardPoolConfigs_,
          triggerConfigUpdates: triggerConfigUpdates_,
          delaysConfig: delayConfig_
        })
      )
    );
  }

  function test_finalizeUpdateConfigsActive() external {
    _test_finalizeUpdateConfigs(SafetyModuleState.ACTIVE);
  }

  function test_finalizeUpdateConfigsPaused() external {
    _test_finalizeUpdateConfigs(SafetyModuleState.PAUSED);
  }

  function _test_finalizeUpdateConfigs(SafetyModuleState state_) internal {
    component.mockSetSafetyModuleState(state_);

    // Add two existing reserve pools.
    component.mockAddReservePool(reservePool1);
    component.mockAddReservePool(reservePool2);

    // Add two existing reward pools.
    component.mockAddRewardPool(rewardPool1);
    component.mockAddRewardPool(rewardPool2);

    // Create valid config update.
    Delays memory delayConfig_ = _generateValidDelays();
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](3);
    rewardPoolConfigs_[0] =
      RewardPoolConfig({asset: rewardPool1.asset, dripModel: IDripModel(new MockDripModel(_randomUint256()))});
    rewardPoolConfigs_[1] =
      RewardPoolConfig({asset: rewardPool2.asset, dripModel: IDripModel(new MockDripModel(_randomUint256()))});
    rewardPoolConfigs_[2] = _generateValidRewardPoolConfig();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](3);
    reservePoolConfigs_[0] = ReservePoolConfig({
      asset: reservePool1.asset,
      rewardsPoolsWeight: uint16(MathConstants.ZOC) / 4,
      maxSlashPercentage: MathConstants.WAD
    });
    reservePoolConfigs_[1] = ReservePoolConfig({
      asset: reservePool2.asset,
      rewardsPoolsWeight: uint16(MathConstants.ZOC) / 4,
      maxSlashPercentage: MathConstants.WAD
    });
    reservePoolConfigs_[2] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC) / 2, MathConstants.WAD);
    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](2);
    triggerConfigUpdates_[0] = _generateValidTriggerConfig();
    triggerConfigUpdates_[1] = _generateValidTriggerConfig();

    ConfigUpdateMetadata memory lastConfigUpdate_ =
      _getConfigUpdateMetadata(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    // Ensure config updates can be applied
    vm.warp(lastConfigUpdate_.configUpdateTime);

    _expectEmit();
    emit TestableConfiguratorEvents.DripAndResetCumulativeRewardsValuesCalled();
    _expectEmit();
    emit ConfigUpdatesFinalized(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );

    // Delay config updates applied.
    Delays memory delays_ = component.getDelays();
    assertEq(delays_.configUpdateDelay, delayConfig_.configUpdateDelay);
    assertEq(delays_.configUpdateGracePeriod, delayConfig_.configUpdateGracePeriod);
    assertEq(delays_.unstakeDelay, delayConfig_.unstakeDelay);
    assertEq(delays_.withdrawDelay, delayConfig_.withdrawDelay);

    // Reserve pool config updates applied.
    ReservePool[] memory reservePools_ = component.getReservePools();
    assertEq(reservePools_.length, 3);
    _assertReservePoolUpdatesApplied(reservePools_[0], reservePoolConfigs_[0]);
    _assertReservePoolUpdatesApplied(reservePools_[1], reservePoolConfigs_[1]);
    _assertReservePoolUpdatesApplied(reservePools_[2], reservePoolConfigs_[2]);

    // Reward pool config updates applied.
    RewardPool[] memory rewardPools_ = component.getRewardPools();
    assertEq(rewardPools_.length, 3);
    _assertRewardPoolUpdatesApplied(rewardPools_[0], rewardPoolConfigs_[0]);
    _assertRewardPoolUpdatesApplied(rewardPools_[1], rewardPoolConfigs_[1]);
    _assertRewardPoolUpdatesApplied(rewardPools_[2], rewardPoolConfigs_[2]);

    // Trigger config updates applied.
    Trigger memory trigger_ = component.getTriggerData(triggerConfigUpdates_[0].trigger);
    assertEq(trigger_.exists, triggerConfigUpdates_[0].exists);
    assertEq(trigger_.payoutHandler, triggerConfigUpdates_[0].payoutHandler);
    trigger_ = component.getTriggerData(triggerConfigUpdates_[1].trigger);
    assertEq(trigger_.payoutHandler, triggerConfigUpdates_[1].payoutHandler);
    assertEq(trigger_.exists, triggerConfigUpdates_[1].exists);

    // The lastConfigUpdate hash is reset to 0.
    ConfigUpdateMetadata memory result_ = component.getLastConfigUpdate();
    assertEq(result_.queuedConfigUpdateHash, bytes32(0));
  }

  function test_finalizeUpdateConfigs_RevertBeforeConfigUpdateTime() external {
    (
      ReservePoolConfig[] memory reservePoolConfigs_,
      RewardPoolConfig[] memory rewardPoolConfigs_,
      TriggerConfig[] memory triggerConfigUpdates_,
      Delays memory delayConfig_
    ) = _generateBasicConfigs();

    vm.warp(1); // We set the timestamp > 0 so we can warp to a timestamp before configUpdateTime_ for testing.
    uint64 now_ = uint64(block.timestamp);
    uint64 configUpdateTime_ = now_ + _randomUint32();
    uint64 configUpdateDeadline_ = configUpdateTime_ + _randomUint32();
    ConfigUpdateMetadata memory lastConfigUpdate_ = ConfigUpdateMetadata({
      queuedConfigUpdateHash: keccak256(
        abi.encode(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_)
        ),
      configUpdateTime: configUpdateTime_,
      configUpdateDeadline: configUpdateDeadline_
    });
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    // Current timestamp is before configUpdateTime.
    vm.warp(bound(_randomUint256(), 0, configUpdateTime_));
    vm.expectRevert(ICommonErrors.InvalidStateTransition.selector);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );
  }

  function test_finalizeUpdateConfigs_RevertAfterConfigUpdateDeadline() external {
    (
      ReservePoolConfig[] memory reservePoolConfigs_,
      RewardPoolConfig[] memory rewardPoolConfigs_,
      TriggerConfig[] memory triggerConfigUpdates_,
      Delays memory delayConfig_
    ) = _generateBasicConfigs();

    uint64 now_ = uint64(block.timestamp);
    uint64 configUpdateTime_ = now_ + _randomUint32();
    uint64 configUpdateDeadline_ = configUpdateTime_ + _randomUint32();
    ConfigUpdateMetadata memory lastConfigUpdate_ = ConfigUpdateMetadata({
      queuedConfigUpdateHash: keccak256(
        abi.encode(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_)
        ),
      configUpdateTime: configUpdateTime_,
      configUpdateDeadline: configUpdateDeadline_
    });
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    // Current timestamp is after configUpdateDeadline.
    vm.warp(bound(_randomUint256(), configUpdateDeadline_ + 1, type(uint64).max));
    vm.expectRevert(ICommonErrors.InvalidStateTransition.selector);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );
  }

  function test_finalizeUpdateConfigs_RevertQueuedConfigUpdateSafetyModuleStateTriggered() external {
    (
      ReservePoolConfig[] memory reservePoolConfigs_,
      RewardPoolConfig[] memory rewardPoolConfigs_,
      TriggerConfig[] memory triggerConfigUpdates_,
      Delays memory delayConfig_
    ) = _generateBasicConfigs();

    ConfigUpdateMetadata memory lastConfigUpdate_ =
      _getConfigUpdateMetadata(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    vm.warp(lastConfigUpdate_.configUpdateTime); // Ensure delay has passed and is within the grace period.

    // Set state to TRIGGERED.
    component.mockSetSafetyModuleState(SafetyModuleState.TRIGGERED);
    vm.expectRevert(ICommonErrors.InvalidState.selector);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );
  }

  function test_finalizeUpdateConfigs_RevertQueuedConfigUpdateHashReservePoolConfigMismatch() external {
    (
      ReservePoolConfig[] memory reservePoolConfigs_,
      RewardPoolConfig[] memory rewardPoolConfigs_,
      TriggerConfig[] memory triggerConfigUpdates_,
      Delays memory delayConfig_
    ) = _generateBasicConfigs();

    ConfigUpdateMetadata memory lastConfigUpdate_ =
      _getConfigUpdateMetadata(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    vm.warp(lastConfigUpdate_.configUpdateTime); // Ensure delay has passed and is within the grace period.

    // finalizeUpdateConfigs is called with different reserve pool config.
    reservePoolConfigs_[0] = _generateValidReservePoolConfig(uint16(MathConstants.ZOC), MathConstants.WAD);
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );
  }

  function test_finalizeUpdateConfigs_RevertQueuedConfigUpdateHashRewardPoolConfigMismatch() external {
    (
      ReservePoolConfig[] memory reservePoolConfigs_,
      RewardPoolConfig[] memory rewardPoolConfigs_,
      TriggerConfig[] memory triggerConfigUpdates_,
      Delays memory delayConfig_
    ) = _generateBasicConfigs();

    ConfigUpdateMetadata memory lastConfigUpdate_ =
      _getConfigUpdateMetadata(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    vm.warp(lastConfigUpdate_.configUpdateTime); // Ensure delay has passed and is within the grace period.

    // finalizeUpdateConfigs is called with different reward pool config.
    rewardPoolConfigs_[0] = _generateValidRewardPoolConfig();
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );
  }

  function test_finalizeUpdateConfigs_RevertQueuedConfigUpdateHashDelayConfigMismatch() external {
    (
      ReservePoolConfig[] memory reservePoolConfigs_,
      RewardPoolConfig[] memory rewardPoolConfigs_,
      TriggerConfig[] memory triggerConfigUpdates_,
      Delays memory delayConfig_
    ) = _generateBasicConfigs();

    ConfigUpdateMetadata memory lastConfigUpdate_ =
      _getConfigUpdateMetadata(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    vm.warp(lastConfigUpdate_.configUpdateTime); // Ensure delay has passed and is within the grace period.

    // finalizeUpdateConfigs is called with different delay config.
    delayConfig_ = _generateValidDelays();
    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );
  }

  function test_initializeReservePool() external {
    // One existing reserve pool.
    component.mockAddReservePool(reservePool1);
    // New reserve pool config.
    ReservePoolConfig memory newReservePoolConfig_ = _generateValidReservePoolConfig(0, MathConstants.WAD);

    IReceiptTokenFactory receiptTokenFactory_ = component.getReceiptTokenFactory();
    address stkTokenAddress_ =
      receiptTokenFactory_.computeAddress(ISafetyModule(address(component)), 1, IReceiptTokenFactory.PoolType.STAKE);
    address depositTokenAddress_ =
      receiptTokenFactory_.computeAddress(ISafetyModule(address(component)), 1, IReceiptTokenFactory.PoolType.RESERVE);

    _expectEmit();
    emit ReservePoolCreated(1, address(newReservePoolConfig_.asset), stkTokenAddress_, depositTokenAddress_);
    component.initializeReservePool(newReservePoolConfig_);

    // One reserve pool was added, so two total reserve pools.
    assertEq(component.getReservePools().length, 2);
    // Check that the new reserve pool was initialized correctly.
    ReservePool memory newReservePool_ = component.getReservePool(1);
    _assertReservePoolUpdatesApplied(newReservePool_, newReservePoolConfig_);

    IdLookup memory idLookup_ = component.getStkTokenToReservePoolId(stkTokenAddress_);
    assertEq(idLookup_.exists, true);
    assertEq(idLookup_.index, 1);
  }

  function test_initializeRewardPool() external {
    // One existing reward pool.
    component.mockAddRewardPool(rewardPool1);
    // New reward pool config.
    RewardPoolConfig memory newRewardPoolConfig_ = _generateValidRewardPoolConfig();

    IReceiptTokenFactory receiptTokenFactory_ = component.getReceiptTokenFactory();
    address depositTokenAddress_ =
      receiptTokenFactory_.computeAddress(ISafetyModule(address(component)), 1, IReceiptTokenFactory.PoolType.REWARD);

    _expectEmit();
    emit RewardPoolCreated(1, address(newRewardPoolConfig_.asset), depositTokenAddress_);
    component.initializeRewardPool(newRewardPoolConfig_);

    // One reward pool was added, so two total reward pools.
    assertEq(component.getRewardPools().length, 2);
    // Check that the new reward pool was initialized correctly.
    RewardPool memory newRewardPool_ = component.getRewardPool(1);
    _assertRewardPoolUpdatesApplied(newRewardPool_, newRewardPoolConfig_);
  }

  function test_finalizeUpdateConfigs_RevertQueuedConfigUpdateTriggerAlreadyTriggered() external {
    (
      ReservePoolConfig[] memory reservePoolConfigs_,
      RewardPoolConfig[] memory rewardPoolConfigs_,
      TriggerConfig[] memory triggerConfigUpdates_,
      Delays memory delayConfig_
    ) = _generateBasicConfigs();

    // The trigger is already triggered.
    MockTrigger(address(triggerConfigUpdates_[0].trigger)).mockState(TriggerState.TRIGGERED);

    ConfigUpdateMetadata memory lastConfigUpdate_ =
      _getConfigUpdateMetadata(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    vm.warp(lastConfigUpdate_.configUpdateTime); // Ensure delay has passed and is within the grace period.

    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );
  }

  function test_finalizeUpdateConfigs_RevertQueuedConfigUpdateTriggerAlreadyTriggeredSafetyModule() external {
    (
      ReservePoolConfig[] memory reservePoolConfigs_,
      RewardPoolConfig[] memory rewardPoolConfigs_,
      TriggerConfig[] memory triggerConfigUpdates_,
      Delays memory delayConfig_
    ) = _generateBasicConfigs();

    // The trigger has already successfully called `trigger()` on the safety module before.
    component.mockSetTriggerData(
      triggerConfigUpdates_[0].trigger,
      Trigger({
        exists: triggerConfigUpdates_[0].exists,
        payoutHandler: triggerConfigUpdates_[0].payoutHandler,
        triggered: true
      })
    );

    ConfigUpdateMetadata memory lastConfigUpdate_ =
      _getConfigUpdateMetadata(reservePoolConfigs_, rewardPoolConfigs_, triggerConfigUpdates_, delayConfig_);
    component.mockSetLastConfigUpdate(lastConfigUpdate_);

    vm.warp(lastConfigUpdate_.configUpdateTime); // Ensure delay has passed and is within the grace period.

    vm.expectRevert(IConfiguratorErrors.InvalidConfiguration.selector);
    component.finalizeUpdateConfigs(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        rewardPoolConfigs: rewardPoolConfigs_,
        triggerConfigUpdates: triggerConfigUpdates_,
        delaysConfig: delayConfig_
      })
    );
  }
}

interface TestableConfiguratorEvents {
  event DripAndResetCumulativeRewardsValuesCalled();
}

contract TestableConfigurator is Configurator, TestableConfiguratorEvents {
  constructor(address owner_, IManager manager_, IReceiptTokenFactory receiptTokenFactory_) {
    __initGovernable(owner_, owner_);
    cozyManager = manager_;
    receiptTokenFactory = receiptTokenFactory_;
  }

  // -------- Mock setters --------
  function mockSetDelays(Delays memory delays_) external {
    delays = delays_;
  }

  function mockSetLastConfigUpdate(ConfigUpdateMetadata memory lastConfigUpdate_) external {
    lastConfigUpdate = lastConfigUpdate_;
  }

  function mockSetSafetyModuleState(SafetyModuleState safetyModuleState_) external {
    safetyModuleState = safetyModuleState_;
  }

  function mockAddReservePool(ReservePool memory reservePool_) external {
    reservePools.push(reservePool_);
  }

  function mockAddRewardPool(RewardPool memory rewardPool_) external {
    rewardPools.push(rewardPool_);
  }

  function mockSetTriggerData(ITrigger trigger_, Trigger memory triggerData_) public {
    triggerData[trigger_] = triggerData_;
  }

  // -------- Mock getters --------
  function getStkTokenToReservePoolId(address stkToken_) external view returns (IdLookup memory) {
    return stkTokenToReservePoolIds[IReceiptToken(stkToken_)];
  }

  function getReceiptTokenFactory() external view returns (IReceiptTokenFactory) {
    return receiptTokenFactory;
  }

  function getDelays() external view returns (Delays memory) {
    return delays;
  }

  function getLastConfigUpdate() external view returns (ConfigUpdateMetadata memory) {
    return lastConfigUpdate;
  }

  function getReservePools() external view returns (ReservePool[] memory) {
    return reservePools;
  }

  function getReservePool(uint16 reservePoolId_) external view returns (ReservePool memory) {
    return reservePools[reservePoolId_];
  }

  function getRewardPool(uint16 rewardPoolId_) external view returns (RewardPool memory) {
    return rewardPools[rewardPoolId_];
  }

  function getRewardPools() external view returns (RewardPool[] memory) {
    return rewardPools;
  }

  function getTriggerData(ITrigger trigger_) external view returns (Trigger memory) {
    return triggerData[trigger_];
  }

  // -------- Internal function wrappers for testing --------
  function isValidConfiguration(
    ReservePoolConfig[] calldata reservePoolConfigs_,
    RewardPoolConfig[] calldata rewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) external view returns (bool) {
    return ConfiguratorLib.isValidConfiguration(
      reservePoolConfigs_,
      rewardPoolConfigs_,
      delaysConfig_,
      cozyManager.allowedReservePools(),
      cozyManager.allowedRewardPools()
    );
  }

  function isValidUpdate(UpdateConfigsCalldataParams calldata configUpdates_) external view returns (bool) {
    return ConfiguratorLib.isValidUpdate(reservePools, rewardPools, triggerData, configUpdates_, cozyManager);
  }

  function initializeReservePool(ReservePoolConfig calldata reservePoolConfig_) external {
    ConfiguratorLib.initializeReservePool(
      reservePools, stkTokenToReservePoolIds, receiptTokenFactory, reservePoolConfig_
    );
  }

  function initializeRewardPool(RewardPoolConfig calldata rewardPoolConfig_) external {
    ConfiguratorLib.initializeRewardPool(rewardPools, receiptTokenFactory, rewardPoolConfig_);
  }

  function _dripAndResetCumulativeRewardsValues(
    ReservePool[] storage, /* reservePools_ */
    RewardPool[] storage /* rewardPools_ */
  ) internal override {
    emit DripAndResetCumulativeRewardsValuesCalled();
  }

  // -------- Overridden abstract function placeholders --------
  function claimRewards(uint16, /* reservePoolId_ */ address receiver_) public view override {
    __readStub__();
  }

  // Mock drip of rewards based on mocked next amount.
  function dripRewards() public view override {
    __readStub__();
  }

  function dripFees() public view override {
    __readStub__();
  }

  function _getNextDripAmount(uint256, /* totalBaseAmount_ */ IDripModel, /* dripModel_ */ uint256 /* lastDripTime_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _computeNextDripAmount(uint256, /* totalBaseAmount_ */ uint256 /* dripFactor_ */ )
    internal
    view
    override
    returns (uint256)
  {
    __readStub__();
  }

  function _updateUnstakesAfterTrigger(
    uint16, /* reservePoolId_ */
    ReservePool storage, /* reservePool_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _updateWithdrawalsAfterTrigger(
    uint16, /* reservePoolId_ */
    ReservePool storage, /* reservePool_ */
    uint256, /* oldStakeAmount_ */
    uint256 /* slashAmount_ */
  ) internal view override returns (uint256) {
    __readStub__();
  }

  function _assertValidDepositBalance(
    IERC20, /* token_ */
    uint256, /* tokenPoolBalance_ */
    uint256 /* depositAmount_ */
  ) internal view override {
    __readStub__();
  }

  function _updateUserRewards(
    uint256, /*userStkTokenBalance_*/
    mapping(uint16 => ClaimableRewardsData) storage, /*claimableRewards_*/
    UserRewardsData[] storage /*userRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _dripRewardPool(RewardPool storage /*rewardPool_*/ ) internal view override {
    __readStub__();
  }

  function _applyPendingDrippedRewards(
    ReservePool storage, /*reservePool_*/
    mapping(uint16 => ClaimableRewardsData) storage /*claimableRewards_*/
  ) internal view override {
    __readStub__();
  }

  function _dripFeesFromReservePool(ReservePool storage, /*reservePool_*/ IDripModel /*dripModel_*/ )
    internal
    view
    override
  {
    __readStub__();
  }
}
