// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {DripModelConstant} from "cozy-safety-module-models/DripModelConstant.sol";
import {DripModelExponential} from "cozy-safety-module-models/DripModelExponential.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {UpdateConfigsCalldataParams, ReservePoolConfig} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {TriggerConfig} from "../src/lib/structs/Trigger.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";

abstract contract DripModelIntegrationTestSetup is MockDeployProtocol {
  uint256 internal constant ONE_YEAR = 365.25 days;

  ISafetyModule safetyModule;
  address self = address(this);
  IERC20 reserveAsset;
  address alice = _randomAddress();

  function setUp() public virtual override {
    super.setUp();

    reserveAsset = IERC20(address(new MockERC20("MockReserve", "MOCK", 18)));

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = ReservePoolConfig({maxSlashPercentage: 0, asset: reserveAsset});

    Delays memory delaysConfig_ =
      Delays({withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({
      trigger: ITrigger(address(new MockTrigger(TriggerState.ACTIVE))),
      payoutHandler: _randomAddress(),
      exists: true
    });

    safetyModule = manager.createSafetyModule(
      self,
      self,
      UpdateConfigsCalldataParams({
        reservePoolConfigs: reservePoolConfigs_,
        triggerConfigUpdates: triggerConfig_,
        delaysConfig: delaysConfig_
      }),
      _randomBytes32()
    );
  }

  function deposit(ISafetyModule safetyModule_, uint256 reserveAssetAmount_, address receiver_) internal {
    deal(
      address(reserveAsset),
      address(safetyModule_),
      reserveAsset.balanceOf(address(safetyModule_)) + reserveAssetAmount_
    );
    safetyModule_.depositReserveAssetsWithoutTransfer(0, reserveAssetAmount_, receiver_);
  }
}

contract FeesDripModelExponentialIntegration is DripModelIntegrationTestSetup {
  uint256 internal constant DEFAULT_DRIP_RATE = 9_116_094_774; // 25% annually as a WAD
  uint256 internal constant RESERVE_POOL_AMOUNT = 1000;

  function setUp() public virtual override {
    super.setUp();
    deposit(safetyModule, RESERVE_POOL_AMOUNT, _randomAddress());
  }

  function _setOverrideFeeDripModel(uint256 rate_) internal {
    DripModelExponential feeDripModel_ = new DripModelExponential(rate_);
    vm.prank(address(owner));
    manager.updateOverrideFeeDripModel(safetyModule, IDripModel(address(feeDripModel_)));
  }

  function _assertFeeDripAmountAndReset(uint256 skipTime_, uint256 expectedClaimedFees_) internal {
    skip(skipTime_);
    address receiver_ = _randomAddress();

    IDripModel dripModel_ = manager.getFeeDripModel(safetyModule);
    vm.prank(address(manager));
    safetyModule.claimFees(receiver_, dripModel_);
    assertEq(reserveAsset.balanceOf(receiver_), expectedClaimedFees_);

    // Reset reserve pool.
    uint256 currentAmount_ = safetyModule.reservePools(0).depositAmount;
    if (RESERVE_POOL_AMOUNT - currentAmount_ > 0) {
      deposit(safetyModule, RESERVE_POOL_AMOUNT - currentAmount_, _randomAddress());
    }
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

contract FeesDripModelConstantIntegration is DripModelIntegrationTestSetup {
  uint256 internal constant RESERVE_POOL_AMOUNT = 1000;
  uint256 internal constant DEFAULT_DRIP_RATE = 10; // 10 per second
  uint256 internal constant DEFAULT_DRIP_RATE_INTERVAL = 100 seconds;

  function setUp() public virtual override {
    super.setUp();
    deposit(safetyModule, RESERVE_POOL_AMOUNT, _randomAddress());
  }

  function _setOverrideFeeDripModel(uint256 rate_) internal {
    DripModelConstant feeDripModel_ = new DripModelConstant(_randomAddress(), rate_);
    vm.prank(address(owner));
    manager.updateOverrideFeeDripModel(safetyModule, IDripModel(address(feeDripModel_)));
  }

  function _assertFeeDripAmountAndReset(uint256 skipTime_, uint256 expectedClaimedFees_) internal {
    skip(skipTime_);
    address receiver_ = _randomAddress();

    IDripModel dripModel_ = manager.getFeeDripModel(safetyModule);
    vm.prank(address(manager));
    safetyModule.claimFees(receiver_, dripModel_);
    assertEq(reserveAsset.balanceOf(receiver_), expectedClaimedFees_);

    // Reset reserve pool.
    uint256 currentAmount_ = safetyModule.reservePools(0).depositAmount;
    if (RESERVE_POOL_AMOUNT - currentAmount_ > 0) {
      deposit(safetyModule, RESERVE_POOL_AMOUNT - currentAmount_, _randomAddress());
    }
  }

  function _testSeveralRewardsDrips(uint256 rate_, uint256[] memory expectedClaimedFees_) internal {
    _setOverrideFeeDripModel(rate_);
    _assertFeeDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL, expectedClaimedFees_[0]);
    _assertFeeDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL / 2, expectedClaimedFees_[1]);
    _assertFeeDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL / 4, expectedClaimedFees_[2]);
    _assertFeeDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL / 10, expectedClaimedFees_[3]);
    _assertFeeDripAmountAndReset(DEFAULT_DRIP_RATE_INTERVAL / 20, expectedClaimedFees_[4]);
    _assertFeeDripAmountAndReset(0, expectedClaimedFees_[5]);
  }

  function test_FeesDripOnePercent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 1000; // 1000 * dripFactor(100 seconds) ~= 1000 * 1 ~= 1000
    expectedClaimedRewards_[1] = 500; // 1000 * dripFactor(50 seconds) ~= 1000 * 0.5 ~= 500
    expectedClaimedRewards_[2] = 250; // 1000 * dripFactor(25 seconds) ~= 1000 * 0.25 ~= 250
    expectedClaimedRewards_[3] = 100; // 1000 * dripFactor(10 seconds) ~= 1000 * 0.1 ~= 100
    expectedClaimedRewards_[4] = 50; // 1000 * dripFactor(5 seconds) ~= 1000 * 0.05 ~= 50
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(DEFAULT_DRIP_RATE, expectedClaimedRewards_);
  }

  function test_FeesDripZeroPercent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 0; // 1000 * dripFactor(100 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[1] = 0; // 1000 * dripFactor(50 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[2] = 0; // 1000 * dripFactor(25 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[3] = 0; // 1000 * dripFactor(10 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[4] = 0; // 1000 * dripFactor(5 seconds) = 1000 * 0 = 0
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) ~= 1000 * 0 ~= 0
    _testSeveralRewardsDrips(0, expectedClaimedRewards_);
  }

  function test_FeesDrip100Percent() public {
    uint256[] memory expectedClaimedRewards_ = new uint256[](6);
    expectedClaimedRewards_[0] = 1000; // 1000 * dripFactor(100 seconds) = 1000 * 1 = 1000
    expectedClaimedRewards_[1] = 1000; // 1000 * dripFactor(50 seconds) = 1000 * 1 = 1000
    expectedClaimedRewards_[2] = 1000; // 1000 * dripFactor(25 seconds) = 1000 * 1 = 1000
    expectedClaimedRewards_[3] = 1000; // 1000 * dripFactor(10 seconds) = 1000 * 1 = 1000
    expectedClaimedRewards_[4] = 1000; // 1000 * dripFactor(5 seconds) = 1000 * 1 = 1000
    expectedClaimedRewards_[5] = 0; // 1000 * dripFactor(0) = 1000 * 0 = 0
    _testSeveralRewardsDrips(RESERVE_POOL_AMOUNT, expectedClaimedRewards_);
  }
}
