// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleReservePoolAndSingleRewardPool,
  InvariantTestWithMultipleReservePoolsAndMultipleRewardPools
} from "./utils/InvariantTestBase.sol";

abstract contract FeesInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  function invariant_dripFeesAccounting() public syncCurrentTimestamp(safetyModuleHandler) {
    // Can't drip fees if the safety module is not active.
    if (safetyModule.safetyModuleState() != SafetyModuleState.ACTIVE) return;

    ReservePool[] memory beforeReservePools_ = new ReservePool[](numReservePools);
    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      beforeReservePools_[reservePoolId_] = getReservePool(safetyModule, reservePoolId_);
    }

    safetyModuleHandler.dripFees(_randomAddress(), _randomUint256());

    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory afterReservePool_ = getReservePool(safetyModule, reservePoolId_);
      ReservePool memory beforeReservePool_ = beforeReservePools_[reservePoolId_];
      _require_accountingUpdateOnDripFees(reservePoolId_, afterReservePool_, beforeReservePool_);
    }
  }

  function invariant_dripFeesFromReservePoolAccounting() public syncCurrentTimestamp(safetyModuleHandler) {
    // Can't drip fees if the safety module is not active.
    if (safetyModule.safetyModuleState() != SafetyModuleState.ACTIVE) return;

    ReservePool[] memory beforeReservePools_ = new ReservePool[](numReservePools);
    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      beforeReservePools_[reservePoolId_] = getReservePool(safetyModule, reservePoolId_);
    }

    safetyModuleHandler.dripFeesFromReservePool(_randomAddress(), _randomUint256());

    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory afterReservePool_ = getReservePool(safetyModule, reservePoolId_);
      ReservePool memory beforeReservePool_ = beforeReservePools_[reservePoolId_];

      if (reservePoolId_ == safetyModuleHandler.currentReservePoolId()) {
        _require_accountingUpdateOnDripFees(reservePoolId_, afterReservePool_, beforeReservePool_);
      } else {
        _require_noAccountingUpdateOnDripFees(reservePoolId_, afterReservePool_, beforeReservePool_);
      }
    }
  }

  function _require_accountingUpdateOnDripFees(
    uint16 reservePoolId_,
    ReservePool memory afterReservePool_,
    ReservePool memory beforeReservePool_
  ) internal view {
    require(
      afterReservePool_.feeAmount >= beforeReservePool_.feeAmount,
      string.concat(
        "Invariant Violated: A reserve pool's fee amount must increase when fees are dripped.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", afterReservePool_.feeAmount: ",
        Strings.toString(afterReservePool_.feeAmount),
        ", beforeReservePool_.feeAmount: ",
        Strings.toString(beforeReservePool_.feeAmount)
      )
    );

    require(
      afterReservePool_.stakeAmount <= beforeReservePool_.stakeAmount,
      string.concat(
        "Invariant Violated: A reserve pool's stake amount must decrease when fees are dripped.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", afterReservePool_.stakeAmount: ",
        Strings.toString(afterReservePool_.stakeAmount),
        ", beforeReservePool_.stakeAmount: ",
        Strings.toString(beforeReservePool_.stakeAmount)
      )
    );

    require(
      afterReservePool_.depositAmount <= beforeReservePool_.depositAmount,
      string.concat(
        "Invariant Violated: A reserve pool's deposit amount must decrease when fees are dripped.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", afterReservePool_.depositAmount: ",
        Strings.toString(afterReservePool_.depositAmount),
        ", beforeReservePool_.depositAmount: ",
        Strings.toString(beforeReservePool_.depositAmount)
      )
    );

    uint256 feeDelta_ = afterReservePool_.feeAmount - beforeReservePool_.feeAmount;
    uint256 stakePlusDepositDelta_ = (beforeReservePool_.stakeAmount - afterReservePool_.stakeAmount)
      + (beforeReservePool_.depositAmount - afterReservePool_.depositAmount);
    require(
      feeDelta_ == stakePlusDepositDelta_,
      string.concat(
        "Invariant Violated: A reserve pool's change in fee amount must equal the sum of the changes in stake and deposit amount when fees are dripped.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", feeDelta_: ",
        Strings.toString(feeDelta_),
        ", stakePlusDepositDelta_: ",
        Strings.toString(stakePlusDepositDelta_)
      )
    );

    require(
      afterReservePool_.lastFeesDripTime == block.timestamp,
      string.concat(
        "Invariant Violated: A reserve pool's last fees drip time must be block.timestamp when fees are dripped.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", afterReservePool_.lastFeesDripTime: ",
        Strings.toString(afterReservePool_.lastFeesDripTime),
        ", block.timestamp: ",
        Strings.toString(block.timestamp)
      )
    );
  }

  function _require_noAccountingUpdateOnDripFees(
    uint16 reservePoolId_,
    ReservePool memory afterReservePool_,
    ReservePool memory beforeReservePool_
  ) internal view {
    require(
      afterReservePool_.feeAmount == beforeReservePool_.feeAmount,
      string.concat(
        "Invariant Violated: A reserve pool's fee amount must not change when fees are dripped for another pool.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", afterReservePool_.feeAmount: ",
        Strings.toString(afterReservePool_.feeAmount),
        ", beforeReservePool_.feeAmount: ",
        Strings.toString(beforeReservePool_.feeAmount)
      )
    );

    require(
      afterReservePool_.stakeAmount == beforeReservePool_.stakeAmount,
      string.concat(
        "Invariant Violated: A reserve pool's stake amount must not change when fees are dripped for another pool.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", afterReservePool_.stakeAmount: ",
        Strings.toString(afterReservePool_.stakeAmount),
        ", beforeReservePool_.stakeAmount: ",
        Strings.toString(beforeReservePool_.stakeAmount)
      )
    );

    require(
      afterReservePool_.depositAmount == beforeReservePool_.depositAmount,
      string.concat(
        "Invariant Violated: A reserve pool's deposit amount must not change when fees are dripped for another pool.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", afterReservePool_.depositAmount: ",
        Strings.toString(afterReservePool_.depositAmount),
        ", beforeReservePool_.depositAmount: ",
        Strings.toString(beforeReservePool_.depositAmount)
      )
    );

    require(
      afterReservePool_.lastFeesDripTime < block.timestamp,
      string.concat(
        "Invariant Violated: A reserve pool's last fees drip time must be less than block.timestamp when fees are dripped.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", afterReservePool_.lastFeesDripTime: ",
        Strings.toString(afterReservePool_.lastFeesDripTime),
        ", block.timestamp: ",
        Strings.toString(block.timestamp)
      )
    );
  }
}

contract FeesInvariantsSingleReservePoolSingleRewardPool is
  FeesInvariants,
  InvariantTestWithSingleReservePoolAndSingleRewardPool
{}

contract FeesInvariantsMultipleReservePoolsMultipleRewardPools is
  FeesInvariants,
  InvariantTestWithMultipleReservePoolsAndMultipleRewardPools
{}
