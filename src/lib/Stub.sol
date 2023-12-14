// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

function __readStub__() view {
  assembly {
    pop(sload(0x100000000000000000000000000000000))
  }
  revert("NOT_IMPLEMENTED");
}

function __writeStub__() {
  assembly {
    sstore(0x100000000000000000000000000000000, 0)
  }
  revert("NOT_IMPLEMENTED");
}
