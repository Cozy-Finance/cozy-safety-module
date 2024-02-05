// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

struct Delays {
  // Duration between when safety module updates are queued and when they can be executed.
  uint64 configUpdateDelay;
  // Defines how long the owner has to execute a configuration change, once it can be executed.
  uint64 configUpdateGracePeriod;
  // Delay for two-step withdraw process (for deposited assets).
  uint64 withdrawDelay;
}
