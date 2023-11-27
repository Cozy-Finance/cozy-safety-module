// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Ownable} from "../../src/lib/Ownable.sol";
import {SafetyModule} from "../../src/cozy-v2/SafetyModule.sol";
import {TestBase} from "../utils/TestBase.sol";

contract TestSafetyModule is TestBase {
  SafetyModule safetyModule;

  address owner;
  address trigger;

  function setUp() public {
    owner = _randomAddress();
    trigger = _randomAddress();

    safetyModule = new SafetyModule();
    safetyModule.initialize(owner, trigger);
  }

  function test_initialize() public {
    safetyModule = new SafetyModule();
    safetyModule.initialize(owner, trigger);

    assertEq(safetyModule.owner(), owner);
    assertEq(safetyModule.trigger(), trigger);
  }

  function test_ReverInitialized() public {
    vm.expectRevert(SafetyModule.Initialized.selector);
    safetyModule.initialize(_randomAddress(), _randomAddress());
  }

  function test_triggerSafetyModule() public {
    assertFalse(safetyModule.isTriggered());

    vm.prank(trigger);
    _expectEmit();
    emit SafetyModule.Triggered();
    safetyModule.triggerSafetyModule();

    assertTrue(safetyModule.isTriggered());
  }

  function testFuzz_RevertTriggerSafetyModuleUnauthorized(address caller_) public {
    vm.assume(caller_ != trigger);
    assertFalse(safetyModule.isTriggered());

    vm.prank(caller_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    safetyModule.triggerSafetyModule();
  }
}
