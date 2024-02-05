// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {ReceiptToken} from "cozy-safety-module-shared/ReceiptToken.sol";
import {ReceiptTokenFactory} from "cozy-safety-module-shared/ReceiptTokenFactory.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {TestBase} from "./utils/TestBase.sol";

contract ReceiptTokenFactoryTest is TestBase {
  ReceiptToken depositReceiptTokenLogic;
  ReceiptToken stkReceiptTokenLogic;
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
    depositReceiptTokenLogic = new ReceiptToken();
    stkReceiptTokenLogic = new ReceiptToken();

    depositReceiptTokenLogic.initialize(address(0), "", "", 0);
    stkReceiptTokenLogic.initialize(address(0), "", "", 0);

    receiptTokenFactory = new ReceiptTokenFactory(
      IReceiptToken(address(depositReceiptTokenLogic)), IReceiptToken(address(stkReceiptTokenLogic))
    );
  }

  function test_deployReceiptTokenFactory() public {
    assertEq(address(receiptTokenFactory.depositReceiptTokenLogic()), address(depositReceiptTokenLogic));
    assertEq(address(receiptTokenFactory.stkReceiptTokenLogic()), address(stkReceiptTokenLogic));
  }

  function test_RevertDeployReceiptTokenFactoryZeroAddressLogicContracts() public {
    vm.expectRevert(ReceiptTokenFactory.InvalidAddress.selector);
    new ReceiptTokenFactory(IReceiptToken(address(0)), IReceiptToken(address(stkReceiptTokenLogic)));

    vm.expectRevert(ReceiptTokenFactory.InvalidAddress.selector);
    new ReceiptTokenFactory(IReceiptToken(address(depositReceiptTokenLogic)), IReceiptToken(address(0)));

    vm.expectRevert(ReceiptTokenFactory.InvalidAddress.selector);
    new ReceiptTokenFactory(IReceiptToken(address(0)), IReceiptToken(address(0)));
  }

  function test_deployDepositReceiptToken() public {
    uint16 poolId_ = _randomUint16();
    uint8 decimals_ = _randomUint8();

    address computedReserveDepositReceiptTokenAddress_ =
      receiptTokenFactory.computeAddress(address(mockSafetyModule), poolId_, IReceiptTokenFactory.PoolType.RESERVE);

    _expectEmit();
    emit ReceiptTokenDeployed(
      IReceiptToken(computedReserveDepositReceiptTokenAddress_),
      mockSafetyModule,
      poolId_,
      IReceiptTokenFactory.PoolType.RESERVE,
      decimals_
    );
    vm.prank(address(mockSafetyModule));
    IReceiptToken reserveDepositReceiptToken_ =
      receiptTokenFactory.deployReceiptToken(poolId_, IReceiptTokenFactory.PoolType.RESERVE, decimals_);

    assertEq(address(reserveDepositReceiptToken_), computedReserveDepositReceiptTokenAddress_);
    assertEq(reserveDepositReceiptToken_.module(), address(mockSafetyModule));
    assertEq(reserveDepositReceiptToken_.name(), "Cozy Reserve Deposit Token");
    assertEq(reserveDepositReceiptToken_.symbol(), "cozyDep");

    address computedRewardDepositReceiptTokenAddress_ =
      receiptTokenFactory.computeAddress(address(mockSafetyModule), poolId_, IReceiptTokenFactory.PoolType.REWARD);

    emit ReceiptTokenDeployed(
      IReceiptToken(computedRewardDepositReceiptTokenAddress_),
      mockSafetyModule,
      poolId_,
      IReceiptTokenFactory.PoolType.REWARD,
      decimals_
    );
    vm.prank(address(mockSafetyModule));
    IReceiptToken rewardDepositReceiptToken_ =
      receiptTokenFactory.deployReceiptToken(poolId_, IReceiptTokenFactory.PoolType.REWARD, decimals_);

    assertEq(address(rewardDepositReceiptToken_), computedRewardDepositReceiptTokenAddress_);
    assertEq(rewardDepositReceiptToken_.module(), address(mockSafetyModule));
    assertEq(rewardDepositReceiptToken_.name(), "Cozy Reward Deposit Token");
    assertEq(rewardDepositReceiptToken_.symbol(), "cozyDep");

    address computedStkTokenAddress_ =
      receiptTokenFactory.computeAddress(address(mockSafetyModule), poolId_, IReceiptTokenFactory.PoolType.STAKE);

    emit ReceiptTokenDeployed(
      IReceiptToken(computedStkTokenAddress_), mockSafetyModule, poolId_, IReceiptTokenFactory.PoolType.STAKE, decimals_
    );
    vm.prank(address(mockSafetyModule));
    IReceiptToken stkToken_ =
      receiptTokenFactory.deployReceiptToken(poolId_, IReceiptTokenFactory.PoolType.STAKE, decimals_);

    assertEq(address(stkToken_), computedStkTokenAddress_);
    assertEq(stkToken_.module(), address(mockSafetyModule));
    assertEq(stkToken_.name(), "Cozy Stake Token");
    assertEq(stkToken_.symbol(), "cozyStk");
  }
}
