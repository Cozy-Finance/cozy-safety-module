// SPDX-License-Identifier: UNLICENSED
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
  uint256 depositAmount;
  uint256 pendingWithdrawalsAmount;
  uint256 feeAmount;
  /// @dev The max percentage of the deposit amount that can be slashed in a SINGLE slash as a WAD. If multiple slashes
  /// occur, they compound, and the final deposit amount can be less than (1 - maxSlashPercentage)% following all the
  /// slashes.
  uint256 maxSlashPercentage;
  IERC20 asset;
  IReceiptToken depositReceiptToken;
  uint128 lastFeesDripTime;
}

struct IdLookup {
  uint16 index;
  bool exists;
}
