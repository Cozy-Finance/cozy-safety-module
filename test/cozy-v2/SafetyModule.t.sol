// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
import {Ownable} from "../../src/lib/Ownable.sol";
import {SafetyModule} from "../../src/cozy-v2/SafetyModule.sol";
import {TestBase} from "../utils/TestBase.sol";

contract TestSafetyModule is TestBase {
  SafetyModule safetyModule;

  address owner;
  address trigger;

  MockERC20 tokenA = new MockERC20('TestA', 'TESTA', 6);
  MockERC20 tokenB = new MockERC20('TestB', 'TESTB', 18);

  function setUp() public {
    owner = _randomAddress();
    trigger = _randomAddress();

    safetyModule = new SafetyModule();
    safetyModule.initialize(owner, trigger);
  }

  function _triggerSafetyModule() internal {
    vm.prank(trigger);
    safetyModule.triggerSafetyModule();
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

  function test_withdraw() public {
    address receiver_ = _randomAddress();
    uint256 depositAmount_ = 1000e6;

    // The safety module owns some tokens
    tokenA.mint(address(safetyModule), depositAmount_);

    // Safety module becomes triggered
    _triggerSafetyModule();

    // Owner withdraws tokens from the safety module
    SafetyModule.WithdrawData[] memory withdrawData_ = new SafetyModule.WithdrawData[](1);
    withdrawData_[0] =
      SafetyModule.WithdrawData({token: IERC20(address(tokenA)), receiver: receiver_, amount: depositAmount_});
    vm.prank(owner);
    safetyModule.withdraw(withdrawData_);

    // Tokens are transfered to the receiver
    assertEq(tokenA.balanceOf(address(safetyModule)), 0);
    assertEq(tokenA.balanceOf(receiver_), depositAmount_);
  }

  function test_withdrawTokenMultipleTimes() public {
    address receiver_ = _randomAddress();
    uint256 depositAmount_ = 1000e6;

    // The safety module owns some tokens
    tokenA.mint(address(safetyModule), depositAmount_);

    // Safety module becomes triggered
    _triggerSafetyModule();

    // Owner withdraws half of the tokens from the safety module
    SafetyModule.WithdrawData[] memory withdrawData_ = new SafetyModule.WithdrawData[](1);
    withdrawData_[0] =
      SafetyModule.WithdrawData({token: IERC20(address(tokenA)), receiver: receiver_, amount: depositAmount_ / 2});
    vm.prank(owner);
    safetyModule.withdraw(withdrawData_);

    // Half of the tokens are transfered to the receiver
    assertEq(tokenA.balanceOf(address(safetyModule)), depositAmount_ / 2);
    assertEq(tokenA.balanceOf(receiver_), depositAmount_ / 2);

    // Owner withdraws remaining tokens from the safety module
    vm.prank(owner);
    safetyModule.withdraw(withdrawData_);

    // The tokens are transfered to the receiver
    assertEq(tokenA.balanceOf(address(safetyModule)), 0);
    assertEq(tokenA.balanceOf(receiver_), depositAmount_);
  }

  function test_withdrawMultipleTokens() public {
    address receiver_ = _randomAddress();
    uint256 depositAmountA_ = 1000e6;
    uint256 depositAmountB_ = 500e18;

    // The safety module owns some tokens
    tokenA.mint(address(safetyModule), depositAmountA_);
    tokenB.mint(address(safetyModule), depositAmountB_);

    // Safety module becomes triggered
    _triggerSafetyModule();

    // Owner withdraws the tokens from the safety module
    SafetyModule.WithdrawData[] memory withdrawData_ = new SafetyModule.WithdrawData[](2);
    withdrawData_[0] =
      SafetyModule.WithdrawData({token: IERC20(address(tokenA)), receiver: receiver_, amount: depositAmountA_});
    withdrawData_[1] =
      SafetyModule.WithdrawData({token: IERC20(address(tokenB)), receiver: receiver_, amount: depositAmountB_});
    vm.prank(owner);
    safetyModule.withdraw(withdrawData_);

    // The tokens are transfered to the receiver
    assertEq(tokenA.balanceOf(address(safetyModule)), 0);
    assertEq(tokenB.balanceOf(address(safetyModule)), 0);
    assertEq(tokenA.balanceOf(receiver_), depositAmountA_);
    assertEq(tokenB.balanceOf(receiver_), depositAmountB_);
  }

  function test_withdrawMultipleTokensMultipleTimes() public {
    address receiver_ = _randomAddress();
    uint256 depositAmountA_ = 1000e6;
    uint256 depositAmountB_ = 500e18;

    // The safety module owns some tokens
    tokenA.mint(address(safetyModule), depositAmountA_);
    tokenB.mint(address(safetyModule), depositAmountB_);

    // Safety module becomes triggered
    _triggerSafetyModule();

    // Owner withdraws the tokens from the safety module
    SafetyModule.WithdrawData[] memory withdrawData_ = new SafetyModule.WithdrawData[](2);
    withdrawData_[0] =
      SafetyModule.WithdrawData({token: IERC20(address(tokenA)), receiver: receiver_, amount: depositAmountA_ / 2});
    withdrawData_[1] =
      SafetyModule.WithdrawData({token: IERC20(address(tokenB)), receiver: receiver_, amount: depositAmountB_ / 2});
    vm.prank(owner);
    safetyModule.withdraw(withdrawData_);

    // Half of the tokens are transfered to the receiver
    assertEq(tokenA.balanceOf(address(safetyModule)), depositAmountA_ / 2);
    assertEq(tokenB.balanceOf(address(safetyModule)), depositAmountB_ / 2);
    assertEq(tokenA.balanceOf(receiver_), depositAmountA_ / 2);
    assertEq(tokenB.balanceOf(receiver_), depositAmountB_ / 2);

    vm.prank(owner);
    safetyModule.withdraw(withdrawData_);

    // The remaining tokens are transfered to the receiver
    assertEq(tokenA.balanceOf(address(safetyModule)), 0);
    assertEq(tokenB.balanceOf(address(safetyModule)), 0);
    assertEq(tokenA.balanceOf(receiver_), depositAmountA_);
    assertEq(tokenB.balanceOf(receiver_), depositAmountB_);
  }

  function test_withdrawETH() public {
    address receiver_ = _randomAddress();
    uint256 depositAmount_ = 500e18;

    // The safety module owns some ETH
    vm.deal(address(safetyModule), depositAmount_);

    // Safety module becomes triggered
    _triggerSafetyModule();

    vm.prank(owner);
    safetyModule.withdrawETH(receiver_, depositAmount_);
    assertEq(receiver_.balance, depositAmount_);
    assertEq(address(safetyModule).balance, 0);
  }

  function test_withdrawETHMultipleTimes() public {
    address receiver_ = _randomAddress();
    uint256 depositAmount_ = 500e18;

    // The safety module owns some ETH
    vm.deal(address(safetyModule), depositAmount_);

    // Safety module becomes triggered
    _triggerSafetyModule();

    // Withdraw half of the ETH
    vm.prank(owner);
    safetyModule.withdrawETH(receiver_, depositAmount_ / 2);
    assertEq(receiver_.balance, depositAmount_ / 2);
    assertEq(address(safetyModule).balance, depositAmount_ / 2);

    // Withdraw the remaining ETH
    vm.prank(owner);
    safetyModule.withdrawETH(receiver_, depositAmount_ / 2);
    assertEq(receiver_.balance, depositAmount_);
    assertEq(address(safetyModule).balance, 0);
  }

  function testFuzz_RevertWithdrawUnauthorized(address caller_) public {
    vm.assume(caller_ != owner);
    address receiver_ = _randomAddress();
    uint256 depositAmount_ = 1000e6;

    // The safety module owns some tokens
    tokenA.mint(address(safetyModule), depositAmount_);

    // Safety module becomes triggered
    _triggerSafetyModule();

    SafetyModule.WithdrawData[] memory withdrawData_ = new SafetyModule.WithdrawData[](1);
    withdrawData_[0] =
      SafetyModule.WithdrawData({token: IERC20(address(tokenA)), receiver: receiver_, amount: depositAmount_ / 2});

    // Withdraw failes, caller is unauthorized
    vm.prank(caller_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    safetyModule.withdraw(withdrawData_);
  }

  function testFuzz_RevertWithdrawInvalidState() public {
    address receiver_ = _randomAddress();
    uint256 depositAmount_ = 1000e6;

    // The safety module owns some tokens
    tokenA.mint(address(safetyModule), depositAmount_);

    SafetyModule.WithdrawData[] memory withdrawData_ = new SafetyModule.WithdrawData[](1);
    withdrawData_[0] =
      SafetyModule.WithdrawData({token: IERC20(address(tokenA)), receiver: receiver_, amount: depositAmount_ / 2});

    // Withdraw fails, safety module is not triggered
    vm.prank(owner);
    vm.expectRevert(SafetyModule.InvalidState.selector);
    safetyModule.withdraw(withdrawData_);
  }

  function testFuzz_RevertWithdrawETHUnauthorized(address caller_) public {
    vm.assume(caller_ != owner);
    address receiver_ = _randomAddress();
    uint256 depositAmount_ = 1000e18;

    // The safety module owns some ETH
    vm.deal(address(safetyModule), depositAmount_);

    // Safety module becomes triggered
    _triggerSafetyModule();

    // Withdraw is unauthorized
    vm.prank(caller_);
    vm.expectRevert(Ownable.Unauthorized.selector);
    safetyModule.withdrawETH(receiver_, depositAmount_);
  }

  function testFuzz_RevertWithdrawETHInvalidState() public {
    address receiver_ = _randomAddress();
    uint256 depositAmount_ = 1000e6;

    // The safety module owns some ETH
    vm.deal(address(safetyModule), depositAmount_);

    // Withdraw failes, safety module is not triggered
    vm.prank(owner);
    vm.expectRevert(SafetyModule.InvalidState.selector);
    safetyModule.withdrawETH(receiver_, depositAmount_);
  }
}

contract TestSafetyModuleForkTest is TestBase {
  uint256 optimismForkBlock = 112800342;

  // Dogfood safety module deployed on Optimism
  SafetyModule safetyModule = SafetyModule(0xEeA665DCA17b65124B955FBA9BF6dFF9e0eE5358);

  // Cozy owned 2/3 multisig
  address owner = 0xbD1051d14E40BD7AeAc21892eDaD9bafC6352D72;

  MockERC20 token;

  function setUp() public {
    vm.createSelectFork(vm.envString("OPTIMISM_RPC_URL"), optimismForkBlock);
    token = new MockERC20('Test', 'TEST', 6);
  }

  function test_triggerAndWithdraw() public {
    address receiver_ = owner;
    uint256 depositAmount_ = 1000e6;

    // The safety module owns some tokens
    token.mint(address(safetyModule), depositAmount_);
    assertEq(token.balanceOf(receiver_), 0);

    // Trigger the safety module
    vm.prank(owner);
    safetyModule.triggerSafetyModule();

    // Owner withdraws tokens from the safety module
    SafetyModule.WithdrawData[] memory withdrawData_ = new SafetyModule.WithdrawData[](1);
    withdrawData_[0] =
      SafetyModule.WithdrawData({token: IERC20(address(token)), receiver: receiver_, amount: depositAmount_});
    vm.prank(owner);
    safetyModule.withdraw(withdrawData_);

    // Tokens are transfered to the receiver
    assertEq(token.balanceOf(address(safetyModule)), 0);
    assertEq(token.balanceOf(receiver_), depositAmount_);
  }
}
