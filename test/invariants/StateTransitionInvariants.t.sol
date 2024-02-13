// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {ReservePool} from "../../src/lib/structs/Pools.sol";
import {SafetyModuleState} from "../../src/lib/SafetyModuleStates.sol";
import {Trigger} from "../../src/lib/structs/Trigger.sol";
import {ITrigger} from "../../src/interfaces/ITrigger.sol";
import {
  InvariantTestBaseWithStateTransitions,
  InvariantTestWithSingleReservePool,
  InvariantTestWithMultipleReservePools
} from "./utils/InvariantTestBase.sol";

abstract contract StateTransitionInvariantsWithStateTransitions is InvariantTestBaseWithStateTransitions {
  using FixedPointMathLib for uint256;

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
}

contract StateTransitionInvariantsWithStateTransitionsSingleReservePool is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithSingleReservePool
{}

contract StateTransitionInvariantsWithStateTransitionsMultipleReservePools is
  StateTransitionInvariantsWithStateTransitions,
  InvariantTestWithMultipleReservePools
{}
