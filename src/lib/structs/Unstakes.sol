// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";
import {IRewardsDripModel} from "../../interfaces/IRewardsDripModel.sol";

struct Unstake {
  uint16 reservePoolId; // ID of the reserve pool.
  uint216 stkTokenAmount; // Staked token amount burned to queue the unstake.
  uint128 reserveTokenAmount; // Reserve token amount that will be paid out upon completion of the unstake.
  address owner; // Owner of the staked tokens.
  address receiver; // Receiver of reserve assets.
  uint40 queueTime; // Timestamp at which the unstake was requested.
  uint40 delay; // Safety module unstake delay at the time of request.
  uint32 queuedAccISFsLength; // Length of pendingUnstakingAccISFs at queue time.
  uint256 queuedAccISF; // Last pendingUnstakingAccISFs value at queue time.
}

struct UnstakePreview {
  uint40 delayRemaining; // Safety module unstake delay remaining.
  uint216 stkTokenAmount; // Staked token amount burned to queue the unstake.
  uint128 reserveTokenAmount; // Reserve token amount that will be paid out upon completion of the unstake.
  address owner; // Owner of the shares.
  address receiver; // Receiver of redeemed assets.
}
