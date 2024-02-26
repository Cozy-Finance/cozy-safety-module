// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IChainlinkTriggerFactory} from "src/interfaces/IChainlinkTriggerFactory.sol";
import {IConnector} from "./interfaces/IConnector.sol";
import {ICozySafetyModuleManager} from "./interfaces/ICozySafetyModuleManager.sol";
import {IOwnableTriggerFactory} from "./interfaces/IOwnableTriggerFactory.sol";
import {IWeth} from "./interfaces/IWeth.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IUMATriggerFactory} from "./interfaces/IUMATriggerFactory.sol";
import {CozyRouterCommon} from "./lib/router/CozyRouterCommon.sol";
import {SafetyModuleDeploymentHelpers} from "./lib/router/SafetyModuleDeploymentHelpers.sol";
import {SafetyModuleActions} from "./lib/router/SafetyModuleActions.sol";
import {TokenHelpers} from "./lib/router/TokenHelpers.sol";
import {TriggerDeploymentHelpers} from "./lib/router/TriggerDeploymentHelpers.sol";

contract CozyRouter is
  CozyRouterCommon,
  SafetyModuleDeploymentHelpers,
  SafetyModuleActions,
  TokenHelpers,
  TriggerDeploymentHelpers
{
  /// @dev Thrown when a call in `aggregate` fails, contains the index of the call and the data it returned.
  error CallFailed(uint256 index, bytes returnData);

  constructor(
    ICozySafetyModuleManager manager_,
    IWeth weth_,
    IStETH stEth_,
    IWstETH wstEth_,
    IChainlinkTriggerFactory chainlinkTriggerFactory_,
    IOwnableTriggerFactory ownableTriggerFactory_,
    IUMATriggerFactory umaTriggerFactory_
  )
    CozyRouterCommon(manager_)
    TokenHelpers(weth_, stEth_, wstEth_)
    TriggerDeploymentHelpers(chainlinkTriggerFactory_, ownableTriggerFactory_, umaTriggerFactory_)
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
