// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "../../src/interfaces/IDripModel.sol";

contract MockDripModel is IDripModel {
  uint256 public dripFactorConstant;

  constructor(uint256 dripFactorConstant_) {
    dripFactorConstant = dripFactorConstant_;
  }

  function dripFactor(uint256 lastDripTime_) external view override returns (uint256) {
    if (block.timestamp - lastDripTime_ == 0) return 0;
    return dripFactorConstant;
  }
}
