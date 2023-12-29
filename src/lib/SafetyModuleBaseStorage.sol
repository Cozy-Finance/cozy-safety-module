// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {ReservePool, AssetPool, IdLookup, UndrippedRewardPool} from "./structs/Pools.sol";
import {UserRewardsData} from "./structs/Rewards.sol";
import {Delays} from "./structs/Delays.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";

abstract contract SafetyModuleBaseStorage {
  /// @dev Reserve pool index in this array is its ID
  ReservePool[] public reservePools;

  /// @dev Undripped reward pool index in this array is its ID
  UndrippedRewardPool[] public undrippedRewardPools;

  /// @notice Maps a reserve pool id to an undripped reward pool id to claimable reward index
  mapping(uint16 => mapping(uint16 => uint256)) public claimableRewardsIndices;

  /// @notice Maps a reserve pool id to a user address to a user reward pool accounting struct.
  mapping(uint16 => mapping(address => UserRewardsData[])) public userRewards;

  /// @dev Used when claiming rewards
  mapping(IReceiptToken stkToken_ => IdLookup reservePoolId_) public stkTokenToReservePoolIds;

  /// @dev Used for doing aggregate accounting of reserve assets.
  mapping(IERC20 reserveAsset_ => AssetPool assetPool_) public assetPools;

  /// @dev Config, withdrawal and unstake delays.
  Delays public delays;

  /// @dev Has config for deposit fee and where to send fees
  IManager public immutable cozyManager;

  /// @notice Address of the Cozy protocol ReceiptTokenFactory.
  IReceiptTokenFactory public immutable receiptTokenFactory;

  /// @notice The state of this SafetyModule.
  SafetyModuleState public safetyModuleState;

  /// @notice Last rewards drip time. Drips from all undripped reward pools occur simultaneously.
  uint256 public lastRewardsDripTime;

  /// @notice Last fees drip time.
  uint256 public lastFeesDripTime;
}
