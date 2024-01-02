// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IDripModel} from "../../interfaces/IDripModel.sol";
import {ISafetyModule} from "../../interfaces/ISafetyModule.sol";

struct FeesConfig {
  IDripModel feeDripModel; // The default drip model for all fees.
  mapping(ISafetyModule => DripModelLookup) overrideFeeDripModels; // Override drip models for specific SafetyModules.
}

struct DripModelLookup {
  IDripModel dripModel;
  bool exists;
}
