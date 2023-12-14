// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

abstract contract PayoutHandler {
  struct SlashAmount {
    uint16 reservePoolId;
    uint128 amount;
  }

  /// @dev slashes, sends assets, and unfreezes the safety module
  function slash(SlashAmount[] memory slashAmounts_, address receiver_) external {}
}
