// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IManager} from "../../src/interfaces/IManager.sol";
import {ISafetyModule} from "../../src/interfaces/ISafetyModule.sol";
import {IDripModel} from "../../src/interfaces/IDripModel.sol";
import {Governable} from "../../src/lib/Governable.sol";

contract MockManager is Governable {
  IDripModel public feeDripModel;
  uint256 public allowedReservePools;
  uint256 public allowedRewardPools;

  function initGovernable(address owner_, address pauser_) external {
    __initGovernable(owner_, pauser_);
  }

  function setOwner(address owner_) external {
    owner = owner_;
  }

  function setFeeDripModel(IDripModel feeDripModel_) external {
    feeDripModel = feeDripModel_;
  }

  function getFeeDripModel(ISafetyModule /* safetyModule_ */ ) external view returns (IDripModel) {
    return feeDripModel;
  }

  function setAllowedReservePools(uint256 allowedReservePools_) external {
    allowedReservePools = allowedReservePools_;
  }
}
