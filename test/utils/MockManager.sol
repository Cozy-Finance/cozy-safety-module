// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IManager} from "../../src/interfaces/IManager.sol";
import {Governable} from "../../src/lib/Governable.sol";

contract MockManager is Governable {
  function initGovernable(address owner_, address pauser_) external {
    __initGovernable(owner_, pauser_);
  }

  function setOwner(address owner_) external {
    owner = owner_;
  }
}
