// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "./interfaces/IERC20.sol";
import {IManager} from "./interfaces/IManager.sol";
import {IDripModel} from "./interfaces/IDripModel.sol";
import {IReceiptToken} from "./interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "./interfaces/IReceiptTokenFactory.sol";
import {UndrippedRewardPoolConfig, ReservePoolConfig, UpdateConfigsCalldataParams} from "./lib/structs/Configs.sol";
import {Delays} from "./lib/structs/Delays.sol";
import {TriggerConfig} from "./lib/structs/Trigger.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";
import {Depositor} from "./lib/Depositor.sol";
import {Redeemer} from "./lib/Redeemer.sol";
import {SlashHandler} from "./lib/SlashHandler.sol";
import {Staker} from "./lib/Staker.sol";
import {SafetyModuleBaseStorage} from "./lib/SafetyModuleBaseStorage.sol";
import {SafetyModuleState} from "./lib/SafetyModuleStates.sol";
import {RewardsHandler} from "./lib/RewardsHandler.sol";
import {FeesHandler} from "./lib/FeesHandler.sol";
import {StateChanger} from "./lib/StateChanger.sol";

contract SafetyModule is
  SafetyModuleBaseStorage,
  Depositor,
  Redeemer,
  SlashHandler,
  Staker,
  RewardsHandler,
  FeesHandler,
  StateChanger
{
  constructor(IManager manager_, IReceiptTokenFactory receiptTokenFactory_) {
    _assertAddressNotZero(address(manager_));
    _assertAddressNotZero(address(receiptTokenFactory_));
    cozyManager = manager_;
    receiptTokenFactory = receiptTokenFactory_;
  }

  function initialize(address owner_, address pauser_, UpdateConfigsCalldataParams calldata configs_) external {
    // Safety Modules are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the logic
    // contract. When the set is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);

    ConfiguratorLib.applyConfigUpdates(
      reservePools, undrippedRewardPools, triggerData, delays, stkTokenToReservePoolIds, receiptTokenFactory, configs_
    );

    dripTimes.lastFeesDripTime = uint128(block.timestamp);
    dripTimes.lastRewardsDripTime = uint128(block.timestamp);
  }
}
