// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {ICommonErrors} from "cozy-safety-module-shared/interfaces/ICommonErrors.sol";
import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafetyModuleBaseStorage} from "./SafetyModuleBaseStorage.sol";
import {ReservePool} from "./structs/Pools.sol";

abstract contract SafetyModuleCommon is SafetyModuleBaseStorage, ICommonErrors {
  /// @notice Returns the receipt token amount for a given amount of reserve assets after taking into account
  /// any pending fee drip.
  /// @dev Defined in SafetyModuleInspector.
  function convertToReceiptTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    public
    view
    virtual
    returns (uint256);

  // @dev Returns the reserve asset amount for a given amount of deposit receipt tokens after taking into account any
  // pending fee drip.
  /// @dev Defined in SafetyModuleInspector.
  function convertToReserveAssetAmount(uint256 reservePoolId_, uint256 depositReceiptTokenAmount_)
    public
    view
    virtual
    returns (uint256);

  /// @notice Updates the fee amounts for each reserve pool by applying a drip factor on the stake and deposit amounts.
  /// @dev Defined in FeesHandler.
  function dripFees() public virtual;

  /// @dev Helper to assert that the safety module has a balance of tokens that matches the required amount for a
  /// deposit.
  /// @dev Defined in Depositor.
  function _assertValidDepositBalance(IERC20 token_, uint256 tokenPoolBalance_, uint256 depositAmount_)
    internal
    view
    virtual;

  /// @dev Returns the next amount of fees to be dripped given a base amount and a drip model.
  /// @dev Defined in FeesHandler.
  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_)
    internal
    view
    virtual
    returns (uint256);

  /// @dev Prepares pending withdrawals to have their exchange rates adjusted after a trigger. Defined in `Redeemer`.
  /// @dev Defined in Redeemer.
  function _updateWithdrawalsAfterTrigger(
    uint8 reservePoolId_,
    ReservePool storage reservePool_,
    uint256 depositAmount_,
    uint256 slashAmount_
  ) internal virtual returns (uint256 newPendingWithdrawalsAmount_);

  /// @dev Drips fees from a specific reserve pool.
  /// @dev Defined in FeesHandler.
  function _dripFeesFromReservePool(ReservePool storage reservePool_, IDripModel dripModel_) internal virtual;
}
