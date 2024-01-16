// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ITrigger} from "../../interfaces/ITrigger.sol";

/// @param exists Whether the trigger exists.
/// @param payoutHandler The payout handler that is authorized to slash assets when the trigger is triggered.
/// @param triggered Whether the trigger has triggered the safety module. A trigger cannot trigger the safety module
///        more than once.
struct Trigger {
  bool exists;
  address payoutHandler;
  bool triggered;
}

struct TriggerConfig {
  ITrigger trigger;
  address payoutHandler;
  bool exists;
}

struct TriggerMetadata {
  // The name that should be used for safety modules that use the trigger.
  string name;
  // A human-readable description of the trigger.
  string description;
  // The URI of a logo image to represent the trigger.
  string logoURI;
  // Any extra data that should be included in the trigger's metadata.
  string extraData;
}
