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

  /// @param weth_ WETH9 address.
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

  // ---------------------------
  // -------- Multicall --------
  // ---------------------------

  /// @notice Enables batching of multiple router calls into a single transaction.
  /// @dev All methods in this contract must be payable to support sending ETH with a batch call.
  /// @param calls_ Array of ABI encoded calls to be performed.
  function aggregate(bytes[] calldata calls_) external payable returns (bytes[] memory returnData_) {
    returnData_ = new bytes[](calls_.length);

    for (uint256 i = 0; i < calls_.length; i = i++) {
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

  /// @notice Pulls `amount_` of the specified `token_` from the caller and sends them to `recipient_`.
  /// @dev Used for migration scenarios to allow users to transfer excess tokens to a new set when a refund from an old
  /// set is insufficient for the new purchase.
  function pullToken(IERC20 token_, address recipient_, uint256 amount_) external payable {
    _assertAddressNotZero(recipient_);
    token_.safeTransferFrom(msg.sender, recipient_, amount_);
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

  /// @notice Wraps caller's entire balance of stETH as wstETH and transfers to `set_`.
  /// Requires pre-approval of the router to transfer the caller's stETH.
  /// @dev This function should be `aggregate` called with `purchaseWithoutTransfer` or `depositWithoutTransfer`.
  function wrapStEth(address set_) external {
    _assertIsValidSafetyModule(set_);
    wrapStEth(set_, stEth.balanceOf(msg.sender));
  }

  /// @notice Wraps `amount_` of stETH as wstETH and transfers to `set_`.
  /// Requires pre-approval of the router to transfer the caller's stETH.
  /// @dev This function should be `aggregate` called with `purchaseWithoutTransfer` or `depositWithoutTransfer`.
  function wrapStEth(address set_, uint256 amount_) public {
    _assertIsValidSafetyModule(set_);
    IERC20(address(stEth)).safeTransferFrom(msg.sender, address(this), amount_);
    uint256 wstEthAmount_ = wstEth.wrap(stEth.balanceOf(address(this)));
    IERC20(address(wstEth)).safeTransfer(set_, wstEthAmount_);
  }

  /// @notice Unwraps router's balance of wstETH into stETH and transfers to `recipient_`.
  /// @dev This function should be `aggregate` called with `sell/cancel` or `completeRedeem/completeWithdraw`. This
  /// should also be called with `withdraw/redeem` in the case that instant withdrawals/redemptions can occur due to
  /// the set being PAUSED.
  function unwrapStEth(address recipient_) external {
    _assertAddressNotZero(recipient_);
    uint256 stEthAmount_ = wstEth.unwrap(wstEth.balanceOf(address(this)));
    IERC20(address(stEth)).safeTransfer(recipient_, stEthAmount_);
  }

  /// @notice Wraps all ETH held by this contact into WETH and sends WETH to the `set_`.
  /// @dev This function should be `aggregate` called with `purchaseWithoutTransfer` or `depositWithoutTransfer`.
  function wrapWeth(address set_) external payable {
    _assertIsValidSafetyModule(set_);
    uint256 amount_ = address(this).balance;
    weth.deposit{value: amount_}();
    IERC20(address(weth)).safeTransfer(set_, amount_);
  }

  /// @notice Wraps the specified `amount_` of ETH from this contact into WETH and sends WETH to the `set_`.
  /// @dev This function should be `aggregate` called with `purchaseWithoutTransfer` or `depositWithoutTransfer`.
  function wrapWeth(address set_, uint256 amount_) external payable {
    _assertIsValidSafetyModule(set_);
    // Using msg.value in a multicall is dangerous, so we avoid it.
    if (address(this).balance < amount_) revert InsufficientBalance();
    weth.deposit{value: amount_}();
    IERC20(address(weth)).safeTransfer(set_, amount_);
  }

  /// @notice Unwraps all WETH held by this contact and sends ETH to the `recipient_`.
  /// @dev Reentrancy is possible here, but this router is stateless and therefore a reentrant call is not harmful.
  /// @dev This function should be `aggregate` called with `sell/cancel` or `completeRedeem/completeWithdraw`. This
  /// should also be called with `withdraw/redeem` in the case that instant withdrawals/redemptions can occur due to
  /// the set being PAUSED.
  function unwrapWeth(address recipient_) external payable {
    _assertAddressNotZero(recipient_);
    uint256 amount_ = weth.balanceOf(address(this));
    weth.withdraw(amount_);
    // Enables reentrancy, but this is a stateless router so it's ok.
    Address.sendValue(payable(recipient_), amount_);
  }

  /// @notice Unwraps the specified `amount_` of WETH held by this contact and sends ETH to the `recipient_`.
  /// @dev Reentrancy is possible here, but this router is stateless and therefore a reentrant call is not harmful.
  /// @dev This function should be `aggregate` called with `sell/cancel` or `completeRedeem/completeWithdraw`. This
  /// should also be called with `withdraw/redeem` in the case that instant withdrawals/redemptions can occur due to
  /// the set being PAUSED.
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

  /// @notice Deposits assets into the `safetyModule_`. Mints `depositTokenAmount_` to `receiver_` by depositing exactly
  /// `assets_` of the reserve/reward pool's underlying tokens into the `safetyModule_`, and reverts if less than
  ///`minSharesReceived_` are minted. The specified amount of assets are transferred from the caller to the Safety
  /// Module.
  function deposit(
    bool isReserveAssetDeposit_,
    ISafetyModule safetyModule_,
    uint16 poolId_,
    uint256 assetAmount_,
    address receiver_,
    uint256 minSharesReceived_ // The minimum amount of shares the user expects to receive.
  ) external payable returns (uint256 depositTokenAmount_) {
    // Caller must first approve this router to spend the set's asset.
    IERC20 asset_;
    if (isReserveAssetDeposit_) (,,,,,, asset_,,,) = safetyModule_.reservePools(poolId_);
    else (, asset_,,) = safetyModule_.undrippedRewardPools(poolId_);
    asset_.safeTransferFrom(msg.sender, address(safetyModule_), assetAmount_);

    depositTokenAmount_ = depositWithoutTransfer(
      isReserveAssetDeposit_, safetyModule_, poolId_, assetAmount_, receiver_, minSharesReceived_
    );
  }

  /// @notice Executes a deposit against `safetyModule_` in the reserve/reward pool corresponding to `poolId_`, sending
  /// the resulting deposit tokens to `receiver_`. This method does not transfer the assets to the Safety Module which
  /// are necessary for the deposit, thus the caller should ensure that a transfer to the Safety Module with the
  /// needed amount of assets (`assetAmount_`) of the reserve/reward pool's underlying asset (viewable with
  /// `safetyModule.reservePools(reservePoolId_)` or `safetyModule.undrippedRewardPools(rewardPoolId_)`) is transferred
  /// to the Safety Module before calling this method.
  /// In general, prefer using `CozyRouter.deposit` / `SafetyModule.depositRewardAssets to deposit into
  /// a Safety Module, this method is here to facilitate MultiCall transactions.
  function depositWithoutTransfer(
    bool isReserveAssetDeposit_,
    ISafetyModule safetyModule_,
    uint16 poolId_,
    uint256 assetAmount_,
    address receiver_,
    uint256 minSharesReceived_ // The minimum amount of shares the user expects to receive.
  ) public payable returns (uint256 depositTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositTokenAmount_ = isReserveAssetDeposit_
      ? safetyModule_.depositReserveAssetsWithoutTransfer(poolId_, assetAmount_, receiver_)
      : safetyModule_.depositRewardAssetsWithoutTransfer(poolId_, assetAmount_, receiver_);
    if (depositTokenAmount_ < minSharesReceived_) revert SlippageExceeded();
  }

  /// @notice Stakes assets into the `safetyModule_`. Mints `stakeTokenAmount_` to `receiver_` by staking exactly
  /// `assets_` of the reserve pool's underlying tokens into the `safetyModule_`, and reverts if less than
  ///`minSharesReceived_` are minted. The specified amount of assets are transferred from the caller to the Safety
  /// Module.
  function stake(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 minSharesReceived_ // The minimum amount of shares the user expects to receive.
  ) external payable returns (uint256 stakeTokenAmount_) {
    // Caller must first approve this router to spend the set's asset.
    (,,,,,, IERC20 asset_,,,) = safetyModule_.reservePools(reservePoolId_);
    asset_.safeTransferFrom(msg.sender, address(safetyModule_), reserveAssetAmount_);

    stakeTokenAmount_ =
      stakeWithoutTransfer(safetyModule_, reservePoolId_, reserveAssetAmount_, receiver_, minSharesReceived_);
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
    uint256 minSharesReceived_ // The minimum amount of shares the user expects to receive.
  ) public payable returns (uint256 stakeTokenAmount_) {
    _assertAddressNotZero(receiver_);
    stakeTokenAmount_ = safetyModule_.stakeWithoutTransfer(reservePoolId_, reserveAssetAmount_, receiver_);
    if (stakeTokenAmount_ < minSharesReceived_) revert SlippageExceeded();
  }

  /// @notice Calls the connector to wrap the base asset, send the wrapped assets to `safetyModule_`, and then
  /// `depositWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `baseAssetAmount_` of the base asset.
  function wrapBaseAssetViaConnectorAndDeposit(
    bool isReserveAssetDeposit_,
    IConnector connector_,
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 baseAssetAmount_,
    address receiver_,
    uint256 minSharesReceived_ // The minimum amount of shares the user expects to receive.
  ) external payable returns (uint256 depositTokenAmount_) {
    connector_.baseAsset().safeTransferFrom(msg.sender, address(connector_), baseAssetAmount_);
    uint256 depositAssetAmount_ = connector_.wrapBaseAsset(address(safetyModule_), baseAssetAmount_);
    depositTokenAmount_ = depositWithoutTransfer(
      isReserveAssetDeposit_, safetyModule_, reservePoolId_, depositAssetAmount_, receiver_, minSharesReceived_
    );
  }

  /// @notice Calls the connector to wrap the base asset, send the wrapped assets to `set_`, and then
  /// `stakeWithoutTransfer`.
  /// @dev This will revert if the router is not approved for at least `baseAssetAmount_` of the base asset.
  function wrapBaseAssetViaConnectorAndStake(
    IConnector connector_,
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 baseAssetAmount_,
    address receiver_,
    uint256 minSharesReceived_ // The minimum amount of shares the user expects to receive.
  ) external payable returns (uint256 depositTokenAmount_) {
    connector_.baseAsset().safeTransferFrom(msg.sender, address(connector_), baseAssetAmount_);
    uint256 depositAssetAmount_ = connector_.wrapBaseAsset(address(safetyModule_), baseAssetAmount_);
    depositTokenAmount_ =
      stakeWithoutTransfer(safetyModule_, reservePoolId_, depositAssetAmount_, receiver_, minSharesReceived_);
  }

  // --------------------------------------
  // -------- Withdrawal / Unstake --------
  // --------------------------------------

  /// @notice Removes assets from a `safetyModule_` reserve pool. Burns `depositTokenAmount_` from owner and sends
  /// exactly
  /// `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`, and reverts if more than
  /// `maxSharesBurned_` are burned. If the safety module is PAUSED, withdrawal can be completed immediately, otherwise
  /// this queues a redemption which can be completed once sufficient delay has elapsed.
  function withdrawReservePoolAssets(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 maxSharesBurned_
  ) external payable returns (uint64 redemptionId_, uint256 depositTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositTokenAmount_ = safetyModule_.convertToReserveDepositTokenAmount(reservePoolId_, reserveAssetAmount_);
    if (depositTokenAmount_ > maxSharesBurned_) revert SlippageExceeded();
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    (redemptionId_,) = safetyModule_.redeem(reservePoolId_, depositTokenAmount_, receiver_, msg.sender);
  }

  /// @notice Removes assets from a `safetyModule_` reserve pool. Burns `depositTokenAmount_` from owner and sends
  /// exactly
  /// `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`, and reverts if less than
  /// `minAssetsReceived_` would be received. If the safety module is PAUSED, withdrawal can be completed immediately,
  ///  otherwise this queues a redemption which can be completed once sufficient delay has elapsed.
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
  /// more than  `maxSharesBurned_` are burned. Withdrawal of assets from undripped reward pools can be completed
  /// instantly.
  function withdrawRewardPoolAssets(
    ISafetyModule safetyModule_,
    uint16 rewardPoolId_,
    uint256 rewardAssetAmount_,
    address receiver_,
    uint256 maxSharesBurned_
  ) external payable returns (uint256 depositTokenAmount_) {
    _assertAddressNotZero(receiver_);
    depositTokenAmount_ = safetyModule_.convertToRewardDepositTokenAmount(rewardPoolId_, rewardAssetAmount_);
    if (depositTokenAmount_ > maxSharesBurned_) revert SlippageExceeded();
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    safetyModule_.redeemUndrippedRewards(rewardPoolId_, depositTokenAmount_, receiver_, msg.sender);
  }

  // @notice Removes assets from a `safetyModule_` undripped reward pool. Burns `depositTokenAmount_` from owner and
  /// sends exactly `rewardAssetAmount_` of the reward pool's underlying tokens to the `receiver_`, and reverts if
  /// less than  `minAssetsReceived_` would be received. Withdrawal of assets from undripped reward pools can be
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

  /// @notice Unstakes exactly `stakeTokenAmount` from a `safetyModule_` reserve pool. Burns `depositTokenAmount_` from
  /// owner and sends exactly `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`, and
  /// reverts
  /// if less than `minAssetsReceived_` of the reserve pool asset would be received. If the safety module is PAUSED,
  /// unstake
  /// can be completed immediately, otherwise this queues a redemption which can be completed once sufficient delay has
  /// elapsed. This also claims any outstanding rewards that the user is entitled to.
  function unstake(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 stakeTokenAmount_,
    address receiver_,
    uint256 minAssetsReceived_
  ) external payable returns (uint64 redemptionId_, uint256 reserveAssetAmount_) {
    _assertAddressNotZero(receiver_);
    // Caller must first approve the CozyRouter to spend the stake tokens.
    (redemptionId_, reserveAssetAmount_) =
      safetyModule_.unstake(reservePoolId_, stakeTokenAmount_, receiver_, msg.sender);
    if (reserveAssetAmount_ < minAssetsReceived_) revert SlippageExceeded();
  }

  /// @notice Unstakes exactly `reserveAssetAmount_` from a `safetyModule_` reserve pool. Burns `depositTokenAmount_`
  /// from
  /// owner and sends exactly `reserveAssetAmount_` of the reserve pool's underlying tokens to the `receiver_`, and
  /// reverts
  /// if more than `maxSharesBurned_` are burned. If the safety module is PAUSED, unstake can be completed immediately,
  /// otherwise this queues a redemption which can be completed once sufficient delay has elapsed. This also claims any
  /// outstanding rewards that the user is entitled to.
  function unstakeAssetAmount(
    ISafetyModule safetyModule_,
    uint16 reservePoolId_,
    uint256 reserveAssetAmount_,
    address receiver_,
    uint256 maxSharesBurned_
  ) external payable returns (uint64 redemptionId_, uint256 stkTokenAmount_) {
    _assertAddressNotZero(receiver_);
    stkTokenAmount_ = safetyModule_.convertToStakeTokenAmount(reservePoolId_, reserveAssetAmount_);
    if (stkTokenAmount_ > maxSharesBurned_) revert SlippageExceeded();
    // Caller must first approve the CozyRouter to spend the deposit tokens.
    (redemptionId_,) = safetyModule_.unstake(reservePoolId_, stkTokenAmount_, receiver_, msg.sender);
  }

  // /// @notice Completes the redemption corresponding to `id_` in `safetyModule_`.
  function completeWithdraw(ISafetyModule safetyModule_, uint64 id_) external payable {
    safetyModule_.completeRedemption(id_);
  }

  /// @notice Completes the redemption corresponding to `id_` in `safetyModule_`.
  function completeRedeem(ISafetyModule safetyModule_, uint64 id_) external payable {
    safetyModule_.completeRedemption(id_);
  }

  /// @notice Calls the connector to unwrap the wrapped assets and transfer base assets back to `receiver_`.
  /// @dev This assumes that all assets that need to be withdrawn are sitting in the connector. It expects the
  /// integrator has called `CozyRouter.withdraw/redeem` with `receiver == address(connector_)`.
  /// @dev This function should be `aggregate` called with `completeWithdraw/Redeem`, or `withdraw/redeem`. It can
  /// be called with `withdraw/redeem` in the case that instant withdrawals can occur due to the safety module being
  /// PAUSED.
  function unwrapWrappedAssetViaConnectorForWithdraw(IConnector connector_, address receiver_) external payable {
    uint256 assets_ = connector_.balanceOf(address(connector_));
    if (assets_ > 0) connector_.unwrapWrappedAsset(receiver_, assets_);
  }

  /// @notice Calls the connector to unwrap the wrapped assets and transfer base assets back to `receiver_`.
  /// @dev This assumes that `assets_` amount of the wrapped assets are sitting in the connector. So, it expects
  /// the integrator has called a safety module operation such as `CozyRouter.withdraw` with `receiver ==
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

  // -------------------------
  // -------- Helpers --------
  // -------------------------

  function _assertIsValidSafetyModule(address safetyModule_) internal view {
    if (!manager.isSafetyModule(ISafetyModule(safetyModule_))) revert InvalidAddress();
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }
}
