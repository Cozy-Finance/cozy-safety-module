// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Depositor} from "./Depositor.sol";
import {IDepositorErrors} from "../interfaces/IDepositorErrors.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {ClaimableRewardsData} from "./structs/Rewards.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafeCastLib} from "./SafeCastLib.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";

abstract contract Staker is SafetyModuleCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;

  /// @dev Emitted when a user stakes.
  event Staked(
    address indexed caller_,
    address indexed receiver_,
    IReceiptToken indexed stkToken_,
    uint256 reserveAssetAmount_,
    uint256 stkTokenAmount_
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
    _assertValidDepositBalance(reserveAsset_, assetPool_.amount, reserveAssetAmount_);

    stkTokenAmount_ = _executeStake(reservePoolId_, reserveAssetAmount_, receiver_, assetPool_, reservePool_);
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

    _assertValidDepositBalance(reserveAsset_, assetPool_.amount, reserveAssetAmount_);

    stkTokenAmount_ = _executeStake(reservePoolId_, reserveAssetAmount_, receiver_, assetPool_, reservePool_);
  }

  function _executeStake(
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    AssetPool storage assetPool_,
    ReservePool storage reservePool_
  ) internal returns (uint256 stkTokenAmount_) {
    if (safetyModuleState == SafetyModuleState.PAUSED) revert InvalidState();

    IReceiptToken stkToken_ = reservePool_.stkToken;

    stkTokenAmount_ = SafetyModuleCalculationsLib.convertToReceiptTokenAmount(
      reserveAssetAmount_, stkToken_.totalSupply(), reservePool_.stakeAmount
    );
    // Increment reserve pool accounting only after calculating `stkTokenAmount_` to mint.
    reservePool_.stakeAmount += reserveAssetAmount_;
    assetPool_.amount += reserveAssetAmount_;

    // Update user rewards before minting any new stkTokens.
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewards[reservePoolId_];
    _applyPendingDrippedRewards(reservePool_, claimableRewards_);
    _updateUserRewards(stkToken_.balanceOf(receiver_), claimableRewards_, userRewards[reservePoolId_][receiver_]);

    stkToken_.mint(receiver_, stkTokenAmount_);
    emit Staked(msg.sender, receiver_, stkToken_, reserveAssetAmount_, stkTokenAmount_);
  }
}
