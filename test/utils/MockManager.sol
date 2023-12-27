// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IERC20} from "../../src/interfaces/IERC20.sol";
import {IManager} from "../../src/interfaces/IManager.sol";
import {Governable} from "../../src/lib/Governable.sol";

contract MockManager is Governable {}