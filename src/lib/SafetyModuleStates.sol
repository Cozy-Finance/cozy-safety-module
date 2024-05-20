// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

enum SafetyModuleState {
  ACTIVE,
  TRIGGERED,
  PAUSED
}

enum TriggerState {
  ACTIVE,
  TRIGGERED,
  FROZEN
}
