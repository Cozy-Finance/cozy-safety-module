// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {IWeth} from "../../interfaces/IWeth.sol";
import {IStETH} from "../../interfaces/IStETH.sol";
import {IWstETH} from "../../interfaces/IWstETH.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";

abstract contract TokenHelpers is CozyRouterCommon {
  using Address for address;
  using SafeERC20 for IERC20;

  /// @notice WETH9 address.
  IWeth public immutable weth;

  /// @notice Staked ETH address.
  IStETH public immutable stEth;

  /// @notice Wrapped staked ETH address.
  IWstETH public immutable wstEth;

  /// @dev Thrown when the router's balance is too low to perform the requested action.
  error InsufficientBalance();

  /// @dev Thrown when a token or ETH transfer failed.
  error TransferFailed();

  constructor(IWeth weth_, IStETH stEth_, IWstETH wstEth_) {
    _assertAddressNotZero(address(weth_));

    // The addresses for stEth and wstEth can be 0 in our current deployment setup
    weth = weth_;
    stEth = stEth_;
    wstEth = wstEth_;

    if (address(stEth) != address(0)) IERC20(address(stEth)).safeIncreaseAllowance(address(wstEth), type(uint256).max);
  }

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

  /// @notice Wraps caller's entire balance of stETH as wstETH and transfers to `safetyModule_`.
  /// Requires pre-approval of the router to transfer the caller's stETH.
  /// @dev This function should be `aggregate` called with deposit or stake without transfer functions.
  function wrapStEth(address safetyModule_) external {
    _assertIsValidSafetyModule(safetyModule_);
    wrapStEth(safetyModule_, stEth.balanceOf(msg.sender));
  }

  /// @notice Wraps `amount_` of stETH as wstETH and transfers to `safetyModule_`.
  /// Requires pre-approval of the router to transfer the caller's stETH.
  /// @dev This function should be `aggregate` called with deposit or stake without transfer functions.
  function wrapStEth(address safetyModule_, uint256 amount_) public {
    _assertIsValidSafetyModule(safetyModule_);
    IERC20(address(stEth)).safeTransferFrom(msg.sender, address(this), amount_);
    uint256 wstEthAmount_ = wstEth.wrap(stEth.balanceOf(address(this)));
    IERC20(address(wstEth)).safeTransfer(safetyModule_, wstEthAmount_);
  }

  /// @notice Unwraps router's balance of wstETH into stETH and transfers to `recipient_`.
  /// @dev This function should be `aggregate` called with `completeRedeem/completeWithdraw/completeUnstake`. This
  /// should also be called with withdraw/redeem/unstake functions in the case that instant withdrawals/redemptions
  /// can occur due to the safety module being PAUSED.
  function unwrapStEth(address recipient_) external {
    _assertAddressNotZero(recipient_);
    uint256 stEthAmount_ = wstEth.unwrap(wstEth.balanceOf(address(this)));
    IERC20(address(stEth)).safeTransfer(recipient_, stEthAmount_);
  }

  /// @notice Wraps all ETH held by this contact into WETH and sends WETH to the `safetyModule_`.
  /// @dev This function should be `aggregate` called with deposit or stake without transfer functions.
  function wrapWeth(address safetyModule_) external payable {
    _assertIsValidSafetyModule(safetyModule_);
    uint256 amount_ = address(this).balance;
    weth.deposit{value: amount_}();
    IERC20(address(weth)).safeTransfer(safetyModule_, amount_);
  }

  /// @notice Wraps the specified `amount_` of ETH from this contact into WETH and sends WETH to the `safetyModule_`.
  /// @dev This function should be `aggregate` called with deposit or stake without transfer functions.
  function wrapWeth(address safetyModule_, uint256 amount_) external payable {
    _assertIsValidSafetyModule(safetyModule_);
    // Using msg.value in a multicall is dangerous, so we avoid it.
    if (address(this).balance < amount_) revert InsufficientBalance();
    weth.deposit{value: amount_}();
    IERC20(address(weth)).safeTransfer(safetyModule_, amount_);
  }

  /// @notice Unwraps all WETH held by this contact and sends ETH to the `recipient_`.
  /// @dev Reentrancy is possible here, but this router is stateless and therefore a reentrant call is not harmful.
  /// @dev This function should be `aggregate` called with `completeRedeem/completeWithdraw/completeUnstake`. This
  /// should also be called with withdraw/redeem/unstake functions in the case that instant withdrawals/redemptions
  /// can occur due to the safety module being PAUSED.
  function unwrapWeth(address recipient_) external payable {
    _assertAddressNotZero(recipient_);
    uint256 amount_ = weth.balanceOf(address(this));
    weth.withdraw(amount_);
    // Enables reentrancy, but this is a stateless router so it's ok.
    Address.sendValue(payable(recipient_), amount_);
  }

  /// @notice Unwraps the specified `amount_` of WETH held by this contact and sends ETH to the `recipient_`.
  /// @dev Reentrancy is possible here, but this router is stateless and therefore a reentrant call is not harmful.
  /// @dev This function should be `aggregate` called with `completeRedeem/completeWithdraw/completeUnstake`. This
  /// should also be called with withdraw/redeem/unstake functions in the case that instant withdrawals/redemptions
  /// can occur due to the safety module being PAUSED.
  function unwrapWeth(address recipient_, uint256 amount_) external payable {
    _assertAddressNotZero(recipient_);
    if (weth.balanceOf(address(this)) < amount_) revert InsufficientBalance();
    weth.withdraw(amount_);
    // Enables reentrancy, but this is a stateless router so it's ok.
    Address.sendValue(payable(recipient_), amount_);
  }
}
