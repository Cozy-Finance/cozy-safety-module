// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface ISlashHandlerEvents {
  event Slashed(
    address indexed payoutHandler_, address indexed receiver_, uint256 indexed reservePoolId_, uint256 assetAmount_
  );
}
