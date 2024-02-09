// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {ICozySafetyModuleManager} from "./ICozySafetyModuleManager.sol";
import {ITrigger} from "./ITrigger.sol";
import {TriggerMetadata} from "../lib/structs/Trigger.sol";

/**
 * @notice Deploys Chainlink triggers that ensure two oracles stay within the given price
 * tolerance. It also supports creating a fixed price oracle to use as the truth oracle, useful
 * for e.g. ensuring stablecoins maintain their peg.
 */
interface IChainlinkTriggerFactory {
  /// @notice Call this function to determine the address at which a trigger
  /// with the supplied configuration would be deployed.
  /// @param truthOracle_ The address of the desired truthOracle for the trigger.
  /// @param trackingOracle_ The address of the desired trackingOracle for the trigger.
  /// @param priceTolerance_ The priceTolerance that the deployed trigger would
  /// have. See ChainlinkTrigger.priceTolerance() for more information.
  /// @param truthFrequencyTolerance_ The frequency tolerance that the deployed trigger would
  /// have for the truth oracle. See ChainlinkTrigger.truthFrequencyTolerance() for more information.
  /// @param trackingFrequencyTolerance_ The frequency tolerance that the deployed trigger would
  /// have for the tracking oracle. See ChainlinkTrigger.trackingFrequencyTolerance() for more information.
  /// @param triggerCount_ The zero-indexed ordinal of the trigger with respect to its
  /// configuration, e.g. if this were to be the fifth trigger deployed with
  /// these configs, then _triggerCount should be 4.
  function computeTriggerAddress(
    AggregatorV3Interface truthOracle_,
    AggregatorV3Interface trackingOracle_,
    uint256 priceTolerance_,
    uint256 truthFrequencyTolerance_,
    uint256 trackingFrequencyTolerance_,
    uint256 triggerCount_
  ) external view returns (address address_);

  /// @notice Call this function to compute the address that a
  /// FixedPriceAggregator contract would be deployed to with the provided args.
  /// @param _price The fixed price, in the decimals indicated, returned by the deployed oracle.
  /// @param _decimals The number of decimals of the fixed price.
  function computeFixedPriceAggregatorAddress(int256 _price, uint8 _decimals) external view returns (address);

  /// @notice Call this function to deploy a ChainlinkTrigger.
  /// @param truthOracle_ The address of the desired truthOracle for the trigger.
  /// @param trackingOracle_ The address of the desired trackingOracle for the trigger.
  /// @param priceTolerance_ The priceTolerance that the deployed trigger will
  /// have. See ChainlinkTrigger.priceTolerance() for more information.
  /// @param truthFrequencyTolerance_ The frequency tolerance that the deployed trigger will
  /// have for the truth oracle. See ChainlinkTrigger.truthFrequencyTolerance() for more information.
  /// @param trackingFrequencyTolerance_ The frequency tolerance that the deployed trigger will
  /// have for the tracking oracle. See ChainlinkTrigger.trackingFrequencyTolerance() for more information.
  /// @param metadata_ See TriggerMetadata for more info.
  function deployTrigger(
    AggregatorV3Interface truthOracle_,
    AggregatorV3Interface trackingOracle_,
    uint256 priceTolerance_,
    uint256 truthFrequencyTolerance_,
    uint256 trackingFrequencyTolerance_,
    TriggerMetadata memory metadata_
  ) external returns (ITrigger trigger_);

  /// @notice Call this function to deploy a ChainlinkTrigger with a
  /// FixedPriceAggregator as its truthOracle. This is useful if you were
  /// building a market in which you wanted to track whether or not a stablecoin
  /// asset had become depegged.
  /// @param _price The fixed price, or peg, with which to compare the trackingOracle price.
  /// @param _decimals The number of decimals of the fixed price. This should
  /// match the number of decimals used by the desired _trackingOracle.
  /// @param _trackingOracle The address of the desired trackingOracle for the trigger.
  /// @param _priceTolerance The priceTolerance that the deployed trigger will
  /// have. See ChainlinkTrigger.priceTolerance() for more information.
  /// @param _frequencyTolerance The frequency tolerance that the deployed trigger will
  /// have for the tracking oracle. See ChainlinkTrigger.trackingFrequencyTolerance() for more information.
  function deployTrigger(
    int256 _price,
    uint8 _decimals,
    AggregatorV3Interface _trackingOracle,
    uint256 _priceTolerance,
    uint256 _frequencyTolerance,
    TriggerMetadata memory _metadata
  ) external returns (ITrigger _trigger);

  /// @notice Call this function to determine the identifier of the supplied trigger
  /// configuration. This identifier is used both to track the number of
  /// triggers deployed with this configuration (see `triggerCount`) and is
  /// emitted at the time triggers with that configuration are deployed.
  /// @param truthOracle_ The address of the desired truthOracle for the trigger.
  /// @param trackingOracle_ The address of the desired trackingOracle for the trigger.
  /// @param priceTolerance_ The priceTolerance that the deployed trigger will
  /// have. See ChainlinkTrigger.priceTolerance() for more information.
  /// @param truthFrequencyTolerance_ The frequency tolerance that the deployed trigger will
  /// have for the truth oracle. See ChainlinkTrigger.truthFrequencyTolerance() for more information.
  /// @param trackingFrequencyTolerance_ The frequency tolerance that the deployed trigger will
  /// have for the tracking oracle. See ChainlinkTrigger.trackingFrequencyTolerance() for more information.
  function triggerConfigId(
    AggregatorV3Interface truthOracle_,
    AggregatorV3Interface trackingOracle_,
    uint256 priceTolerance_,
    uint256 truthFrequencyTolerance_,
    uint256 trackingFrequencyTolerance_
  ) external view returns (bytes32);

  /// @notice Maps the triggerConfigId to the number of triggers created with those configs.
  function triggerCount(bytes32) external view returns (uint256);
}
