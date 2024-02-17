// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {Slash} from "../../src/lib/structs/Slash.sol";
import {Trigger} from "../../src/lib/structs/Trigger.sol";
import {TriggerState} from "../../src/lib/SafetyModuleStates.sol";
import {ITrigger} from "../../src/interfaces/ITrigger.sol";
import {IStateChangerErrors} from "../../src/interfaces/IStateChangerErrors.sol";
import {MockTrigger} from "../utils/MockTrigger.sol";
import {
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract StateTransitionInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  function invariant_nonZeroPendingSlashesImpliesTriggeredOrPaused() public syncCurrentTimestamp(safetyModuleHandler) {
    if (safetyModule.numPendingSlashes() > 0) {
      require(
        safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED
          || safetyModule.safetyModuleState() == SafetyModuleState.PAUSED,
        "Invariant Violated: The safety module's state must be triggered or paused when the number of pending slashes is non-zero."
      );
    } else {
      require(
        safetyModule.safetyModuleState() == SafetyModuleState.ACTIVE
          || safetyModule.safetyModuleState() == SafetyModuleState.PAUSED,
        "Invariant Violated: The safety module's state must be active or paused when the number of pending slashes is zero."
      );
    }
  }

  mapping(address => bool) internal payoutHandlerSeen;

  function invariant_numPendingSlashesEqualsPayoutHandlerNumPendingSlashesSum()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    ITrigger[] memory triggers_ = safetyModuleHandler.getTriggers();

    uint256 payoutHandlerNumPendingSlashesSum_ = 0;
    for (uint256 i = 0; i < triggers_.length; i++) {
      Trigger memory triggerData_ = safetyModule.triggerData(triggers_[i]);
      if (!payoutHandlerSeen[triggerData_.payoutHandler]) {
        payoutHandlerSeen[triggerData_.payoutHandler] = true;
        payoutHandlerNumPendingSlashesSum_ += safetyModule.payoutHandlerNumPendingSlashes(triggerData_.payoutHandler);
      }
    }

    require(
      safetyModule.numPendingSlashes() == payoutHandlerNumPendingSlashesSum_,
      string.concat(
        "Invariant Violated: The number of pending slashes must equal the sum of the payout handler's number of pending slashes.",
        " safetyModule.numPendingSlashes: ",
        Strings.toString(safetyModule.numPendingSlashes()),
        ", payoutHandlerNumPendingSlashesSum_: ",
        Strings.toString(payoutHandlerNumPendingSlashesSum_)
      )
    );
  }

  function invariant_triggeredTriggersAreTriggered() public syncCurrentTimestamp(safetyModuleHandler) {
    ITrigger[] memory triggeredTriggers_ = safetyModuleHandler.getTriggeredTriggers();

    for (uint256 i = 0; i < triggeredTriggers_.length; i++) {
      Trigger memory triggerData_ = safetyModule.triggerData(triggeredTriggers_[i]);
      require(
        triggerData_.triggered && triggerData_.exists,
        string.concat(
          "Invariant Violated: A trigger must be marked as triggered when its state is triggered.",
          " trigger: ",
          Strings.toHexString(uint160(address(triggeredTriggers_[i])))
        )
      );
    }
  }

  function invariant_triggersExistence() public syncCurrentTimestamp(safetyModuleHandler) {
    ITrigger[] memory triggers_ = safetyModuleHandler.getTriggers();

    for (uint256 i = 0; i < triggers_.length; i++) {
      Trigger memory triggerData_ = safetyModule.triggerData(triggers_[i]);
      require(
        triggerData_.exists,
        string.concat(
          "Invariant Violated: Triggers configured for the safety module to use must exist.",
          " trigger: ",
          Strings.toHexString(uint160(address(triggers_[i])))
        )
      );
    }

    for (uint256 i = 0; i < nonExistingTriggers.length; i++) {
      Trigger memory triggerData_ = safetyModule.triggerData(nonExistingTriggers[i]);
      require(
        !triggerData_.exists,
        string.concat(
          "Invariant Violated: Triggers not configured for the safety module to use must not exist.",
          " trigger: ",
          Strings.toHexString(uint160(address(nonExistingTriggers[i])))
        )
      );
    }
  }

  function invariant_pauseByAuthorizedCallerPossible() public syncCurrentTimestamp(safetyModuleHandler) {
    address[3] memory authorizedCallers_ =
      [safetyModule.owner(), safetyModule.pauser(), address(safetyModule.cozySafetyModuleManager())];
    address caller_ = authorizedCallers_[_randomUint16() % authorizedCallers_.length];

    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidStateTransition.selector);
    }

    vm.prank(caller_);
    safetyModule.pause();
    require(
      safetyModule.safetyModuleState() == SafetyModuleState.PAUSED,
      "Invariant Violated: The safety module's state must be paused."
    );
  }

  function invariant_pauseByUnauthorizedCallerReverts() public syncCurrentTimestamp(safetyModuleHandler) {
    address[3] memory authorizedCallers_ =
      [safetyModule.owner(), safetyModule.pauser(), address(safetyModule.cozySafetyModuleManager())];
    address caller_ = _randomAddress();
    for (uint256 i = 0; i < authorizedCallers_.length; i++) {
      vm.assume(caller_ != authorizedCallers_[i]);
    }

    vm.expectRevert(ICommonErrors.InvalidStateTransition.selector);
    vm.prank(caller_);
    safetyModule.pause();
  }

  function invariant_unpauseTransitionsToExpectedSafetyModuleState() public syncCurrentTimestamp(safetyModuleHandler) {
    address[2] memory authorizedCallers_ = [safetyModule.owner(), address(safetyModule.cozySafetyModuleManager())];
    address caller_ = authorizedCallers_[_randomUint16() % authorizedCallers_.length];

    SafetyModuleState expectedState_;
    SafetyModuleState currentState_ = safetyModule.safetyModuleState();
    if (currentState_ != SafetyModuleState.PAUSED) expectedState_ = currentState_;
    else expectedState_ = safetyModule.numPendingSlashes() > 0 ? SafetyModuleState.TRIGGERED : SafetyModuleState.ACTIVE;

    if (currentState_ != SafetyModuleState.PAUSED) vm.expectRevert(ICommonErrors.InvalidStateTransition.selector);

    vm.prank(caller_);
    safetyModule.unpause();
    require(
      safetyModule.safetyModuleState() == expectedState_,
      "Invariant Violated: The safety module's state does not match expected state after unpause."
    );
  }

  function invariant_unpauseByUnauthorizedCallerReverts() public syncCurrentTimestamp(safetyModuleHandler) {
    address[2] memory authorizedCallers_ = [safetyModule.owner(), address(safetyModule.cozySafetyModuleManager())];
    address[2] memory callers_ = [_randomAddress(), safetyModule.pauser()];
    for (uint256 i = 0; i < authorizedCallers_.length; i++) {
      vm.assume(callers_[0] != authorizedCallers_[i]);
    }

    for (uint256 i = 0; i < callers_.length; i++) {
      vm.expectRevert(ICommonErrors.InvalidStateTransition.selector);
      vm.prank(callers_[i]);
      safetyModule.unpause();
    }
  }

  function invariant_triggerTransitionsToExpectedSafetyModuleState() public syncCurrentTimestamp(safetyModuleHandler) {
    (ITrigger selectedTrigger_, Trigger memory selectedTriggerData_) = _pickRandomTriggerAndTriggerData();

    SafetyModuleState expectedState_;
    if (safetyModule.safetyModuleState() == SafetyModuleState.ACTIVE) {
      expectedState_ = SafetyModuleState.TRIGGERED;
    } else if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      expectedState_ = SafetyModuleState.TRIGGERED;
    } else {
      expectedState_ = SafetyModuleState.PAUSED;
    }

    bool shouldRevert = !selectedTriggerData_.exists || selectedTrigger_.state() != TriggerState.TRIGGERED
      || selectedTriggerData_.triggered;
    if (shouldRevert) {
      expectedState_ = safetyModule.safetyModuleState();
      vm.expectRevert(IStateChangerErrors.InvalidTrigger.selector);
    }

    vm.prank(selectedTriggerData_.payoutHandler);
    safetyModule.trigger(selectedTrigger_);
    require(
      safetyModule.safetyModuleState() == expectedState_,
      "Invariant Violated: The safety module's state does not match expected state after trigger."
    );
  }

  function invariant_triggerUpdatesNumPendingSlashes() public syncCurrentTimestamp(safetyModuleHandler) {
    (ITrigger selectedTrigger_, Trigger memory selectedTriggerData_) = _pickRandomTriggerAndTriggerData();

    bool shouldRevert = !selectedTriggerData_.exists || selectedTrigger_.state() != TriggerState.TRIGGERED
      || selectedTriggerData_.triggered;

    uint256 expectedNumPendingSlashes_ = safetyModule.numPendingSlashes();
    uint256 payoutHandlerNumPendingSlashes_ =
      safetyModule.payoutHandlerNumPendingSlashes(selectedTriggerData_.payoutHandler);
    if (!shouldRevert) {
      expectedNumPendingSlashes_ += 1;
      payoutHandlerNumPendingSlashes_ += 1;
    }
    if (shouldRevert) vm.expectRevert(IStateChangerErrors.InvalidTrigger.selector);

    vm.prank(selectedTriggerData_.payoutHandler);
    safetyModule.trigger(selectedTrigger_);
    require(
      safetyModule.numPendingSlashes() == expectedNumPendingSlashes_,
      string.concat(
        "Invariant Violated: The number of pending slashes must be updated after a trigger.",
        " safetyModule.numPendingSlashes: ",
        Strings.toString(safetyModule.numPendingSlashes()),
        ", expectedNumPendingSlashes_: ",
        Strings.toString(expectedNumPendingSlashes_)
      )
    );
    require(
      safetyModule.payoutHandlerNumPendingSlashes(selectedTriggerData_.payoutHandler) == payoutHandlerNumPendingSlashes_,
      string.concat(
        "Invariant Violated: The payout handler's number of pending slashes must be updated after a trigger.",
        " safetyModule.payoutHandlerNumPendingSlashes(selectedTriggerData_.payoutHandler): ",
        Strings.toString(safetyModule.payoutHandlerNumPendingSlashes(selectedTriggerData_.payoutHandler)),
        ", payoutHandlerNumPendingSlashes_: ",
        Strings.toString(payoutHandlerNumPendingSlashes_)
      )
    );
  }

  function invariant_triggerUpdatesTriggerDataBool() public syncCurrentTimestamp(safetyModuleHandler) {
    ITrigger selectedTrigger_ = safetyModuleHandler.pickValidTrigger(_randomUint256());
    // If there are no valid triggers, we skip this invariant.
    if (selectedTrigger_ == ITrigger(safetyModuleHandler.DEFAULT_ADDRESS())) return;
    Trigger memory selectedTriggerData_ = safetyModule.triggerData(selectedTrigger_);

    // Trigger the trigger.
    MockTrigger(address(selectedTrigger_)).mockState(TriggerState.TRIGGERED);

    vm.prank(selectedTriggerData_.payoutHandler);
    safetyModule.trigger(selectedTrigger_);
    require(
      safetyModule.triggerData(selectedTrigger_).triggered,
      "Invariant Violated: The trigger's triggered bool must be updated after a trigger."
    );
  }

  function invariant_slashTransitionsToExpectedSafetyModuleState() public syncCurrentTimestamp(safetyModuleHandler) {
    ITrigger selectedTrigger_ = safetyModuleHandler.pickValidTrigger(_randomUint256());
    // If there are no valid triggers, we skip this invariant.
    if (selectedTrigger_ == ITrigger(safetyModuleHandler.DEFAULT_ADDRESS())) return;
    Trigger memory selectedTriggerData_ = safetyModule.triggerData(selectedTrigger_);
    // Trigger the trigger.
    MockTrigger(address(selectedTrigger_)).mockState(TriggerState.TRIGGERED);
    // Trigger the safety module putting it in triggered or paused state.
    safetyModule.trigger(selectedTrigger_);

    SafetyModuleState currentState_ = safetyModule.safetyModuleState();
    SafetyModuleState expectedState_;
    if (currentState_ == SafetyModuleState.TRIGGERED && safetyModule.numPendingSlashes() == 1) {
      expectedState_ = SafetyModuleState.ACTIVE;
    } else if (currentState_ == SafetyModuleState.TRIGGERED && safetyModule.numPendingSlashes() >= 2) {
      expectedState_ = SafetyModuleState.TRIGGERED;
    } else {
      expectedState_ = currentState_;
    }

    if (currentState_ != SafetyModuleState.TRIGGERED) vm.expectRevert(ICommonErrors.InvalidState.selector);

    // Slash the safety module.
    vm.prank(selectedTriggerData_.payoutHandler);
    safetyModule.slash(new Slash[](0), _randomAddress());

    require(
      safetyModule.safetyModuleState() == expectedState_,
      "Invariant Violated: The safety module's state does not match expected state after slash."
    );
  }

  function invariant_slashUpdatesNumPendingSlashes() public syncCurrentTimestamp(safetyModuleHandler) {
    ITrigger selectedTrigger_ = safetyModuleHandler.pickValidTrigger(_randomUint256());
    // If there are no valid triggers, we skip this invariant.
    if (selectedTrigger_ == ITrigger(safetyModuleHandler.DEFAULT_ADDRESS())) return;
    Trigger memory selectedTriggerData_ = safetyModule.triggerData(selectedTrigger_);
    // Trigger the trigger.
    MockTrigger(address(selectedTrigger_)).mockState(TriggerState.TRIGGERED);

    // Trigger the safety module putting it in triggered or paused state.
    safetyModule.trigger(selectedTrigger_);

    uint256 expectedNumPendingSlashes_ = safetyModule.numPendingSlashes();
    uint256 payoutHandlerNumPendingSlashes_ =
      safetyModule.payoutHandlerNumPendingSlashes(selectedTriggerData_.payoutHandler);
    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      expectedNumPendingSlashes_ -= 1;
      payoutHandlerNumPendingSlashes_ -= 1;
    } else {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
    }

    // Slash the safety module.
    vm.prank(selectedTriggerData_.payoutHandler);
    safetyModule.slash(new Slash[](0), _randomAddress());

    require(
      safetyModule.numPendingSlashes() == expectedNumPendingSlashes_,
      string.concat(
        "Invariant Violated: The number of pending slashes must be updated after a slash.",
        " safetyModule.numPendingSlashes: ",
        Strings.toString(safetyModule.numPendingSlashes()),
        ", expectedNumPendingSlashes_: ",
        Strings.toString(expectedNumPendingSlashes_)
      )
    );
    require(
      safetyModule.payoutHandlerNumPendingSlashes(selectedTriggerData_.payoutHandler) == payoutHandlerNumPendingSlashes_,
      string.concat(
        "Invariant Violated: The payout handler's number of pending slashes must be updated after a slash.",
        " safetyModule.payoutHandlerNumPendingSlashes(selectedTriggerData_.payoutHandler): ",
        Strings.toString(safetyModule.payoutHandlerNumPendingSlashes(selectedTriggerData_.payoutHandler)),
        ", payoutHandlerNumPendingSlashes_: ",
        Strings.toString(payoutHandlerNumPendingSlashes_)
      )
    );
  }

  function invariant_redeemRevertsWhenTriggered() public syncCurrentTimestamp(safetyModuleHandler) {
    uint8 reservePoolId_ = safetyModuleHandler.pickValidReservePoolId(_randomUint256());

    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(_randomAddress());
      safetyModule.redeem(reservePoolId_, _randomUint256(), _randomAddress(), _randomAddress());
    }
  }

  function invariant_previewRedemptionRevertsWhenTriggered() public syncCurrentTimestamp(safetyModuleHandler) {
    uint8 reservePoolId_ = safetyModuleHandler.pickValidReservePoolId(_randomUint256());

    if (safetyModule.safetyModuleState() == SafetyModuleState.TRIGGERED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(_randomAddress());
      safetyModule.previewRedemption(reservePoolId_, _randomUint256());
    }
  }

  function invariant_depositReserveAssetsWithoutTransferRevertsWhenPaused()
    public
    syncCurrentTimestamp(safetyModuleHandler)
  {
    uint8 reservePoolId_ = safetyModuleHandler.pickValidReservePoolId(_randomUint256());

    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(_randomAddress());
      safetyModule.depositReserveAssetsWithoutTransfer(reservePoolId_, _randomUint256(), _randomAddress());
    }
  }

  function invariant_depositReserveAssetsRevertsWhenPaused() public syncCurrentTimestamp(safetyModuleHandler) {
    address actor_ = _randomAddress();
    uint8 reservePoolId_ = safetyModuleHandler.pickValidReservePoolId(_randomUint256());
    IERC20 asset_ = safetyModule.reservePools(reservePoolId_).asset;

    uint256 depositAmount_ = bound(_randomUint64(), 1, type(uint64).max);
    deal(address(asset_), actor_, depositAmount_, true);

    vm.prank(actor_);
    asset_.approve(address(safetyModule), depositAmount_);

    if (safetyModule.safetyModuleState() == SafetyModuleState.PAUSED) {
      vm.expectRevert(ICommonErrors.InvalidState.selector);
      vm.prank(actor_);
      safetyModule.depositReserveAssets(reservePoolId_, depositAmount_, _randomAddress(), actor_);
    }
  }

  function _pickRandomTriggerAndTriggerData() internal view returns (ITrigger, Trigger memory) {
    ITrigger[] memory triggers_ = safetyModuleHandler.getTriggers();
    ITrigger selectedTrigger_ = triggers_[_randomUint256() % triggers_.length];
    return (selectedTrigger_, safetyModule.triggerData(selectedTrigger_));
  }
}

contract StateTransitionInvariantsWithStateTransitionsSingleReservePool is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithSingleReservePool
{}

contract StateTransitionInvariantsWithStateTransitionsMultipleReservePools is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithMultipleReservePools
{}
