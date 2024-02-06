// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafetyModuleBaseStorage} from "./SafetyModuleBaseStorage.sol";
import {ICommonErrors} from "../interfaces/ICommonErrors.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";
import {ReservePool} from "./structs/Pools.sol";

abstract contract SafetyModuleCommon is SafetyModuleBaseStorage, ICommonErrors {
  /// @notice Updates the fee amounts for each reserve pool by applying a drip factor on the stake and deposit amounts.
  /// @dev Defined in FeesHandler.
  function dripFees() public virtual;

  /// @dev Helper to assert that the safety module has a balance of tokens that matches the required amount for a
  /// deposit.
  function _assertValidDepositBalance(IERC20 token_, uint256 tokenPoolBalance_, uint256 depositAmount_)
    internal
    view
    virtual;

  // @dev Returns the next amount of fees to be dripped given a base amount and a drip model.
  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    virtual
    returns (uint256);

  /// @dev Prepares pending withdrawals to have their exchange rates adjusted after a trigger. Defined in `Redeemer`.
  function _updateWithdrawalsAfterTrigger(
    uint16 reservePoolId_,
    ReservePool storage reservePool_,
    uint256 depositAmount_,
    uint256 slashAmount_
  ) internal virtual returns (uint256 newPendingWithdrawalsAmount_);

  function _dripFeesFromReservePool(ReservePool storage reservePool_, IDripModel dripModel_) internal virtual;
}
