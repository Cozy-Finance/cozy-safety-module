// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {Governable} from "cozy-safety-module-shared/lib/Governable.sol";
import {ICozySafetyModuleManager} from "../../src/interfaces/ICozySafetyModuleManager.sol";
import {ISafetyModule} from "../../src/interfaces/ISafetyModule.sol";

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
