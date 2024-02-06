// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {UpdateConfigsCalldataParams, ReservePoolConfig} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {TriggerConfig} from "../src/lib/structs/Trigger.sol";
import {Manager} from "../src/Manager.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {SafetyModuleState, TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {IManagerEvents} from "../src/interfaces/IManagerEvents.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {TestBase} from "./utils/TestBase.sol";

abstract contract ManagerTestSetup is TestBase {
  function _defaultSetUp() internal returns (UpdateConfigsCalldataParams memory updateConfigsCalldataParams_) {
    IERC20 asset_ = IERC20(address(new MockERC20("MockAsset", "MOCK", 18)));

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] = ReservePoolConfig({maxSlashPercentage: 0, asset: asset_});

    TriggerConfig[] memory triggerConfigUpdates_ = new TriggerConfig[](1);
    triggerConfigUpdates_[0] =
      TriggerConfig({trigger: new MockTrigger(TriggerState.ACTIVE), exists: true, payoutHandler: address(0xFEEB)});

    Delays memory delaysConfig_ =
      Delays({withdrawDelay: 1 days, configUpdateDelay: 10 days, configUpdateGracePeriod: 1 days});

    updateConfigsCalldataParams_ = UpdateConfigsCalldataParams({
      reservePoolConfigs: reservePoolConfigs_,
      triggerConfigUpdates: triggerConfigUpdates_,
      delaysConfig: delaysConfig_
    });
  }
}

contract ManagerTestSetupWithSafetyModules is MockDeployProtocol, ManagerTestSetup {
  ISafetyModule[] safetyModules;

  ISafetyModule safetyModuleA;
  ISafetyModule safetyModuleB;

  MockERC20 mockAsset;
  IERC20 asset;

  function setUp() public virtual override {
    super.setUp();
    mockAsset = new MockERC20("Mock Asset", "MOCK", 6);
    asset = IERC20(address(mockAsset));
    UpdateConfigsCalldataParams memory updateConfigsCalldataParams_ = _defaultSetUp();
    updateConfigsCalldataParams_.reservePoolConfigs[0].asset = asset;
    safetyModuleA =
      manager.createSafetyModule(_randomAddress(), _randomAddress(), updateConfigsCalldataParams_, _randomBytes32());
    safetyModuleB =
      manager.createSafetyModule(_randomAddress(), _randomAddress(), updateConfigsCalldataParams_, _randomBytes32());
    safetyModules.push(safetyModuleA);
    safetyModules.push(safetyModuleB);
  }
}

contract ManagerTestCreateSafetyModule is MockDeployProtocol, ManagerTestSetup {
  function test_createSafetyModule() public {
    UpdateConfigsCalldataParams memory updateConfigsCalldataParams_ = _defaultSetUp();
    ISafetyModule safetyModule_ =
      manager.createSafetyModule(_randomAddress(), _randomAddress(), updateConfigsCalldataParams_, _randomBytes32());
    assertEq(manager.isSafetyModule(safetyModule_), true);
  }

  function test_createSafetyModule_revertInvalidOwnerAddress() public {
    UpdateConfigsCalldataParams memory updateConfigsCalldataParams_ = _defaultSetUp();

    vm.expectRevert(Ownable.InvalidAddress.selector);
    manager.createSafetyModule(address(0), _randomAddress(), updateConfigsCalldataParams_, _randomBytes32());
  }

  function test_createSafetyModule_revertInvalidPauserAddress() public {
    UpdateConfigsCalldataParams memory updateConfigsCalldataParams_ = _defaultSetUp();

    vm.expectRevert(Ownable.InvalidAddress.selector);
    manager.createSafetyModule(_randomAddress(), address(0), updateConfigsCalldataParams_, _randomBytes32());
  }

  function test_createSafetyModule_revertInvalidDelays() public {
    UpdateConfigsCalldataParams memory updateConfigsCalldataParams_ = _defaultSetUp();
    updateConfigsCalldataParams_.delaysConfig =
      Delays({withdrawDelay: 2 days, configUpdateDelay: 1 days, configUpdateGracePeriod: 1 days});

    vm.expectRevert(Manager.InvalidConfiguration.selector);
    manager.createSafetyModule(_randomAddress(), _randomAddress(), updateConfigsCalldataParams_, _randomBytes32());
  }

  function test_createSafetyModule_revertTooManyReservePools() public {
    UpdateConfigsCalldataParams memory updateConfigsCalldataParams_ = _defaultSetUp();

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](ALLOWED_RESERVE_POOLS + 1);
    for (uint256 i = 0; i < ALLOWED_RESERVE_POOLS + 1; i++) {
      reservePoolConfigs_[i] = ReservePoolConfig({
        maxSlashPercentage: MathConstants.WAD,
        asset: IERC20(address(new MockERC20("MockAsset", "MOCK", 18)))
      });
    }
    updateConfigsCalldataParams_.reservePoolConfigs = reservePoolConfigs_;

    vm.expectRevert(Manager.InvalidConfiguration.selector);
    manager.createSafetyModule(_randomAddress(), _randomAddress(), updateConfigsCalldataParams_, _randomBytes32());
  }

  function test_createSafetyModule_revertInvalidMaxSlashPercentage() public {
    UpdateConfigsCalldataParams memory updateConfigsCalldataParams_ = _defaultSetUp();
    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](1);
    reservePoolConfigs_[0] =
      ReservePoolConfig({maxSlashPercentage: 1e18 + 1, asset: updateConfigsCalldataParams_.reservePoolConfigs[0].asset});
    updateConfigsCalldataParams_.reservePoolConfigs = reservePoolConfigs_;

    vm.expectRevert(Manager.InvalidConfiguration.selector);
    manager.createSafetyModule(_randomAddress(), _randomAddress(), updateConfigsCalldataParams_, _randomBytes32());
  }
}

contract ManagerTestDeploy is MockDeployProtocol {
  function test_governableOwnable() public {
    assertEq(manager.owner(), owner);
    assertEq(manager.pauser(), pauser);
  }

  function test_factoryAddress() public {
    assertEq(address(manager.safetyModuleFactory()), address(safetyModuleFactory));
  }

  function test_feeDripModel() public {
    assertEq(address(manager.feeDripModel()), address(feeDripModel));
  }

  function test_allowedReservePools() public {
    assertEq(manager.allowedReservePools(), ALLOWED_RESERVE_POOLS);
  }
}

contract ManagerUpdateFeeModels is MockDeployProtocol {
  function test_updateFeeDripModel_revertNonOwnerAddress() public {
    IDripModel feeDripModel_ = IDripModel(_randomAddress());

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    manager.updateFeeDripModel(feeDripModel_);
  }

  function test_updateOverrideFeeDripModel_revertNonOwnerAddress() public {
    IDripModel feeDripModel_ = IDripModel(_randomAddress());
    ISafetyModule safetyModule_ = ISafetyModule(_randomAddress());

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    manager.updateOverrideFeeDripModel(safetyModule_, feeDripModel_);
  }

  function test_resetOverrideFeeDripModel_revertNonOwnerAddress() public {
    ISafetyModule safetyModule_ = ISafetyModule(_randomAddress());

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(_randomAddress());
    manager.resetOverrideFeeDripModel(safetyModule_);
  }

  function testFuzz_updateFeeDripModel(address feeDripModelAddress_) public {
    IDripModel feeDripModel_ = IDripModel(feeDripModelAddress_);

    _expectEmit();
    emit IManagerEvents.FeeDripModelUpdated(feeDripModel_);
    vm.prank(owner);
    manager.updateFeeDripModel(feeDripModel_);
    assertEq(address(manager.feeDripModel()), address(feeDripModel_));
  }

  function testFuzz_updateOverrideFeeDripModel(address feeDripModelAddress_, address safetyModuleAddress_) public {
    IDripModel feeDripModel_ = IDripModel(feeDripModelAddress_);
    ISafetyModule safetyModule_ = ISafetyModule(safetyModuleAddress_);

    assertEq(address(manager.feeDripModel()), address(feeDripModel));
    assertEq(address(manager.getFeeDripModel(safetyModule_)), address(manager.feeDripModel()));

    _expectEmit();
    emit IManagerEvents.OverrideFeeDripModelUpdated(safetyModule_, feeDripModel_);
    vm.prank(owner);
    manager.updateOverrideFeeDripModel(safetyModule_, feeDripModel_);

    assertEq(address(manager.getFeeDripModel(safetyModule_)), address(feeDripModel_));
  }

  function testFuzz_resetOverrideFeeDripModel(
    address feeDripModelAddress_,
    address newDefaultFeeDripModelAddress_,
    address safetyModuleAddress_
  ) public {
    IDripModel feeDripModel_ = IDripModel(feeDripModelAddress_);
    ISafetyModule safetyModule_ = ISafetyModule(safetyModuleAddress_);

    vm.prank(owner);
    manager.updateOverrideFeeDripModel(safetyModule_, feeDripModel_);
    assertEq(address(manager.getFeeDripModel(safetyModule_)), address(feeDripModel_));

    _expectEmit();
    emit IManagerEvents.OverrideFeeDripModelUpdated(safetyModule_, manager.feeDripModel());
    vm.prank(owner);
    manager.resetOverrideFeeDripModel(safetyModule_);
    assertEq(address(manager.getFeeDripModel(safetyModule_)), address(manager.feeDripModel()));

    IDripModel newDefaultFeeDripModel_ = IDripModel(newDefaultFeeDripModelAddress_);
    vm.prank(owner);
    manager.updateFeeDripModel(newDefaultFeeDripModel_);
    assertEq(address(manager.getFeeDripModel(safetyModule_)), address(newDefaultFeeDripModel_));
  }

  function testFuzz_getFeeDripModel(
    address feeDripModelAddress_,
    address safetyModuleAddress_,
    address otherSafetyModuleAddress_
  ) public {
    vm.assume(safetyModuleAddress_ != otherSafetyModuleAddress_);

    IDripModel feeDripModel_ = IDripModel(feeDripModelAddress_);
    ISafetyModule safetyModule_ = ISafetyModule(safetyModuleAddress_);
    ISafetyModule otherSafetyModule_ = ISafetyModule(otherSafetyModuleAddress_);

    vm.prank(owner);
    manager.updateOverrideFeeDripModel(safetyModule_, feeDripModel_);

    assertEq(address(manager.getFeeDripModel(safetyModule_)), address(feeDripModel_));
    assertEq(address(manager.getFeeDripModel(otherSafetyModule_)), address(manager.feeDripModel()));
  }
}

contract ManagerClaimFeesTest is ManagerTestSetupWithSafetyModules {
  event ClaimedFees(IERC20 indexed reserveAsset_, uint256 feeAmount_, address indexed owner_);

  function test_managerClaimFees() public {
    // Arbitrary amounts.
    uint128 depositAmountA_ = 1_000_000;
    uint128 depositAmountB_ = 2_000_000;
    mockAsset.mint(address(safetyModuleA), depositAmountA_);
    mockAsset.mint(address(safetyModuleB), depositAmountB_);
    SafetyModule(address(safetyModuleA)).depositReserveAssetsWithoutTransfer(0, depositAmountA_, _randomAddress());
    SafetyModule(address(safetyModuleB)).depositReserveAssetsWithoutTransfer(0, depositAmountB_, _randomAddress());

    skip(1);

    _expectEmit();
    emit ClaimedFees(asset, depositAmountA_ / 2, owner); // Drip model drips 50% each time.
    _expectEmit();
    emit IManagerEvents.ClaimedSafetyModuleFees(safetyModuleA);
    _expectEmit();
    emit ClaimedFees(asset, depositAmountB_ / 2, owner);
    _expectEmit();
    emit IManagerEvents.ClaimedSafetyModuleFees(safetyModuleB);

    vm.prank(_randomAddress()); // Anyone can call this function on behalf of the manager's owner.
    manager.claimFees(safetyModules);
  }
}

contract ManagerPauseTest is ManagerTestSetupWithSafetyModules {
  function test_pauseSafetyModuleArrayFromOwner() public {
    vm.prank(owner);
    manager.pause(safetyModules);

    assertEq(SafetyModuleState.PAUSED, SafetyModule(address(safetyModuleA)).safetyModuleState());
    assertEq(SafetyModuleState.PAUSED, SafetyModule(address(safetyModuleB)).safetyModuleState());
  }

  function test_pauseSafetyModuleArrayFromPauser() public {
    vm.prank(pauser);
    manager.pause(safetyModules);

    assertEq(SafetyModuleState.PAUSED, SafetyModule(address(safetyModuleA)).safetyModuleState());
    assertEq(SafetyModuleState.PAUSED, SafetyModule(address(safetyModuleB)).safetyModuleState());
  }

  function testFuzz_pauseSafetyModuleArrayRevertsWithUnauthorized(address addr_) public {
    vm.assume(addr_ != owner && addr_ != pauser);
    vm.prank(addr_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    manager.pause(safetyModules);

    assertEq(SafetyModuleState.ACTIVE, SafetyModule(address(safetyModuleA)).safetyModuleState());
    assertEq(SafetyModuleState.ACTIVE, SafetyModule(address(safetyModuleB)).safetyModuleState());
  }
}

contract ManagerUnpauseSet is ManagerTestSetupWithSafetyModules {
  function setUp() public override {
    super.setUp();
    vm.prank(owner);
    manager.pause(safetyModules);
  }

  function test_unpauseSafetyModuleArrayFromOwner() public {
    vm.prank(owner);
    manager.unpause(safetyModules);

    assertEq(SafetyModuleState.ACTIVE, SafetyModule(address(safetyModuleA)).safetyModuleState());
    assertEq(SafetyModuleState.ACTIVE, SafetyModule(address(safetyModuleB)).safetyModuleState());
  }

  function test_unpauseSafetyModuleArrayFromPauser() public {
    vm.prank(pauser);
    vm.expectRevert(Ownable.Unauthorized.selector);
    manager.unpause(safetyModules);

    assertEq(SafetyModuleState.PAUSED, SafetyModule(address(safetyModuleA)).safetyModuleState());
    assertEq(SafetyModuleState.PAUSED, SafetyModule(address(safetyModuleB)).safetyModuleState());
  }

  function testFuzz_unpauseSafetyModuleArrayRevertsWithUnauthorized(address addr_) public {
    vm.assume(addr_ != owner);
    vm.prank(addr_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    manager.unpause(safetyModules);

    assertEq(SafetyModuleState.PAUSED, SafetyModule(address(safetyModuleA)).safetyModuleState());
    assertEq(SafetyModuleState.PAUSED, SafetyModule(address(safetyModuleB)).safetyModuleState());
  }
}
