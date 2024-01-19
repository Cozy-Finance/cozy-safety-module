// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {RewardPoolConfig, UpdateConfigsCalldataParams, ReservePoolConfig} from "../../src/lib/structs/Configs.sol";
import {Delays} from "../../src/lib/structs/Delays.sol";
import {RewardPool, ReservePool} from "../../src/lib/structs/Pools.sol";
import {TriggerConfig} from "../../src/lib/structs/Trigger.sol";
import {Slash} from "../../src/lib/structs/Slash.sol";
import {TriggerState} from "../../src/lib/SafetyModuleStates.sol";
import {SafetyModule} from "../../src/SafetyModule.sol";
import {MathConstants} from "../../src/lib/MathConstants.sol";
import {IDripModel} from "../../src/interfaces/IDripModel.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {ITrigger} from "../../src/interfaces/ITrigger.sol";
import {ISafetyModule} from "../../src/interfaces/ISafetyModule.sol";
import {MockDeployProtocol} from "../utils/MockDeployProtocol.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {MockTrigger} from "../utils/MockTrigger.sol";
import {console2} from "forge-std/console2.sol";

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
        rewardPoolConfigs: _createRewardPools(numRewardAssets),
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
    uint16 weightSum_ = 0;
    for (uint256 i = 0; i < numPools; i++) {
      reservePoolConfigs_[i] = ReservePoolConfig({
        maxSlashPercentage: MathConstants.WAD,
        asset: IERC20(address(new MockERC20("Mock Reserve Asset", "cozyRes", 18))),
        rewardsPoolsWeight: i == numPools - 1
          ? uint16(MathConstants.ZOC - weightSum_)
          : uint16(MathConstants.ZOC / numPools)
      });
      weightSum_ += reservePoolConfigs_[i].rewardsPoolsWeight;
    }
    return reservePoolConfigs_;
  }

  function _createRewardPools(uint16 numPools) internal returns (RewardPoolConfig[] memory) {
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](numPools);
    for (uint256 i = 0; i < numPools; i++) {
      rewardPoolConfigs_[i] = RewardPoolConfig({
        asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyRew", 18))),
        dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
      });
    }
    return rewardPoolConfigs_;
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

  function _setUpDepositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    ReservePool memory reservePool_ = getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_);
    deal(address(reservePool_.asset), address(safetyModule), type(uint256).max);
  }

  function _depositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    _setUpDepositReserveAssets(reservePoolId_, reserveAssetAmount_, receiver_);
    safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function _setUpDepositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) internal {
    RewardPool memory rewardPool_ = getRewardPool(ISafetyModule(address(safetyModule)), rewardPoolId_);
    deal(address(rewardPool_.asset), address(safetyModule), type(uint256).max);
  }

  function _depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) internal {
    _setUpDepositRewardAssets(rewardPoolId_, rewardAssetAmount_, receiver_);
    safetyModule.depositRewardAssetsWithoutTransfer(rewardPoolId_, rewardAssetAmount_, receiver_);
  }

  function _setUpStake(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    ReservePool memory reservePool_ = getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_);
    deal(address(reservePool_.asset), address(safetyModule), type(uint256).max);
  }

  function _stake(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) internal {
    _setUpStake(reservePoolId_, reserveAssetAmount_, receiver_);
    safetyModule.stakeWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  function _setUpRedeem(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    internal
    returns (uint256 depositTokenAmount_)
  {
    _depositReserveAssets(reservePoolId_, reserveAssetAmount_, receiver_);

    depositTokenAmount_ = safetyModule.convertToReserveDepositTokenAmount(reservePoolId_, reserveAssetAmount_);
    vm.startPrank(receiver_);
    getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_).depositToken.approve(
      address(safetyModule), depositTokenAmount_
    );
    vm.stopPrank();
  }

  function _setUpUnstake(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    internal
    returns (uint256 stkTokenAmount_)
  {
    _stake(reservePoolId_, reserveAssetAmount_, receiver_);

    stkTokenAmount_ = safetyModule.convertToStakeTokenAmount(reservePoolId_, reserveAssetAmount_);
    vm.startPrank(receiver_);
    getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_).stkToken.approve(
      address(safetyModule), stkTokenAmount_
    );
    vm.stopPrank();
  }

  function _setUpRedeemRewards(uint16 rewardPoolId_, address receiver_) internal returns (uint256 depositTokenAmount_) {
    RewardPool memory rewardPool_ = getRewardPool(ISafetyModule(address(safetyModule)), rewardPoolId_);
    _depositRewardAssets(rewardPoolId_, rewardPool_.undrippedRewards, receiver_);

    depositTokenAmount_ = rewardPool_.depositToken.balanceOf(receiver_);
    vm.startPrank(receiver_);
    rewardPool_.depositToken.approve(address(safetyModule), depositTokenAmount_);
    vm.stopPrank();
  }

  function _setUpConfigUpdate() internal returns (UpdateConfigsCalldataParams memory updateConfigs_) {
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](numReserveAssets + 1);
    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](numRewardAssets + 1);

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
        RewardPool memory rewardPool_ = getRewardPool(ISafetyModule(address(safetyModule)), i);
        rewardPoolConfigs_[i] = RewardPoolConfig({asset: rewardPool_.asset, dripModel: rewardPool_.dripModel});
      } else {
        rewardPoolConfigs_[i] = RewardPoolConfig({
          asset: IERC20(address(new MockERC20("Mock Reward Asset", "cozyRew", 18))),
          dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
        });
      }
    }

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](0);
    Delays memory delaysConfig_ = getDelays(ISafetyModule(address(safetyModule)));

    updateConfigs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      rewardPoolConfigs: rewardPoolConfigs_,
      triggerConfigUpdates: triggerConfig_,
      delaysConfig: delaysConfig_
    });
  }

  function test_createSafetyModule() public {
    UpdateConfigsCalldataParams memory updateConfigs_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: _createReservePools(numReserveAssets),
      rewardPoolConfigs: _createRewardPools(numRewardAssets),
      triggerConfigUpdates: _createTriggerConfig(),
      delaysConfig: DEFAULT_DELAYS
    });

    uint256 gasInitial_ = gasleft();
    _createSafetyModule(updateConfigs_);
    console2.log("Gas used for createSafetyModule: %s", gasInitial_ - gasleft());
  }

  function test_depositReserveAssets() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _setUpDepositReserveAssets(reservePoolId_, reserveAssetAmount_, receiver_);

    uint256 gasInitial_ = gasleft();
    safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
    console2.log("Gas used for depositReserveAssetsWithoutTransfer: %s", gasInitial_ - gasleft());
  }

  function test_depositRewardAssets() public {
    (uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_) = _randomSingleActionFixture(false);
    _setUpDepositRewardAssets(rewardPoolId_, rewardAssetAmount_, receiver_);

    uint256 gasInitial_ = gasleft();
    safetyModule.depositRewardAssetsWithoutTransfer(rewardPoolId_, rewardAssetAmount_, receiver_);
    console2.log("Gas used for depositRewardAssetsWithoutTransfer: %s", gasInitial_ - gasleft());
  }

  function test_stake() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _setUpStake(reservePoolId_, reserveAssetAmount_, receiver_);

    uint256 gasInitial_ = gasleft();
    safetyModule.stakeWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
    console2.log("Gas used for stakeWithoutTransfer: %s", gasInitial_ - gasleft());
  }

  function test_redeem() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    uint256 depositTokenAmount_ = _setUpRedeem(reservePoolId_, reserveAssetAmount_, receiver_);

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    safetyModule.redeem(reservePoolId_, depositTokenAmount_, receiver_, receiver_);
    console2.log("Gas used for redeem: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_completeRedemption() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    uint256 depositTokenAmount_ = _setUpRedeem(reservePoolId_, reserveAssetAmount_, receiver_);

    vm.startPrank(receiver_);
    (uint64 redemptionId_,) = safetyModule.redeem(reservePoolId_, depositTokenAmount_, receiver_, receiver_);
    vm.stopPrank();

    (,, uint64 withdrawDelay_,) = safetyModule.delays();
    skip(withdrawDelay_);

    uint256 gasInitial_ = gasleft();
    safetyModule.completeRedemption(redemptionId_);
    console2.log("Gas used for completeRedemption: %s", gasInitial_ - gasleft());
  }

  function test_redeemRewards() public {
    (uint16 rewardPoolId_,, address receiver_) = _randomSingleActionFixture(false);
    uint256 depositTokenAmount_ = _setUpRedeemRewards(rewardPoolId_, receiver_);

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    safetyModule.redeemRewards(rewardPoolId_, depositTokenAmount_, receiver_, receiver_);
    console2.log("Gas used for redeemRewards: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_unstake() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    uint256 stkTokenAmount_ = _setUpUnstake(reservePoolId_, reserveAssetAmount_, receiver_);

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    safetyModule.unstake(reservePoolId_, stkTokenAmount_, receiver_, receiver_);
    console2.log("Gas used for unstake: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_completeUnstake() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    uint256 stkTokenAmount_ = _setUpUnstake(reservePoolId_, reserveAssetAmount_, receiver_);

    vm.startPrank(receiver_);
    (uint64 redemptionId_,) = safetyModule.unstake(reservePoolId_, stkTokenAmount_, receiver_, receiver_);
    vm.stopPrank();

    (,,, uint64 unstakeDelay_) = safetyModule.delays();
    skip(unstakeDelay_);

    uint256 gasInitial_ = gasleft();
    safetyModule.completeRedemption(redemptionId_);
    console2.log("Gas used for completeRedemption (unstake): %s", gasInitial_ - gasleft());
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

  function test_dripRewards() public {
    skip(_randomUint64());

    uint256 gasInitial_ = gasleft();
    safetyModule.dripRewards();
    console2.log("Gas used for dripRewards: %s", gasInitial_ - gasleft());
  }

  function test_claimRewards() public {
    (uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_) = _randomSingleActionFixture(true);
    _stake(reservePoolId_, reserveAssetAmount_, receiver_);

    skip(_randomUint64());

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    safetyModule.claimRewards(reservePoolId_, receiver_);
    console2.log("Gas used for claimRewards: %s", gasInitial_ - gasleft());
    vm.stopPrank();
  }

  function test_dripFees() public {
    skip(_randomUint64());

    uint256 gasInitial_ = gasleft();
    safetyModule.dripFees();
    console2.log("Gas used for dripFees: %s", gasInitial_ - gasleft());
  }

  function test_stkTokenTransfer() public {
    (uint16 reservePoolId_,, address receiver_) = _randomSingleActionFixture(true);

    ReservePool memory reservePool_ = getReservePool(ISafetyModule(address(safetyModule)), reservePoolId_);
    IERC20 stkToken_ = reservePool_.stkToken;
    _stake(reservePoolId_, reservePool_.stakeAmount, receiver_);

    skip(_randomUint64());

    vm.startPrank(receiver_);
    uint256 gasInitial_ = gasleft();
    stkToken_.transfer(_randomAddress(), stkToken_.balanceOf(receiver_));
    console2.log("Gas used for stkToken_.transfer: %s", gasInitial_ - gasleft());
    vm.stopPrank();
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

    (uint64 configUpdateDelay_,,,) = safetyModule.delays();
    skip(configUpdateDelay_);

    uint256 gasInitial_ = gasleft();
    safetyModule.finalizeUpdateConfigs(updateConfigs_);
    console2.log("Gas used for finalizeUpdateConfigs: %s", gasInitial_ - gasleft());
  }
}

contract BenchmarkMaxPools_30Reserve_25Reward is BenchmarkMaxPools {
  function setUp() public override {
    numReserveAssets = 30;
    numRewardAssets = 25;
    super.setUp();
  }
}
