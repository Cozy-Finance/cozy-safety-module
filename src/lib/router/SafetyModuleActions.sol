  // SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IRewardsManager} from "cozy-safety-module-rewards-manager/interfaces/IRewardsManager.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {IConnector} from "../../interfaces/IConnector.sol";
import {ISafetyModule} from "../../interfaces/ISafetyModule.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";

abstract contract SafetyModuleActions is CozyRouterCommon {
  using SafeERC20 for IERC20;

  // ---------------------------------
  // -------- Deposit / Stake --------
  // ---------------------------------

  /// @notice Deposits assets into a `safetyModule_` reserve pool. Mints `depositReceiptTokenAmount_` to `receiver_` by
  /// depositing exactly `reserveAssetAmount_` of the reserve pool's underlying tokens into the `safetyModule_`. The
  /// specified amount of assets are transferred from the caller to the Safety Module.
  /// @dev This will revert if the router is not approved for at least `reserveAssetAmount_` of the reserve pool's
  /// underlying asset.
  function depositReserveAssets(
    ISafetyModule safetyModule_,
    uint8 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_
  ) public payable returns (uint256 depositReceiptTokenAmount_) {
    IERC20 asset_ = safetyModule_.reservePools(reservePoolId_).asset;
    asset_.safeTransferFrom(msg.sender, address(safetyModule_), reserveAssetAmount_);

    depositReceiptTokenAmount_ =
      depositReserveAssetsWithoutTransfer(safetyModule_, reservePoolId_, reserveAssetAmount_, receiver_);
  }

  /// @notice Deposits assets into a `rewardsManager_` reward pool. Mints `depositReceiptTokenAmount_` to `receiver_`
  /// by depositing exactly `rewardAssetAmount_` of the reward pool's underlying tokens into the `rewardsManager_`.
  /// The specified amount of assets are transferred from the caller to the `rewardsManager_`.
  /// @dev This will revert if the router is not approved for at least `rewardAssetAmount_` of the reward pool's
  /// underlying asset.
  function depositRewardAssets(
    IRewardsManager rewardsManager_,
    uint16 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address receiver_
  ) external payable returns (uint256 depositReceiptTokenAmount_) {
    IERC20 asset_ = rewardsManager_.rewardPools(rewardPoolId_).asset;
    asset_.safeTransferFrom(msg.sender, address(rewardsManager_), rewardAssetAmount_);

    depositReceiptTokenAmount_ =
      depositRewardAssetsWithoutTransfer(rewardsManager_, rewardPoolId_, rewardAssetAmount_, receiver_);
  }

  /// @notice Executes a deposit into `safetyModule_` in the reserve pool corresponding to `reservePoolId_`, sending
  /// the resulting deposit tokens to `receiver_`. This method does not transfer the assets to the Safety Module which
  /// are necessary for the deposit, thus the caller should ensure that a transfer to the Safety Module with the
  /// needed amount of assets (`reserveAssetAmount_`) of the reserve pool's underlying asset (viewable with
  /// `safetyModule.reservePools(reservePoolId_)`) is transferred to the Safety Module before calling this method.
  /// In general, prefer using `CozyRouter.depositReserveAssets` to deposit into a Safety Module reserve pool, this
  /// method is here to facilitate MultiCall transactions.
  function depositReserveAssetsWithoutTransfer(
    ISafetyModule safetyModule_,
    uint8 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_
  ) public payable returns (uint256 depositReceiptTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositReceiptTokenAmount_ =
      safetyModule_.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
  }

  /// @notice Executes a deposit into `rewardsManager_` in the reward pool corresponding to `rewardPoolId_`,
  /// sending the resulting deposit tokens to `receiver_`. This method does not transfer the assets to the Rewards
  /// Manager which are necessary for the deposit, thus the caller should ensure that a transfer to the Rewards Manager
  /// with the needed amount of assets (`rewardAssetAmount_`) of the reward pool's underlying asset (viewable with
  /// `rewardsManager.rewardPools(rewardPoolId_)`) is transferred to the Rewards Manager before calling this
  /// method. In general, prefer using `CozyRouter.depositRewardAssets` to deposit into a Rewards Manager reward pool,
  /// this method is here to facilitate MultiCall transactions.
  function depositRewardAssetsWithoutTransfer(
    IRewardsManager rewardsManager_,
    uint16 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address receiver_
  ) public payable returns (uint256 depositReceiptTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositReceiptTokenAmount_ =
      rewardsManager_.depositRewardAssetsWithoutTransfer(rewardPoolId_, rewardAssetAmount_, receiver_);
  }

  /// @notice Deposits assets into a `safetyModule_` reserve pool and stakes the resulting deposit tokens into a
  /// `rewardsManager_` stake pool.
  /// @dev This method is a convenience method that combines `depositReserveAssets` and `stakeWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `reserveAssetAmount_` of the reserve pool's
  /// underlying asset.
  function depositReserveAssetsAndStake(
    ISafetyModule safetyModule_,
    IRewardsManager rewardsManager_,
    uint8 reservePoolId_,
    uint16 stakePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_
  ) external payable returns (uint256 receiptTokenAmount_) {
    // The stake receipt token amount received from staking is 1:1 with the amount of Safety Module receipt tokens
    // received from depositing into reserves.
    receiptTokenAmount_ =
      depositReserveAssets(safetyModule_, reservePoolId_, reserveAssetAmount_, address(rewardsManager_));
    stakeWithoutTransfer(rewardsManager_, stakePoolId_, receiptTokenAmount_, receiver_);
  }

  /// @notice Deposits assets into a `safetyModule_` reserve pool via a connector and stakes the resulting deposit
  /// tokens into a `rewardsManager_` stake pool.
  /// @dev This method is a convenience method that combines `wrapBaseAssetViaConnectorAndDepositReserveAssets` and
  /// `stakeWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `baseAssetAmount_` of the base asset.
  function depositReserveAssetsViaConnectorAndStake(
    IConnector connector_,
    ISafetyModule safetyModule_,
    IRewardsManager rewardsManager_,
    uint8 reservePoolId_,
    uint16 stakePoolId_,
    uint256 baseAssetAmount_,
    address receiver_
  ) external payable returns (uint256 receiptTokenAmount_) {
    // The stake receipt token amount received from staking is 1:1 with the amount of Safety Module receipt tokens
    // received from depositing into reserves.
    receiptTokenAmount_ = wrapBaseAssetViaConnectorAndDepositReserveAssets(
      connector_, safetyModule_, reservePoolId_, baseAssetAmount_, address(rewardsManager_)
    );
    stakeWithoutTransfer(rewardsManager_, stakePoolId_, receiptTokenAmount_, receiver_);
  }

  /// @notice Stakes assets into the `rewardsManager_`. Mints `stakeTokenAmount_` to `receiver_` by staking exactly
  /// `stakeAssetAmount_` of the stake pool's underlying tokens into the `rewardsManager_`. The specified amount of
  /// assets are transferred from the caller to the `rewardsManager_`.
  /// @dev This will revert if the router is not approved for at least `stakeAssetAmount_` of the stake pool's
  /// underlying asset.
  /// @dev The amount of stake receipt tokens received are 1:1 with `stakeAssetAmount_`.
  function stake(IRewardsManager rewardsManager_, uint16 stakePoolId_, uint256 stakeAssetAmount_, address receiver_)
    external
    payable
  {
    _assertAddressNotZero(receiver_);
    IERC20 asset_ = rewardsManager_.stakePools(stakePoolId_).asset;
    asset_.safeTransferFrom(msg.sender, address(rewardsManager_), stakeAssetAmount_);

    stakeWithoutTransfer(rewardsManager_, stakePoolId_, stakeAssetAmount_, receiver_);
  }

  /// @notice Executes a stake against `rewardsManager_` in the stake pool corresponding to `stakePoolId_`, sending
  /// the resulting stake tokens to `receiver_`. This method does not transfer the assets to the Rewards Manager which
  /// are necessary for the stake, thus the caller should ensure that a transfer to the Rewards Manager with the
  /// needed amount of assets (`stakeAssetAmount_`) of the stake pool's underlying asset (viewable with
  /// `rewardsManager.stakePools(stakePoolId_)`) is transferred to the Rewards Manager before calling this method.
  /// In general, prefer using `CozyRouter.stake` to stake into a Rewards Manager, this method is here to facilitate
  /// MultiCall transactions.
  /// @dev The amount of stake receipt tokens received are 1:1 with `stakeAssetAmount_`.
  function stakeWithoutTransfer(
    IRewardsManager rewardsManager_,
    uint16 stakePoolId_,
    uint256 stakeAssetAmount_,
    address receiver_
  ) public payable {
    _assertAddressNotZero(receiver_);
    rewardsManager_.stakeWithoutTransfer(stakePoolId_, stakeAssetAmount_, receiver_);
  }

  /// @notice Calls the connector to wrap the base asset, send the wrapped assets to `safetyModule_`, and then
  /// `depositReserveAssetsWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `baseAssetAmount_` of the base asset.
  function wrapBaseAssetViaConnectorAndDepositReserveAssets(
    IConnector connector_,
    ISafetyModule safetyModule_,
    uint8 reservePoolId_,
    uint256 baseAssetAmount_,
    address receiver_
  ) public payable returns (uint256 depositReceiptTokenAmount_) {
    uint256 depositAssetAmount_ = _wrapBaseAssetViaConnector(connector_, address(safetyModule_), baseAssetAmount_);
    depositReceiptTokenAmount_ =
      depositReserveAssetsWithoutTransfer(safetyModule_, reservePoolId_, depositAssetAmount_, receiver_);
  }

  /// @notice Calls the connector to wrap the base asset, send the wrapped assets to `rewardsManager_`, and then
  /// `depositRewardAssetsWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `baseAssetAmount_` of the base asset.
  function wrapBaseAssetViaConnectorAndDepositRewardAssets(
    IConnector connector_,
    IRewardsManager rewardsManager_,
    uint8 reservePoolId_,
    uint256 baseAssetAmount_,
    address receiver_
  ) external payable returns (uint256 depositReceiptTokenAmount_) {
    uint256 depositAssetAmount_ = _wrapBaseAssetViaConnector(connector_, address(rewardsManager_), baseAssetAmount_);
    depositReceiptTokenAmount_ =
      depositRewardAssetsWithoutTransfer(rewardsManager_, reservePoolId_, depositAssetAmount_, receiver_);
  }

  // --------------------------------------
  // -------- Withdrawal / Unstake --------
  // --------------------------------------

  /// @notice Removes assets from a `safetyModule_` reserve pool. Burns `depositReceiptTokenAmount_` from caller and
  /// sends exactly `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`. If the safety
  /// module is PAUSED, withdrawal can be completed immediately, otherwise this queues a redemption which can be
  /// completed once sufficient delay has elapsed.
  function withdrawReservePoolAssets(
    ISafetyModule safetyModule_,
    uint8 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_
  ) external payable returns (uint64 redemptionId_, uint256 depositReceiptTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositReceiptTokenAmount_ = safetyModule_.convertToReceiptTokenAmount(reservePoolId_, reserveAssetAmount_);
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    (redemptionId_,) = safetyModule_.redeem(reservePoolId_, depositReceiptTokenAmount_, receiver_, msg.sender);
  }

  /// @notice Removes assets from a `safetyModule_` reserve pool. Burns `depositReceiptTokenAmount_` from caller and
  /// sends exactly `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`. If the safety
  /// module is PAUSED, withdrawal can be completed immediately, otherwise this queues a redemption which can be
  /// completed once sufficient delay has elapsed.
  function redeemReservePoolDepositReceiptTokens(
    ISafetyModule safetyModule_,
    uint8 reservePoolId_,
    uint256 depositReceiptTokenAmount_,
    address receiver_
  ) external payable returns (uint64 redemptionId_, uint256 assetsReceived_) {
    _assertAddressNotZero(receiver_);
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    (redemptionId_, assetsReceived_) =
      safetyModule_.redeem(reservePoolId_, depositReceiptTokenAmount_, receiver_, msg.sender);
  }

  /// @notice Removes assets from a `rewardsManager_` reward pool. Burns `depositReceiptTokenAmount_` from caller and
  /// sends exactly `rewardAssetAmount_` of the reward pool's underlying tokens to the `receiver_`. Withdrawal of
  /// undripped assets from reward pools can be completed instantly.
  function withdrawRewardPoolAssets(
    IRewardsManager rewardsManager_,
    uint8 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address receiver_
  ) external payable returns (uint256 depositReceiptTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositReceiptTokenAmount_ =
      rewardsManager_.convertRewardAssetToReceiptTokenAmount(rewardPoolId_, rewardAssetAmount_);
    // Caller must first approve the CozyRouter to spend the deposit receipt tokens.
    rewardsManager_.redeemUndrippedRewards(rewardPoolId_, depositReceiptTokenAmount_, receiver_, msg.sender);
  }

  // @notice Removes assets from a `rewardsManager_` reward pool. Burns `depositReceiptTokenAmount_` from caller and
  /// sends exactly `rewardAssetAmount_` of the reward pool's underlying tokens to the `receiver_`. Withdrawal of
  /// undripped assets from reward pools can be completed instantly.
  function redeemRewardPoolDepositReceiptTokens(
    IRewardsManager rewardsManager_,
    uint16 rewardPoolId_,
    uint256 depositReceiptTokenAmount_,
    address receiver_
  ) external payable returns (uint256 assetsReceived_) {
    _assertAddressNotZero(receiver_);
    // Caller must first approve the CozyRouter to spend the deposit receipt tokens.
    assetsReceived_ =
      rewardsManager_.redeemUndrippedRewards(rewardPoolId_, depositReceiptTokenAmount_, receiver_, msg.sender);
  }

  /// @notice Unstakes exactly `stakeReceiptTokenAmount` from a `rewardsManager_` stake pool. Burns
  /// `stakeReceiptTokenAmount` from caller and sends the same amount of the stake pool's underlying
  /// tokens to the `receiver_`. This also claims any outstanding rewards that the user is entitled to for the stake
  /// pool.
  /// @dev Caller must first approve the CozyRouter to spend the stake tokens.
  /// @dev The amount of underlying assets received are 1:1 with `stakeReceiptTokenAmount_`.
  function unstake(
    IRewardsManager rewardsManager_,
    uint16 stakePoolId_,
    uint256 stakeReceiptTokenAmount,
    address receiver_
  ) public payable {
    _assertAddressNotZero(receiver_);
    // Exchange rate between rewards manager stake tokens and safety module deposit receipt tokens is 1:1.
    rewardsManager_.unstake(stakePoolId_, stakeReceiptTokenAmount, receiver_, msg.sender);
  }

  /// @notice Burns `rewardsManager_` stake tokens for `stakePoolId_` stake pool from caller and sends exactly
  /// `reserveAssetAmount_` of `safetyModule_` `reservePoolId_` reserve pool's underlying tokens to the `receiver_`,
  /// and reverts if less than `minAssetsReceived_` of the reserve pool asset would be received.
  /// If the safety module is PAUSED, unstake can be completed immediately, otherwise this
  /// queues a redemption which can be completed once sufficient delay has elapsed. This also claims any outstanding
  /// rewards that the user is entitled to.
  /// @dev Caller must first approve the CozyRouter to spend the rewards manager stake tokens.
  function unstakeReserveAssetsAndWithdraw(
    ISafetyModule safetyModule_,
    IRewardsManager rewardsManager_,
    uint8 reservePoolId_,
    uint16 stakePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_
  ) external payable returns (uint64 redemptionId_, uint256 stakeReceiptTokenAmount_) {
    _assertAddressNotZero(receiver_);
    // Exchange rate between rewards manager stake tokens and safety module deposit receipt tokens is 1:1.
    stakeReceiptTokenAmount_ = safetyModule_.convertToReceiptTokenAmount(reservePoolId_, reserveAssetAmount_);

    // The stake receipt tokens are transferred to this router because RewardsManager.claimRewards must be called by
    // the owner of the stake receipt tokens.
    _transferStakeTokensAndClaimRewards(rewardsManager_, stakePoolId_, stakeReceiptTokenAmount_, receiver_);

    rewardsManager_.unstake(stakePoolId_, stakeReceiptTokenAmount_, address(this), address(this));
    (redemptionId_,) = safetyModule_.redeem(reservePoolId_, stakeReceiptTokenAmount_, receiver_, address(this));
  }

  /// @notice Unstakes exactly `stakeReceiptTokenAmount_` of stake receipt tokens from a
  /// `rewardsManager_` stake pool. Burns `rewardsManager` stake tokens for `stakePoolId_`, `safetyModule_`
  /// deposit receipt tokens for `reservePoolId_`, and redeems exactly `reserveAssetAmount_` of the `safetyModule_`
  /// reserve pool's underlying tokens to the `receiver_`. If the safety module is PAUSED, withdrawal/redemption
  /// can be completed immediately, otherwise this queues  a redemption which can be completed once sufficient delay
  /// has elapsed. This also claims any outstanding rewards that the user is entitled to for the stake pool.
  /// @dev Caller must first approve the CozyRouter to spend the rewards manager stake tokens.
  function unstakeStakeReceiptTokensAndRedeem(
    ISafetyModule safetyModule_,
    IRewardsManager rewardsManager_,
    uint8 reservePoolId_,
    uint16 stakePoolId_,
    uint256 stakeReceiptTokenAmount_,
    address receiver_
  ) external payable returns (uint64 redemptionId_, uint256 reserveAssetAmount_) {
    _assertAddressNotZero(receiver_);

    // The stake receipt tokens are transferred to this router because RewardsManager.claimRewards must be called by
    // the owner of the stake receipt tokens.
    _transferStakeTokensAndClaimRewards(rewardsManager_, stakePoolId_, stakeReceiptTokenAmount_, receiver_);

    rewardsManager_.unstake(stakePoolId_, stakeReceiptTokenAmount_, address(this), address(this));

    // // Exchange rate between rewards manager stake tokens and safety module deposit receipt tokens is 1:1.
    (redemptionId_, reserveAssetAmount_) =
      safetyModule_.redeem(reservePoolId_, stakeReceiptTokenAmount_, receiver_, address(this));
  }

  /// @notice Completes the redemption corresponding to `id_` in `safetyModule_`.
  function completeWithdraw(ISafetyModule safetyModule_, uint64 id_) external payable {
    safetyModule_.completeRedemption(id_);
  }

  /// @notice Completes the redemption corresponding to `id_` in `safetyModule_`.
  function completeRedemption(ISafetyModule safetyModule_, uint64 id_) external payable {
    safetyModule_.completeRedemption(id_);
  }

  /// @notice Calls the connector to unwrap the wrapped assets and transfer base assets back to `receiver_`.
  /// @dev This assumes that all assets that need to be withdrawn are sitting in the connector. It expects the
  /// integrator has called `CozyRouter.withdraw/redeem/unstake` with `receiver_ == address(connector_)`.
  /// @dev This function should be `aggregate` called with `completeWithdraw/Redeem/Unstake`, or
  /// `withdraw/redeem/unstake`. It can be called with withdraw/redeem/unstake in the case that instant
  /// withdrawals can occur due to the safety module being PAUSED.
  function unwrapWrappedAssetViaConnectorForWithdraw(IConnector connector_, address receiver_) external payable {
    uint256 assets_ = connector_.balanceOf(address(connector_));
    if (assets_ > 0) connector_.unwrapWrappedAsset(receiver_, assets_);
  }

  /// @notice Calls the connector to unwrap the wrapped assets and transfer base assets back to `receiver_`.
  /// @dev This assumes that `assets_` amount of the wrapped assets are sitting in the connector. So, it expects
  /// the integrator has called a safety module operation such as withdraw with `receiver_ ==
  /// address(connector_)`.
  function unwrapWrappedAssetViaConnector(IConnector connector_, uint256 assets_, address receiver_) external payable {
    if (assets_ > 0) connector_.unwrapWrappedAsset(receiver_, assets_);
  }

  // ----------------------------------
  // -------- Internal helpers --------
  // ----------------------------------

  function _wrapBaseAssetViaConnector(IConnector connector_, address receiver_, uint256 baseAssetAmount_)
    internal
    returns (uint256 depositAssetAmount_)
  {
    connector_.baseAsset().safeTransferFrom(msg.sender, address(connector_), baseAssetAmount_);
    depositAssetAmount_ = connector_.wrapBaseAsset(receiver_, baseAssetAmount_);
  }

  /// @dev Caller must first approve the CozyRouter to spend the stake tokens.
  function _transferStakeTokensAndClaimRewards(
    IRewardsManager rewardsManager_,
    uint16 stakePoolId_,
    uint256 stakeReceiptTokenAmount_,
    address receiver_
  ) internal {
    IERC20(rewardsManager_.stakePools(stakePoolId_).stkReceiptToken).safeTransferFrom(
      msg.sender, address(this), stakeReceiptTokenAmount_
    );
    rewardsManager_.claimRewards(stakePoolId_, receiver_);
  }
}
