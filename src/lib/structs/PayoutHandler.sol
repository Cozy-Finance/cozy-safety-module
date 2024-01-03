// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ITrigger} from "../../interfaces/ITrigger.sol";

struct PayoutHandler {
  bool exists;
  uint16 numPendingSlashes;
}
