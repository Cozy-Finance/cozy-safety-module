// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {RewardPoolConfig, UpdateConfigsCalldataParams, ReservePoolConfig} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {RewardPool} from "../src/lib/structs/Pools.sol";
import {TriggerConfig} from "../src/lib/structs/Trigger.sol";
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

abstract contract DripModelIntegrationTestSetup is MockDeployProtocol {
  uint256 internal constant ONE_YEAR = 365.25 days;
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD

  SafetyModule safetyModule;
  address self = address(this);
  IERC20 rewardAsset;
  IERC20 reserveAsset;
  address alice = _randomAddress();

  function setUp() public virtual override {
    super.setUp();

    reserveAsset = IERC20(address(new MockERC20("MockReserve", "MOCK", 18)));
    rewardAsset = IERC20(address(new MockERC20("MockReward", "MOCK", 18)));

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] =
      ReservePoolConfig({maxSlashPercentage: 0, asset: reserveAsset, rewardsPoolsWeight: uint16(MathConstants.ZOC)});

    RewardPoolConfig[] memory rewardPoolConfigs_ = new RewardPoolConfig[](1);
    rewardPoolConfigs_[0] = RewardPoolConfig({
      asset: rewardAsset,
      dripModel: IDripModel(address(new DripModelExponential(DEFAULT_DRIP_RATE)))
    });

    Delays memory delaysConfig_ =
      Delays({unstakeDelay: 2 days, withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({
      trigger: ITrigger(address(new MockTrigger(TriggerState.ACTIVE))),
      payoutHandler: _randomAddress(),
      exists: true
    });

    safetyModule = SafetyModule(
      address(
        manager.createSafetyModule(
          self,
          self,
          UpdateConfigsCalldataParams({
            reservePoolConfigs: reservePoolConfigs_,
            rewardPoolConfigs: rewardPoolConfigs_,
            triggerConfigUpdates: triggerConfig_,
            delaysConfig: delaysConfig_
          }),
          _randomBytes32()
        )
      )
    );
  }

  function depositRewards(SafetyModule safetyModule_, uint256 rewardAssetAmount_, address receiver_) internal {
    deal(
      address(rewardAsset), address(safetyModule_), rewardAsset.balanceOf(address(safetyModule_)) + rewardAssetAmount_
    );
    safetyModule_.depositRewardAssetsWithoutTransfer(0, rewardAssetAmount_, receiver_);
  }

  function stake(SafetyModule safetyModule_, uint256 reserveAssetAmount_, address receiver_) internal {
    deal(
      address(reserveAsset),
      address(safetyModule_),
      reserveAsset.balanceOf(address(safetyModule_)) + reserveAssetAmount_
    );
    safetyModule_.stakeWithoutTransfer(0, reserveAssetAmount_, receiver_);
  }
}

contract RewardsDripModelIntegrationTest is DripModelIntegrationTestSetup {
  uint256 internal constant REWARD_POOL_AMOUNT = 1000;

  function setUp() public virtual override {
    super.setUp();
    depositRewards(safetyModule, REWARD_POOL_AMOUNT, _randomAddress());
    stake(safetyModule, 99, alice);
  }

  function _setRewardsDripModel(uint256 rate_) internal {
    DripModelExponential rewardsDripModel_ = new DripModelExponential(rate_);
    (,,,, IDripModel currentRewardsDripModel_,) = safetyModule.rewardPools(0);
    vm.etch(address(currentRewardsDripModel_), address(rewardsDripModel_).code);
  }

  function _assertRewardDripAmountAndReset(uint256 skipTime_, uint256 expectedClaimedRewards_) internal {
    skip(skipTime_);
    address receiver_ = _randomAddress();

    vm.prank(alice);
    safetyModule.claimRewards(0, receiver_);
    assertEq(rewardAsset.balanceOf(receiver_), expectedClaimedRewards_);

    // Reset reward pool.
    (uint256 currentAmount_,,,,,) = safetyModule.rewardPools(0);
    depositRewards(safetyModule, REWARD_POOL_AMOUNT - currentAmount_, _randomAddress());
  }

  function _testSeveralRewardsDrips(uint256 rate_, uint256[] memory expectedClaimedRewards_) internal {
    _setRewardsDripModel(rate_);
    _assertRewardDripAmountAndReset(ONE_YEAR, expectedClaimedRewards_[0]);
    _assertRewardDripAmountAndReset(ONE_YEAR / 2, expectedClaimedRewards_[1]);
    _assertRewardDripAmountAndReset(ONE_YEAR / 4, expectedClaimedRewards_[2]);
    _assertRewardDripAmountAndReset(ONE_YEAR / 10, expectedClaimedRewards_[3]);
    _assertRewardDripAmountAndReset(ONE_YEAR / 20, expectedClaimedRewards_[4]);
    _assertRewardDripAmountAndReset(0, expectedClaimedRewards_[5]);
  }

  function test_RewardsDrip50Percent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 249; // 1000 * dripFactor(1 year) ~= 1000 * 0.25 ~= 249 (up to rounding down in favor
      // the protocol)
    expectedClaimedRewards_[1] = 132; // 1000 * dripFactor(0.5 years) ~= 1000 * 0.13397459686 ~= 132
    expectedClaimedRewards_[2] = 68; // 1000 * dripFactor(0.25 years) ~= 1000 * 0.06939514124 ~= 68
    expectedClaimedRewards_[3] = 27; // 1000 * dripFactor(0.1 years) ~= 1000 * 0.02835834225 ~= 27
    expectedClaimedRewards_[4] = 13; // 1000 * dripFactor(0.05 years) ~= 1000 * 0.0142811467 ~= 13
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(DEFAULT_DRIP_RATE, expectedClaimedRewards_);
  }

  function test_RewardsDripZeroPercent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 0; // 1000 * dripFactor(1 year) = 1000 * 0 = 0
    expectedClaimedRewards_[1] = 0; // 1000 * dripFactor(0.5 years) = 1000 * 0 = 0
    expectedClaimedRewards_[2] = 0; // 1000 * dripFactor(0.25 years) = 1000 * 0 = 0
    expectedClaimedRewards_[3] = 0; // 1000 * dripFactor(0.1 years) = 1000 * 0 = 0
    expectedClaimedRewards_[4] = 0; // 1000 * dripFactor(0.05 years) = 1000 * 0 = 0
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(0, expectedClaimedRewards_);
  }

  function test_RewardsDrip100Percent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 999; // 1000 * dripFactor(1 year) = 1000 * 1 ~= 999 (up to rounding down in favor
      // the protocol)
    expectedClaimedRewards_[1] = 999; // 1000 * dripFactor(0.5 years) = 1000 * 1 ~= 999
    expectedClaimedRewards_[2] = 999; // 1000 * dripFactor(0.25 years) = 1000 * 1 ~= 999
    expectedClaimedRewards_[3] = 999; // 1000 * dripFactor(0.1 years) = 1000 * 1 ~= 999
    expectedClaimedRewards_[4] = 999; // 1000 * dripFactor(0.05 years) = 1000 * 1 ~= 999
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(MathConstants.WAD, expectedClaimedRewards_);
  }
}

contract FeesDripModelIntegration is DripModelIntegrationTestSetup {
  uint256 internal constant RESERVE_POOL_AMOUNT = 1000;

  function setUp() public virtual override {
    super.setUp();
    stake(safetyModule, RESERVE_POOL_AMOUNT, _randomAddress());
  }

  function _setOverrideFeeDripModel(uint256 rate_) internal {
    DripModelExponential feeDripModel_ = new DripModelExponential(rate_);
    vm.prank(address(owner));
    manager.updateOverrideFeeDripModel(ISafetyModule(address(safetyModule)), IDripModel(address(feeDripModel_)));
  }

  function _assertFeeDripAmountAndReset(uint256 skipTime_, uint256 expectedClaimedFees_) internal {
    skip(skipTime_);
    address receiver_ = _randomAddress();

    vm.prank(address(manager));
    safetyModule.claimFees(receiver_);
    assertEq(reserveAsset.balanceOf(receiver_), expectedClaimedFees_);

    // Reset reserve pool.
    (uint256 currentAmount_,,,,,,,,,,) = safetyModule.reservePools(0);
    stake(safetyModule, RESERVE_POOL_AMOUNT - currentAmount_, _randomAddress());
  }

  function _testSeveralRewardsDrips(uint256 rate_, uint256[] memory expectedClaimedFees_) internal {
    _setOverrideFeeDripModel(rate_);
    _assertFeeDripAmountAndReset(ONE_YEAR, expectedClaimedFees_[0]);
    _assertFeeDripAmountAndReset(ONE_YEAR / 2, expectedClaimedFees_[1]);
    _assertFeeDripAmountAndReset(ONE_YEAR / 4, expectedClaimedFees_[2]);
    _assertFeeDripAmountAndReset(ONE_YEAR / 10, expectedClaimedFees_[3]);
    _assertFeeDripAmountAndReset(ONE_YEAR / 20, expectedClaimedFees_[4]);
    _assertFeeDripAmountAndReset(0, expectedClaimedFees_[5]);
  }

  function test_FeesDrip50Percent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 250; // 1000 * dripFactor(1 year) ~= 1000 * 0.25 ~= 250
    expectedClaimedRewards_[1] = 133; // 1000 * dripFactor(0.5 years) ~= 1000 * 0.13397459686 ~= 133
    expectedClaimedRewards_[2] = 69; // 1000 * dripFactor(0.25 years) ~= 1000 * 0.06939514124 ~= 69
    expectedClaimedRewards_[3] = 28; // 1000 * dripFactor(0.1 years) ~= 1000 * 0.02835834225 ~= 28
    expectedClaimedRewards_[4] = 14; // 1000 * dripFactor(0.05 years) ~= 1000 * 0.0142811467 ~= 14
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(DEFAULT_DRIP_RATE, expectedClaimedRewards_);
  }

  function test_FeesDripZeroPercent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 0; // 1000 * dripFactor(1 year) = 1000 * 0 = 0
    expectedClaimedRewards_[1] = 0; // 1000 * dripFactor(0.5 years) = 1000 * 0 = 0
    expectedClaimedRewards_[2] = 0; // 1000 * dripFactor(0.25 years) = 1000 * 0 = 0
    expectedClaimedRewards_[3] = 0; // 1000 * dripFactor(0.1 years) = 1000 * 0 = 0
    expectedClaimedRewards_[4] = 0; // 1000 * dripFactor(0.05 years) = 1000 * 0 = 0
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(0, expectedClaimedRewards_);
  }

  function test_FeesDrip100Percent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 1000; // 1000 * dripFactor(1 year) = 1000 * 1 = 1000
    expectedClaimedRewards_[1] = 1000; // 1000 * dripFactor(0.5 years) = 1000 * 1 = 1000
    expectedClaimedRewards_[2] = 1000; // 1000 * dripFactor(0.25 years) = 1000 * 1 = 1000
    expectedClaimedRewards_[3] = 1000; // 1000 * dripFactor(0.1 years) = 1000 * 1 = 1000
    expectedClaimedRewards_[4] = 1000; // 1000 * dripFactor(0.05 years) = 1000 * 1 = 1000
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) = 1000 * 0 = 0
    _testSeveralRewardsDrips(MathConstants.WAD, expectedClaimedRewards_);
  }
}
