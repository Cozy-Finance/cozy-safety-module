// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

interface ISlashHandlerEvents {
  /// @dev Emitted when a reserve pool is slashed.
  event Slashed(
    address indexed payoutHandler_, address indexed receiver_, uint8 indexed reservePoolId_, uint256 assetAmount_
  );
}
