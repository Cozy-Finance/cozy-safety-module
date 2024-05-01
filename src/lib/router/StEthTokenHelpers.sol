// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {IWeth} from "../../interfaces/IWeth.sol";
import {IStETH} from "../../interfaces/IStETH.sol";
import {IWstETH} from "../../interfaces/IWstETH.sol";
import {TokenHelpers} from "./TokenHelpers.sol";

abstract contract StEthTokenHelpers is TokenHelpers {
  using Address for address;
  using SafeERC20 for IERC20;

  /// @notice Staked ETH address.
  IStETH public immutable stEth;

  /// @notice Wrapped staked ETH address.
  IWstETH public immutable wstEth;

  constructor(IStETH stEth_, IWstETH wstEth_) {
    // The addresses for stEth and wstEth can be 0 in our current deployment setup
    stEth = stEth_;
    wstEth = wstEth_;

    if (address(stEth) != address(0)) IERC20(address(stEth)).safeIncreaseAllowance(address(wstEth), type(uint256).max);
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
}
