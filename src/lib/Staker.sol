// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Depositor} from "./Depositor.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IStakerErrors} from "../interfaces/IStakerErrors.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafeCastLib} from "./SafeCastLib.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";

abstract contract Staker is SafetyModuleCommon, IStakerErrors {
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;

  /// @dev Emitted when a user stakes.
  event Staked(
    address indexed caller_, address indexed receiver_, uint256 reserveAssetAmount_, uint256 stkTokenAmount_
  );

  /// @notice Stake by minting `stkTokenAmount_` stkTokens to `receiver_` after depositing exactly `reserveAssetAmount_`
  /// of
  /// the reserve asset.
  /// @dev Assumes that `from_` has already approved this contract to transfer `amount_` of reserve asset.
  function stake(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 stkTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 reserveAsset_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[reserveAsset_];

    // Pull in stake tokens. After the transfer we ensure we no longer need any assets. This check is
    // required to support fee on transfer tokens, for example if USDT enables a fee.
    // Also, we need to transfer before minting or ERC777s could reenter.
    reserveAsset_.safeTransferFrom(from_, address(this), reserveAssetAmount_);
    if (reserveAsset_.balanceOf(address(this)) - assetPool_.amount < reserveAssetAmount_) revert InvalidStake();

    stkTokenAmount_ = _executeStake(reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  /// @notice Stake by minting `stkTokenAmount_` stkTokens to `receiver_`.
  /// @dev Assumes that `amount_` of reserve asset has already been transferred to this contract.
  function stakeWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 stkTokenAmount_)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    IERC20 reserveAsset_ = reservePool_.asset;
    AssetPool storage assetPool_ = assetPools[reserveAsset_];

    if (reserveAsset_.balanceOf(address(this)) - assetPool_.amount < reserveAssetAmount_) revert InvalidStake();

    stkTokenAmount_ = _executeStake(reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  function _executeStake(
    uint256 reserveAssetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    ReservePool storage reservePool_
  ) internal returns (uint256 stkTokenAmount_) {
    if (safetyModuleState == SafetyModuleState.PAUSED) revert InvalidState();

    IReceiptToken stkToken_ = reservePool_.stkToken;

    stkTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_, reservePool_.stkToken.totalSupply(), reservePool_.stakeAmount
    );
    // Increment reserve pool accounting only after calculating `stkTokenAmount_` to mint.
    reservePool_.stakeAmount += reserveAssetAmount_;
    assetPool_.amount += reserveAssetAmount_;

    reservePool_.stkToken.mint(receiver_, stkTokenAmount_);
    emit Staked(msg.sender, receiver_, reserveAssetAmount_, stkTokenAmount_);
  }
}
