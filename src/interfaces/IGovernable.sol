// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IOwnable} from "./IOwnable.sol";

interface IGovernable is IOwnable {
  function pauser() external view returns (address);
}
