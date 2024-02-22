// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ITrigger} from "../../interfaces/ITrigger.sol";

struct Trigger {
  // Whether the trigger exists.
  bool exists;
  // The payout handler that is authorized to slash assets when the trigger is triggered.
  address payoutHandler;
  // Whether the trigger has triggered the SafetyModule. A trigger cannot trigger the SafetyModule more than once.
  bool triggered;
}

struct TriggerConfig {
  // The trigger that is being configured.
  ITrigger trigger;
  // The address that is authorized to slash assets when the trigger is triggered.
  address payoutHandler;
  // Whether the trigger is used by the SafetyModule.
  bool exists;
}

struct TriggerMetadata {
  // The name that should be used for SafetyModules that use the trigger.
  string name;
  // A human-readable description of the trigger.
  string description;
  // The URI of a logo image to represent the trigger.
  string logoURI;
  // Any extra data that should be included in the trigger's metadata.
  string extraData;
}
