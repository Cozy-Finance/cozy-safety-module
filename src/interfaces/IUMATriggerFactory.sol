// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {ITrigger} from "./ITrigger.sol";
import {TriggerMetadata} from "../lib/structs/Trigger.sol";

/**
 * @notice This is a utility contract to make it easy to deploy UMATriggers for
 * the Cozy protocol.
 * @dev Be sure to approve the trigger to spend the rewardAmount before calling
 * `deployTrigger`, otherwise the latter will revert. Funds need to be available
 * to the created trigger within its constructor so that it can submit its query
 * to the UMA oracle.
 */
interface IUMATriggerFactory {
  /// @notice Call this function to determine the address at which a trigger
  /// with the supplied configuration would be deployed. See `deployTrigger` for
  /// more information on parameters and their meaning.
  function computeTriggerAddress(
    string memory query_,
    IERC20 rewardToken_,
    uint256 rewardAmount_,
    address refundRecipient_,
    uint256 bondAmount_,
    uint256 proposalDisputeWindow_,
    uint256 triggerCount_
  ) external view returns (address address_);

  /// @notice Call this function to deploy a UMATrigger.
  /// @param query_ The query that the trigger will send to the UMA Optimistic
  /// Oracle for evaluation.
  /// @param rewardToken_ The token used to pay the reward to users that propose
  /// answers to the query.
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
  function deployTrigger(
    string memory query_,
    IERC20 rewardToken_,
    uint256 rewardAmount_,
    address refundRecipient_,
    uint256 bondAmount_,
    uint256 proposalDisputeWindow_,
    TriggerMetadata memory metadata_
  ) external returns (ITrigger trigger_);

  /// @notice Call this function to determine the identifier of the supplied
  /// trigger configuration. This identifier is used both to track the number of
  /// triggers deployed with this configuration (see `triggerCount`) and is
  /// emitted as a part of the TriggerDeployed event when triggers are deployed.
  /// @dev This function takes the rewardAmount as an input despite it not being
  /// an argument of the UMATrigger constructor nor it being held in storage by
  /// the trigger. This is done because the rewardAmount is something that
  /// deployers could reasonably differ on. Deployer A might deploy a trigger
  /// that is identical to what Deployer B wants in every way except the amount
  /// of rewardToken that is being offered, and it would still be reasonable for
  /// Deployer B to not want to re-use A's trigger for his own markets.
  function triggerConfigId(
    string memory query_,
    IERC20 rewardToken_,
    uint256 rewardAmount_,
    address refundRecipient_,
    uint256 bondAmount_,
    uint256 proposalDisputeWindow_
  ) external view returns (bytes32);

  /// @notice Maps the triggerConfigId to the number of triggers created with those configs.
  function triggerCount(bytes32) external view returns (uint256);
}
