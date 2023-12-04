// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IOwnable} from "../interfaces/IOwnable.sol";

/**
 * @dev Contract module providing owner functionality, intended to be used through inheritance.
 */
abstract contract Ownable is IOwnable {
  /// @notice Contract owner.
  address public owner;

  /// @notice The pending new owner.
  address public pendingOwner;

  /// @dev Emitted when the owner address is updated.
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  /// @dev Emitted when the first step of the two step ownership transfer is executed.
  event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

  /// @dev Thrown when the caller is not authorized to perform the action.
  error Unauthorized();

  /// @dev Thrown when an invalid address is passed as a parameter.
  error InvalidAddress();

  /// @dev Initializer, replaces constructor for minimal proxies. Must be kept internal and it's up
  /// to the caller to make sure this can only be called once.
  /// @param owner_ The contract owner.
  function __initOwnable(address owner_) internal {
    emit OwnershipTransferred(owner, owner_);
    owner = owner_;
  }

  /// @notice Callable by the pending owner to transfer ownership to them.
  /// @dev Updates the owner in storage to newOwner_ and resets the pending owner.
  function acceptOwnership() external {
    if (msg.sender != pendingOwner) revert Unauthorized();
    delete pendingOwner;
    address oldOwner_ = owner;
    owner = msg.sender;
    emit OwnershipTransferred(oldOwner_, msg.sender);
  }

  /// @notice Starts the ownership transfer of the contract to a new account.
  /// Replaces the pending transfer if there is one.
  /// @param newOwner_ The new owner of the contract.
  function transferOwnership(address newOwner_) external onlyOwner {
    _assertAddressNotZero(newOwner_);
    pendingOwner = newOwner_;
    emit OwnershipTransferStarted(owner, newOwner_);
  }

  /// @dev Revert if the address is the zero address.
  function _assertAddressNotZero(address address_) internal pure {
    if (address_ == address(0)) revert InvalidAddress();
  }

  modifier onlyOwner() {
    if (msg.sender != owner) revert Unauthorized();
    _;
  }
}
