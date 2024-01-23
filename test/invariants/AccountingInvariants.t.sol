// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReservePool, RewardPool} from "../../src/lib/structs/Pools.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
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

  function invariant_internalAssetPoolAmountEqualsERC20BalanceOfSafetyModule()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    uint256 internalAssetPoolAmount_ = safetyModule.assetPools(IERC20(address(asset))).amount;
    uint256 erc20AssetBalance_ = asset.balanceOf(address(safetyModule));
    require(
      internalAssetPoolAmount_ == erc20AssetBalance_,
      string.concat(
        "Invariant Violated: The internal asset pool amount for an asset must equal the asset's ERC20 balance of the safety module.",
        " internalAssetPoolAmount_: ",
        Strings.toString(internalAssetPoolAmount_),
        ", asset.balanceOf(address(safetyModule)): ",
        Strings.toString(erc20AssetBalance_)
      )
    );
  }

  mapping(IERC20 => uint256) internal accountingSums;

  function invariant_internalAssetPoolAmountEqualsSumOfInternalAmounts()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    uint256 accountingSum;
    ReservePool memory reservePool_ = getReservePool(safetyModule, 0);
    RewardPool memory rewardPool_ = getRewardPool(safetyModule, 0);

    accountingSum += (reservePool_.depositAmount + reservePool_.stakeAmount + reservePool_.feeAmount);
    accountingSum += (rewardPool_.undrippedRewards + rewardPool_.cumulativeDrippedRewards);
    accountingSum -= safetyModuleHandler.ghost_rewardsClaimed(IERC20(address(asset)));

    // TODO iterate over each asset and check the invariant applies for each.
    require(
      safetyModule.assetPools(IERC20(address(asset))).amount == accountingSum,
      string.concat(
        "Invariant Violated: The internal asset pool amount for an asset must equal the sum of the internal pool amounts.",
        " safetyModule.assetPools(IERC20(address(asset))).amount): ",
        Strings.toString(safetyModule.assetPools(IERC20(address(asset))).amount),
        ", accountingSums[asset]: ",
        Strings.toString(accountingSum),
        ", asset.balanceOf(safetyModule): ",
        Strings.toString(asset.balanceOf(address(safetyModule))),
        ", safetyModuleHandler.ghost_rewardsClaimed(reservePool_.asset): ",
        Strings.toString(safetyModuleHandler.ghost_rewardsClaimed(reservePool_.asset))
      )
    );
  }
}

contract AccountingInvariantsSingleReservePoolSingleRewardPool is
  AccountingInvariants,
  InvariantTestWithSingleReservePoolAndSingleRewardPool
{}
