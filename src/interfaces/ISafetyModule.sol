// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {UndrippedRewardPoolConfig, ReservePoolConfig} from "../lib/structs/Configs.sol";
import {Delays} from "../lib/structs/Delays.sol";

interface ISafetyModule {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(
    address owner_,
    address pauser_,
    ReservePoolConfig[] calldata reservePoolConfigs_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfigs_,
    Delays calldata delaysConfig_
  ) external;

  function updateUserRewardsForStkTokenTransfer(address from_, address to_) external;
}
