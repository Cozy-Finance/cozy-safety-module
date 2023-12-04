// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

struct InactivePeriod {
  uint64 startTime;
  uint64 cumulativeDuration;
}

/// @dev A safety module is considered inactive when it's FROZEN or PAUSED.
struct InactivityData {
  uint64 inactiveTransitionTime;
  InactivePeriod[] periods;
}
