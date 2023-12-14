// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

interface IERC20Events {
  event Transfer(address indexed from, address indexed to, uint256 amount);
  event Approval(address indexed owner, address indexed spender, uint256 amount);
}
