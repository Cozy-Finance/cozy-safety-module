// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IDripModelConstantFactory} from "cozy-safety-module-models/interfaces/IDripModelConstantFactory.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";

abstract contract DripModelDeploymentHelpers is CozyRouterCommon {
  /// @notice The DripModelConstantFactory address.
  IDripModelConstantFactory public immutable dripModelConstantFactory;

  constructor(IDripModelConstantFactory dripModelConstantFactory_) {
    dripModelConstantFactory = dripModelConstantFactory_;
  }

  /// @notice Deploys a new DripModelConstant.
  function deployDripModelConstant(address owner_, uint256 amountPerSecond_, bytes32 baseSalt_)
    external
    payable
    returns (IDripModel dripModel_)
  {
    dripModel_ = dripModelConstantFactory.deployModel(owner_, amountPerSecond_, computeSalt(msg.sender, baseSalt_));
  }
}
