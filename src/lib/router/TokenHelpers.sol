// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";

abstract contract TokenHelpers is CozyRouterCommon {
  using Address for address;
  using SafeERC20 for IERC20;

  /// @dev Thrown when the router's balance is too low to perform the requested action.
  error InsufficientBalance();

  /// @dev Thrown when a token or ETH transfer failed.
  error TransferFailed();

  /// @notice Approves the router to spend `value_` of the specified `token_`. tokens on behalf of the caller. The
  /// permit transaction must be submitted by the `deadline_`.
  /// @dev More info on permit: https://eips.ethereum.org/EIPS/eip-2612
  function permitRouter(IERC20 token_, uint256 value_, uint256 deadline_, uint8 v_, bytes32 r_, bytes32 s_)
    external
    payable
  {
    // For ERC-2612 permits, use the approval amount as the `value_`. For DAI permits, `value_` should be the
    // nonce as all DAI permits are for `type(uint256).max` by default.
    IERC20(token_).permit(msg.sender, address(this), value_, deadline_, v_, r_, s_);
  }

  /// @notice Transfers the full balance of the router's holdings of `token_` to `recipient_`, as long as the contract
  /// holds at least `amountMin_` tokens.
  function sweepToken(IERC20 token_, address recipient_, uint256 amountMin_) external payable returns (uint256 amount_) {
    _assertAddressNotZero(recipient_);
    amount_ = token_.balanceOf(address(this));
    if (amount_ < amountMin_) revert InsufficientBalance();
    if (amount_ > 0) token_.safeTransfer(recipient_, amount_);
  }

  /// @notice Transfers `amount_` of the router's holdings of `token_` to `recipient_`.
  function transferTokens(IERC20 token_, address recipient_, uint256 amount_) external payable {
    _assertAddressNotZero(recipient_);
    token_.safeTransfer(recipient_, amount_);
  }
}
