// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {DripModelConstant} from "cozy-safety-module-models/DripModelConstant.sol";
import {DripModelConstantFactory} from "cozy-safety-module-models/DripModelConstantFactory.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";

abstract contract DripModelDeploymentHelpers is CozyRouterCommon {
  /// @notice Deploys a new DripModelConstant.
  function deployDripModelConstant(
    DripModelConstantFactory dripModelConstantFactory_,
    address owner_,
    uint256 amountPerSecond_,
    bytes32 baseSalt_
  ) external payable returns (DripModelConstant dripModel_) {
    dripModel_ = dripModelConstantFactory_.deployModel(owner_, amountPerSecond_, baseSalt_);
  }
}
