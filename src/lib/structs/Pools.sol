// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.22;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";

struct AssetPool {
  // The total balance of assets held by a SafetyModule, should be equivalent to
  // token.balanceOf(address(this)), discounting any assets directly sent
  // to the SafetyModule via direct transfer.
  uint256 amount;
}

struct ReservePool {
  // The internally accounted total amount of assets held by the reserve pool. This amount includes
  // pendingWithdrawalsAmount.
  uint256 depositAmount;
  // The amount of assets that are currently queued for withdrawal from the reserve pool.
  uint256 pendingWithdrawalsAmount;
  // The amount of fees that have accumulated in the reserve pool since the last fee claim.
  uint256 feeAmount;
  // The max percentage of the reserve pool deposit amount that can be slashed in a SINGLE slash as a ZOC.
  // If multiple slashes occur, they compound, and the final deposit amount can be less than (1 - maxSlashPercentage)%
  // following all the slashes.
  uint256 maxSlashPercentage;
  // The underlying asset of the reserve pool.
  IERC20 asset;
  // The receipt token that represents reserve pool deposits.
  IReceiptToken depositReceiptToken;
  // The timestamp of the last time fees were dripped to the reserve pool.
  uint128 lastFeesDripTime;
}
