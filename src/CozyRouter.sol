// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {CozyMath} from "./lib/CozyMath.sol";
import {SafeERC20} from "./lib/SafeERC20.sol";
import {UpdateConfigsCalldataParams} from "./lib/structs/Configs.sol";
import {TriggerMetadata} from "./lib/structs/Trigger.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IConnector} from "./interfaces/IConnector.sol";
import {IManager} from "./interfaces/IManager.sol";
import {IOwnableTriggerFactory} from "./interfaces/IOwnableTriggerFactory.sol";
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
  IManager public immutable manager;

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

  /// @dev Thrown when slippage was larger than the specified threshold.
  error SlippageExceeded();

  constructor(
    IManager manager_,
    IWeth weth_,
    IStETH stEth_,
    IWstETH wstEth_,
    IOwnableTriggerFactory ownableTriggerFactory_,
    IUMATriggerFactory umaTriggerFactory_
  ) {
    _assertAddressNotZero(address(weth_));

    // The addresses for stEth and wstEth can be 0 in our current deployment setup
    weth = weth_;
    stEth = stEth_;
    wstEth = wstEth_;

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

  /// @notice Deposits assets into a `safetyModule_` reserve pool. Mints `depositTokenAmount_` to `receiver_` by
  /// depositing exactly `reserveAssetAmount_` of the reserve pool's underlying tokens into the `safetyModule_`,
  /// and reverts if less than `minReceiptTokensReceived_` are minted. The specified amount of assets are transferred
  /// from the caller to the Safety Module.
  function depositReserveAssets(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) external payable returns (uint256 depositTokenAmount_) {
    // Caller must first approve this router to spend the reserve pool's asset.
    (,,,,,, IERC20 asset_,,,) = safetyModule_.reservePools(reservePoolId_);
    asset_.safeTransferFrom(msg.sender, address(safetyModule_), reserveAssetAmount_);

    depositTokenAmount_ = depositReserveAssetsWithoutTransfer(
      safetyModule_, reservePoolId_, reserveAssetAmount_, receiver_, minReceiptTokensReceived_
    );
  }

  /// @notice Deposits assets into a `safetyModule_` undripped reward pool. Mints `depositTokenAmount_` to `receiver_`
  /// by depositing exactly `reserveAssetAmount_` of the reward pool's underlying tokens into the `safetyModule_`, and
  /// reverts if less than `minReceiptTokensReceived_` are minted. The specified amount of assets are transferred from
  /// the caller to the Safety Module.
  function depositRewardAssets(
    ISafetyModule safetyModule_,
    uint16 rewardPoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) external payable returns (uint256 depositTokenAmount_) {
    // Caller must first approve this router to spend the reward pool's asset.
    (,,,,,, IERC20 asset_,,,) = safetyModule_.reservePools(rewardPoolId_);
    asset_.safeTransferFrom(msg.sender, address(safetyModule_), reserveAssetAmount_);

    depositTokenAmount_ = depositRewardAssetsWithoutTransfer(
      safetyModule_, rewardPoolId_, reserveAssetAmount_, receiver_, minReceiptTokensReceived_
    );
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
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) public payable returns (uint256 depositTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositTokenAmount_ =
      safetyModule_.depositReserveAssetsWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
    if (depositTokenAmount_ < minReceiptTokensReceived_) revert SlippageExceeded();
  }

  /// @notice Executes a deposit into `safetyModule_` in the undripped reward pool corresponding to `rewardPoolId`,
  /// sending the resulting deposit tokens to `receiver_`. This method does not transfer the assets to the Safety
  /// Module which are necessary for the deposit, thus the caller should ensure that a transfer to the Safety Module
  /// with the needed amount of assets (`rewardAssetAmount_`) of the reward pool's underlying asset (viewable with
  /// `safetyModule.undrippedRewardPools(rewardPoolId_)`) is transferred to the Safety Module before calling this
  /// method. In general, prefer using `CozyRouter.depositRewardAssets` to deposit into a Safety Module reward pool,
  /// this method is here to facilitate MultiCall transactions.
  function depositRewardAssetsWithoutTransfer(
    ISafetyModule safetyModule_,
    uint16 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) public payable returns (uint256 depositTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositTokenAmount_ = safetyModule_.depositRewardAssetsWithoutTransfer(rewardPoolId_, rewardAssetAmount_, receiver_);
    if (depositTokenAmount_ < minReceiptTokensReceived_) revert SlippageExceeded();
  }

  /// @notice Stakes assets into the `safetyModule_`. Mints `stakeTokenAmount_` to `receiver_` by staking exactly
  /// `assets_` of the reserve pool's underlying tokens into the `safetyModule_`, and reverts if less than
  ///`minReceiptTokensReceived_` are minted. The specified amount of assets are transferred from the caller to the
  /// Safety Module.
  function stake(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) external payable returns (uint256 stakeTokenAmount_) {
    _assertAddressNotZero(receiver_);
    // Caller must first approve this router to spend the reserve pool's asset.
    (,,,,,, IERC20 asset_,,,) = safetyModule_.reservePools(reservePoolId_);
    asset_.safeTransferFrom(msg.sender, address(safetyModule_), reserveAssetAmount_);

    stakeTokenAmount_ =
      stakeWithoutTransfer(safetyModule_, reservePoolId_, reserveAssetAmount_, receiver_, minReceiptTokensReceived_);
  }

  /// @notice Executes a stake against `safetyModule_` in the reserve pool corresponding to `reservePoolId_`, sending
  /// the resulting stake tokens to `receiver_`. This method does not transfer the assets to the Safety Module which
  /// are necessary for the stake, thus the caller should ensure that a transfer to the Safety Module with the
  /// needed amount of assets (`reserveAssetAmount_`) of the reserve pool's underlying asset (viewable with
  /// `safetyModule.reservePools(reservePoolId_)`) is transferred to the Safety Module before calling this method.
  /// In general, prefer using `CozyRouter.stake` to stake into a Safety Module, this method is here to facilitate
  /// MultiCall transactions.
  function stakeWithoutTransfer(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) public payable returns (uint256 stakeTokenAmount_) {
    _assertAddressNotZero(receiver_);
    stakeTokenAmount_ = safetyModule_.stakeWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
    if (stakeTokenAmount_ < minReceiptTokensReceived_) revert SlippageExceeded();
  }

  /// @notice Calls the connector to wrap the base asset, send the wrapped assets to `safetyModule_`, and then
  /// `depositReserveAssetsWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `baseAssetAmount_` of the base asset.
  function wrapBaseAssetViaConnectorAndDepositReserveAssets(
    IConnector connector_,
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 baseAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) external payable returns (uint256 depositTokenAmount_) {
    uint256 depositAssetAmount_ = _wrapBaseAssetViaConnector(connector_, safetyModule_, baseAssetAmount_);
    depositTokenAmount_ = depositReserveAssetsWithoutTransfer(
      safetyModule_, reservePoolId_, depositAssetAmount_, receiver_, minReceiptTokensReceived_
    );
  }

  /// @notice Calls the connector to wrap the base asset, send the wrapped assets to `safetyModule_`, and then
  /// `depositRewardAssetsWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `baseAssetAmount_` of the base asset.
  function wrapBaseAssetViaConnectorAndDepositRewardAssets(
    IConnector connector_,
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 baseAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) external payable returns (uint256 depositTokenAmount_) {
    uint256 depositAssetAmount_ = _wrapBaseAssetViaConnector(connector_, safetyModule_, baseAssetAmount_);
    depositTokenAmount_ = depositRewardAssetsWithoutTransfer(
      safetyModule_, reservePoolId_, depositAssetAmount_, receiver_, minReceiptTokensReceived_
    );
  }

  /// @notice Calls the connector to wrap the base asset, send the wrapped assets to `safetyModule_`, and then
  /// `stakeWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `baseAssetAmount_` of the base asset.
  function wrapBaseAssetViaConnectorAndStake(
    IConnector connector_,
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 baseAssetAmount_,
    address receiver_,
    uint256 minReceiptTokensReceived_ // The minimum amount of receipt tokens the user expects to receive.
  ) external payable returns (uint256 depositTokenAmount_) {
    connector_.baseAsset().safeTransferFrom(msg.sender, address(connector_), baseAssetAmount_);
    uint256 depositAssetAmount_ = connector_.wrapBaseAsset(address(safetyModule_), baseAssetAmount_);
    depositTokenAmount_ =
      stakeWithoutTransfer(safetyModule_, reservePoolId_, depositAssetAmount_, receiver_, minReceiptTokensReceived_);
  }

  // --------------------------------------
  // -------- Withdrawal / Unstake --------
  // --------------------------------------

  /// @notice Removes assets from a `safetyModule_` reserve pool. Burns `depositTokenAmount_` from owner and sends
  /// exactly `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`, and reverts if
  /// more than `maxReceiptTokensBurned_` are burned. If the safety module is PAUSED, withdrawal can be completed
  /// immediately, otherwise this queues a redemption which can be completed once sufficient delay has elapsed.
  function withdrawReservePoolAssets(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 maxReceiptTokensBurned_
  ) external payable returns (uint64 redemptionId_, uint256 depositTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositTokenAmount_ = safetyModule_.convertToReserveDepositTokenAmount(reservePoolId_, reserveAssetAmount_);
    if (depositTokenAmount_ > maxReceiptTokensBurned_) revert SlippageExceeded();
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    (redemptionId_,) = safetyModule_.redeem(reservePoolId_, depositTokenAmount_, receiver_, msg.sender);
  }

  /// @notice Removes assets from a `safetyModule_` reserve pool. Burns `depositTokenAmount_` from owner and sends
  /// exactly `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`, and reverts if less
  /// than `minAssetsReceived_` would be received. If the safety module is PAUSED, withdrawal can be completed
  /// immediately, otherwise this queues a redemption which can be completed once sufficient delay has elapsed.
  function redeemReservePoolDepositTokens(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 depositTokenAmount_,
    address receiver_,
    uint256 minAssetsReceived_
  ) external payable returns (uint64 redemptionId_, uint256 assetsReceived_) {
    _assertAddressNotZero(receiver_);
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    (redemptionId_, assetsReceived_) = safetyModule_.redeem(reservePoolId_, depositTokenAmount_, receiver_, msg.sender);
    if (assetsReceived_ < minAssetsReceived_) revert SlippageExceeded();
  }

  /// @notice Removes assets from a `safetyModule_` undripped reward pool. Burns `depositTokenAmount_` from owner and
  /// sends exactly `rewardAssetAmount_` of the reward pool's underlying tokens to the `receiver_`, and reverts if
  /// more than `maxReceiptTokensBurned_` are burned. Withdrawal of assets from undripped reward pools can be completed
  /// instantly.
  function withdrawRewardPoolAssets(
    ISafetyModule safetyModule_,
    uint16 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address receiver_,
    uint256 maxReceiptTokensBurned_
  ) external payable returns (uint256 depositTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositTokenAmount_ = safetyModule_.convertToRewardDepositTokenAmount(rewardPoolId_, rewardAssetAmount_);
    if (depositTokenAmount_ > maxReceiptTokensBurned_) revert SlippageExceeded();
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    safetyModule_.redeemUndrippedRewards(rewardPoolId_, depositTokenAmount_, receiver_, msg.sender);
  }

  // @notice Removes assets from a `safetyModule_` undripped reward pool. Burns `depositTokenAmount_` from owner and
  /// sends exactly `rewardAssetAmount_` of the reward pool's underlying tokens to the `receiver_`, and reverts if
  /// less than `minAssetsReceived_` would be received. Withdrawal of assets from undripped reward pools can be
  /// completed instantly.
  function redeemRewardPoolDepositTokens(
    ISafetyModule safetyModule_,
    uint16 poolId_,
    uint256 depositTokenAmount_,
    address receiver_,
    uint256 minAssetsReceived_
  ) external payable returns (uint256 assetsReceived_) {
    _assertAddressNotZero(receiver_);
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    assetsReceived_ = safetyModule_.redeemUndrippedRewards(poolId_, depositTokenAmount_, receiver_, msg.sender);
    if (assetsReceived_ < minAssetsReceived_) revert SlippageExceeded();
  }

  /// @notice Unstakes exactly `stakeTokenAmount` from a `safetyModule_` reserve pool. Burns `stkTokenAmount_` from
  /// owner and sends exactly `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`, and
  /// reverts if less than `minAssetsReceived_` of the reserve pool asset would be received. If the safety module is
  /// PAUSED, unstake can be completed immediately, otherwise this queues a redemption which can be completed once
  /// sufficient delay has elapsed. This also claims any outstanding rewards that the user is entitled to.
  function unstake(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 stkTokenAmount_,
    address receiver_,
    uint256 minAssetsReceived_
  ) external payable returns (uint64 redemptionId_, uint256 reserveAssetAmount_) {
    _assertAddressNotZero(receiver_);
    // Caller must first approve the CozyRouter to spend the stake tokens.
    (redemptionId_, reserveAssetAmount_) = safetyModule_.unstake(reservePoolId_, stkTokenAmount_, receiver_, msg.sender);
    if (reserveAssetAmount_ < minAssetsReceived_) revert SlippageExceeded();
  }

  /// @notice Unstakes exactly `reserveAssetAmount_` from a `safetyModule_` reserve pool. Burns `stkTokenAmount_`
  /// from owner and sends exactly `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`,
  /// and reverts if more than `maxReceiptTokensBurned_` are burned. If the safety module is PAUSED, unstake can be
  /// completed immediately, otherwise this queues a redemption which can be completed once sufficient delay has
  /// elapsed. This also claims any outstanding rewards that the user is entitled to.
  function unstakeAssetAmount(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 maxReceiptTokensBurned_
  ) external payable returns (uint64 redemptionId_, uint256 stkTokenAmount_) {
    _assertAddressNotZero(receiver_);
    stkTokenAmount_ = safetyModule_.convertToStakeTokenAmount(reservePoolId_, reserveAssetAmount_);
    if (stkTokenAmount_ > maxReceiptTokensBurned_) revert SlippageExceeded();
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    (redemptionId_,) = safetyModule_.unstake(reservePoolId_, stkTokenAmount_, receiver_, msg.sender);
  }

  /// @notice Completes the redemption corresponding to `id_` in `safetyModule_`.
  function completeWithdraw(ISafetyModule safetyModule_, uint64 id_) external payable {
    safetyModule_.completeRedemption(id_);
  }

  /// @notice Completes the redemption corresponding to `id_` in `safetyModule_`.
  function completeRedemption(ISafetyModule safetyModule_, uint64 id_) external payable {
    safetyModule_.completeRedemption(id_);
  }

  /// @notice Completes the unstake corresponding to redemption id `id_` in `safetyModule_`.
  function completeUnstake(ISafetyModule safetyModule_, uint64 id_) external payable {
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
    // UMATriggerFactory.deployTrigger uses safeTransferFrom to transfer rewardToken_ from msg.sender.
    // In the context of deployTrigger below, msg.sender is this CozyRouter, so the funds must first be transferred
    // here.
    rewardToken_.safeTransferFrom(msg.sender, address(this), rewardAmount_);
    rewardToken_.approve(address(umaTriggerFactory), rewardAmount_);
    trigger_ = umaTriggerFactory.deployTrigger(
      query_, rewardToken_, rewardAmount_, refundRecipient_, bondAmount_, proposalDisputeWindow_, metadata_
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

  /// @notice Deploys a new Cozy Safety Module.
  function deploySafetyModule(
    address owner_,
    address pauser_,
    UpdateConfigsCalldataParams calldata configs_,
    bytes32 salt_
  ) external payable returns (ISafetyModule safetyModule_) {
    safetyModule_ = manager.createSafetyModule(owner_, pauser_, configs_, salt_);
  }

  // ----------------------------------
  // -------- Internal helpers --------
  // ----------------------------------

  function _wrapBaseAssetViaConnector(IConnector connector_, ISafetyModule safetyModule_, uint256 baseAssetAmount_)
    internal
    returns (uint256 depositAssetAmount_)
  {
    connector_.baseAsset().safeTransferFrom(msg.sender, address(connector_), baseAssetAmount_);
    depositAssetAmount_ = connector_.wrapBaseAsset(address(safetyModule_), baseAssetAmount_);
  }

  function _assertIsValidSafetyModule(address safetyModule_) internal view {
    if (!manager.isSafetyModule(ISafetyModule(safetyModule_))) revert InvalidAddress();
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
