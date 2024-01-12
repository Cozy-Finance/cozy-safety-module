// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../src/interfaces/IReceiptTokenFactory.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ReceiptToken} from "../src/ReceiptToken.sol";
import {ReceiptTokenFactory} from "../src/ReceiptTokenFactory.sol";
import {StkToken} from "../src/StkToken.sol";
import {TestBase} from "./utils/TestBase.sol";

contract ReceiptTokenFactoryTest is TestBase {
  ReceiptToken depositTokenLogic;
  StkToken stkTokenLogic;
  ReceiptTokenFactory receiptTokenFactory;

  ISafetyModule mockSafetyModule = ISafetyModule(_randomAddress());

  function setUp() public {
    depositTokenLogic = new ReceiptToken();
    stkTokenLogic = new StkToken();

    depositTokenLogic.initialize(ISafetyModule(address(0)), "", "", 0);
    stkTokenLogic.initialize(ISafetyModule(address(0)), "", "", 0);

    receiptTokenFactory =
      new ReceiptTokenFactory(IReceiptToken(address(depositTokenLogic)), IReceiptToken(address(stkTokenLogic)));
  }

  function test_deployReceiptTokenFactory() public {
    assertEq(address(receiptTokenFactory.depositTokenLogic()), address(depositTokenLogic));
    assertEq(address(receiptTokenFactory.stkTokenLogic()), address(stkTokenLogic));
  }

  function test_RevertDeployReceiptTokenFactoryZeroAddressLogicContracts() public {
    vm.expectRevert(ReceiptTokenFactory.InvalidAddress.selector);
    new ReceiptTokenFactory(IReceiptToken(address(0)), IReceiptToken(address(stkTokenLogic)));

    vm.expectRevert(ReceiptTokenFactory.InvalidAddress.selector);
    new ReceiptTokenFactory(IReceiptToken(address(depositTokenLogic)), IReceiptToken(address(0)));

    vm.expectRevert(ReceiptTokenFactory.InvalidAddress.selector);
    new ReceiptTokenFactory(IReceiptToken(address(0)), IReceiptToken(address(0)));
  }

  function test_deployDepositToken() public {
    uint16 poolId_ = _randomUint16();
    address computedReserveDepositTokenAddress_ =
      receiptTokenFactory.computeAddress(mockSafetyModule, poolId_, IReceiptTokenFactory.PoolType.RESERVE);
    vm.prank(address(mockSafetyModule));
    IReceiptToken reserveDepositToken_ =
      receiptTokenFactory.deployReceiptToken(poolId_, IReceiptTokenFactory.PoolType.RESERVE, _randomUint8());
    assertEq(address(reserveDepositToken_), computedReserveDepositTokenAddress_);
    assertEq(address(reserveDepositToken_.safetyModule()), address(mockSafetyModule));
    assertEq(reserveDepositToken_.name(), "Cozy Reserve Deposit Token");
    assertEq(reserveDepositToken_.symbol(), "cozyDep");

    address computedRewardDepositTokenAddress_ =
      receiptTokenFactory.computeAddress(mockSafetyModule, poolId_, IReceiptTokenFactory.PoolType.REWARD);
    vm.prank(address(mockSafetyModule));
    IReceiptToken rewardDepositToken_ =
      receiptTokenFactory.deployReceiptToken(poolId_, IReceiptTokenFactory.PoolType.REWARD, _randomUint8());
    assertEq(address(rewardDepositToken_), computedRewardDepositTokenAddress_);
    assertEq(address(rewardDepositToken_.safetyModule()), address(mockSafetyModule));
    assertEq(rewardDepositToken_.name(), "Cozy Reward Deposit Token");
    assertEq(rewardDepositToken_.symbol(), "cozyDep");
  }
}
