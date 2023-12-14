// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IStakerErrors} from "../interfaces/IStakerErrors.sol";
import {ReservePool, TokenPool} from "./structs/Pools.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafeCastLib} from "./SafeCastLib.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";

abstract contract Staker is SafetyModuleCommon, IStakerErrors {
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;

  /// @dev Emitted when a user stakes.
  event Staked(address indexed caller_, address indexed receiver_, uint256 amount_, uint256 stkTokenAmount_);

  /// @notice Stake by minting `stkTokenAmount_` stkTokens to `receiver_` after depositing exactly `amount_` of
  /// the reserve token.
  /// @dev Assumes that `from_` has already approved this contract to transfer `amount_` of reserve token.
  function stake(uint16 reservePoolId_, uint256 amount_, address receiver_, address from_)
    external
    returns (uint256 stkTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 token_ = reservePool_.token;
    TokenPool storage tokenPool_ = tokenPools[token_];

    // Pull in stake tokens. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    token_.safeTransferFrom(from_, address(this), amount_);
    if (token_.balanceOf(address(this)) - tokenPool_.balance < amount_) revert InvalidStake();

    stkTokenAmount_ = _executeStake(amount_, receiver_, tokenPools[token_], reservePool_);
  }

  /// @notice Stake by minting `stkTokenAmount_` stkTokens to `receiver_`.
  /// @dev Assumes that `amount_` of reserve token has already been transferred to this contract.
  function stakeWithoutTransfer(uint16 reservePoolId_, uint256 amount_, address receiver_)
    external
    returns (uint256 stkTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 token_ = reservePool_.token;
    TokenPool storage tokenPool_ = tokenPools[token_];

    if (token_.balanceOf(address(this)) - tokenPool_.balance < amount_) revert InvalidStake();

    stkTokenAmount_ = _executeStake(amount_, receiver_, tokenPool_, reservePool_);
  }

  function _executeStake(
    uint256 amount_,
    address receiver_,
    TokenPool storage tokenPool_,
    ReservePool storage reservePool_
  ) internal returns (uint256 stkTokenAmount_) {
    if (safetyModuleState == SafetyModuleState.PAUSED) revert InvalidState();

    stkTokenAmount_ = SafetyModuleCalculationsLib.convertToStkTokenAmount(
      amount_, reservePool_.stkToken.totalSupply(), reservePool_.stakeAmount
    );
    // Increment reserve pool accounting only after calculating `stkTokenAmount_` to mint.
    reservePool_.stakeAmount += amount_;
    tokenPool_.balance += amount_;

    reservePool_.stkToken.mint(receiver_, stkTokenAmount_);
    emit Staked(msg.sender, receiver_, amount_, stkTokenAmount_);
  }
}
