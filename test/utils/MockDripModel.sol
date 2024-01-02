// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "../../src/interfaces/IDripModel.sol";

contract MockDripModel is IDripModel {
  uint256 public dripFactorConstant;

  constructor(uint256 dripFactorConstant_) {
    dripFactorConstant = dripFactorConstant_;
  }

  function dripFactor(uint256, /* lastDripTime_ */ uint256 /* timeSinceLastDrip_ */ )
    external
    view
    override
    returns (uint256)
  {
    return dripFactorConstant;
  }
}
