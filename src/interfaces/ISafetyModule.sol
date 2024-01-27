// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {AssetPool} from "../lib/structs/Pools.sol";
import {UpdateConfigsCalldataParams} from "../lib/structs/Configs.sol";
import {RedemptionPreview} from "../lib/structs/Redemptions.sol";
import {ClaimableRewardsData, PreviewClaimableRewards} from "../lib/structs/Rewards.sol";
import {Slash} from "../lib/structs/Slash.sol";
import {Trigger} from "../lib/structs/Trigger.sol";
import {SafetyModuleState} from "../lib/SafetyModuleStates.sol";
import {IDripModel} from "./IDripModel.sol";
import {IManager} from "./IManager.sol";
import {IReceiptToken} from "./IReceiptToken.sol";
import {IReceiptTokenFactory} from "./IReceiptTokenFactory.sol";
import {ITrigger} from "./ITrigger.sol";
import {RewardPoolConfig, ReservePoolConfig} from "../lib/structs/Configs.sol";

interface ISafetyModule {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(address owner_, address pauser_, UpdateConfigsCalldataParams calldata configs_) external;

  function assetPools(IERC20 asset_) external view returns (AssetPool memory assetPool_);

  function claimableRewards(uint16 reservePoolId_, uint16 rewardPoolId_)
    external
    view
    returns (ClaimableRewardsData memory claimableRewardsData_);

  function claimRewards(uint16 reservePoolId_, address receiver_) external;

  function completeRedemption(uint64 redemptionId_) external returns (uint256 assetAmount_);

  function completeUnstake(uint64 redemptionId_) external returns (uint256 reserveAssetAmount_);

  function convertToReserveDepositTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 depositTokenAmount_);

  function convertToRewardDepositTokenAmount(uint256 rewardPoolId_, uint256 rewardAssetAmount_)
    external
    view
    returns (uint256 depositTokenAmount_);

  function convertToStakeTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 stakeTokenAmount_);

  function convertStakeTokenToReserveAssetAmount(uint256 reservePoolId_, uint256 stakeTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_);

  function convertReserveDepositTokenToReserveAssetAmount(uint256 reservePoolId_, uint256 depositTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_);

  function convertRewardDepositTokenToRewardAssetAmount(uint256 rewardPoolId_, uint256 depositTokenAmount_)
    external
    view
    returns (uint256 rewardAssetAmount_);

  /// @notice Address of the Cozy protocol manager.
  function cozyManager() external view returns (IManager);

  function delays()
    external
    view
    returns (
      // Duration between when safety module updates are queued and when they can be executed.
      uint64 configUpdateDelay,
      // Defines how long the owner has to execute a configuration change, once it can be executed.
      uint64 configUpdateGracePeriod,
      // Delay for two-step unstake process (for staked assets).
      uint64 unstakeDelay,
      // Delay for two-step withdraw process (for deposited assets).
      uint64 withdrawDelay
    );

  /// @dev Expects `from_` to have approved this SafetyModule for `reserveAssetAmount_` of
  /// `reservePools[reservePoolId_].asset` so it can `transferFrom`
  function depositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositTokenAmount_);

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositTokenAmount_);

  function depositRewardAssets(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositTokenAmount_);

  function depositRewardAssetsWithoutTransfer(uint16 rewardPoolId_, uint256 rewardAssetAmount_, address receiver_)
    external
    returns (uint256 depositTokenAmount_);

  function dripFees() external;

  function dripFeesFromReservePool(uint16 reservePoolId_) external;

  /// @notice The number of slashes that must occur before the safety module can be active.
  /// @dev This value is incremented when a trigger occurs, and decremented when a slash from a trigger assigned payout
  /// handler occurs. When this value is non-zero, the safety module is triggered (or paused).
  function numPendingSlashes() external returns (uint16);

  /// @dev Maps payout handlers to the number of times they are allowed to call slash at the current block.
  function payoutHandlerNumPendingSlashes(address payoutHandler_) external returns (uint256);

  function slash(Slash[] memory slashes_, address receiver_) external;

  function stake(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 stkTokenAmount_);

  /// @notice Stake by minting `stkTokenAmount_` stkTokens to `receiver_`.
  /// @dev Assumes that `amount_` of reserve asset has already been transferred to this contract.
  function stakeWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 stkTokenAmount_);

  /// @notice Updates the safety module's user rewards data prior to a stkToken transfer.
  function updateUserRewardsForStkTokenTransfer(address from_, address to_) external;

  /// @notice Returns the address of the SafetyModule owner.
  function owner() external view returns (address);

  /// @notice Pauses the safety module.
  function pause() external;

  /// @notice Address of the SafetyModule pauser.
  function pauser() external view returns (address);

  function previewClaimableRewards(uint16[] calldata reservePoolIds_, address owner_)
    external
    view
    returns (PreviewClaimableRewards[] memory previewClaimableRewards_);

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their queued redemption (i.e. view the
  /// number of reserve assets received) at the current block, given current on-chain conditions.
  function previewQueuedRedemption(uint64 redemptionId_)
    external
    view
    returns (RedemptionPreview memory redemptionPreview_);

  /// @notice Address of the Cozy protocol ReceiptTokenFactory.
  function receiptTokenFactory() external view returns (IReceiptTokenFactory);

  /// @notice Redeems by burning `depositTokenAmount_` of `reservePoolId_` reserve pool deposit tokens and sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeem(uint16 reservePoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_);

  /// @notice Redeem by burning `depositTokenAmount_` of `rewardPoolId_` reward pool deposit tokens and sending
  /// `rewardAssetAmount_` of `rewardPoolId_` reward pool assets to `receiver_`. Reward pool assets can only be redeemed
  /// if they have not been dripped yet.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeemUndrippedRewards(uint16 rewardPoolId_, uint256 depositTokenAmount_, address receiver_, address owner_)
    external
    returns (uint256 rewardAssetAmount_);

  /// @notice Retrieve accounting and metadata about reserve pools.
  function reservePools(uint256 id_)
    external
    view
    returns (
      uint256 stakeAmount,
      uint256 depositAmount,
      uint256 pendingUnstakesAmount,
      uint256 pendingWithdrawalsAmount,
      uint256 feeAmount,
      /// @dev The max percentage of the stake amount that can be slashed in a SINGLE slash as a WAD. If multiple
      /// slashes
      /// occur, they compound, and the final stake amount can be less than (1 - maxSlashPercentage)% following all the
      /// slashes. The max slash percentage is only a guarantee for stakers; depositors are always at risk to be fully
      /// slashed.
      uint256 maxSlashPercentage,
      IERC20 asset,
      IReceiptToken stkToken,
      IReceiptToken depositToken,
      /// @dev The weighting of each stkToken's claim to all reward pools in terms of a ZOC. Must sum to 1.
      /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
      /// wrt totalSupply.
      uint16 rewardsPoolsWeight,
      uint128 lastFeesDripTime
    );

  /// @notice The state of this SafetyModule.
  function safetyModuleState() external view returns (SafetyModuleState);

  function trigger(ITrigger trigger_) external;

  function triggerData(ITrigger trigger_) external view returns (Trigger memory);

  /// @notice Retrieve accounting and metadata about reward pools.
  /// @dev Claimable reward pool IDs are mapped 1:1 with reward pool IDs.
  function rewardPools(uint256 id_)
    external
    view
    returns (
      uint256 amount,
      uint256 cumulativeDrippedRewards,
      uint128 lastDripTime,
      IERC20 asset,
      IDripModel dripModel,
      IReceiptToken depositToken
    );

  /// @notice Redeem by burning `stkTokenAmount_` of `reservePoolId_` reserve pool stake tokens and sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`. Also claims any outstanding rewards
  /// and sends them to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its stake tokens.
  function unstake(uint16 reservePoolId_, uint256 stkTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_);

  /// @notice Unpauses the safety module.
  function unpause() external;

  // @notice Claims the safety module's fees.
  function claimFees(address owner_) external;
}
