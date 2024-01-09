// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {UndrippedRewardPoolConfig, UpdateConfigsCalldataParams, ReservePoolConfig} from "../lib/structs/Configs.sol";
import {Delays} from "../lib/structs/Delays.sol";

interface ISafetyModule {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(address owner_, address pauser_, UpdateConfigsCalldataParams calldata configs_) external;

  /// @notice Updates the safety module's user rewards data prior to a stkToken transfer.
  function updateUserRewardsForStkTokenTransfer(address from_, address to_) external;

  /// @notice Pauses the safety module.
  function pause() external;

  /// @notice Unpauses the safety module.
  function unpause() external;

  // @notice Claims the safety module's fees.
  function claimFees(address owner_) external;
}
