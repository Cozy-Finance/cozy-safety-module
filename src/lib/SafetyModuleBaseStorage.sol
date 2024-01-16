// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {IManager} from "../interfaces/IManager.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "../interfaces/IReceiptTokenFactory.sol";
import {ITrigger} from "../interfaces/ITrigger.sol";
import {ReservePool, AssetPool, IdLookup, UndrippedRewardPool} from "./structs/Pools.sol";
import {Trigger} from "./structs/Trigger.sol";
import {UserRewardsData, ClaimableRewardsData} from "./structs/Rewards.sol";
import {Delays} from "./structs/Delays.sol";
import {DripTimes} from "./structs/DripTimes.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";

abstract contract SafetyModuleBaseStorage {
  /// @dev Reserve pool index in this array is its ID
  ReservePool[] public reservePools;

  /// @dev Undripped reward pool index in this array is its ID
  UndrippedRewardPool[] public undrippedRewardPools;

  /// @notice Maps a reserve pool id to an undripped reward pool id to claimable reward index
  mapping(uint16 => mapping(uint16 => ClaimableRewardsData)) public claimableRewardsIndices;

  /// @notice Maps a reserve pool id to a user address to a user reward pool accounting struct.
  mapping(uint16 => mapping(address => UserRewardsData[])) public userRewards;

  /// @dev Used when claiming rewards
  mapping(IReceiptToken stkToken_ => IdLookup reservePoolId_) public stkTokenToReservePoolIds;

  /// @dev Used for doing aggregate accounting of reserve assets.
  mapping(IERC20 reserveAsset_ => AssetPool assetPool_) public assetPools;

  /// @dev Maps triggers to trigger data.
  mapping(ITrigger trigger_ => Trigger triggerData_) public triggerData;

  /// @dev Maps payout handlers to payout handler data.
  mapping(address payoutHandler_ => uint256 numPendingSlashes_) public payoutHandlerNumPendingSlashes;

  /// @dev Config, withdrawal and unstake delays.
  Delays public delays;

  /// @notice The state of this SafetyModule.
  SafetyModuleState public safetyModuleState;

  /// @notice Fees and rewards drip times.
  DripTimes public dripTimes;

  /// @notice The number of slashes that must occur before the safety module can be active.
  /// @dev This value is incremented when a trigger occurs, and decremented when a slash from a trigger assigned payout
  /// handler occurs. When this value is non-zero, the safety module is triggered (or paused).
  uint16 public numPendingSlashes;

  /// @dev Has config for deposit fee and where to send fees
  IManager public immutable cozyManager;

  /// @notice Address of the Cozy protocol ReceiptTokenFactory.
  IReceiptTokenFactory public immutable receiptTokenFactory;
}
