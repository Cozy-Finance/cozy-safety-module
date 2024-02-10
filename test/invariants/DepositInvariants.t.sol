// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract DepositInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  function invariant_reserveDepositReceiptTokenTotalSupplyIncreasesOnReserveDeposit()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    // Can't deposit if the safety module is paused.
    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) return;

    uint256[] memory totalSupplyBeforeDepositReserves_ = new uint256[](numReservePools);
    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      totalSupplyBeforeDepositReserves_[reservePoolId_] =
        getReservePool(safetyModule, reservePoolId_).depositReceiptToken.totalSupply();
    }

    safetyModuleHandler.depositReserveAssetsWithExistingActorWithoutCountingCall(_randomUint256());

    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      uint256 currentTotalSupply_ = getReservePool(safetyModule, reservePoolId_).depositReceiptToken.totalSupply();

      // safetyModuleHandler.currentReservePoolId is set to the reserve pool that was just deposited into during
      // this invariant test.
      if (reservePoolId_ == safetyModuleHandler.currentReservePoolId()) {
        require(
          currentTotalSupply_ > totalSupplyBeforeDepositReserves_[reservePoolId_],
          string.concat(
            "Invariant Violated: A reserve pool's total supply must increase when a deposit occurs.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", currentTotalSupply_: ",
            Strings.toString(currentTotalSupply_),
            ", totalSupplyBeforeDepositReserves_[reservePoolId_]: ",
            Strings.toString(totalSupplyBeforeDepositReserves_[reservePoolId_])
          )
        );
      } else {
        require(
          currentTotalSupply_ == totalSupplyBeforeDepositReserves_[reservePoolId_],
          string.concat(
            "Invariant Violated: A reserve pool's total supply must not change when a deposit occurs in another reserve pool.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", currentTotalSupply_: ",
            Strings.toString(currentTotalSupply_),
            ", totalSupplyBeforeDepositReserves_[reservePoolId_]: ",
            Strings.toString(totalSupplyBeforeDepositReserves_[reservePoolId_])
          )
        );
      }
    }
  }
}

contract DepositsInvariantsSingleReservePool is DepositInvariants, InvariantTestWithSingleReservePool {}

contract DepositsInvariantsMultipleReservePools is DepositInvariants, InvariantTestWithMultipleReservePools {}
