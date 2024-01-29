// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";
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

  mapping(IERC20 => uint256) internal feesClaimedSums;

  function invariant_claimFeesAccounting() public syncCurrentTimestamp(safetyModuleHandler) {
    ReservePool[] memory beforeReservePools_ = new ReservePool[](numReservePools);
    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory beforeReservePool_ = getReservePool(safetyModule, reservePoolId_);
      beforeReservePools_[reservePoolId_] = beforeReservePool_;
    }

    address owner_ = _randomAddress();
    // Save the `owner_`'s balances and asset pool amounts before claiming fees.
    uint256 numAssets_ = assets.length;
    uint256[] memory beforeOwnerBalances_ = new uint256[](numAssets_);
    uint256[] memory beforeAssetPoolAmounts_ = new uint256[](numAssets_);
    for (uint16 assetId_; assetId_ < numAssets_; assetId_++) {
      IERC20 asset_ = assets[assetId_];
      beforeOwnerBalances_[assetId_] = asset_.balanceOf(owner_);
      beforeAssetPoolAmounts_[assetId_] = safetyModule.assetPools(asset_).amount;
    }

    safetyModuleHandler.claimFees(owner_, _randomUint256());

    for (uint16 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory afterReservePool_ = getReservePool(safetyModule, reservePoolId_);
      ReservePool memory beforeReservePool_ = beforeReservePools_[reservePoolId_];
      // The claimed fees include the old dripped fees and newly dripped fees.
      feesClaimedSums[afterReservePool_.asset] += beforeReservePool_.feeAmount
        + (beforeReservePool_.stakeAmount - afterReservePool_.stakeAmount)
        + (beforeReservePool_.depositAmount - afterReservePool_.depositAmount);

      require(
        afterReservePool_.feeAmount == 0,
        string.concat(
          "Invariant Violated: A reserve pool's fee amount must be 0 after fees are claimed.",
          " reservePoolId_: ",
          Strings.toString(reservePoolId_),
          ", afterReservePool_.feeAmount: ",
          Strings.toString(afterReservePool_.feeAmount)
        )
      );

      require(
        afterReservePool_.stakeAmount <= beforeReservePool_.stakeAmount,
        string.concat(
          "Invariant Violated: A reserve pool's stake amount must decrease when fees are claimed.",
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
          "Invariant Violated: A reserve pool's deposit amount must decrease when fees are claimed.",
          " reservePoolId_: ",
          Strings.toString(reservePoolId_),
          ", afterReservePool_.depositAmount: ",
          Strings.toString(afterReservePool_.depositAmount),
          ", beforeReservePool_.depositAmount: ",
          Strings.toString(beforeReservePool_.depositAmount)
        )
      );

      require(
        afterReservePool_.lastFeesDripTime == block.timestamp,
        string.concat(
          "Invariant Violated: A reserve pool's last fees drip time must be block.timestamp when fees are claimed.",
          " reservePoolId_: ",
          Strings.toString(reservePoolId_),
          ", afterReservePool_.lastFeesDripTime: ",
          Strings.toString(afterReservePool_.lastFeesDripTime),
          ", block.timestamp: ",
          Strings.toString(block.timestamp)
        )
      );
    }

    for (uint16 assetId_; assetId_ < numAssets_; assetId_++) {
      IERC20 asset_ = assets[assetId_];
      require(
        asset_.balanceOf(owner_) == beforeOwnerBalances_[assetId_] + feesClaimedSums[asset_],
        string.concat(
          "Invariant Violated: An owner's asset balance must increase by the summed fee amount claimed when fees are claimed.",
          " assetId_: ",
          Strings.toString(assetId_),
          ", asset_.balanceOf(owner_): ",
          Strings.toString(asset_.balanceOf(owner_)),
          ", beforeOwnerBalances_[assetId_]: ",
          Strings.toString(beforeOwnerBalances_[assetId_]),
          ", feesClaimedSums[asset_]: ",
          Strings.toString(feesClaimedSums[asset_])
        )
      );

      require(
        safetyModule.assetPools(asset_).amount == beforeAssetPoolAmounts_[assetId_] - feesClaimedSums[asset_],
        string.concat(
          "Invariant Violated: An asset pool's amount must decrease by the summed fee amount claimed when fees are claimed.",
          " assetId_: ",
          Strings.toString(assetId_),
          ", safetyModule.assetPools(asset_).amount: ",
          Strings.toString(safetyModule.assetPools(asset_).amount),
          ", beforeAssetPoolAmounts_[assetId_]: ",
          Strings.toString(beforeAssetPoolAmounts_[assetId_]),
          ", feesClaimedSums[asset_]: ",
          Strings.toString(feesClaimedSums[asset_])
        )
      );
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
