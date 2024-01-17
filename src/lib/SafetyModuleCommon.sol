// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {SafetyModuleBaseStorage} from "./SafetyModuleBaseStorage.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {UserRewardsData, ClaimableRewardsData} from "./structs/Rewards.sol";
import {ReservePool, UndrippedRewardPool} from "./structs/Pools.sol";

abstract contract SafetyModuleCommon is SafetyModuleBaseStorage, ICommonErrors {
  /// @notice Claim staking rewards for a given reserve pool.
  function claimRewards(uint16 reservePoolId_, address receiver_) public virtual;

  /// @notice Updates the balances for each undripped reward pool by applying a drip factor on them, and increment the
  /// claimable rewards index for each claimable rewards pool.
  /// @dev Defined in RewardsHandler.
  function dripRewards() public virtual;

  /// @notice Updates the fee amounts for each reserve pool by applying a drip factor on the stake and deposit amounts.
  /// @dev Defined in FeesHandler.
  function dripFees() public virtual;

  /// @dev Helper to assert that the safety module has a balance of tokens that matches the required amount for a
  /// deposit.
  function _assertValidDepositBalance(IERC20 token_, uint256 tokenPoolBalance_, uint256 depositAmount_)
    internal
    view
    virtual;

  // @dev Returns the next amount of rewards/fees to be dripped given a base amount and a drip model.
  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_, uint256 deltaT_)
    internal
    view
    virtual
    returns (uint256);

  // @dev Compute the next amount of rewards/fees to be dripped given a base amount and a drip factor.
  function _computeNextDripAmount(uint256 totalBaseAmount_, uint256 dripFactor_)
    internal
    view
    virtual
    returns (uint256);

  /// @dev Prepares pending unstakes to have their exchange rates adjusted after a trigger. Defined in `Redeemer`.
  function _updateUnstakesAfterTrigger(
    uint16 reservePoolId_,
    ReservePool storage reservePool_,
    uint256 stakeAmount_,
    uint256 slashAmount_
  ) internal virtual returns (uint256 newPendingUnstakesAmount_);

  /// @dev Prepares pending withdrawals to have their exchange rates adjusted after a trigger. Defined in `Redeemer`.
  function _updateWithdrawalsAfterTrigger(
    uint16 reservePoolId_,
    ReservePool storage reservePool_,
    uint256 stakeAmount_,
    uint256 slashAmount_
  ) internal virtual returns (uint256 newPendingWithdrawalsAmount_);

  function _updateUserRewards(
    uint256 userStkTokenBalance_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewardsIndices_,
    UserRewardsData[] storage userRewards_
  ) internal virtual;

  function _dripRewardPool(UndrippedRewardPool storage undrippedRewardPool_) internal virtual;

  function applyPendingDrippedRewards_(
    ReservePool storage reservePool_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_
  ) internal virtual;

  function _dripFeesFromReservePool(ReservePool storage reservePool_, IDripModel dripModel_) internal virtual;
}
