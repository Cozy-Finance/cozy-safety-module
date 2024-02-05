// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IReceiptToken} from "../src/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../src/interfaces/IReceiptTokenFactory.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {ReceiptToken} from "../src/ReceiptToken.sol";
import {ReceiptTokenFactory} from "../src/ReceiptTokenFactory.sol";
import {TestBase} from "./utils/TestBase.sol";

contract ReceiptTokenFactoryTest is TestBase {
  ReceiptToken depositTokenLogic;
  ReceiptToken stkTokenLogic;
  ReceiptTokenFactory receiptTokenFactory;

  ISafetyModule mockSafetyModule = ISafetyModule(_randomAddress());

  /// @dev Emitted when a new ReceiptToken is deployed.
  event ReceiptTokenDeployed(
    IReceiptToken receiptToken,
    ISafetyModule indexed safetyModule,
    uint16 indexed reservePoolId,
    IReceiptTokenFactory.PoolType indexed poolType,
    uint8 decimals_
  );

  function setUp() public {
    depositTokenLogic = new ReceiptToken();
    stkTokenLogic = new ReceiptToken();

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
    uint8 decimals_ = _randomUint8();

    address computedReserveDepositTokenAddress_ =
      receiptTokenFactory.computeAddress(mockSafetyModule, poolId_, IReceiptTokenFactory.PoolType.RESERVE);

    _expectEmit();
    emit ReceiptTokenDeployed(
      IReceiptToken(computedReserveDepositTokenAddress_),
      mockSafetyModule,
      poolId_,
      IReceiptTokenFactory.PoolType.RESERVE,
      decimals_
    );
    vm.prank(address(mockSafetyModule));
    IReceiptToken reserveDepositToken_ =
      receiptTokenFactory.deployReceiptToken(poolId_, IReceiptTokenFactory.PoolType.RESERVE, decimals_);

    assertEq(address(reserveDepositToken_), computedReserveDepositTokenAddress_);
    assertEq(address(reserveDepositToken_.safetyModule()), address(mockSafetyModule));
    assertEq(reserveDepositToken_.name(), "Cozy Reserve Deposit Token");
    assertEq(reserveDepositToken_.symbol(), "cozyDep");

    address computedRewardDepositTokenAddress_ =
      receiptTokenFactory.computeAddress(mockSafetyModule, poolId_, IReceiptTokenFactory.PoolType.REWARD);

    emit ReceiptTokenDeployed(
      IReceiptToken(computedRewardDepositTokenAddress_),
      mockSafetyModule,
      poolId_,
      IReceiptTokenFactory.PoolType.REWARD,
      decimals_
    );
    vm.prank(address(mockSafetyModule));
    IReceiptToken rewardDepositToken_ =
      receiptTokenFactory.deployReceiptToken(poolId_, IReceiptTokenFactory.PoolType.REWARD, decimals_);

    assertEq(address(rewardDepositToken_), computedRewardDepositTokenAddress_);
    assertEq(address(rewardDepositToken_.safetyModule()), address(mockSafetyModule));
    assertEq(rewardDepositToken_.name(), "Cozy Reward Deposit Token");
    assertEq(rewardDepositToken_.symbol(), "cozyDep");

    address computedStkTokenAddress_ =
      receiptTokenFactory.computeAddress(mockSafetyModule, poolId_, IReceiptTokenFactory.PoolType.STAKE);

    emit ReceiptTokenDeployed(
      IReceiptToken(computedStkTokenAddress_), mockSafetyModule, poolId_, IReceiptTokenFactory.PoolType.STAKE, decimals_
    );
    vm.prank(address(mockSafetyModule));
    IReceiptToken stkToken_ =
      receiptTokenFactory.deployReceiptToken(poolId_, IReceiptTokenFactory.PoolType.STAKE, decimals_);

    assertEq(address(stkToken_), computedStkTokenAddress_);
    assertEq(address(stkToken_.safetyModule()), address(mockSafetyModule));
    assertEq(stkToken_.name(), "Cozy Stake Token");
    assertEq(stkToken_.symbol(), "cozyStk");
  }
}
