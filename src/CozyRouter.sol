// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {CozyMath} from "./lib/CozyMath.sol";
import {UpdateConfigsCalldataParams} from "./lib/structs/Configs.sol";
import {TriggerMetadata} from "./lib/structs/Trigger.sol";
import {IChainlinkTriggerFactory} from "src/interfaces/IChainlinkTriggerFactory.sol";
import {IConnector} from "./interfaces/IConnector.sol";
import {ICozySafetyModuleManager} from "./interfaces/ICozySafetyModuleManager.sol";
import {IMetadataRegistry} from "./interfaces/IMetadataRegistry.sol";
import {IOwnableTriggerFactory} from "./interfaces/IOwnableTriggerFactory.sol";
import {IRewardsManager} from "./interfaces/IRewardsManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {IWeth} from "./interfaces/IWeth.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {ITrigger} from "./interfaces/ITrigger.sol";
import {IWstETH} from "./interfaces/IWstETH.sol";
import {IUMATriggerFactory} from "./interfaces/IUMATriggerFactory.sol";

contract CozyRouter {
  using Address for address;
  using CozyMath for uint256;
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;

  /// @notice WETH9 address.
  IWeth public immutable weth;

  /// @notice Staked ETH address.
  IStETH public immutable stEth;

  /// @notice Wrapped staked ETH address.
  IWstETH public immutable wstEth;

  /// @notice The Cozy Safety Module Manager address.
  ICozySafetyModuleManager public immutable manager;

  IChainlinkTriggerFactory public immutable chainlinkTriggerFactory;

  IOwnableTriggerFactory public immutable ownableTriggerFactory;

  IUMATriggerFactory public immutable umaTriggerFactory;

  /// @dev Thrown when a call in `aggregate` fails, contains the index of the call and the data it returned.
  error CallFailed(uint256 index, bytes returnData);

  /// @dev Thrown when an invalid address is passed as a parameter.
  error InvalidAddress();

  /// @dev Thrown when the router's balance is too low to perform the requested action.
  error InsufficientBalance();

  /// @dev Thrown when a token or ETH transfer failed.
  error TransferFailed();

  constructor(
    ICozySafetyModuleManager manager_,
    IWeth weth_,
    IStETH stEth_,
    IWstETH wstEth_,
    IChainlinkTriggerFactory chainlinkTriggerFactory_,
    IOwnableTriggerFactory ownableTriggerFactory_,
    IUMATriggerFactory umaTriggerFactory_
  ) {
    _assertAddressNotZero(address(weth_));

    // The addresses for stEth and wstEth can be 0 in our current deployment setup
    weth = weth_;
    stEth = stEth_;
    wstEth = wstEth_;

    chainlinkTriggerFactory = chainlinkTriggerFactory_;
    ownableTriggerFactory = ownableTriggerFactory_;
    umaTriggerFactory = umaTriggerFactory_;

    manager = manager_;

    if (address(stEth) != address(0)) IERC20(address(stEth)).safeIncreaseAllowance(address(wstEth), type(uint256).max);
  }

  receive() external payable {}

  // ---------------------------
  // -------- Multicall --------
  // ---------------------------

  /// @notice Enables batching of multiple router calls into a single transaction.
  /// @dev All methods in this contract must be payable to support sending ETH with a batch call.
  /// @param calls_ Array of ABI encoded calls to be performed.
  function aggregate(bytes[] calldata calls_) external payable returns (bytes[] memory returnData_) {
    returnData_ = new bytes[](calls_.length);

    for (uint256 i = 0; i < calls_.length; i++) {
      (bool success_, bytes memory response_) = address(this).delegatecall(calls_[i]);
      if (!success_) revert CallFailed(i, response_);
      returnData_[i] = response_;
    }
  }

  // -------------------------------
  // -------- Token Helpers --------
  // -------------------------------

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

  // ---------------------------------
  // -------- Deposit / Stake --------
  // ---------------------------------

  /// @notice Deposits assets into a `safetyModule_` reserve pool. Mints `depositReceiptTokenAmount_` to `receiver_` by
  /// depositing exactly `reserveAssetAmount_` of the reserve pool's underlying tokens into the `safetyModule_`. The
  /// specified amount of assets are transferred from the caller to the Safety Module.
  function depositReserveAssets(
    ISafetyModule safetyModule_,
    uint8 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_
  ) public payable returns (uint256 depositReceiptTokenAmount_) {
    // Caller must first approve this router to spend the reserve pool's asset.
    IERC20 asset_ = safetyModule_.reservePools(reservePoolId_).asset;
    asset_.safeTransferFrom(msg.sender, address(safetyModule_), reserveAssetAmount_);

    depositReceiptTokenAmount_ =
      depositReserveAssetsWithoutTransfer(safetyModule_, reservePoolId_, reserveAssetAmount_, receiver_);
  }

  /// @notice Deposits assets into a `rewardsManager_` reward pool. Mints `depositReceiptTokenAmount_` to `receiver_`
  /// by depositing exactly `rewardAssetAmount_` of the reward pool's underlying tokens into the `rewardsManager_`.
  /// The specified amount of assets are transferred from the caller to the `rewardsManager_`.
  function depositRewardAssets(
    IRewardsManager rewardsManager_,
    uint16 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address receiver_
  ) external payable returns (uint256 depositReceiptTokenAmount_) {
    // Caller must first approve this router to spend the reward pool's asset.
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

  /// @notice Stakes assets into the `rewardsManager_`. Mints `stakeTokenAmount_` to `receiver_` by staking exactly
  /// `stakeAssetAmount_` of the stake pool's underlying tokens into the `rewardsManager_`. The specified amount of
  /// assets are transferred from the caller to the `rewardsManager_`.
  function stake(IRewardsManager rewardsManager_, uint16 stakePoolId_, uint256 stakeAssetAmount_, address receiver_)
    external
    payable
    returns (uint256 stakeReceiptTokenAmount_)
  {
    _assertAddressNotZero(receiver_);
    // Caller must first approve this router to spend the stake pool's asset.
    IERC20 asset_ = rewardsManager_.stakePools(stakePoolId_).asset;
    asset_.safeTransferFrom(msg.sender, address(rewardsManager_), stakeAssetAmount_);

    stakeReceiptTokenAmount_ = stakeWithoutTransfer(rewardsManager_, stakePoolId_, stakeAssetAmount_, receiver_);
  }

  /// @notice Executes a stake against `rewardsManager_` in the stake pool corresponding to `stakePoolId_`, sending
  /// the resulting stake tokens to `receiver_`. This method does not transfer the assets to the Rewards Manager which
  /// are necessary for the stake, thus the caller should ensure that a transfer to the Rewards Manager with the
  /// needed amount of assets (`stakeAssetAmount_`) of the stake pool's underlying asset (viewable with
  /// `rewardsManager.stakePools(stakePoolId_)`) is transferred to the Rewards Manager before calling this method.
  /// In general, prefer using `CozyRouter.stake` to stake into a Rewards Manager, this method is here to facilitate
  /// MultiCall transactions.
  function stakeWithoutTransfer(
    IRewardsManager rewardsManager_,
    uint16 stakePoolId_,
    uint256 stakeAssetAmount_,
    address receiver_
  ) public payable returns (uint256 stakeReceiptTokenAmount_) {
    _assertAddressNotZero(receiver_);
    stakeReceiptTokenAmount_ = rewardsManager_.stakeWithoutTransfer(stakePoolId_, stakeAssetAmount_, receiver_);
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
  ) external payable returns (uint256 depositReceiptTokenAmount_) {
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
  /// `stakeReceiptTokenAmount` from caller and sends exactly `stakeAssetAmount_` of the stake pool's underlying
  /// tokens to the `receiver_`. This also claims any outstanding rewards that the user is entitled to for the stake
  /// pool.
  function unstake(
    IRewardsManager rewardsManager_,
    uint16 stakePoolId_,
    uint256 stakeReceiptTokenAmount,
    address receiver_
  ) public payable returns (uint256 stakeAssetAmount_) {
    _assertAddressNotZero(receiver_);
    // Caller must first approve the CozyRouter to spend the stake tokens.
    // Exchange rate between rewards manager stake tokens and safety module deposit receipt tokens is 1:1.
    stakeAssetAmount_ = rewardsManager_.unstake(stakePoolId_, stakeReceiptTokenAmount, receiver_, msg.sender);
  }

  /// @notice Burns `rewardsManager_` stake tokens for `stakePoolId_` stake pool from caller and sends exactly
  /// `reserveAssetAmount_` of `safetyModule_` `reservePoolId_` reserve pool's underlying tokens to the `receiver_`,
  /// and reverts if less than `minAssetsReceived_` of the reserve pool asset would be received.
  /// If the safety module is PAUSED, unstake can be completed immediately, otherwise this
  /// queues a redemption which can be completed once sufficient delay has elapsed. This also claims any outstanding
  /// rewards that the user is entitled to.
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

    // Caller must first approve the CozyRouter to spend the rewards manager stake tokens.
    unstake(rewardsManager_, stakePoolId_, stakeReceiptTokenAmount_, address(this));

    (redemptionId_,) = safetyModule_.redeem(reservePoolId_, stakeReceiptTokenAmount_, receiver_, address(this));
  }

  /// @notice Unstakes exactly `stakeReceiptTokenAmount_` of stake receipt tokens from a
  /// `rewardsManager_` stake pool. Burns `rewardsManager` stake tokens for `stakePoolId_`, `safetyModule_`
  /// deposit receipt tokens for `reservePoolId_`, and redeems exactly `reserveAssetAmount_` of the `safetyModule_`
  /// reserve pool's underlying tokens to the `receiver_`. If the safety module is PAUSED, withdrawal/redemption
  /// can be completed immediately, otherwise this queues  a redemption which can be completed once sufficient delay
  /// has elapsed. This also claims any outstanding rewards that the user is entitled to for the stake pool.
  function unstakeStakeReceiptTokensAndRedeem(
    ISafetyModule safetyModule_,
    IRewardsManager rewardsManager_,
    uint8 reservePoolId_,
    uint16 stakePoolId_,
    uint256 stakeReceiptTokenAmount_,
    address receiver_
  ) external payable returns (uint64 redemptionId_, uint256 reserveAssetAmount_) {
    _assertAddressNotZero(receiver_);

    // Caller must first approve the CozyRouter to spend the rewards manager stake tokens.
    unstake(rewardsManager_, stakePoolId_, stakeReceiptTokenAmount_, address(this));

    // Exchange rate between rewards manager stake tokens and safety module deposit receipt tokens is 1:1.
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

  // ------------------------------------
  // -------- Deployment Helpers --------
  // ------------------------------------

  /// @notice Deploys a new ChainlinkTrigger.
  /// @param truthOracle_ The address of the desired truthOracle for the trigger.
  /// @param trackingOracle_ The address of the desired trackingOracle for the trigger.
  /// @param priceTolerance_ The priceTolerance that the deployed trigger will
  /// have. See ChainlinkTrigger.priceTolerance() for more information.
  /// @param truthFrequencyTolerance_ The frequency tolerance that the deployed trigger will
  /// have for the truth oracle. See ChainlinkTrigger.truthFrequencyTolerance() for more information.
  /// @param trackingFrequencyTolerance_ The frequency tolerance that the deployed trigger will
  /// have for the tracking oracle. See ChainlinkTrigger.trackingFrequencyTolerance() for more information.
  /// @param metadata_ See TriggerMetadata for more info.
  function deployChainlinkTrigger(
    AggregatorV3Interface truthOracle_,
    AggregatorV3Interface trackingOracle_,
    uint256 priceTolerance_,
    uint256 truthFrequencyTolerance_,
    uint256 trackingFrequencyTolerance_,
    TriggerMetadata memory metadata_
  ) external payable returns (ITrigger trigger_) {
    trigger_ = chainlinkTriggerFactory.deployTrigger(
      truthOracle_, trackingOracle_, priceTolerance_, truthFrequencyTolerance_, trackingFrequencyTolerance_, metadata_
    );
  }

  /// @notice Deploys a new ChainlinkTrigger with a FixedPriceAggregator as its truthOracle. This is useful if you were
  /// configurating a safety module in which you wanted to track whether or not a stablecoin asset had become depegged.
  /// @param price_ The fixed price, or peg, with which to compare the trackingOracle price.
  /// @param decimals_ The number of decimals of the fixed price. This should
  /// match the number of decimals used by the desired _trackingOracle.
  /// @param trackingOracle_ The address of the desired trackingOracle for the trigger.
  /// @param priceTolerance_ The priceTolerance that the deployed trigger will
  /// have. See ChainlinkTrigger.priceTolerance() for more information.
  /// @param frequencyTolerance_ The frequency tolerance that the deployed trigger will
  /// have for the tracking oracle. See ChainlinkTrigger.trackingFrequencyTolerance() for more information.
  /// @param metadata_ See TriggerMetadata for more info.
  function deployChainlinkFixedPriceTrigger(
    int256 price_,
    uint8 decimals_,
    AggregatorV3Interface trackingOracle_,
    uint256 priceTolerance_,
    uint256 frequencyTolerance_,
    TriggerMetadata memory metadata_
  ) external payable returns (ITrigger trigger_) {
    trigger_ = chainlinkTriggerFactory.deployTrigger(
      price_, decimals_, trackingOracle_, priceTolerance_, frequencyTolerance_, metadata_
    );
  }

  /// @notice Deploys a new OwnableTrigger.
  /// @param owner_ The owner of the trigger.
  /// @param metadata_ See TriggerMetadata for more info.
  /// @param salt_ The salt used to derive the trigger's address.
  function deployOwnableTrigger(address owner_, TriggerMetadata memory metadata_, bytes32 salt_)
    external
    payable
    returns (ITrigger trigger_)
  {
    trigger_ = ownableTriggerFactory.deployTrigger(owner_, metadata_, salt_);
  }

  /// @notice Deploys a new UMATrigger.
  /// @dev Be sure to approve the CozyRouter to spend the `rewardAmount_` before calling
  /// `deployUMATrigger`, otherwise the latter will revert. Funds need to be available
  /// to the created trigger within its constructor so that it can submit its query
  /// to the UMA oracle.
  /// @param query_ The query that the trigger will send to the UMA Optimistic
  /// Oracle for evaluation.
  /// @param rewardToken_ The token used to pay the reward to users that propose
  /// answers to the query. The reward token must be approved by UMA governance.
  /// Approved tokens can be found with the UMA AddressWhitelist contract on each
  /// chain supported by UMA.
  /// @param rewardAmount_ The amount of rewardToken that will be paid as a
  /// reward to anyone who proposes an answer to the query.
  /// @param refundRecipient_ Default address that will recieve any leftover
  /// rewards at UMA query settlement time.
  /// @param bondAmount_ The amount of `rewardToken` that must be staked by a
  /// user wanting to propose or dispute an answer to the query. See UMA's price
  /// dispute workflow for more information. It's recommended that the bond
  /// amount be a significant value to deter addresses from proposing malicious,
  /// false, or otherwise self-interested answers to the query.
  /// @param proposalDisputeWindow_ The window of time in seconds within which a
  /// proposed answer may be disputed. See UMA's "customLiveness" setting for
  /// more information. It's recommended that the dispute window be fairly long
  /// (12-24 hours), given the difficulty of assessing expected queries (e.g.
  /// "Was protocol ABCD hacked") and the amount of funds potentially at stake.
  /// @param metadata_ See TriggerMetadata for more info.
  function deployUMATrigger(
    string memory query_,
    IERC20 rewardToken_,
    uint256 rewardAmount_,
    address refundRecipient_,
    uint256 bondAmount_,
    uint256 proposalDisputeWindow_,
    TriggerMetadata memory metadata_
  ) external payable returns (ITrigger trigger_) {
    // UMATriggerFactory.deployTrigger uses safeTransferFrom to transfer rewardToken_ from caller.
    // In the context of deployTrigger below, msg.sender is this CozyRouter, so the funds must first be transferred
    // here.
    rewardToken_.safeTransferFrom(msg.sender, address(this), rewardAmount_);
    rewardToken_.approve(address(umaTriggerFactory), rewardAmount_);
    trigger_ = umaTriggerFactory.deployTrigger(
      query_, rewardToken_, rewardAmount_, refundRecipient_, bondAmount_, proposalDisputeWindow_, metadata_
    );
  }

  /// @notice Deploys a new Cozy Safety Module.
  function deploySafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 salt_
  ) external payable returns (ISafetyModule safetyModule_) {
    safetyModule_ = manager.createSafetyModule(owner_, pauser_, configs_, salt_);
  }

  /// @notice Update metadata for a safety module.
  /// @dev `msg.sender` must be the owner of the safety module.
  /// @param metadataRegistry_ The address of the metadata registry.
  /// @param safetyModule_ The address of the safety module.
  /// @param metadata_ The new metadata for the safety module.
  function updateSafetyModuleMetadata(
    IMetadataRegistry metadataRegistry_,
    address safetyModule_,
    IMetadataRegistry.Metadata calldata metadata_
  ) external payable {
    metadataRegistry_.updateSafetyModuleMetadata(safetyModule_, metadata_, msg.sender);
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

  function _assertIsValidSafetyModule(address safetyModule_) internal view {
    if (!manager.isSafetyModule(ISafetyModule(safetyModule_))) revert InvalidAddress();
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
