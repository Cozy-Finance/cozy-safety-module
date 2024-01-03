// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IManagerEvents} from "./IManagerEvents.sol";
import {ISafetyModule} from "./ISafetyModule.sol";
import {IDripModel} from "./IDripModel.sol";

interface IManager is IManagerEvents {
  function getFeeDripModel(ISafetyModule safetyModule_) external view returns (IDripModel);
}
