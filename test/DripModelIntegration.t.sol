// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {
  UndrippedRewardPoolConfig, UpdateConfigsCalldataParams, ReservePoolConfig
} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {UndrippedRewardPool} from "../src/lib/structs/Pools.sol";
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
    reservePoolConfigs_[0] = ReservePoolConfig({asset: reserveAsset, rewardsPoolsWeight: 10_000});

    UndrippedRewardPoolConfig[] memory undrippedRewardPoolConfigs_ = new UndrippedRewardPoolConfig[](1);
    // Let's set the rewards model drip rate to 25% annually.
    // r = 9116094774 as a WAD
    // At this rate, the dripFactor is:
    //  - 0.13397459686 at 0.5 years
    //  - 0.06939514124 at 0.25 years
    //  - 0.02835834225 at 0.1 years
    //  - 0.0142811467 at 0.05 years
    undrippedRewardPoolConfigs_[0] = UndrippedRewardPoolConfig({
      asset: rewardAsset,
      dripModel: IDripModel(address(new DripModelExponential(9_116_094_774)))
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
            undrippedRewardPoolConfigs: undrippedRewardPoolConfigs_,
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
  function setUp() public virtual override {
    super.setUp();
    depositRewards(safetyModule, 1000, _randomAddress());
    stake(safetyModule, 99, alice);
  }

  function test_skipOneYear() public {
    vm.warp(ONE_YEAR);
    address receiver_ = _randomAddress();

    vm.prank(alice);
    safetyModule.claimRewards(0, receiver_);
    // 1000 * dripFactor(1 year) ~= 1000 * 0.25 ~= 248 (up to rounding down in favor the protocol)
    assertEq(rewardAsset.balanceOf(receiver_), 248);
  }

  function test_skipOneHalfYear() public {
    vm.warp(ONE_YEAR / 2);
    address receiver_ = _randomAddress();

    vm.prank(alice);
    safetyModule.claimRewards(0, receiver_);
    // 1000 * dripFactor(0.5 years) ~= 1000 * 0.13397459686 ~= 132 (up to rounding down in favor the protocol)
    assertEq(rewardAsset.balanceOf(receiver_), 132);
  }

  function test_skipOneFourthYear() public {
    vm.warp(ONE_YEAR / 4);
    address receiver_ = _randomAddress();

    vm.prank(alice);
    safetyModule.claimRewards(0, receiver_);
    // 1000 * dripFactor(0.25 years) ~= 1000 * 0.06939514124 ~= 68 (up to rounding down in favor the protocol)
    assertEq(rewardAsset.balanceOf(receiver_), 68);
  }

  function test_skipOneTenthYear() public {
    vm.warp(ONE_YEAR / 10);
    address receiver_ = _randomAddress();

    vm.prank(alice);
    safetyModule.claimRewards(0, receiver_);
    // 1000 * dripFactor(0.1 years) ~= 1000 * 0.02835834225 ~= 27 (up to rounding down in favor the protocol)
    assertEq(rewardAsset.balanceOf(receiver_), 27);
  }

  function test_skipOneTwentiethYear() public {
    vm.warp(ONE_YEAR / 20);
    address receiver_ = _randomAddress();

    vm.prank(alice);
    safetyModule.claimRewards(0, receiver_);
    // 1000 * dripFactor(0.05 years) ~= 1000 * 0.0142811467 ~= 13 (up to rounding down in favor the protocol)
    assertEq(rewardAsset.balanceOf(receiver_), 13);
  }
}

contract FeesDripModelIntegration is DripModelIntegrationTestSetup {
  function setUp() public virtual override {
    super.setUp();

    // Set the fee drip model to a constant drip rate of 25% annually.
    DripModelExponential feeDripModel_ = new DripModelExponential(9_116_094_774);
    vm.prank(address(owner));
    manager.updateOverrideFeeDripModel(ISafetyModule(address(safetyModule)), IDripModel(address(feeDripModel_)));

    stake(safetyModule, 1000, alice);
  }

  function test_skipOneYear() public {
    vm.warp(ONE_YEAR);
    address receiver_ = _randomAddress();

    vm.prank(address(manager));
    safetyModule.claimFees(receiver_);
    // 1000 * dripFactor(1 year) ~= 1000 * 0.25 ~= 249 (up to rounding down in favor the protocol)
    assertEq(reserveAsset.balanceOf(receiver_), 249);
  }

  function test_skipOneHalfYear() public {
    vm.warp(ONE_YEAR / 2);
    address receiver_ = _randomAddress();

    vm.prank(address(manager));
    safetyModule.claimFees(receiver_);
    // 1000 * dripFactor(0.5 years) ~= 1000 * 0.13397459686 ~= 133 (up to rounding down in favor the protocol)
    assertEq(reserveAsset.balanceOf(receiver_), 133);
  }

  function test_skipOneFourthYear() public {
    vm.warp(ONE_YEAR / 4);
    address receiver_ = _randomAddress();

    vm.prank(address(manager));
    safetyModule.claimFees(receiver_);
    // 1000 * dripFactor(0.25 years) ~= 1000 * 0.06939514124 ~= 69 (up to rounding down in favor the protocol)
    assertEq(reserveAsset.balanceOf(receiver_), 69);
  }

  function test_skipOneTenthYear() public {
    vm.warp(ONE_YEAR / 10);
    address receiver_ = _randomAddress();

    vm.prank(address(manager));
    safetyModule.claimFees(receiver_);
    // 1000 * dripFactor(0.1 years) ~= 1000 * 0.02835834225 ~= 28 (up to rounding down in favor the protocol)
    assertEq(reserveAsset.balanceOf(receiver_), 28);
  }

  function test_skipOneTwentiethYear() public {
    vm.warp(ONE_YEAR / 20);
    address receiver_ = _randomAddress();

    vm.prank(address(manager));
    safetyModule.claimFees(receiver_);
    // 1000 * dripFactor(0.05 years) ~= 1000 * 0.0142811467 ~= 14 (up to rounding down in favor the protocol)
    assertEq(reserveAsset.balanceOf(receiver_), 14);
  }
}
