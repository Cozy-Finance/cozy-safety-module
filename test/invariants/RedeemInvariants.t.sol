// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {RedemptionPreview} from "../../src/lib/structs/Redemptions.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {IRedemptionErrors} from "../../src/interfaces/IRedemptionErrors.sol";
import {SafetyModuleHandler} from "./handlers/SafetyModuleHandler.sol";
import {
  InvariantTestBase,
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract RedeemInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  using FixedPointMathLib for uint256;

  function assertActorCompleteRedeemedAssetsLteRedeemed(address actor_) external view {
    for (uint8 i = 0; i < numReservePools; i++) {
      SafetyModuleHandler.GhostReservePool memory reservePool_ =
        safetyModuleHandler.getActorGhostReservePoolCumulative(actor_, i);
      require(
        reservePool_.completedRedeemAssetAmount <= reservePool_.redeemAssetAmount,
        "Invariant violated: The amount of assets a user complete redeems should be less than or equal to the amount they queued."
      );
    }
  }

  function assertActorRedeemedSharesLteMintedShares(address actor_) external view {
    for (uint8 i = 0; i < numReservePools; i++) {
      SafetyModuleHandler.GhostReservePool memory reservePool_ =
        safetyModuleHandler.getActorGhostReservePoolCumulative(actor_, i);
      require(
        reservePool_.redeemSharesAmount <= reservePool_.depositSharesAmount,
        "Invariant violated: The amount of shares a user can redeem should be less than or equal to the amount they've minted from deposits, if they have not received any additional shares via transfer."
      );
    }
  }

  function assertActorBalanceOfSharesEqualsMintedMinusRedeemed(address actor_) external view {
    for (uint8 i = 0; i < numReservePools; i++) {
      SafetyModuleHandler.GhostReservePool memory reservePool_ =
        safetyModuleHandler.getActorGhostReservePoolCumulative(actor_, i);
      require(
        reservePool_.depositSharesAmount - reservePool_.redeemSharesAmount
          == getReservePool(safetyModule, i).depositReceiptToken.balanceOf(actor_),
        "Invariant violated: The amount of shares a user owns are the amount of shares they've minted from deposits minus the amount of shares they burned from redeems, if they have not received any additional shares via transfer."
      );
    }
  }

  function invariant_completeRedeemedAssetsLteRedeemed() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint8 i = 0; i < numReservePools; i++) {
      SafetyModuleHandler.GhostReservePool memory reservePool_ = safetyModuleHandler.getGhostReservePoolCumulative(i);
      require(
        reservePool_.completedRedeemAssetAmount <= reservePool_.redeemAssetAmount,
        "Invariant violated: The sum of assets removed from the safety module in completed redemptions should be less than or equal to the sum of assets queued for redemption."
      );
    }
  }

  function invariant_redeemedSharesLteMintedShares() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint8 i = 0; i < numReservePools; i++) {
      SafetyModuleHandler.GhostReservePool memory reservePool_ = safetyModuleHandler.getGhostReservePoolCumulative(i);
      require(
        reservePool_.redeemSharesAmount <= reservePool_.depositSharesAmount,
        "Invariant violated: The sum of shares removed from the safety module in redemptions should be less than or equal to the sum of shares minted from deposits."
      );
    }
  }

  function invariant_balanceOfSharesEqualsMintedMinusRedeemed() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint8 i = 0; i < numReservePools; i++) {
      SafetyModuleHandler.GhostReservePool memory reservePool_ = safetyModuleHandler.getGhostReservePoolCumulative(i);
      require(
        reservePool_.depositSharesAmount - reservePool_.redeemSharesAmount
          == getReservePool(safetyModule, i).depositReceiptToken.totalSupply(),
        "Invariant violated: The sum of shares owned by users should be the sum of shares minted from deposits minus the sum of shares removed from the safety module in redemptions."
      );
    }
  }

  function invariant_actorCompleteRedeemedAssetsLteRedeemed() public syncCurrentTimestamp(safetyModuleHandler) {
    safetyModuleHandler.forEachActor(this.assertActorCompleteRedeemedAssetsLteRedeemed);
  }

  function invariant_actorRedeemedSharesLteMintedShares() public syncCurrentTimestamp(safetyModuleHandler) {
    safetyModuleHandler.forEachActor(this.assertActorRedeemedSharesLteMintedShares);
  }

  function invariant_actorBalanceOfSharesEqualsMintedMinusRedeemed() public syncCurrentTimestamp(safetyModuleHandler) {
    safetyModuleHandler.forEachActor(this.assertActorBalanceOfSharesEqualsMintedMinusRedeemed);
  }

  function invariant_pendingWithdrawalsIncreasesWithRedeem() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint8 i = 0; i < numReservePools; i++) {
      require(
        safetyModuleHandler.getGhostRedeemAssetsPendingRedemptionChange(i).before
          <= safetyModuleHandler.getGhostRedeemAssetsPendingRedemptionChange(i).afterwards,
        "Invariant Violated: Assets pending redemption should only increase when a redemption is queued."
      );
    }
  }

  function invariant_pendingWithdrawalsDecreasesWithCompleteRedeem() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint8 i = 0; i < numReservePools; i++) {
      require(
        safetyModuleHandler.getGhostCompleteRedeemAssetsPendingRedemptionChange(i).before
          >= safetyModuleHandler.getGhostCompleteRedeemAssetsPendingRedemptionChange(i).afterwards,
        "Invariant Violated: Assets pending redemption should only decrease when a redemption is completed."
      );
    }
  }

  function invariant_completeRedemptionAssetsLteQueuedAssets() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint256 i = 0; i < safetyModuleHandler.getGhostRedemptionsLength(); i++) {
      SafetyModuleHandler.GhostRedemption memory queuedRedemption_ = safetyModuleHandler.getGhostRedemption(i);
      if (queuedRedemption_.completed) {
        require(
          safetyModuleHandler.getGhostRedemptionCompleted(queuedRedemption_.id).assets <= queuedRedemption_.assetAmount,
          "Invariant Violated: The amount of assets received when a redemption is completed must be less than or equal to the queued amount."
        );
      }
    }
  }

  /// @notice Verifies assets may never be redeemed for free using convertToAssets()
  function invariant_convertconvertToReserveAssetAmountRoundingDirection()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    for (uint8 i = 0; i < numReservePools; i++) {
      uint256 assets_ = safetyModule.convertToReserveAssetAmount(i, 0);
      require(
        assets_ == 0,
        string.concat(
          "Invariant violated: convertToReserveAssetAmount() must not allow assets to be withdrawn at no cost.",
          " assets_: ",
          Strings.toString(assets_)
        )
      );
    }
  }

  function invariant_previewQueuedRedemptionMatchesQueuedRedemption() public syncCurrentTimestamp(safetyModuleHandler) {
    for (uint64 i = 0; i < safetyModuleHandler.getGhostRedemptionsLength(); i++) {
      SafetyModuleHandler.GhostRedemption memory queuedRedemption_ = safetyModuleHandler.getGhostRedemption(i);
      // Redemptions queued when PAUSED immediately complete and do not get recorded in the safety module, so they are
      // recorded as 0s. Similarly, completed redemptions are deleted and recorded as 0s.
      bool zeroed_ = queuedRedemption_.state == SafetyModuleState.PAUSED || queuedRedemption_.completed == true;
      RedemptionPreview memory previewQueuedRedemption_ = safetyModule.previewQueuedRedemption(queuedRedemption_.id);
      require(
        previewQueuedRedemption_.receiptTokenAmount == (zeroed_ ? 0 : queuedRedemption_.receiptTokenAmount),
        "Invariant violated: The receipt token amount of the queued redemption must match the receipt token amount of the previewed redemption."
      );
      require(
        zeroed_
          ? (previewQueuedRedemption_.reserveAssetAmount == 0)
          : (previewQueuedRedemption_.reserveAssetAmount <= queuedRedemption_.assetAmount),
        "Invariant violated: The reserve asset amount of the queued redemption must be greater than the reserve asset amount of the previewed redemption."
      );
      require(
        previewQueuedRedemption_.owner == (zeroed_ ? address(0) : queuedRedemption_.owner),
        "Invariant violated: The owner of the queued redemption must match the owner of the previewed redemption."
      );
      require(
        previewQueuedRedemption_.receiver == (zeroed_ ? address(0) : queuedRedemption_.receiver),
        "Invariant violated: The receiver of the queued redemption must match the receiver of the previewed redemption."
      );
      require(
        previewQueuedRedemption_.receiptToken
          == (
            zeroed_
              ? IReceiptToken(address(0))
              : getReservePool(safetyModule, queuedRedemption_.reservePoolId).depositReceiptToken
          ),
        "Invariant violated: The receipt token of the queued redemption must match the receipt token of the previewed redemption."
      );
      require(
        zeroed_
          ? (previewQueuedRedemption_.delayRemaining == 0)
          : (previewQueuedRedemption_.delayRemaining <= safetyModule.delays().withdrawDelay),
        "Invariant violated: The delay remaining of the previewed redemption must be less than or equal to the withdrawal delay."
      );
    }
  }

  function invariant_redeemMatchesConvertToReserveAssetAmount() public syncCurrentTimestamp(safetyModuleHandler) {
    address actor_ = safetyModuleHandler.pickActorWithReserveDeposits(_randomUint256());
    uint8 reservePoolId_ = safetyModuleHandler.pickReservePoolIdForActorWithReserveDeposits(_randomUint256(), actor_);
    uint256 redeemableBalance_ = getReservePool(safetyModule, reservePoolId_).depositReceiptToken.balanceOf(actor_);
    SafetyModuleState state_ = safetyModule.safetyModuleState();

    // We only want to redeem the full amount sometimes, to reduce the amount of times all of the actors in the
    // invariant test run redeem all of their shares immediately after depositing.
    if (redeemableBalance_ != 0 && _randomUint256() % 2 != 1) {
      uint256 balanceConvertedToAssets_ = safetyModule.convertToReserveAssetAmount(reservePoolId_, redeemableBalance_);
      if (balanceConvertedToAssets_ > 0 && (state_ != SafetyModuleState.TRIGGERED)) {
        vm.startPrank(actor_);
        (, uint256 redeemedAssets_) = safetyModule.redeem(reservePoolId_, redeemableBalance_, actor_, actor_);
        vm.stopPrank();
        require(
          balanceConvertedToAssets_ == redeemedAssets_,
          "Invariant violated: The amount of shares converted to assets (using safetyModule.convertToReserveAssetAmount()) that a user can redeem should be equal to the amount of assets returned by safetyModule.redeem()."
        );
      } else {
        // Here we expect reverts either InvalidState, RoundsToZero, or NotEnoughAssets.
        vm.expectRevert();
        vm.startPrank(actor_);
        safetyModule.redeem(reservePoolId_, redeemableBalance_, actor_, actor_);
        vm.stopPrank();
      }
    }
  }

  function invariant_redeemMatchesPreviewRedemption() public syncCurrentTimestamp(safetyModuleHandler) {
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;
    address actor_ = safetyModuleHandler.pickActorWithReserveDeposits(_randomUint256());
    uint8 reservePoolId_ = safetyModuleHandler.pickReservePoolIdForActorWithReserveDeposits(_randomUint256(), actor_);

    uint256 redeemedAmount_ =
      bound(_randomUint64(), 0, getReservePool(safetyModule, reservePoolId_).depositReceiptToken.balanceOf(actor_));

    uint256 previewRedeemedAssets_ = safetyModule.previewRedemption(reservePoolId_, redeemedAmount_);
    if (previewRedeemedAssets_ > 0) {
      vm.startPrank(actor_);
      (, uint256 redeemedAssets_) = safetyModule.redeem(reservePoolId_, redeemedAmount_, actor_, actor_);
      vm.stopPrank();
      require(
        previewRedeemedAssets_ == redeemedAssets_,
        "Invariant violated: The amount of assets returned by safetyModule.redeem() should be equal to the amount of assets returned by safetyModule.previewRedeem()."
      );
    } else {
      // Here we expect reverts either RoundsToZero or NotEnoughAssets.
      vm.expectRevert();
      vm.startPrank(actor_);
      safetyModule.redeem(reservePoolId_, redeemedAmount_, actor_, actor_);
      vm.stopPrank();
    }
  }

  function invariant_completeRedemptionRevertsBeforeDelayElapsedElseSucceeds()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    uint64 redemptionIndex_ = safetyModuleHandler.pickRedemptionIndex(_randomUint256());
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED || redemptionIndex_ == type(uint64).max) return;

    SafetyModuleHandler.GhostRedemption memory queuedRedemption_ =
      safetyModuleHandler.getGhostRedemption(redemptionIndex_);

    RedemptionPreview memory previewRedemption_ = safetyModule.previewQueuedRedemption(queuedRedemption_.id);
    if (previewRedemption_.delayRemaining > 0) {
      vm.warp(block.timestamp + previewRedemption_.delayRemaining - 1);
      vm.expectRevert(IRedemptionErrors.DelayNotElapsed.selector);
      safetyModule.completeRedemption(queuedRedemption_.id);
    } else if (queuedRedemption_.state == SafetyModuleState.PAUSED) {
      // Redemptions queued when PAUSED immediately complete and do not get recorded in the safety module.
      vm.expectRevert(IRedemptionErrors.RedemptionNotFound.selector);
      safetyModule.completeRedemption(queuedRedemption_.id);
    } else {
      // Suceessful completion of redemption.
      safetyModule.completeRedemption(queuedRedemption_.id);
    }
  }

  function invariant_completeRedemptionMatchesPreviewQueuedRedemption()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    uint64 redemptionIndex_ = safetyModuleHandler.pickRedemptionIndex(_randomUint256());
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED || redemptionIndex_ == type(uint64).max) return;

    SafetyModuleHandler.GhostRedemption memory queuedRedemption_ =
      safetyModuleHandler.getGhostRedemption(redemptionIndex_);

    if (queuedRedemption_.state == SafetyModuleState.PAUSED) {
      RedemptionPreview memory previewRedemption_ = safetyModule.previewQueuedRedemption(queuedRedemption_.id);
      require(
        previewRedemption_.owner == address(0),
        "Invariant violated: The delay remaining of the previewed redemption must be 0 when the redemption is paused."
      );
      // Redemptions queued when PAUSED immediately complete and do not get recorded in the safety module.
      vm.expectRevert(IRedemptionErrors.RedemptionNotFound.selector);
      safetyModule.completeRedemption(queuedRedemption_.id);
    } else {
      vm.warp(block.timestamp + safetyModule.previewQueuedRedemption(queuedRedemption_.id).delayRemaining);
      RedemptionPreview memory previewRedemption_ = safetyModule.previewQueuedRedemption(queuedRedemption_.id);
      uint256 redeemedAssets_ = safetyModule.completeRedemption(queuedRedemption_.id);
      require(
        redeemedAssets_ == previewRedemption_.reserveAssetAmount,
        "Invariant violated: The receipt token amount of the previewed redemption must be 0 when the redemption is completed."
      );
      require(
        previewRedemption_.delayRemaining == 0,
        "Invariant violated: The delay remaining of the previewed redemption must be 0 when the redemption is successfully completed."
      );
    }
  }

  function invariant_redeemRevertsForInsufficientBalance() public syncCurrentTimestamp(safetyModuleHandler) {
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    address actor_ = safetyModuleHandler.pickActorWithReserveDeposits(_randomUint256());
    uint8 reservePoolId_ = safetyModuleHandler.pickReservePoolIdForActorWithReserveDeposits(_randomUint256(), actor_);
    uint256 redeemAmount_ = bound(
      _randomUint256(),
      getReservePool(safetyModule, reservePoolId_).depositReceiptToken.balanceOf(actor_) + 1,
      type(uint128).max
    );
    uint256 previewRedeemedAssets_ = safetyModule.previewRedemption(reservePoolId_, redeemAmount_);

    if (previewRedeemedAssets_ > 0) {
      _expectPanic(PANIC_MATH_UNDEROVERFLOW);
      safetyModule.redeem(reservePoolId_, redeemAmount_, actor_, actor_);
    }
  }
}

abstract contract RedeemInvariants is InvariantTestBase {
  function invariant_redeemAccounting() public syncCurrentTimestamp(safetyModuleHandler) {
    address actor_ = safetyModuleHandler.pickActorWithReserveDeposits(_randomUint256());
    uint8 reservePoolId_ = safetyModuleHandler.pickReservePoolIdForActorWithReserveDeposits(_randomUint256(), actor_);

    uint256 redeemedAmount_ =
      bound(_randomUint64(), 0, getReservePool(safetyModule, reservePoolId_).depositReceiptToken.balanceOf(actor_));
    uint256 previewRedeemedAssets_ = safetyModule.previewRedemption(reservePoolId_, redeemedAmount_);

    if (previewRedeemedAssets_ != 0) {
      ReservePool[] memory beforeReservePools_ = new ReservePool[](numReservePools);
      for (uint8 i; i < numReservePools; i++) {
        beforeReservePools_[i] = getReservePool(safetyModule, i);
      }

      vm.startPrank(actor_);
      (, uint256 redeemedAssets_) = safetyModule.redeem(reservePoolId_, redeemedAmount_, actor_, actor_);
      vm.stopPrank();

      for (uint8 i; i < numReservePools; i++) {
        ReservePool memory beforeReservePool_ = beforeReservePools_[i];
        ReservePool memory afterReservePool_ = getReservePool(safetyModule, i);
        require(
          beforeReservePool_.depositAmount >= afterReservePool_.depositAmount,
          "Invariant violated: The reserve pool's deposit amount decrease due to possible fees drip."
        );
        require(
          afterReservePool_.pendingWithdrawalsAmount
            == beforeReservePool_.pendingWithdrawalsAmount + (i == reservePoolId_ ? redeemedAssets_ : 0),
          "Invariant violated: The reserve pool's pending withdrawals amount should increase on redemption by the amount of redeemed assets."
        );
      }
    }
  }
}

contract RedeemInvariantsSingleReservePool is RedeemInvariants, InvariantTestWithSingleReservePool {}

contract RedeemInvariantsMultipleReservePools is RedeemInvariants, InvariantTestWithMultipleReservePools {}

contract RedeemInvariantsWithStateTransitionsSingleReservePool is
  RedeemInvariantsWithStateTransitions,
  InvariantTestWithSingleReservePool
{}

contract RedeemInvariantsWithStateTransitionsMultipleReservePools is
  RedeemInvariantsWithStateTransitions,
  InvariantTestWithMultipleReservePools
{}
