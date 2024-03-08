// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IDripModel} from "cozy-safety-module-shared/interfaces/IDripModel.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {SafetyModuleState} from "../lib/SafetyModuleStates.sol";
import {AssetPool} from "../lib/structs/Pools.sol";
import {UpdateConfigsCalldataParams, ConfigUpdateMetadata} from "../lib/structs/Configs.sol";
import {ReservePool} from "../lib/structs/Pools.sol";
import {RedemptionPreview} from "../lib/structs/Redemptions.sol";
import {Slash} from "../lib/structs/Slash.sol";
import {Trigger} from "../lib/structs/Trigger.sol";
import {Delays} from "../lib/structs/Delays.sol";
import {ICozySafetyModuleManager} from "./ICozySafetyModuleManager.sol";
import {ITrigger} from "./ITrigger.sol";

interface ISafetyModule {
  /// @notice The asset pools configured for this SafetyModule.
  /// @dev Used for doing aggregate accounting of reserve assets.
  function assetPools(IERC20 asset_) external view returns (AssetPool memory assetPool_);

  /// @notice Claims any accrued fees to the CozySafetyModuleManager owner.
  /// @dev Validation is handled in the CozySafetyModuleManager, which is the only account authorized to call this
  /// method.
  /// @param owner_ The address to transfer the fees to.
  /// @param dripModel_ The drip model to use for calculating fee drip.
  function claimFees(address owner_, IDripModel dripModel_) external;

  /// @notice Completes the redemption request for the specified redemption ID.
  /// @param redemptionId_ The ID of the redemption to complete.
  function completeRedemption(uint64 redemptionId_) external returns (uint256 assetAmount_);

  /// @notice Returns the receipt token amount for a given amount of reserve assets after taking into account
  /// any pending fee drip.
  /// @param reservePoolId_ The ID of the reserve pool to convert the reserve asset amount for.
  /// @param reserveAssetAmount_ The amount of reserve assets to convert to deposit receipt tokens.
  function convertToReceiptTokenAmount(uint8 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 depositReceiptTokenAmount_);

  /// @notice Returns the reserve asset amount for a given amount of deposit receipt tokens after taking into account
  /// any
  /// pending fee drip.
  /// @param reservePoolId_ The ID of the reserve pool to convert the deposit receipt token amount for.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to convert to reserve assets.
  function convertToReserveAssetAmount(uint8 reservePoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_);

  /// @notice Address of the Cozy Safety Module protocol manager contract.
  function cozySafetyModuleManager() external view returns (ICozySafetyModuleManager);

  /// @notice Config, withdrawal and unstake delays.
  function delays() external view returns (Delays memory delays_);

  /// @notice Deposits reserve assets into the SafetyModule and mints deposit receipt tokens.
  /// @dev Expects `msg.sender` to have approved this SafetyModule for `reserveAssetAmount_` of
  /// `reservePools[reservePoolId_].asset` so it can `transferFrom` the assets to this SafetyModule.
  /// @param reservePoolId_ The ID of the reserve pool to deposit assets into.
  /// @param reserveAssetAmount_ The amount of reserve assets to deposit.
  /// @param receiver_ The address to receive the deposit receipt tokens.
  function depositReserveAssets(uint8 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  /// @notice Deposits reserve assets into the SafetyModule and mints deposit receipt tokens.
  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  /// @param reservePoolId_ The ID of the reserve pool to deposit assets into.
  /// @param reserveAssetAmount_ The amount of reserve assets to deposit.
  /// @param receiver_ The address to receive the deposit receipt tokens.
  function depositReserveAssetsWithoutTransfer(uint8 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  /// @notice Updates the fee amounts for each reserve pool by applying a drip factor on the deposit amounts.
  function dripFees() external;

  /// @notice Drips fees from a specific reserve pool.
  /// @param reservePoolId_ The ID of the reserve pool to drip fees from.
  function dripFeesFromReservePool(uint8 reservePoolId_) external;

  /// @notice Execute queued updates to the safety module configs.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function finalizeUpdateConfigs(UpdateConfigsCalldataParams calldata configUpdates_) external;

  /// @notice Returns the maximum amount of assets that can be slashed from the specified reserve pool.
  /// @param reservePoolId_ The ID of the reserve pool to get the maximum slashable amount for.
  function getMaxSlashableReservePoolAmount(uint8 reservePoolId_)
    external
    view
    returns (uint256 slashableReservePoolAmount_);

  /// @notice Initializes the SafetyModule with the specified parameters.
  /// @dev Replaces the constructor for minimal proxies.
  /// @param owner_ The SafetyModule owner.
  /// @param pauser_ The SafetyModule pauser.
  /// @param configs_ The SafetyModule configuration parameters. These configs must obey requirements described in
  /// `Configurator.updateConfigs`.
  function initialize(address owner_, address pauser_, UpdateConfigsCalldataParams calldata configs_) external;

  /// @notice Metadata about the most recently queued configuration update.
  function lastConfigUpdate() external view returns (ConfigUpdateMetadata memory);

  /// @notice The number of slashes that must occur before the SafetyModule can be active.
  /// @dev This value is incremented when a trigger occurs, and decremented when a slash from a trigger assigned payout
  /// handler occurs. When this value is non-zero, the SafetyModule is triggered (or paused).
  function numPendingSlashes() external returns (uint16);

  /// @notice Returns the address of the SafetyModule owner.
  function owner() external view returns (address);

  /// @notice Pauses the SafetyModule if it's a valid state transition.
  /// @dev Only the owner or pauser can call this function.
  function pause() external;

  /// @notice Address of the SafetyModule pauser.
  function pauser() external view returns (address);

  /// @notice Maps payout handlers to the number of slashes they are currently entitled to.
  /// @dev The number of slashes that a payout handler is entitled to is increased each time a trigger triggers this
  /// SafetyModule, if the payout handler is assigned to the trigger. The number of slashes is decreased each time a
  /// slash from the trigger assigned payout handler occurs.
  function payoutHandlerNumPendingSlashes(address payoutHandler_) external returns (uint256);

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their queued redemption (i.e. view the
  /// number of reserve assets received) at the current block, given current on-chain conditions.
  /// @param redemptionId_ The ID of the redemption to preview.
  function previewQueuedRedemption(uint64 redemptionId_)
    external
    view
    returns (RedemptionPreview memory redemptionPreview_);

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their redemption (i.e. view the number
  /// of reserve assets received) at the current block, given current on-chain conditions.
  /// @param reservePoolId_ The ID of the reserve pool to redeem from.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to redeem.
  function previewRedemption(uint8 reservePoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_);

  /// @notice Address of the Cozy Safety Module protocol ReceiptTokenFactory.
  function receiptTokenFactory() external view returns (IReceiptTokenFactory);

  /// @notice Queues a redemption by burning `depositReceiptTokenAmount_` of `reservePoolId_` reserve pool deposit
  /// tokens.
  /// When the redemption is completed, `reserveAssetAmount_` of `reservePoolId_` reserve pool assets will be sent
  /// to `receiver_` if the reserve pool's assets are not slashed. If the SafetyModule is paused, the redemption
  /// will be completed instantly.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  /// @param reservePoolId_ The ID of the reserve pool to redeem from.
  /// @param depositReceiptTokenAmount_ The amount of deposit receipt tokens to redeem.
  /// @param receiver_ The address to receive the reserve assets.
  /// @param owner_ The address that owns the deposit receipt tokens.
  function redeem(uint8 reservePoolId_, uint256 depositReceiptTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_);

  /// @notice Accounting and metadata for reserve pools configured for this SafetyModule.
  /// @dev Reserve pool index in this array is its ID
  function reservePools(uint256 id_) external view returns (ReservePool memory reservePool_);

  /// @notice The state of this SafetyModule.
  function safetyModuleState() external view returns (SafetyModuleState);

  /// @notice Slashes the reserve pools, sends the assets to the receiver, and returns the safety module to the ACTIVE
  /// state if there are no payout handlers that still need to slash assets. Note: Payout handlers can call this
  /// function once for each triggered trigger that has it assigned as its payout handler.
  /// @param slashes_ The slashes to execute.
  /// @param receiver_ The address to receive the slashed assets.
  function slash(Slash[] memory slashes_, address receiver_) external;

  /// @notice Triggers the SafetyModule by referencing one of the triggers configured for this SafetyModule.
  /// @param trigger_ The trigger to reference when triggering the SafetyModule.
  function trigger(ITrigger trigger_) external;

  /// @notice Returns trigger related data.
  /// @param trigger_ The trigger to get data for.
  function triggerData(ITrigger trigger_) external view returns (Trigger memory);

  /// @notice Unpauses the SafetyModule.
  function unpause() external;

  /// @notice Signal an update to the safety module configs. Existing queued updates are overwritten.
  /// @param configUpdates_ The new configs. Includes:
  /// - reservePoolConfigs: The array of new reserve pool configs, sorted by associated ID. The array may also
  /// include config for new reserve pools.
  /// - triggerConfigUpdates: The array of trigger config updates. It only needs to include config for updates to
  /// existing triggers or new triggers.
  /// - delaysConfig: The new delays config.
  function updateConfigs(UpdateConfigsCalldataParams calldata configUpdates_) external;
}
