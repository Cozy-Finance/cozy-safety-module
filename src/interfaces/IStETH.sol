// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IStETH {
  function allowance(address owner_, address spender_) external view returns (uint256);
  function approve(address spender_, uint256 amount_) external returns (bool);
  function balanceOf(address account_) external view returns (uint256);
  function getSharesByPooledEth(uint256 ethAmount_) external view returns (uint256);
  function getPooledEthByShares(uint256 sharesAmount_) external view returns (uint256);
  function getTotalPooledEther() external returns (uint256);
  function getTotalShares() external returns (uint256);
  function transfer(address recipient_, uint256 amount_) external returns (bool);
  function transferFrom(address sender_, address recipient_, uint256 amount_) external returns (bool);
  function submit(address referral_) external payable returns (uint256);
}
