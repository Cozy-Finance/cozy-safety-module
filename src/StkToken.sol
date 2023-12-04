// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IManager} from "./interfaces/IManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {MintData} from "./lib/structs/MintData.sol";
import {LFT} from "./lib/LFT.sol";

contract StkToken is LFT {
  /// @notice Address of the Cozy protocol manager.
  IManager public immutable cozyManager;

  /// @notice Address of this token's safety module.
  ISafetyModule public safetyModule;

  /// @dev Thrown if the minimal proxy contract is already initialized.
  error Initialized();

  /// @dev Thrown when an address is invalid.
  error InvalidAddress();

  /// @dev Thrown when the caller is not authorized to perform the action.
  error Unauthorized();

  /// @param manager_ Cozy protocol Manager.
  constructor(IManager manager_) {
    if (address(manager_) == address(0)) revert InvalidAddress();
    cozyManager = manager_;
  }

  /// @notice Replaces the constructor for minimal proxies.
  /// @param safetyModule_ The safety module for this StkToken.
  /// @param decimals_ The decimal places of the token.
  function initialize(ISafetyModule safetyModule_, uint8 decimals_) external {
    // TODO: Name and symbol?
    __initLFT("Cozy Stake Token", "cozyStk", decimals_);
    safetyModule = safetyModule_;
  }

  // -------- LFT Implementation --------

  /// @notice Returns the balance of matured tokens held by `user_`.
  function balanceOfMatured(address user_) public view override returns (uint256 balance_) {
    // We read the number of total tokens they have, and subtract any un-matured protection. This is required
    // to ensure that tokens transferred to the user are counted, as they would not be in the protections array.
    balance_ = balanceOf[user_];
    // TODO: Balance of matured
  }

  /// @notice Mints `amount_` of tokens to `to_`.
  function mint(address to_, uint216 amount_) external onlySafetyModule {
    _mintTokens(to_, amount_);
  }

  function burn(address caller_, address owner_, uint216 amount_) external onlySafetyModule {
    if (caller_ != owner_) {
      uint256 allowed_ = allowance[owner_][caller_]; // Saves gas for limited approvals.
      if (allowed_ != type(uint256).max) _setAllowance(owner_, caller_, allowed_ - amount_);
    }
    _burn(owner_, amount_);
  }

  /// @notice Sets the allowance such that the `_spender` can spend `_amount` of `_owner`s tokens.
  function _setAllowance(address _owner, address _spender, uint256 _amount) internal {
    allowance[_owner][_spender] = _amount;
  }

  // -------- Modifiers --------

  /// @dev Checks that msg.sender is the set address.
  modifier onlySafetyModule() {
    if (msg.sender != address(safetyModule)) revert Unauthorized();
    _;
  }
}
