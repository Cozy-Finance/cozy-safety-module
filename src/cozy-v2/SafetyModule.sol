// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {Address} from "openzeppelin-contracts/contracts/utils/Address.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {Ownable} from "../lib/Ownable.sol";
import {SafeERC20} from "../lib/SafeERC20.sol";

contract SafetyModule is Ownable {
  using Address for address;
  using SafeERC20 for IERC20;

  address public trigger;

  bool public isTriggered;

  bool public isInitialized;

  /// @dev Thrown if the contract is already initialized.
  error Initialized();

  /// @dev Thrown if the contract is not in a valid state to execute an operation.
  error InvalidState();

  event WithdrawToken(IERC20 indexed token, address indexed receiver, uint256 amount);
  event WithdrawETH(address indexed receiver, uint256 amount);
  event Triggered();

  struct WithdrawData {
    IERC20 token;
    address receiver;
    uint256 amount;
  }

  /// @notice Replaces the constructor for minimal proxies.
  /// @param owner_ The owner of the safety module.
  /// @param trigger_ The trigger of the safety module.
  function initialize(address owner_, address trigger_) external uninitialized {
    __initOwnable(owner_);
    trigger = trigger_;
    isInitialized = true;
  }

  /// @notice Sends tokens held by this safety module to a specified address. Only callable by the owner while the
  /// safety module is triggered.
  function withdraw(WithdrawData[] memory withdrawData) external onlyOwner onlyTriggered {
    for (uint256 i = 0; i < withdrawData.length; i++) {
      withdrawData[i].token.safeTransfer(withdrawData[i].receiver, withdrawData[i].amount);
      emit WithdrawToken(withdrawData[i].token, withdrawData[i].receiver, withdrawData[i].amount);
    }
  }

  /// @notice Sends an amount of ETH held by this safety module to a specified address. Only callable by the owner while
  /// the safety module is triggered.
  function withdrawETH(address receiver_, uint256 amount_) external onlyOwner onlyTriggered {
    // Enables reentrancy, but this contract does not use internal accounting so it's ok.
    Address.sendValue(payable(receiver_), amount_);
    emit WithdrawETH(receiver_, amount_);
  }

  /// @notice Triggers the safety module. Only callable by the trigger.
  /// @dev Once the safety module is triggered, it cannot be untriggered.
  function triggerSafetyModule() external onlyTrigger {
    isTriggered = true;
    emit Triggered();
  }

  modifier uninitialized() {
    if (isInitialized) revert Initialized();
    _;
  }

  modifier onlyTrigger() {
    if (msg.sender != trigger) revert Unauthorized();
    _;
  }

  modifier onlyTriggered() {
    if (!isTriggered) revert InvalidState();
    _;
  }
}
