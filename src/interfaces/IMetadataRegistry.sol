// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

interface IMetadataRegistry {
  struct Metadata {
    string name;
    string description;
    string logoURI;
    string extraData;
  }

  /// @notice Update metadata for a safety module. This function can be called by the CozyRouter.
  /// @param safetyModule_ The address of the safety module.
  /// @param metadata_ The new metadata for the safety module.
  /// @param caller_ The address of the CozyRouter caller.
  function updateSafetyModuleMetadata(address safetyModule_, Metadata calldata metadata_, address caller_) external;
}
