// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {ITrigger} from "../../src/interfaces/ITrigger.sol";
import {TriggerState} from "../../src/lib/SafetyModuleStates.sol";

contract MockTrigger is ITrigger {
  TriggerState public state;

  constructor(TriggerState state_) {
    state = state_;
  }

  function mockState(TriggerState state_) external {
    state = state_;
  }
}
