// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {UndrippedRewardPoolConfig} from "../lib/structs/Configs.sol";

interface ISafetyModule {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(
    address owner_,
    address pauser_,
    IERC20[] calldata reserveAssets_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfig_,
    uint128 unstakeDelay_
  ) external;

  function updateUserRewardsForStkTokenTransfer(address from_, address to_) external;
}
