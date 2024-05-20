// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

/// @notice Delays for the SafetyModule.
struct Delays {
  // Duration between when SafetyModule updates are queued and when they can be executed.
  uint64 configUpdateDelay;
  // Defines how long the owner has to execute a configuration change, once it can be executed.
  uint64 configUpdateGracePeriod;
  // Delay for two-step withdraw process (for deposited reserve assets).
  uint64 withdrawDelay;
}
