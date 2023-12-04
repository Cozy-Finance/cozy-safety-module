// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {ISafetyModule} from "./ISafetyModule.sol";
import {IStkToken} from "./IStkToken.sol";

interface IStkTokenFactory {
  /// @dev Emitted when a new StkToken is deployed.
  event StkTokenDeployed(
    IStkToken stkToken, ISafetyModule indexed safetyModule, uint8 indexed reservePoolId, uint8 decimals_
  );

  /// @notice Creates a new StkToken contract with the given number of `decimals_`. The StkToken's safety module is
  /// identified by the caller address. The reserve pool id of the StkToken in the safety module is used to generate
  /// a unique salt for deploy.
  function deployStkToken(uint8 reservePoolId_, uint8 decimals_) external returns (IStkToken stkToken_);
}
