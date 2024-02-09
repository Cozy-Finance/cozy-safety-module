// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {IReceiptToken} from "cozy-safety-module-shared/interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "cozy-safety-module-shared/interfaces/IReceiptTokenFactory.sol";
import {SafetyModuleState} from "../lib/SafetyModuleStates.sol";
import {AssetPool} from "../lib/structs/Pools.sol";
import {UpdateConfigsCalldataParams} from "../lib/structs/Configs.sol";
import {ReservePool} from "../lib/structs/Pools.sol";
import {RedemptionPreview} from "../lib/structs/Redemptions.sol";
import {Slash} from "../lib/structs/Slash.sol";
import {Trigger} from "../lib/structs/Trigger.sol";
import {IDripModel} from "./IDripModel.sol";
import {ICozySafetyModuleManager} from "./ICozySafetyModuleManager.sol";
import {ITrigger} from "./ITrigger.sol";

interface ISafetyModule {
  /// @notice Replaces the constructor for minimal proxies.
  function initialize(address owner_, address pauser_, UpdateConfigsCalldataParams calldata configs_) external;

  function assetPools(IERC20 asset_) external view returns (AssetPool memory assetPool_);

  function completeRedemption(uint64 redemptionId_) external returns (uint256 assetAmount_);

  function convertToReceiptTokenAmount(uint256 reservePoolId_, uint256 reserveAssetAmount_)
    external
    view
    returns (uint256 depositReceiptTokenAmount_);

  function convertToReserveAssetAmount(uint256 reservePoolId_, uint256 depositReceiptTokenAmount_)
    external
    view
    returns (uint256 reserveAssetAmount_);

  /// @notice Address of the Cozy safety module protocol manager.
  function cozySafetyModuleManager() external view returns (ICozySafetyModuleManager);

  function delays()
    external
    view
    returns (
      // Duration between when safety module updates are queued and when they can be executed.
      uint64 configUpdateDelay,
      // Defines how long the owner has to execute a configuration change, once it can be executed.
      uint64 configUpdateGracePeriod,
      // Delay for two-step withdraw process (for deposited assets).
      uint64 withdrawDelay
    );

  /// @dev Expects `from_` to have approved this SafetyModule for `reserveAssetAmount_` of
  /// `reservePools[reservePoolId_].asset` so it can `transferFrom`
  function depositReserveAssets(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_, address from_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(uint16 reservePoolId_, uint256 reserveAssetAmount_, address receiver_)
    external
    returns (uint256 depositReceiptTokenAmount_);

  function dripFees() external;

  function dripFeesFromReservePool(uint16 reservePoolId_) external;

  /// @notice The number of slashes that must occur before the safety module can be active.
  /// @dev This value is incremented when a trigger occurs, and decremented when a slash from a trigger assigned payout
  /// handler occurs. When this value is non-zero, the safety module is triggered (or paused).
  function numPendingSlashes() external returns (uint16);

  /// @dev Maps payout handlers to the number of times they are allowed to call slash at the current block.
  function payoutHandlerNumPendingSlashes(address payoutHandler_) external returns (uint256);

  function slash(Slash[] memory slashes_, address receiver_) external;

  /// @notice Returns the address of the SafetyModule owner.
  function owner() external view returns (address);

  /// @notice Pauses the safety module.
  function pause() external;

  /// @notice Address of the SafetyModule pauser.
  function pauser() external view returns (address);

  /// @notice Allows an on-chain or off-chain user to simulate the effects of their queued redemption (i.e. view the
  /// number of reserve assets received) at the current block, given current on-chain conditions.
  function previewQueuedRedemption(uint64 redemptionId_)
    external
    view
    returns (RedemptionPreview memory redemptionPreview_);

  /// @notice Address of the Cozy protocol ReceiptTokenFactory.
  function receiptTokenFactory() external view returns (IReceiptTokenFactory);

  /// @notice Redeems by burning `depositReceiptTokenAmount_` of `reservePoolId_` reserve pool deposit tokens and
  /// sending
  /// `reserveAssetAmount_` of `reservePoolId_` reserve pool assets to `receiver_`.
  /// @dev Assumes that user has approved the SafetyModule to spend its deposit tokens.
  function redeem(uint16 reservePoolId_, uint256 depositReceiptTokenAmount_, address receiver_, address owner_)
    external
    returns (uint64 redemptionId_, uint256 reserveAssetAmount_);

  /// @notice Retrieve accounting and metadata about reserve pools.
  function reservePools(uint256 id_) external view returns (ReservePool memory reservePool_);

  /// @notice The state of this SafetyModule.
  function safetyModuleState() external view returns (SafetyModuleState);

  function trigger(ITrigger trigger_) external;

  function triggerData(ITrigger trigger_) external view returns (Trigger memory);

  /// @notice Unpauses the safety module.
  function unpause() external;

  // @notice Claims the safety module's fees.
  function claimFees(address owner_) external;
}
