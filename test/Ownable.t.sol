// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Ownable} from "../src/lib/Ownable.sol";
import {TestBase} from "./utils/TestBase.sol";

contract OwnableHarness is Ownable {
  function initOwnable(address owner_) external {
    __initOwnable(owner_);
  }
}

contract OwnableTestSetup is TestBase {
  OwnableHarness ownableHarness;

  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

  function setUp() public virtual {
    ownableHarness = new OwnableHarness();
  }
}

contract OwnableConstructorTest is OwnableTestSetup {
  function test_OwnableConstructor() public {
    assertEq(ownableHarness.owner(), address(0));
  }

  function test_OwnableInit() public {
    address newOwner_ = _randomAddress();
    _expectEmit();
    emit OwnershipTransferred(address(0), newOwner_);
    ownableHarness.initOwnable(newOwner_);
  }
}

contract OwnableInitializedTest is OwnableTestSetup {
  address owner = address(this);

  function setUp() public override {
    super.setUp();
    ownableHarness.initOwnable(owner);
  }

  function test_TransferOwnership() public {
    address newOwner_ = _randomAddress();
    _expectEmit();
    emit OwnershipTransferStarted(owner, newOwner_);
    vm.prank(owner);
    ownableHarness.transferOwnership(newOwner_);

    // Owner is not updated yet, but the pending owner is.
    assertEq(ownableHarness.pendingOwner(), newOwner_);
    assertEq(ownableHarness.owner(), owner);

    _expectEmit();
    emit OwnershipTransferred(owner, newOwner_);
    vm.prank(newOwner_);
    ownableHarness.acceptOwnership();

    // Owner is updated, and the pending owner is reset.
    assertEq(ownableHarness.pendingOwner(), address(0));
    assertEq(ownableHarness.owner(), newOwner_);
  }

  function test_TransferOwnershipUnauthorized() public {
    address newOwner_ = _randomAddress();
    address caller_ = _randomAddress();

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(caller_);
    ownableHarness.transferOwnership(newOwner_);
  }

  function test_TransferOwnershipRevertsIfNewOwnerIsZeroAddress() public {
    vm.prank(owner);
    vm.expectRevert(Ownable.InvalidAddress.selector);
    ownableHarness.transferOwnership(address(0));
  }

  function test_AcceptOwnershipUnauthorized() public {
    address newOwner_ = _randomAddress();
    address caller_ = _randomAddress();

    _expectEmit();
    emit OwnershipTransferStarted(owner, newOwner_);
    vm.prank(owner);
    ownableHarness.transferOwnership(newOwner_);

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(caller_);
    ownableHarness.acceptOwnership();
  }
}
