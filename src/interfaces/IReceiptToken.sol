// SPDX-License-Identifier: Unlicensed
pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {ISafetyModule} from "./ISafetyModule.sol";

interface IReceiptToken is IERC20 {
  /// @notice Replaces the constructor for minimal proxies.
  /// @param safetyModule_ The safety module for this ReceiptToken.
  /// @param _name The name of the token.
  /// @param _symbol The symbol of the token.
  /// @param decimals_ The decimal places of the token.
  function initialize(ISafetyModule safetyModule_, string memory _name, string memory _symbol, uint8 decimals_)
    external;

  /// @notice Mints `amount_` of tokens to `to_`.
  function mint(address to_, uint256 amount_) external;

  /// @notice Burns `amount_` of tokens from `from`_.
  function burn(address caller_, address from_, uint256 amount_) external;

  /// @notice Address of this token's safety module.
  function safetyModule() external view returns (ISafetyModule);
}
