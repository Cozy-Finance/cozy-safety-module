// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, ReservePool} from "../../src/lib/structs/Pools.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {IDepositorErrors} from "../../src/interfaces/IDepositorErrors.sol";
import {
  InvariantTestBase,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract DepositInvariants is InvariantTestBase {
  using FixedPointMathLib for uint256;

  struct InternalBalances {
    uint256 assetPoolAmount;
    uint256 reservePoolAmount;
    uint256 assetAmount;
    uint256 feeAmount;
  }

  function invariant_reserveDepositReceiptTokenTotalSupplyAndInternalBalancesIncreaseOnReserveDeposit()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    uint256[] memory totalSupplyBeforeDepositReserves_ = new uint256[](numReservePools);
    InternalBalances[] memory internalBalancesBeforeDepositReserves_ = new InternalBalances[](numReservePools);
    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory reservePool_ = safetyModule.reservePools(reservePoolId_);

      totalSupplyBeforeDepositReserves_[reservePoolId_] = reservePool_.depositReceiptToken.totalSupply();
      internalBalancesBeforeDepositReserves_[reservePoolId_] = InternalBalances({
        assetPoolAmount: safetyModule.assetPools(reservePool_.asset).amount,
        reservePoolAmount: reservePool_.depositAmount,
        assetAmount: reservePool_.asset.balanceOf(address(safetyModule)),
        feeAmount: reservePool_.feeAmount
      });
    }

    safetyModuleHandler.depositReserveAssetsWithExistingActorWithoutCountingCall(_randomUint256());

    // safetyModuleHandler.currentReservePoolId is set to the reserve pool that was just deposited into during
    // this invariant test.
    uint8 depositedReservePoolId_ = safetyModuleHandler.currentReservePoolId();
    IERC20 depositReservePoolAsset_ = getReservePool(safetyModule, depositedReservePoolId_).asset;
    SafetyModuleState safetyModuleState_ = safetyModule.safetyModuleState();

    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      ReservePool memory currentReservePool_ = getReservePool(safetyModule, reservePoolId_);
      AssetPool memory currentAssetPool_ = safetyModule.assetPools(currentReservePool_.asset);

      if (safetyModuleState_ != SafetyModuleState.ACTIVE) {
        require(
          internalBalancesBeforeDepositReserves_[reservePoolId_].feeAmount == currentReservePool_.feeAmount,
          string.concat(
            "Invariant violated: The reserve pool's fee amount must not change after a deposit when the safety module is not active.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", internalBalancesBeforeDepositReserves_[reservePoolId_].feeAmount: ",
            Strings.toString(internalBalancesBeforeDepositReserves_[reservePoolId_].feeAmount),
            ", currentReservePool_.feeAmount: ",
            Strings.toString(currentReservePool_.feeAmount)
          )
        );
      } else {
        require(
          internalBalancesBeforeDepositReserves_[reservePoolId_].feeAmount <= currentReservePool_.feeAmount,
          string.concat(
            "Invariant violated: The reserve pool's fee amount may increase due to possible fees drip on deposit.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", internalBalancesBeforeDepositReserves_[reservePoolId_].feeAmount: ",
            Strings.toString(internalBalancesBeforeDepositReserves_[reservePoolId_].feeAmount),
            ", currentReservePool_.feeAmount: ",
            Strings.toString(currentReservePool_.feeAmount)
          )
        );
      }

      if (reservePoolId_ == depositedReservePoolId_) {
        require(
          currentReservePool_.depositReceiptToken.totalSupply() > totalSupplyBeforeDepositReserves_[reservePoolId_],
          string.concat(
            "Invariant Violated: A reserve pool's total supply must increase when a deposit occurs.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", currentReservePool_.depositReceiptToken.totalSupply(): ",
            Strings.toString(currentReservePool_.depositReceiptToken.totalSupply()),
            ", totalSupplyBeforeDepositReserves_[reservePoolId_]: ",
            Strings.toString(totalSupplyBeforeDepositReserves_[reservePoolId_])
          )
        );
        require(
          currentAssetPool_.amount > internalBalancesBeforeDepositReserves_[reservePoolId_].assetPoolAmount,
          string.concat(
            "Invariant Violated: An asset pool's internal balance must increase when a deposit occurs into a reserve pool using the asset.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", currentAssetPool_.amount: ",
            Strings.toString(currentAssetPool_.amount),
            ", internalBalancesBeforeDepositReserves_[reservePoolId_].assetPoolAmount: ",
            Strings.toString(internalBalancesBeforeDepositReserves_[reservePoolId_].assetPoolAmount)
          )
        );
        require(
          currentReservePool_.asset.balanceOf(address(safetyModule))
            > internalBalancesBeforeDepositReserves_[reservePoolId_].assetAmount,
          string.concat(
            "Invariant Violated: The safety module's balance of the reserve pool asset must increase when a deposit occurs.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", currentReservePool_.asset.balanceOf(address(safetyModule)): ",
            Strings.toString(currentReservePool_.asset.balanceOf(address(safetyModule))),
            ", internalBalancesBeforeDepositReserves_[reservePoolId_].assetAmount: ",
            Strings.toString(internalBalancesBeforeDepositReserves_[reservePoolId_].assetAmount)
          )
        );
      } else {
        require(
          currentReservePool_.depositReceiptToken.totalSupply() == totalSupplyBeforeDepositReserves_[reservePoolId_],
          string.concat(
            "Invariant Violated: A reserve pool's total supply must not change when a deposit occurs in another reserve pool.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", currentReservePool_.depositReceiptToken.totalSupply(): ",
            Strings.toString(currentReservePool_.depositReceiptToken.totalSupply()),
            ", totalSupplyBeforeDepositReserves_[reservePoolId_]: ",
            Strings.toString(totalSupplyBeforeDepositReserves_[reservePoolId_])
          )
        );
        require(
          currentReservePool_.depositAmount == internalBalancesBeforeDepositReserves_[reservePoolId_].reservePoolAmount,
          string.concat(
            "Invariant Violated: A reserve pool's deposit amount must not change when a deposit occurs in another reserve pool.",
            " reservePoolId_: ",
            Strings.toString(reservePoolId_),
            ", currentReservePool_.depositAmount: ",
            Strings.toString(currentReservePool_.depositAmount),
            ", internalBalancesBeforeDepositReserves_[reservePoolId_].reservePoolAmount: ",
            Strings.toString(internalBalancesBeforeDepositReserves_[reservePoolId_].reservePoolAmount)
          )
        );
        if (currentReservePool_.asset != depositReservePoolAsset_) {
          require(
            currentAssetPool_.amount == internalBalancesBeforeDepositReserves_[reservePoolId_].assetPoolAmount,
            string.concat(
              "Invariant Violated: An asset pool's internal balance must not change when a deposit occurs in a reserve pool with a different underlying asset.",
              " reservePoolId_: ",
              Strings.toString(reservePoolId_),
              ", currentAssetPool_.amount: ",
              Strings.toString(currentAssetPool_.amount),
              ", internalBalancesBeforeDepositReserves_[reservePoolId_].assetPoolAmount: ",
              Strings.toString(internalBalancesBeforeDepositReserves_[reservePoolId_].assetPoolAmount)
            )
          );
          require(
            currentReservePool_.asset.balanceOf(address(safetyModule))
              == internalBalancesBeforeDepositReserves_[reservePoolId_].assetAmount,
            string.concat(
              "Invariant Violated: The safety module's asset balance for a specific asset must not change when a deposit occurs in a reserve pool with a different underlying asset.",
              " reservePoolId_: ",
              Strings.toString(reservePoolId_),
              ", currentReservePool_.asset.balanceOf(address(safetyModule)): ",
              Strings.toString(currentReservePool_.asset.balanceOf(address(safetyModule))),
              ", internalBalancesBeforeDepositReserves_[reservePoolId_].assetAmount: ",
              Strings.toString(internalBalancesBeforeDepositReserves_[reservePoolId_].assetAmount)
            )
          );
        }
      }
    }
  }

  function invariant_exchangeRatesForZeroAssetsAndReceiptTokens() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint8 reservePoolId_; reservePoolId_ < numReservePools; reservePoolId_++) {
      require(
        safetyModule.convertToReceiptTokenAmount(reservePoolId_, 0) == 0,
        string.concat(
          "Invariant Violated: The exchange rate for 0 reserve assets must be 0.",
          " reservePoolId_: ",
          Strings.toString(reservePoolId_),
          ", safetyModule.convertToReceiptTokenAmount(reservePoolId_, 0): ",
          Strings.toString(safetyModule.convertToReceiptTokenAmount(reservePoolId_, 0))
        )
      );
      require(
        safetyModule.convertToReserveAssetAmount(reservePoolId_, 0) == 0,
        string.concat(
          "Invariant Violated: The exchange rate for 0 receipt tokens must be 0.",
          " reservePoolId_: ",
          Strings.toString(reservePoolId_),
          ", safetyModule.convertToReserveAssetAmount(reservePoolId_, 0): ",
          Strings.toString(safetyModule.convertToReserveAssetAmount(reservePoolId_, 0))
        )
      );
    }
  }

  function invariant_depositPreviewMatches() public syncCurrentTimestamp(safetyModuleHandler) {
    uint256 assetAmount_ = safetyModuleHandler.boundDepositAssetAmount(_randomUint256());
    uint8 reservePoolId_ = safetyModuleHandler.pickValidReservePoolId(_randomUint256());
    address actor_ = safetyModuleHandler.pickActor(_randomUint256());
    uint256 expectedReceiptTokenAmount_ = safetyModule.convertToReceiptTokenAmount(reservePoolId_, assetAmount_);

    uint256 actorReceiptTokenBalBeforeDeposit_ =
      safetyModule.reservePools(reservePoolId_).depositReceiptToken.balanceOf(actor_);
    safetyModuleHandler.depositReserveAssetsWithExistingActorWithoutCountingCall(reservePoolId_, assetAmount_, actor_);
    uint256 receivedReceiptTokenAmount_ = safetyModule.reservePools(reservePoolId_).depositReceiptToken.balanceOf(
      actor_
    ) - actorReceiptTokenBalBeforeDeposit_;

    require(
      receivedReceiptTokenAmount_ == expectedReceiptTokenAmount_,
      string.concat(
        "Invariant Violated: The amount of receipt tokens received from a deposit must match the expected amount previewed.",
        " assetAmount_: ",
        Strings.toString(assetAmount_),
        ", expectedReceiptTokenAmount_: ",
        Strings.toString(expectedReceiptTokenAmount_),
        ", receivedReceiptTokenAmount_: ",
        Strings.toString(receivedReceiptTokenAmount_)
      )
    );
  }

  function invariant_cannotDepositZeroAssets() public syncCurrentTimestamp(safetyModuleHandler) {
    uint8 reservePoolId_ = safetyModuleHandler.pickValidReservePoolId(_randomUint256());
    address actor_ = safetyModuleHandler.pickActor(_randomUint256());

    vm.prank(actor_);
    vm.expectRevert(ICommonErrors.RoundsToZero.selector);
    safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, 0, actor_);
  }

  function invariant_cannotDepositWithInsufficientAssets() public syncCurrentTimestamp(safetyModuleHandler) {
    uint8 reservePoolId_ = safetyModuleHandler.pickValidReservePoolId(_randomUint256());
    address actor_ = safetyModuleHandler.pickActor(_randomUint256());
    uint256 assetAmount_ = safetyModuleHandler.boundDepositAssetAmount(_randomUint256());

    vm.prank(actor_);
    vm.expectRevert(IDepositorErrors.InvalidDeposit.selector);
    safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, assetAmount_, actor_);
  }
}

contract DepositsInvariantsSingleReservePool is DepositInvariants, InvariantTestWithSingleReservePool {}

contract DepositsInvariantsMultipleReservePools is DepositInvariants, InvariantTestWithMultipleReservePools {}
