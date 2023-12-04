// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {IGovernable} from "../interfaces/IGovernable.sol";
import {Ownable} from "./Ownable.sol";

/**
 * @dev Contract module providing owner and pauser functionality, intended to be used through inheritance.
 * @dev No modifiers are provided to avoid the chance of dead code, as the child contract may
 * have more complex authentication requirements than just a modifier from this contract.
 */
abstract contract Governable is Ownable, IGovernable {
  /// @notice Contract pauser.
  address public pauser;

  /// @dev Emitted when the pauser address is updated.
  event PauserUpdated(address indexed newPauser_);

  /// @dev Initializer, replaces constructor for minimal proxies. Must be kept internal and it's up
  /// to the caller to make sure this can only be called once.
  /// @param owner_ The contract owner.
  /// @param pauser_ The contract pauser.
  function __initGovernable(address owner_, address pauser_) internal {
    __initOwnable(owner_);
    pauser = pauser_;
    emit PauserUpdated(pauser_);
  }

  /// @notice Update pauser to `_newPauser`.
  /// @param _newPauser The new pauser.
  function updatePauser(address _newPauser) external {
    if (msg.sender != owner && msg.sender != pauser) revert Unauthorized();
    emit PauserUpdated(_newPauser);
    pauser = _newPauser;
  }
}
