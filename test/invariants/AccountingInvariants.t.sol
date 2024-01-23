// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {InvariantTestBase, InvariantTestWithSingleReservePoolAndSingleRewardPool} from "./utils/InvariantTestBase.sol";

abstract contract AccountingInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  function invariant_reserveDepositAmountGtePendingRedemptionAmounts() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory reservePool_ = getReservePool(safetyModule, reservePoolId_);

      require(
        reservePool_.depositAmount >= reservePool_.pendingWithdrawalsAmount,
        string.concat(
          "Invariant Violated: A reserve pool's deposit amount must be greater than or equal to its pending withdrawals amount.",
          " reservePoolId_: ",
          Strings.toString(reservePoolId_),
          ", reservePool_.depositAmount: ",
          Strings.toString(reservePool_.depositAmount),
          ", reservePool_.pendingWithdrawalsAmount: ",
          Strings.toString(reservePool_.pendingWithdrawalsAmount)
        )
      );

      require(
        reservePool_.stakeAmount >= reservePool_.pendingUnstakesAmount,
        string.concat(
          "Invariant Violated: A reserve pool's stake amount must be greater than or equal to its pending unstakes amount.",
          " reservePoolId_: ",
          Strings.toString(reservePoolId_),
          ", reservePool_.depositAmount: ",
          Strings.toString(reservePool_.stakeAmount),
          ", reservePool_.pendingUnstakesAmount: ",
          Strings.toString(reservePool_.pendingUnstakesAmount)
        )
      );
    }
  }
}

contract AccountingInvariantsSingleReservePoolSingleRewardPool is
  AccountingInvariants,
  InvariantTestWithSingleReservePoolAndSingleRewardPool
{}
