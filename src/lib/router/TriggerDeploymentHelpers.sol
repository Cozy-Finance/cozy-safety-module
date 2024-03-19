// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {SafeERC20} from "cozy-safety-module-shared/lib/SafeERC20.sol";
import {TriggerMetadata} from "../structs/Trigger.sol";
import {ITrigger} from "../../interfaces/ITrigger.sol";
import {IChainlinkTriggerFactory} from "../../interfaces/IChainlinkTriggerFactory.sol";
import {IOwnableTriggerFactory} from "../../interfaces/IOwnableTriggerFactory.sol";
import {IUMATriggerFactory} from "../../interfaces/IUMATriggerFactory.sol";
import {CozyRouterCommon} from "./CozyRouterCommon.sol";
import {TriggerFactories} from "../structs/TriggerFactories.sol";

abstract contract TriggerDeploymentHelpers is CozyRouterCommon {
  using SafeERC20 for IERC20;

  IChainlinkTriggerFactory public immutable chainlinkTriggerFactory;

  IOwnableTriggerFactory public immutable ownableTriggerFactory;

  IUMATriggerFactory public immutable umaTriggerFactory;

  constructor(TriggerFactories memory triggerFactories_) {
    chainlinkTriggerFactory = triggerFactories_.chainlinkTriggerFactory;
    ownableTriggerFactory = triggerFactories_.ownableTriggerFactory;
    umaTriggerFactory = triggerFactories_.umaTriggerFactory;
  }

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
}
