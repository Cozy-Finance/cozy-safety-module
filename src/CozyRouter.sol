// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ICozyManager} from "cozy-safety-module-rewards-manager/interfaces/ICozyManager.sol";
import {IDripModelConstantFactory} from "cozy-safety-module-models/interfaces/IDripModelConstantFactory.sol";
import {ICozySafetyModuleManager} from "./interfaces/ICozySafetyModuleManager.sol";
import {IWeth} from "./interfaces/IWeth.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {CozyRouterCommon} from "./lib/router/CozyRouterCommon.sol";
import {DripModelDeploymentHelpers} from "./lib/router/DripModelDeploymentHelpers.sol";
import {RewardsManagerDeploymentHelpers} from "./lib/router/RewardsManagerDeploymentHelpers.sol";
import {SafetyModuleDeploymentHelpers} from "./lib/router/SafetyModuleDeploymentHelpers.sol";
import {SafetyModuleActions} from "./lib/router/SafetyModuleActions.sol";
import {TokenHelpers} from "./lib/router/TokenHelpers.sol";
import {TriggerDeploymentHelpers} from "./lib/router/TriggerDeploymentHelpers.sol";
import {TriggerFactories} from "./lib/structs/TriggerFactories.sol";

contract CozyRouter is
  CozyRouterCommon,
  SafetyModuleDeploymentHelpers,
  RewardsManagerDeploymentHelpers,
  DripModelDeploymentHelpers,
  SafetyModuleActions,
  TokenHelpers,
  TriggerDeploymentHelpers
{
  /// @dev Thrown when a call in `aggregate` fails, contains the index of the call and the data it returned.
  error CallFailed(uint256 index, bytes returnData);

  constructor(
    ICozySafetyModuleManager safetyModuleCozyManager_,
    ICozyManager rewardsManagerCozyManager_,
    IWeth weth_,
    IStETH stEth_,
    IWstETH wstEth_,
    TriggerFactories memory triggerFactories_,
    IDripModelConstantFactory dripModelConstantFactory_
  )
    CozyRouterCommon(safetyModuleCozyManager_)
    TokenHelpers(weth_, stEth_, wstEth_)
    DripModelDeploymentHelpers(dripModelConstantFactory_)
    RewardsManagerDeploymentHelpers(rewardsManagerCozyManager_)
    TriggerDeploymentHelpers(triggerFactories_)
  {}

  receive() external payable {}

  // ---------------------------
  // -------- Multicall --------
  // ---------------------------

  /// @notice Enables batching of multiple router calls into a single transaction.
  /// @dev All methods in this contract must be payable to support sending ETH with a batch call.
  /// @param calls_ Array of ABI encoded calls to be performed.
  function aggregate(bytes[] calldata calls_) external payable returns (bytes[] memory returnData_) {
    returnData_ = new bytes[](calls_.length);

    for (uint256 i = 0; i < calls_.length; i++) {
      (bool success_, bytes memory response_) = address(this).delegatecall(calls_[i]);
      if (!success_) revert CallFailed(i, response_);
      returnData_[i] = response_;
    }
  }
}
