// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {ISafetyModule} from "./ISafetyModule.sol";
import {IReceiptToken} from "./IReceiptToken.sol";

interface IReceiptTokenFactory {
  enum PoolType {
    DEPOSIT,
    STAKE,
    REWARD
  }

  /// @dev Emitted when a new ReceiptToken is deployed.
  event ReceiptTokenDeployed(
    IReceiptToken receiptToken,
    ISafetyModule indexed safetyModule,
    uint8 indexed reservePoolId,
    PoolType indexed poolType,
    uint8 decimals_
  );

  /// @notice Creates a new ReceiptToken contract with the given number of `decimals_`. The ReceiptToken's safety module
  /// is
  /// identified by the caller address. The reserve pool id of the ReceiptToken in the safety module is used to generate
  /// a unique salt for deploy.
  /// @notice Creates a new ReceiptToken contract with the given number of `decimals_`. The ReceiptToken's safety module
  /// is
  /// identified by the caller address. The pool id of the ReceiptToken in the safety module and its `PoolType` is used
  /// to
  /// generate a unique salt for deploy.
  function deployReceiptToken(uint8 poolId_, PoolType poolType_, uint8 decimals_)
    external
    returns (IReceiptToken receiptToken_);
}
