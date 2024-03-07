// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {
  InvariantTestBase,
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract FeesInvariantsShared {
  function _require_accountingUpdateOnDripFees(
    uint8 reservePoolId_,
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
    uint256 depositDelta_ = beforeReservePool_.depositAmount - afterReservePool_.depositAmount;
    require(
      feeDelta_ == depositDelta_,
      string.concat(
        "Invariant Violated: A reserve pool's change in fee amount must equal the change in deposit amount when fees are dripped.",
        " reservePoolId_: ",
        Strings.toString(reservePoolId_),
        ", feeDelta_: ",
        Strings.toString(feeDelta_),
        ", depositDelta_: ",
        Strings.toString(depositDelta_)
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
    uint8 reservePoolId_,
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

abstract contract FeesInvariants is InvariantTestBase, FeesInvariantsShared {
  using FixedPointMathLib for uint256;

  function invariant_dripFeesAccounting() public syncCurrentTimestamp(safetyModuleHandler) {
    ReservePool[] memory beforeReservePools_ = new ReservePool[](numReservePools);
    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      beforeReservePools_[reservePoolId_] = getReservePool(safetyModule, reservePoolId_);
    }

    safetyModuleHandler.dripFees(_randomAddress(), _randomUint256());

    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory afterReservePool_ = getReservePool(safetyModule, reservePoolId_);
      ReservePool memory beforeReservePool_ = beforeReservePools_[reservePoolId_];
      _require_accountingUpdateOnDripFees(reservePoolId_, afterReservePool_, beforeReservePool_);
    }
  }

  function invariant_dripFeesFromReservePoolAccounting() public syncCurrentTimestamp(safetyModuleHandler) {
    ReservePool[] memory beforeReservePools_ = new ReservePool[](numReservePools);
    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      beforeReservePools_[reservePoolId_] = getReservePool(safetyModule, reservePoolId_);
    }

    safetyModuleHandler.dripFeesFromReservePool(_randomAddress(), _randomUint256());

    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory afterReservePool_ = getReservePool(safetyModule, reservePoolId_);
      ReservePool memory beforeReservePool_ = beforeReservePools_[reservePoolId_];

      if (reservePoolId_ == safetyModuleHandler.currentReservePoolId()) {
        _require_accountingUpdateOnDripFees(reservePoolId_, afterReservePool_, beforeReservePool_);
      } else {
        _require_noAccountingUpdateOnDripFees(reservePoolId_, afterReservePool_, beforeReservePool_);
      }
    }
  }
}

abstract contract FeesInvariantsWithStateTransitions is InvariantTestBase, FeesInvariantsShared {
  mapping(IERC20 => uint256) internal feesClaimedSums;

  function invariant_claimFeesAccounting() public syncCurrentTimestamp(safetyModuleHandler) {
    ReservePool[] memory beforeReservePools_ = new ReservePool[](numReservePools);
    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
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

    SafetyModuleState safetyModuleState_ = safetyModule.safetyModuleState();
    uint256 timeBeforeClaimFees_ = block.timestamp;
    safetyModuleHandler.claimFees(owner_, _randomUint256());

    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory afterReservePool_ = getReservePool(safetyModule, reservePoolId_);
      ReservePool memory beforeReservePool_ = beforeReservePools_[reservePoolId_];
      // The claimed fees include the old dripped fees and newly dripped fees.
      feesClaimedSums[afterReservePool_.asset] +=
        beforeReservePool_.feeAmount + (beforeReservePool_.depositAmount - afterReservePool_.depositAmount);

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

      if (safetyModuleState_ == SafetyModuleState.ACTIVE) {
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
      } else {
        require(
          // If block.timestamp == timeBeforeClaimFees_, the SafetyModule may have been paused/triggered in the
          // same block before the fees were claimed. Thus, we allow the last fees drip time to be equal to
          // timeBeforeClaimFees_ as well here.
          afterReservePool_.lastFeesDripTime <= timeBeforeClaimFees_,
          string.concat(
            "Invariant Violated: A reserve pool's last fees drip time must be less than or equal to block.timestamp when fees are claimed and the SafetyModule is not active.",
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
}

contract FeesInvariantsSingleReservePool is FeesInvariants, InvariantTestWithSingleReservePool {}

contract FeesInvariantsMultipleReservePools is FeesInvariants, InvariantTestWithMultipleReservePools {}

contract FeesInvariantsWithStateTransitionsSingleReservePool is
  FeesInvariantsWithStateTransitions,
  InvariantTestWithSingleReservePool
{}

contract FeesInvariantsWithStateTransitionsMultipleReservePools is
  FeesInvariantsWithStateTransitions,
  InvariantTestWithMultipleReservePools
{}
