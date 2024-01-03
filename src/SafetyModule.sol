// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "./interfaces/IERC20.sol";
import {IManager} from "./interfaces/IManager.sol";
import {IDripModel} from "./interfaces/IDripModel.sol";
import {IReceiptToken} from "./interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "./interfaces/IReceiptTokenFactory.sol";
import {UndrippedRewardPoolConfig, ReservePoolConfig} from "./lib/structs/Configs.sol";
import {Delays} from "./lib/structs/Delays.sol";
import {ConfiguratorLib} from "./lib/ConfiguratorLib.sol";
import {Depositor} from "./lib/Depositor.sol";
import {Governable} from "./lib/Governable.sol";
import {Redeemer} from "./lib/Redeemer.sol";
import {TriggerHandler} from "./lib/TriggerHandler.sol";
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
  TriggerHandler,
  SlashHandler,
  Staker,
  RewardsHandler,
  FeesHandler
{
  constructor(IManager manager_, IReceiptTokenFactory receiptTokenFactory_) {
    _assertAddressNotZero(address(manager_));
    _assertAddressNotZero(address(receiptTokenFactory_));
    cozyManager = manager_;
    receiptTokenFactory = receiptTokenFactory_;
  }

  function initialize(
    address owner_,
    address pauser_,
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) external {
    // Safety Modules are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the logic
    // contract. When the set is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);

    ConfiguratorLib.applyConfigUpdates(
      reservePools,
      undrippedRewardPools,
      delays,
      stkTokenToReservePoolIds,
      receiptTokenFactory,
      reservePoolConfigs_,
      undrippedRewardPoolConfigs_,
      delaysConfig_
    );

    dripTimes.lastFeesDripTime = uint128(block.timestamp);
    dripTimes.lastRewardsDripTime = uint128(block.timestamp);
  }
}
