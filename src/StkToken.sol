// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {InactivePeriod, InactivityData} from "./lib/structs/InactivityData.sol";
import {IManager} from "./interfaces/IManager.sol";
import {ISafetyModule} from "./interfaces/ISafetyModule.sol";
import {MintData} from "./lib/structs/MintData.sol";
import {LFT} from "./lib/LFT.sol";

contract StkToken is LFT {
  /// @notice Address of the Cozy protocol manager.
  IManager public immutable cozyManager;

  /// @notice Address of this token's safety module.
  ISafetyModule public safetyModule;

  /// @notice Stores metadata about previous inactive periods.
  InactivityData public inactivityData;

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
    // TODO: Binary search logic for balance of matured
    // if (balance_ == 0) return 0;

    // MintData[] storage mints_ = mints[user_];
    // uint256 high_ = mints_.length;
    // // If the user has a balance without a mint (i.e. if someone transferred them tokens), we can return early
    // because
    // // only matured tokens can be transferred.
    // if (high_ == 0) return balance_;

    // uint256[] storage cumulativeMinted_ = cumulativeMinted[user_];
    // // If we were to load this into memory, malicious owners would be able to DOS Sets if they pause/unpause many
    // times.
    // InactivityData storage inactivityData_ = inactivityData;
    // uint32 delay_ = manager.purchaseDelay();

    // // Perform a binary search to find the most recently matured mint of ptokens. The balance of matured ptokens for
    // // a user is calculated by `balance - (cumulative ptokens minted - cumulative matured ptokens minted)`.
    // uint256 low_ = 0;
    // unchecked {
    //   while (low_ < high_) {
    //     // This will never overflow since low_ and high_ are bounded by the length of the mints array.
    //     uint256 mid_ = (low_ + high_) / 2;
    //     uint256 activeTimeElapsed_ = DelayLib.getDelayTimeAccrued(
    //       mints_[mid_].time,
    //       block.timestamp,
    //       // If inactiveTransitionTime_ > 0, the market is in an inactive state, and so we calculate the current
    //       // inactive period duration.
    //       // This will never overflow because of the invariant block.timestamp >=
    //       // inactivityData_.inactiveTransitionTime.
    //       inactivityData_.inactiveTransitionTime > 0 ? block.timestamp - inactivityData_.inactiveTransitionTime : 0,
    //       inactivityData.periods
    //     );
    //     if (activeTimeElapsed_ < delay_) {
    //       high_ = mid_;
    //     } else {
    //       // Realistically this cannot overflow since mid_ is bounded by the length of the mints array.
    //       low_ = mid_ + 1;
    //     }
    //   }

    //   // If high_ == 0, there are no matured tokens.
    //   // high_ - 1 will never overflow if high_ > 0. high_ cannot be < 0.
    //   uint256 cumulativeMatured_ = high_ == 0 ? 0 : cumulativeMinted_[high_ - 1];

    //   // This cannot overflow since we only execute this block if there's a balance, which means
    //   // cumulativeMinted_.length >= 1.
    //   balance_ -= (cumulativeMinted_[cumulativeMinted_.length - 1] - cumulativeMatured_);
    // }
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

  // -------- Inactive Periods --------

  /// @notice Updates the inactive transition time to `timestamp_`.
  function updateInactiveTransitionTime(uint64 timestamp_) external onlySafetyModule {
    inactivityData.inactiveTransitionTime = timestamp_;
  }

  /// @notice Adds an inactive period and resets the inactive transition time to zero.
  /// @dev Inactive periods should only be added when the related market has transitioned out of an inactive state.
  ///      When the market is not in an inactive state, `inactiveTransitionTime` should be set to 0.
  function addInactivePeriod() external onlySafetyModule {
    uint64 inactiveTransitionTime_ = inactivityData.inactiveTransitionTime; // Saves an extra SLOAD.

    inactivityData.periods.push(
      InactivePeriod(inactiveTransitionTime_, _getNewCumulativePreviousInactiveDuration(uint64(block.timestamp)))
    );
    // Reset inactiveTransitionTime for the market; when a new inactive period is added, the market has transitioned
    // out of an inactive state.
    inactivityData.inactiveTransitionTime = 0;
  }

  function _getNewCumulativePreviousInactiveDuration(uint64 now_) internal view returns (uint64) {
    // TODO: Inactive period logic
    // return DelayLib.getNewCumulativePreviousInactiveDuration(inactivityData, now_);
  }

  // -------- Modifiers --------

  /// @dev Checks that msg.sender is the set address.
  modifier onlySafetyModule() {
    if (msg.sender != address(safetyModule)) revert Unauthorized();
    _;
  }
}
