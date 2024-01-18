// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {InvariantTestBase, InvariantTestWithSingleReservePoolAndSingleRewardPool} from "./utils/InvariantTestBase.sol";

abstract contract DepositInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  function invariant_totalSupplyIncreasesOnDeposit() public syncCurrentTimestamp(safetyModuleHandler) {
    uint256[] memory totalSupplyBeforeDepositReserves_ = new uint256[](numReservePools);
    uint256[] memory totalSupplyBeforeDepositRewards_ = new uint256[](numRewardPools);

    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      totalSupplyBeforeDepositReserves_[reservePoolId_] =
        getReservePool(safetyModule, reservePoolId_).depositToken.totalSupply();
    }

    for (uint16 rewardPoolId_; rewardPoolId_ < numRewardPools; rewardPoolId_++) {
      totalSupplyBeforeDepositRewards_[rewardPoolId_] =
        getUndrippedRewardPool(safetyModule, rewardPoolId_).depositToken.totalSupply();
    }

    safetyModuleHandler.depositReserveAssetsWithoutCountingCall(_randomUint256());

    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      uint256 currentTotalSupply_ = getReservePool(safetyModule, reservePoolId_).depositToken.totalSupply();

      if (reservePoolId_ == safetyModuleHandler.currentReservePoolId()) {
        require(
          currentTotalSupply_ > totalSupplyBeforeDepositReserves_[reservePoolId_],
          "Invariant Violated: A reserve pool's total supply must increase when a deposit occurs."
        );
      } else {
        require(
          currentTotalSupply_ == totalSupplyBeforeDepositReserves_[reservePoolId_],
          "Invariant Violated: A reserve pool's total supply must not change when a deposit occurs in another reserve pool."
        );
      }
    }
  }
}

contract DepositsInvariantsSingleReservePoolSingleRewardPool is
  DepositInvariants,
  InvariantTestWithSingleReservePoolAndSingleRewardPool
{}
