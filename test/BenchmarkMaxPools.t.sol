// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {
  UndrippedRewardPoolConfig, UpdateConfigsCalldataParams, ReservePoolConfig
} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {UndrippedRewardPool, ReservePool} from "../src/lib/structs/Pools.sol";
import {TriggerConfig} from "../src/lib/structs/Trigger.sol";
import {Slash} from "../src/lib/structs/Slash.sol";
import {TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";

abstract contract BenchmarkMaxPools is MockDeployProtocol {
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD
  uint256 internal constant DEFAULT_SKIP_DAYS = 10;
  Delays DEFAULT_DELAYS =
    Delays({unstakeDelay: 2 days, withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});
  
  SafetyModule safetyModule;
  MockTrigger trigger;
  uint16 numRewardAssets;
  uint16 numReserveAssets;
  address self = address(this);
  address payoutHandler = _randomAddress();

  function setUp() public virtual override {
    super.setUp();

    _createSafetyModule(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: _createReservePools(numReserveAssets),
        undrippedRewardPoolConfigs: _createUndrippedRewardPools(numRewardAssets),
        triggerConfigUpdates: _createTriggerConfig(),
        delaysConfig: DEFAULT_DELAYS
      })
    );

    _initializeRewardPools();
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
        asset: IERC20(address(new MockERC20("Mock Reserve Asset", "cozyRes", 18))),
        rewardsPoolsWeight: uint16(MathConstants.ZOC / numPools)
      });
    }
    return reservePoolConfigs_;
  }

  function _createUndrippedRewardPools(uint16 numPools) internal returns (UndrippedRewardPoolConfig[] memory) {
    UndrippedRewardPoolConfig[] memory undrippedRewardPoolConfigs_ = new UndrippedRewardPoolConfig[](numPools);
    for (uint256 i = 0; i < numPools; i++) {
      undrippedRewardPoolConfigs_[i] = UndrippedRewardPoolConfig({
        asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyRew", 18))),
        dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
      });
    }
    return undrippedRewardPoolConfigs_;
  }

  function _createTriggerConfig() internal returns (TriggerConfig[] memory) {
    trigger = new MockTrigger(TriggerState.ACTIVE);
    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({trigger: ITrigger(address(trigger)), payoutHandler: payoutHandler, exists: true});
    return triggerConfig_;
  }

  function _initializeRewardPools() internal {
    for (uint16 i = 0; i < numRewardAssets; i++) {
      (, uint256 rewardAssetAmount_, address receiver_) = _randomSingleActionFixture(false);
      _depositRewardAssets(i, rewardAssetAmount_, receiver_);
    }
  }

  function _initializeReservePools() internal {
    for (uint16 i = 0; i < numReserveAssets; i++) {
      (, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
      _stake(i, reserveAssetAmount_, receiver_);
    }
  }

  function _randomSingleActionFixture(bool isReserveAction_) internal view returns (uint16, uint256, address) {
    return (
      isReserveAction_ ? (_randomUint16() % numReserveAssets) : (_randomUint16() % numRewardAssets),
      _randomUint256() % 999_999_999_999_999,
      _randomAddress()
    );
  }

  function _depositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    ReservePool memory reservePool_ = getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_);
    deal(address(reservePool_.asset), address(safetyModule), type(uint256).max);
    safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function _depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) internal {
    UndrippedRewardPool memory rewardPool_ = getUndrippedRewardPool(ISafetyModule(address(safetyModule)), rewardPoolId_);
    deal(address(rewardPool_.asset), address(safetyModule), type(uint256).max);
    safetyModule.depositRewardAssetsWithoutTransfer(rewardPoolId_, rewardAssetAmount_, receiver_);
  }

  function _stake(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    ReservePool memory reservePool_ = getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_);
    deal(address(reservePool_.asset), address(safetyModule), type(uint256).max);
    safetyModule.stakeWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function _redeem(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    _depositReserveAssets(reservePoolId_, reserveAssetAmount_, receiver_);

    uint256 depositTokenAmount_ = safetyModule.convertToReserveDepositTokenAmount(reservePoolId_, reserveAssetAmount_);
    vm.startPrank(receiver_);
    getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_).depositToken.approve(
      address(safetyModule), depositTokenAmount_
    );
    (uint64 redemptionId_,) = safetyModule.redeem(reservePoolId_, depositTokenAmount_, receiver_, receiver_);
    vm.stopPrank();

    (,,, uint64 withdrawDelay_) = safetyModule.delays();
    skip(withdrawDelay_);
    safetyModule.completeRedemption(redemptionId_);
  }

  function _unstake(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    _stake(reservePoolId_, reserveAssetAmount_, receiver_);

    uint256 stkTokenAmount_ = safetyModule.convertToStakeTokenAmount(reservePoolId_, reserveAssetAmount_);
    vm.startPrank(receiver_);
    getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_).stkToken.approve(
      address(safetyModule), stkTokenAmount_
    );
    (uint64 redemptionId_,) = safetyModule.unstake(reservePoolId_, stkTokenAmount_, receiver_, receiver_);
    vm.stopPrank();

    (,, uint64 unstakeDelay_,) = safetyModule.delays();
    skip(unstakeDelay_);
    safetyModule.completeRedemption(redemptionId_);
  }

  function _redeemUndrippedRewards(uint16 rewardPoolId_, address receiver_) internal {
    UndrippedRewardPool memory rewardPool_ = getUndrippedRewardPool(ISafetyModule(address(safetyModule)), rewardPoolId_);
    _depositRewardAssets(rewardPoolId_, rewardPool_.amount, receiver_);

    uint256 depositTokenAmount_ = rewardPool_.depositToken.balanceOf(receiver_);
    vm.startPrank(receiver_);
    rewardPool_.depositToken.approve(address(safetyModule), depositTokenAmount_);
    safetyModule.redeemUndrippedRewards(rewardPoolId_, depositTokenAmount_, receiver_, receiver_);
    vm.stopPrank();
  }

  function _trigger() internal {
    trigger.mockState(TriggerState.TRIGGERED);
    safetyModule.trigger(ITrigger(address(trigger)));
  }

  function test_createSafetyModule() public {
    _createSafetyModule(
      UpdateConfigsCalldataParams({
        reservePoolConfigs: _createReservePools(numReserveAssets),
        undrippedRewardPoolConfigs: _createUndrippedRewardPools(numRewardAssets),
        triggerConfigUpdates: _createTriggerConfig(),
        delaysConfig: DEFAULT_DELAYS
      })
    );
  }

  function test_depositReserveAssets() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _depositReserveAssets(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function test_depositRewardAssets() public {
    (uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) = _randomSingleActionFixture(false);
    _depositRewardAssets(rewardPoolId_, rewardAssetAmount_, receiver_);
  }

  function test_stake() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _stake(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function test_redeem() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _redeem(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function test_redeemUndrippedRewards() public {
    (uint16 rewardPoolId_,, address receiver_) = _randomSingleActionFixture(false);
    _redeemUndrippedRewards(rewardPoolId_, receiver_);
  }

  function test_unstake() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _unstake(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function test_pause() public {
    vm.prank(owner);
    safetyModule.pause();
  }

  function test_unpause() public {
    vm.startPrank(owner);
    safetyModule.pause();
    safetyModule.unpause();
    vm.stopPrank();
  }

  function test_trigger() public {
    _trigger();
  }

  function test_slash() public {
    _trigger();

    Slash[] memory slashes_ = new Slash[](numReserveAssets);
    vm.prank(payoutHandler);
    safetyModule.slash(slashes_, _randomAddress());
  }

  function test_dripRewards() public {
    skip(_randomUint64());
    safetyModule.dripRewards();
  }

  function test_claimRewards() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _stake(reservePoolId_, reserveAssetAmount_, receiver_);

    skip(_randomUint64());

    vm.prank(receiver_);
    safetyModule.claimRewards(reservePoolId_, receiver_);
  }

  function test_dripFees() public {
    skip(_randomUint64());
    safetyModule.dripFees();
  }

  function test_stkTokenTransfer() public {
    (uint16 reservePoolId_,, address receiver_) = _randomSingleActionFixture(true);

    ReservePool memory reservePool_ = getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_);
    IERC20 stkToken_ = reservePool_.stkToken;
    _stake(reservePoolId_, reservePool_.stakeAmount, receiver_);

    skip(_randomUint64());

    vm.startPrank(receiver_);
    stkToken_.transfer(_randomAddress(), stkToken_.balanceOf(receiver_));
    vm.stopPrank();
  }

  function test_configUpdate() public {
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](numReserveAssets + 1);
    UndrippedRewardPoolConfig[] memory undrippedRewardPoolConfigs_ =
      new UndrippedRewardPoolConfig[](numRewardAssets + 1);

    uint16 weightSum_ = 0;
    for (uint256 i = 0; i < numReserveAssets + 1; i++) {
      IERC20 asset_ = i < numReserveAssets
        ? getReservePool(ISafetyModule(address(safetyModule)), i).asset
        : IERC20(address(new MockERC20("Mock Reserve Asset", "cozyRes", 18)));
      reservePoolConfigs_[i] = ReservePoolConfig({
        maxSlashPercentage: MathConstants.WAD / 2,
        asset: asset_,
        rewardsPoolsWeight: i == numReserveAssets
          ? uint16(MathConstants.ZOC - weightSum_)
          : uint16(MathConstants.ZOC / (numReserveAssets + 1))
      });
      weightSum_ += reservePoolConfigs_[i].rewardsPoolsWeight;
    }

    for (uint256 i = 0; i < numRewardAssets + 1; i++) {
      if (i < numRewardAssets) {
        UndrippedRewardPool memory rewardPool_ = getUndrippedRewardPool(ISafetyModule(address(safetyModule)), i);
        undrippedRewardPoolConfigs_[i] =
          UndrippedRewardPoolConfig({asset: rewardPool_.asset, dripModel: rewardPool_.dripModel});
      } else {
        undrippedRewardPoolConfigs_[i] = UndrippedRewardPoolConfig({
          asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyRew", 18))),
          dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
        });
      }
    }

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](0);
    Delays memory delaysConfig_ = getDelays(ISafetyModule(address(safetyModule)));

    UpdateConfigsCalldataParams memory updateConfigs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      undrippedRewardPoolConfigs: undrippedRewardPoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delaysConfig_
    });

    vm.startPrank(owner);
    safetyModule.updateConfigs(updateConfigs_);
    vm.stopPrank();

    skip(delaysConfig_.configUpdateDelay);

    vm.startPrank(owner);
    safetyModule.finalizeUpdateConfigs(updateConfigs_);
    vm.stopPrank();
  }
}

contract BenchmarkMaxPools_1Reserve_1Reward is BenchmarkMaxPools {
  function setUp() public override {
    numReserveAssets = 1;
    numRewardAssets = 1;
    super.setUp();
  }
}

contract BenchmarkMaxPools_10Reserve_1Reward is BenchmarkMaxPools {
  function setUp() public override {
    numReserveAssets = 10;
    numRewardAssets = 1;
    super.setUp();
  }
}

contract BenchmarkMaxPools_1Reserve_10Reward is BenchmarkMaxPools {
  function setUp() public override {
    numReserveAssets = 1;
    numRewardAssets = 10;
    super.setUp();
  }
}

contract BenchmarkMaxPools_10Reserve_10Reward is BenchmarkMaxPools {
  function setUp() public override {
    numRewardAssets = 10;
    numReserveAssets = 10;
    super.setUp();
  }
}
