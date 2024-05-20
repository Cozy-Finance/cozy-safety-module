// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IChainlinkTriggerFactory} from "../../interfaces/IChainlinkTriggerFactory.sol";
import {IOwnableTriggerFactory} from "../../interfaces/IOwnableTriggerFactory.sol";
import {IUMATriggerFactory} from "../../interfaces/IUMATriggerFactory.sol";

struct TriggerFactories {
  IChainlinkTriggerFactory chainlinkTriggerFactory;
  IOwnableTriggerFactory ownableTriggerFactory;
  IUMATriggerFactory umaTriggerFactory;
}
