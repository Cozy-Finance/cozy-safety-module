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
  /// @param reservePoolId_ The ID of the reserve pool to convert the reserve asset amount for.
  /// @param reserveAssetAmount_ The amount of reserve assets to convert to deposit receipt tokens.
  function convertToReceiptTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    public
    view
    virtual
    returns (uint256);

  // @notice Returns the reserve asset amount for a given amount of deposit receipt tokens after taking into account any
  // pending fee drip.
  /// @dev Defined in SafetyModuleInspector.
  /// @param reservePoolId_ The ID of the reserve pool to convert the deposit receipt token amount for.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to convert to reserve assets.
  function convertToReserveAssetAmount(uint256 reservePoolId_, uint256 depositReceiptTokenAmount_)
    public
    view
    virtual
    returns (uint256);

  /// @notice Updates the fee amounts for each reserve pool by applying a drip factor on the deposit amounts.
  /// @dev Defined in FeesHandler.
  function dripFees() public virtual;

  /// @notice Drips fees from the specified reserve pool.
  /// @dev Defined in FeesHandler.
  /// @param reservePool_ The reserve pool to drip fees from.
  /// @param dripModel_ The drip model to use for calculating the fees to drip.
  function _dripFeesFromReservePool(ReservePool storage reservePool_, IDripModel dripModel_) internal virtual;

  /// @notice Returns the next amount of fees to drip from the reserve pool.
  /// @dev Defined in FeesHandler.
  /// @param totalBaseAmount_ The total amount assets in the reserve pool, before the next drip.
  /// @param dripModel_ The drip model to use for calculating the fees to drip.
  /// @param lastDripTime_ The last time fees were dripped from the reserve pool.
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
}
