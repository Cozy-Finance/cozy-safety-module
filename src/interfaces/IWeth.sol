// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

/**
 * @dev Interface for WETH9.
 */
interface IWeth {
  /// @notice Returns the remaining number of tokens that `spender_` will be allowed to spend on behalf of `holder_`.
  function allowance(address holder, address spender) external view returns (uint256 remainingAllowance_);

  /// @notice Sets `amount_` as the allowance of `spender_` over the caller's tokens.
  function approve(address spender, uint256 amount) external returns (bool success_);

  /// @notice Returns the amount of tokens owned by `account_`.
  function balanceOf(address account_) external view returns (uint256 balance_);

  /// @notice Returns the decimal places of the token.
  function decimals() external view returns (uint8);

  /// @notice Deposit ETH and receive WETH.
  function deposit() external payable;

  /// @notice Returns the name of the token.
  function name() external view returns (string memory);

  /// @notice Returns the symbol of the token.
  function symbol() external view returns (string memory);

  /// @notice Returns the amount of tokens in existence.
  function totalSupply() external view returns (uint256 supply_);

  /// @notice Moves `amount_` tokens from the caller's account to `to_`.
  function transfer(address to_, uint256 amount_) external returns (bool success_);

  /// @notice Moves `amount_` tokens from `from_` to `to_` using the allowance mechanism. `amount_` is then deducted
  /// from the caller's allowance.
  function transferFrom(address from_, address to_, uint256 amount_) external returns (bool success_);

  /// @notice Burn WETH to withdraw ETH.
  function withdraw(uint256 amount_) external;
}
