// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IStkToken} from "../interfaces/IStkToken.sol";
import {IStkTokenFactory} from "../interfaces/IStkTokenFactory.sol";
import {IRewardsDripModel} from "../interfaces/IRewardsDripModel.sol";
import {ReservePool, TokenPool, IdLookup} from "./structs/Pools.sol";
import {RewardPool, UndrippedRewardPool, ClaimedRewards} from "./structs/Rewards.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";

abstract contract SafetyModuleBaseStorage {
  /// @dev reserve pool index in this array is its ID
  ReservePool[] public reservePools;

  /// @dev claimable reward pool index in this array is its ID
  RewardPool[] public claimableRewardPools;

  /// @dev undripped reward pool index in this array is its ID
  UndrippedRewardPool[] public undrippedRewardPools;

  /// @dev claimable and undripped reward pools are mapped 1:1
  mapping(IERC20 asset_ => uint16[] ids_) public rewardPoolIds;

  /// @dev Used when claiming rewards
  mapping(IStkToken stkToken_ => IdLookup reservePoolId_) public stkTokenToReservePoolIds;

  /// @dev Used when depositing
  mapping(IERC20 reserveToken_ => IdLookup reservePoolId_) public reserveTokenToReservePoolIds;

  /// @dev Used for doing aggregate accounting of reserve tokens.
  mapping(IERC20 reserveToken_ => TokenPool tokenPool_) public tokenPools;

  /// @dev The weighting of each stkToken's claim to all reward pools. Must sum to 1.
  /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
  /// wrt totalSupply.
  uint16[] public stkTokenRewardPoolWeights;

  /// @dev Two step delay for unstaking.
  /// Need to accomodate for multiple triggers when unstaking
  uint256 public unstakeDelay;

  /// @dev Has config for deposit fee and where to send fees
  IManager public immutable cozyManager;

  /// @notice Address of the Cozy protocol stkTokenFactory.
  IStkTokenFactory public immutable stkTokenFactory;

  /// @notice The state of this SafetyModule.
  SafetyModuleState public safetyModuleState;
}
