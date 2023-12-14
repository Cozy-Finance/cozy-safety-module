// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {IRewardsDripModel} from "../interfaces/IRewardsDripModel.sol";
import {ReservePool, AssetPool, IdLookup, UndrippedRewardPool} from "./structs/Pools.sol";
import {RewardPool, UndrippedRewardPool, ClaimedRewards} from "./structs/Rewards.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";

abstract contract SafetyModuleBaseStorage {
  /// @dev Reserve pool index in this array is its ID
  ReservePool[] public reservePools;

  /// @dev Claimable reward pool index in this array is its ID
  RewardPool[] public claimableRewardPools;

  /// @dev Undripped reward pool index in this array is its ID
  UndrippedRewardPool[] public undrippedRewardPools;

  /// @dev Claimable and undripped reward pools are mapped 1:1 to underlying assets
  mapping(IERC20 asset_ => uint16[] ids_) public rewardPoolIds;

  /// @dev Used when claiming rewards
  mapping(IReceiptToken stkToken_ => IdLookup reservePoolId_) public stkTokenToReservePoolIds;

  /// @dev Used for doing aggregate accounting of reserve assets.
  mapping(IERC20 reserveAsset_ => AssetPool assetPool_) public assetPools;

  /// @dev The weighting of each stkToken's claim to all reward pools. Must sum to 1.
  /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
  /// wrt totalSupply.
  uint16[] public stkTokenRewardPoolWeights;

  /// @dev Delay for two-step unstake process.
  uint256 public unstakeDelay;

  /// @dev Has config for deposit fee and where to send fees
  IManager public immutable cozyManager;

  /// @notice Address of the Cozy protocol ReceiptTokenFactory.
  IReceiptTokenFactory public immutable receiptTokenFactory;

  /// @notice The state of this SafetyModule.
  SafetyModuleState public safetyModuleState;
}
