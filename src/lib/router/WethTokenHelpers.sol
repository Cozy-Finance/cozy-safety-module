// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {IWeth} from "../../interfaces/IWeth.sol";
import {TokenHelpers} from "./TokenHelpers.sol";

abstract contract WethTokenHelpers is TokenHelpers {
  using Address for address;
  using SafeERC20 for IERC20;

  /// @notice The address that conforms to the IWETH9 interface.
  IWeth public immutable wrappedNativeToken;

  constructor(IWeth weth_) {
    _assertAddressNotZero(address(weth_));
    wrappedNativeToken = weth_;
  }

  /// @notice Wraps all native tokens held by this contact into the wrapped native token and sends them to the
  /// `safetyModule_`.
  /// @dev This function should be `aggregate` called with deposit or stake without transfer functions.
  function wrapNativeToken(address safetyModule_) external payable {
    _assertIsValidSafetyModule(safetyModule_);
    uint256 amount_ = address(this).balance;
    wrappedNativeToken.deposit{value: amount_}();
    IERC20(address(wrappedNativeToken)).safeTransfer(safetyModule_, amount_);
  }

  /// @notice Wraps the specified `amount_` of native tokens from this contact into wrapped native tokens and sends them
  /// to the `safetyModule_`.
  /// @dev This function should be `aggregate` called with deposit or stake without transfer functions.
  function wrapNativeToken(address safetyModule_, uint256 amount_) external payable {
    _assertIsValidSafetyModule(safetyModule_);
    // Using msg.value in a multicall is dangerous, so we avoid it.
    if (address(this).balance < amount_) revert InsufficientBalance();
    wrappedNativeToken.deposit{value: amount_}();
    IERC20(address(wrappedNativeToken)).safeTransfer(safetyModule_, amount_);
  }

  /// @notice Unwraps all wrapped native tokens held by this contact and sends native tokens to the `recipient_`.
  /// @dev Reentrancy is possible here, but this router is stateless and therefore a reentrant call is not harmful.
  /// @dev This function should be `aggregate` called with `completeRedeem/completeWithdraw/completeUnstake`. This
  /// should also be called with withdraw/redeem/unstake functions in the case that instant withdrawals/redemptions
  /// can occur due to the safety module being PAUSED.
  function unwrapNativeToken(address recipient_) external payable {
    _assertAddressNotZero(recipient_);
    uint256 amount_ = wrappedNativeToken.balanceOf(address(this));
    wrappedNativeToken.withdraw(amount_);
    // Enables reentrancy, but this is a stateless router so it's ok.
    Address.sendValue(payable(recipient_), amount_);
  }

  /// @notice Unwraps the specified `amount_` of wrapped native tokens held by this contact and sends native tokens to
  /// the `recipient_`.
  /// @dev Reentrancy is possible here, but this router is stateless and therefore a reentrant call is not harmful.
  /// @dev This function should be `aggregate` called with `completeRedeem/completeWithdraw/completeUnstake`. This
  /// should also be called with withdraw/redeem/unstake functions in the case that instant withdrawals/redemptions
  /// can occur due to the safety module being PAUSED.
  function unwrapNativeToken(address recipient_, uint256 amount_) external payable {
    _assertAddressNotZero(recipient_);
    if (wrappedNativeToken.balanceOf(address(this)) < amount_) revert InsufficientBalance();
    wrappedNativeToken.withdraw(amount_);
    // Enables reentrancy, but this is a stateless router so it's ok.
    Address.sendValue(payable(recipient_), amount_);
  }
}
