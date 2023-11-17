// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

/// @dev Specifying amounts to slash beforehand, triggers are binary. This is weird because:
///      - How do you specify the % amounts to slash before a trigger occurs? Potentially have to
///        update the configs often.
///          - Dependent on amount of assets in the safety module
///          - Dependent on amount lost
///          - Dependent on the mix of assets
contract SafetyModuleA {
  mapping(uint16 trigger_ => uint16 triggerConfigId_) public triggerConfigIds;

  /// @dev x triggers * n assets matrix.
  /// @dev Per asset leverage achieved by not constraining to 100% sum per col and row
  mapping(uint16 triggerConfigId_ => uint16[] slashPercentages_) public triggerConfigs;

  uint256[] public assets;
}

/// @dev Specifying amounts at time of trigger.
contract SafetyModuleB {
  uint256[] public assets;

  /// @dev slashAmounts_ maps to each asset
  function trigger(uint16[] memory slashAmounts_, bool isPercentages_) public {}
}
