// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";

struct Redemption {
  uint8 reservePoolId; // ID of the reserve pool.
  uint216 receiptTokenAmount; // Deposit receipt token amount burned to queue the redemption.
  IReceiptToken receiptToken; // The receipt token being redeemed.
  uint128 assetAmount; // Asset amount that will be paid out upon completion of the redemption.
  address owner; // Owner of the deposit tokens.
  address receiver; // Receiver of reserve assets.
  uint40 queueTime; // Timestamp at which the redemption was requested.
  uint40 delay; // SafetyModule redemption delay at the time of request.
  uint32 queuedAccISFsLength; // Length of pendingRedemptionAccISFs at queue time.
  uint256 queuedAccISF; // Last pendingRedemptionAccISFs value at queue time.
}

struct RedemptionPreview {
  uint40 delayRemaining; // SafetyModule redemption delay remaining.
  uint216 receiptTokenAmount; // Deposit receipt token amount burned to queue the redemption.
  IReceiptToken receiptToken; // The receipt token being redeemed.
  uint128 reserveAssetAmount; // Asset amount that will be paid out upon completion of the redemption.
  address owner; // Owner of the deposit receipt tokens.
  address receiver; // Receiver of the assets.
}
