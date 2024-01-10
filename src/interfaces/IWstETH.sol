// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IWstETH {
  function balanceOf(address account) external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function unwrap(uint256 wstETHAmount) external returns (uint256);
  function wrap(uint256 stETHAmount) external returns (uint256);
}
