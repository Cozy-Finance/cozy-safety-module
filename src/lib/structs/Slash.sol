// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

struct Slash {
  // ID of the reserve pool.
  uint8 reservePoolId;
  // Asset amount that will be slashed from the reserve pool.
  uint256 amount;
}
