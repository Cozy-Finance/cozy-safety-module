// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Ownable} from "cozy-safety-module-shared/lib/Ownable.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {MathConstants} from "cozy-safety-module-shared/lib/MathConstants.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {AssetPool, ReservePool} from "../../src/lib/structs/Pools.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {ConfigUpdateMetadata} from "../../src/lib/structs/Configs.sol";
import {Slash} from "../../src/lib/structs/Slash.sol";
import {Trigger} from "../../src/lib/structs/Trigger.sol";
import {TriggerState} from "../../src/lib/SafetyModuleStates.sol";
import {ISlashHandlerErrors} from "../../src/interfaces/ISlashHandlerErrors.sol";
import {ITrigger} from "../../src/interfaces/ITrigger.sol";
import {IStateChangerErrors} from "../../src/interfaces/IStateChangerErrors.sol";
import {MockTrigger} from "../utils/MockTrigger.sol";
import {
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract StateTransitionInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  using FixedPointMathLib for uint256;

  mapping(IERC20 => uint256) expectedAssetSlashAmounts;
  mapping(IERC20 => uint256) assetPoolsBeforeSlash;

  struct InternalReservePoolBalances {
    uint256 depositAmount;
    uint256 pendingWithdrawalsAmount;
  }

  function invariant_slashAccountingUpdates() public syncCurrentTimestamp(safetyModuleHandler) {
    ITrigger selectedTrigger_ = safetyModuleHandler.pickValidTrigger(_randomUint256());
    // If there are no valid triggers, we skip this invariant.
    if (selectedTrigger_ == ITrigger(safetyModuleHandler.DEFAULT_ADDRESS())) return;
    Trigger memory selectedTriggerData_ = safetyModule.triggerData(selectedTrigger_);
    // Trigger the trigger.
    MockTrigger(address(selectedTrigger_)).mockState(TriggerState.TRIGGERED);

    // Trigger the safety module putting it in triggered or paused state.
    safetyModule.trigger(selectedTrigger_);

    // If the safety module is not in the triggered state, we skip these invariants.
    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) return;

    Slash[] memory slashes_ = new Slash[](numReservePools);
    InternalReservePoolBalances[] memory reservePoolBeforeSlash_ = new InternalReservePoolBalances[](numReservePools);
    for (uint8 i = 0; i < numReservePools; i++) {
      ReservePool memory reservePool_ = safetyModule.reservePools(i);
      slashes_[i] = Slash({reservePoolId: i, amount: _pickSlashAmount(i)});
      reservePoolBeforeSlash_[i].depositAmount = reservePool_.depositAmount;
      reservePoolBeforeSlash_[i].pendingWithdrawalsAmount = reservePool_.pendingWithdrawalsAmount;
      expectedAssetSlashAmounts[reservePool_.asset] += slashes_[i].amount;
    }

    for (uint8 i = 0; i < assets.length; i++) {
      assetPoolsBeforeSlash[assets[i]] = safetyModule.assetPools(assets[i]).amount;
    }

    // Slash the safety module.
    vm.prank(selectedTriggerData_.payoutHandler);
    safetyModule.slash(slashes_, _randomAddress());

    for (uint8 i = 0; i < numReservePools; i++) {
      ReservePool memory reservePool_ = safetyModule.reservePools(i);

      require(
        reservePoolBeforeSlash_[i].depositAmount - reservePool_.depositAmount == slashes_[i].amount,
        string.concat(
          "Invariant failed: Reserve pool deposit amount slashed does not equal the amount specified in the slash.",
          " reservePoolBeforeSlash_[i].depositAmount: ",
          Strings.toString(reservePoolBeforeSlash_[i].depositAmount),
          ", reservePool_.depositAmount: ",
          Strings.toString(reservePool_.depositAmount),
          ", slashes_[i].amount: ",
          Strings.toString(slashes_[i].amount)
        )
      );

      require(
        reservePoolBeforeSlash_[i].pendingWithdrawalsAmount - reservePool_.pendingWithdrawalsAmount
          <= slashes_[i].amount
        // The pending withdrawals amount slashed is rounded up.
        || (reservePoolBeforeSlash_[i].pendingWithdrawalsAmount - reservePool_.pendingWithdrawalsAmount)
          - slashes_[i].amount == 1,
        string.concat(
          "Invariant failed: Reserve pool pending withdrawals slashed is not lte the amount specified in the slash.",
          " reservePoolBeforeSlash_[i].pendingWithdrawalsAmount: ",
          Strings.toString(reservePoolBeforeSlash_[i].pendingWithdrawalsAmount),
          ", reservePool_.pendingWithdrawalsAmount: ",
          Strings.toString(reservePool_.pendingWithdrawalsAmount),
          ", slashes_[i].amount: ",
          Strings.toString(slashes_[i].amount),
          ", reservePool.depositAmount: ",
          Strings.toString(reservePool_.depositAmount)
        )
      );

      uint256 pendingRedemptionsPercentageChange_ = reservePoolBeforeSlash_[i].pendingWithdrawalsAmount == 0
        ? 0
        : reservePool_.pendingWithdrawalsAmount.mulDivDown(
          MathConstants.ZOC, reservePoolBeforeSlash_[i].pendingWithdrawalsAmount
        );
      uint256 depositAmountPercentageChange_ = reservePoolBeforeSlash_[i].depositAmount == 0
        ? 0
        : reservePool_.depositAmount.mulDivDown(MathConstants.ZOC, reservePoolBeforeSlash_[i].depositAmount);
      require(
        pendingRedemptionsPercentageChange_ <= depositAmountPercentageChange_,
        string.concat(
          "Invariant failed: The percentage change in pending redemptions must be less than or equal to the percentage change in deposit amount.",
          " pendingRedemptionsPercentageChange_: ",
          Strings.toString(pendingRedemptionsPercentageChange_),
          ", depositAmountPercentageChange_: ",
          Strings.toString(depositAmountPercentageChange_)
        )
      );
    }
    for (uint8 i = 0; i < assets.length; i++) {
      require(
        safetyModule.assetPools(assets[i]).amount
          == assetPoolsBeforeSlash[assets[i]] - expectedAssetSlashAmounts[assets[i]],
        string.concat(
          "Invariant failed: Asset pool amount slashed does not equal the amount specified in the slash.",
          " safetyModule.assetPools(assets[i]).amount: ",
          Strings.toString(safetyModule.assetPools(assets[i]).amount),
          ", assetPoolsBeforeSlash[assets[i]]: ",
          Strings.toString(assetPoolsBeforeSlash[assets[i]]),
          ", expectedAssetSlashAmounts[assets[i]]: ",
          Strings.toString(expectedAssetSlashAmounts[assets[i]])
        )
      );
    }

    if (safetyModule.safetyModuleState() == SafetyModuleState.ACTIVE) {
      ConfigUpdateMetadata memory lastConfigUpdate_ = safetyModule.lastConfigUpdate();
      require(
        lastConfigUpdate_.queuedConfigUpdateHash == bytes32(0),
        "Invariant failed: The queued config update hash must be reset to zero when the Safety Module returns to the ACTIVE state after slashing."
      );
    }
  }

  function invariant_cannotSlashReservePoolMoreThanOnceInSingleTx() public syncCurrentTimestamp(safetyModuleHandler) {
    if (numReservePools == 1) return;
    ITrigger selectedTrigger_ = safetyModuleHandler.pickValidTrigger(_randomUint256());
    // If there are no valid triggers, we skip this invariant.
    if (selectedTrigger_ == ITrigger(safetyModuleHandler.DEFAULT_ADDRESS())) return;
    Trigger memory selectedTriggerData_ = safetyModule.triggerData(selectedTrigger_);
    // Trigger the trigger.
    MockTrigger(address(selectedTrigger_)).mockState(TriggerState.TRIGGERED);

    // Trigger the safety module putting it in triggered or paused state.
    safetyModule.trigger(selectedTrigger_);

    // If the safety module is not in the triggered state, we skip these invariants.
    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) return;

    // Randomize number of reservePools to slash.
    Slash[] memory slashes_ = new Slash[](bound(_randomUint256() % numReservePools, 2, numReservePools));
    for (uint8 i = 0; i < slashes_.length; i++) {
      slashes_[i] = Slash({reservePoolId: i, amount: _pickSlashAmount(i)});
    }

    // Randomize which reservePool slash is duped.
    uint256 dupedA_ = _randomUint256() % slashes_.length;
    bool useBefore_ = (dupedA_ != 0 && _randomUint256() % 2 == 0) || dupedA_ == slashes_.length - 1;
    uint256 dupedB_ = useBefore_
      ? bound(_randomUint256() % slashes_.length, 0, dupedA_ - 1)
      : bound(_randomUint256() % slashes_.length, dupedA_ + 1, slashes_.length - 1);
    slashes_[dupedB_] = slashes_[dupedA_];

    // Attempt to slash the safety module.
    vm.prank(selectedTriggerData_.payoutHandler);
    vm.expectRevert(
      abi.encodeWithSelector(ISlashHandlerErrors.AlreadySlashed.selector, slashes_[dupedA_].reservePoolId)
    );
    safetyModule.slash(slashes_, _randomAddress());
  }

  function invariant_cannotSlashIfSafetyModuleNotTriggered() public syncCurrentTimestamp(safetyModuleHandler) {
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) return;

    for (uint256 i = 0; i < triggers.length; i++) {
      ITrigger trigger_ = triggers[i];
      Trigger memory triggerData_ = safetyModule.triggerData(trigger_);

      // Attempt to slash the safety module.
      if (safetyModule.payoutHandlerNumPendingSlashes(triggerData_.payoutHandler) == 0) {
        vm.expectRevert(Ownable.Unauthorized.selector);
      } else {
        vm.expectRevert(ICommonErrors.InvalidState.selector);
      }
      vm.prank(triggerData_.payoutHandler);
      safetyModule.slash(new Slash[](0), _randomAddress());
    }
  }

  function invariant_cannotSlashIfNoPendingSlashesForCaller() public syncCurrentTimestamp(safetyModuleHandler) {
    address caller_ = _randomAddress();
    if (safetyModule.payoutHandlerNumPendingSlashes(caller_) > 0) return;

    vm.expectRevert(Ownable.Unauthorized.selector);
    vm.prank(caller_);
    safetyModule.slash(new Slash[](0), _randomAddress());
  }

  function invariant_cannotSlashMoreThanMaxSlashPercentage() public syncCurrentTimestamp(safetyModuleHandler) {
    ITrigger selectedTrigger_ = safetyModuleHandler.pickValidTrigger(_randomUint256());
    // If there are no valid triggers, we skip this invariant.
    if (selectedTrigger_ == ITrigger(safetyModuleHandler.DEFAULT_ADDRESS())) return;
    Trigger memory selectedTriggerData_ = safetyModule.triggerData(selectedTrigger_);
    // Trigger the trigger.
    MockTrigger(address(selectedTrigger_)).mockState(TriggerState.TRIGGERED);

    // Trigger the safety module putting it in triggered or paused state.
    safetyModule.trigger(selectedTrigger_);

    // If the safety module is not in the triggered state, we skip these invariants.
    if (safetyModule.safetyModuleState() != SafetyModuleState.TRIGGERED) return;

    Slash[] memory slashes_ = new Slash[](1);
    uint8 reservePoolId_ = safetyModuleHandler.pickValidReservePoolId(_randomUint256());
    ReservePool memory reservePool_ = safetyModule.reservePools(reservePoolId_);

    if (reservePool_.depositAmount == 0) return;

    uint256 maxSlashAmount_ = safetyModule.getMaxSlashableReservePoolAmount(reservePoolId_);
    uint256 amountToSlash_ = bound(_randomUint256(), maxSlashAmount_ + 1, type(uint128).max);
    uint256 slashPercentage_ = amountToSlash_.mulDivUp(MathConstants.ZOC, reservePool_.depositAmount);
    slashes_[0] = Slash({reservePoolId: reservePoolId_, amount: amountToSlash_});

    // Attempt to slash the safety module.
    vm.prank(selectedTriggerData_.payoutHandler);
    vm.expectRevert(
      abi.encodeWithSelector(ISlashHandlerErrors.ExceedsMaxSlashPercentage.selector, reservePoolId_, slashPercentage_)
    );
    safetyModule.slash(slashes_, _randomAddress());
  }

  function _pickSlashAmount(uint8 reservePoolId_) internal view returns (uint256) {
    ReservePool memory reservePool_ = safetyModule.reservePools(reservePoolId_);
    uint256 slashPercentage_ = bound(_randomUint256() % MathConstants.ZOC, 0, reservePool_.maxSlashPercentage);
    return reservePool_.depositAmount.mulDivDown(slashPercentage_, MathConstants.ZOC);
  }
}

contract SlashInvariantsWithStateTransitionsSingleReservePool is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithSingleReservePool
{}

contract SlashInvariantsWithStateTransitionsMultipleReservePools is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithMultipleReservePools
{}
