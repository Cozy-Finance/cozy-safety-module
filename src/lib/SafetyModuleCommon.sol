// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../interfaces/IERC20.sol";
import {SafetyModuleBaseStorage} from "./SafetyModuleBaseStorage.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {UserRewardsData} from "./structs/Rewards.sol";

abstract contract SafetyModuleCommon is SafetyModuleBaseStorage, ICommonErrors {
  /// @notice Claim staking rewards for a given reserve pool.
  function claimRewards(uint16 reservePoolId_, address receiver_) public virtual;

  /// @notice Updates the balances for each undripped reward pool by applying a drip factor on them, and increment the
  /// claimable rewards index for each claimable rewards pool.
  /// @dev Defined in RewardsHandler.
  function dripRewards() public virtual;

  /// @dev Helper to assert that the safety module has a balance of tokens that matches the required amount for a
  /// deposit.
  function _assertValidDepositBalance(IERC20 token_, uint256 tokenPoolBalance_, uint256 depositAmount_)
    internal
    view
    virtual;

  /// @dev Prepares pending unstakes to have their exchange rates adjusted after a trigger. Defined in `Redeemer`.
  function _updateUnstakesAfterTrigger(uint16 reservePoolId_, uint128 stakeAmount_, uint128 slashAmount_)
    internal
    virtual;

  /// @dev Prepares pending withdrawals to have their exchange rates adjusted after a trigger. Defined in `Redeemer`.
  function _updateWithdrawalsAfterTrigger(uint16 reservePoolId_, uint128 stakeAmount_, uint128 slashAmount_)
    internal
    virtual;

  function _updateUserRewards(
    uint256 userStkTokenBalance_,
    mapping(uint16 => uint256) storage claimableRewardsIndices_,
    UserRewardsData[] storage userRewards_
  ) internal virtual;
}
