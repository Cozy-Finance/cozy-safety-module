// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "./ERC20.sol";
import "./structs/MintData.sol";

/**
 * @notice Latent Fungible Token (LFT) implementation. An LFT is a token that is initially non-transferrable
 * and non-fungible, but becomes transferrable and fungible at some time. The `balanceOf` method behaves the same
 * as an ERC-20 and returns the full balance. However, not all of those tokens are necessarily fungible and spendable.
 * A `balanceOfMatured` method is added which returns the amount of tokens that are fungible and can be spent. The
 * logic for determining matured balance can vary and must be implemented.
 */
abstract contract LFT is ERC20 {
  /// @notice Mapping from user address to array of their mints (MintData).
  mapping(address => MintData[]) public mints;

  /// @notice Mapping from user address to the cumulative amount of tokens minted at the time of each of mint.
  mapping(address => uint256[]) public cumulativeMinted;

  /// @dev Thrown when an operation cannot be performed because the user does not have a sufficient matured balance.
  error InsufficientBalance();

  /// @dev Initializer, replaces constructor for minimal proxies. Must be kept internal and it's up
  /// to the caller to make sure this can only be called once.
  /// @param name_ The name of the token.
  /// @param symbol_ The symbol of the token.
  /// @param decimals_ The decimal places of the token.
  function __initLFT(string memory name_, string memory symbol_, uint8 decimals_) internal {
    __initERC20(name_, symbol_, decimals_);
  }

  /// @notice Returns the quantity of matured tokens held by the given `user_`.
  /// @dev A user's `balanceOfMatured` is computed by starting with `balanceOf[user_]` then subtracting the sum of
  /// all `amounts` from the  user's `mints` array that are not yet matured. How to determine when a given mint
  /// is matured is left to the implementer. It can be simple such as maturing when `block.timestamp >= time + delay`,
  /// or something more complex.
  function balanceOfMatured(address user_) public view virtual returns (uint256);

  function getMints(address user_) public view returns (MintData[] memory) {
    return mints[user_];
  }

  /// @notice Moves `amount_` tokens from the caller's account to `to_`. Tokens must be matured to transfer them.
  function transfer(address to_, uint256 amount_) public override returns (bool) {
    _assertSufficientMaturedBalance(msg.sender, amount_);
    return super.transfer(to_, amount_);
  }

  /// @notice Moves `amount_` tokens from `from_` to `to_`. Tokens must be matured to transfer them.
  function transferFrom(address from_, address to_, uint256 amount_) public override returns (bool) {
    _assertSufficientMaturedBalance(from_, amount_);
    return super.transferFrom(from_, to_, amount_);
  }

  /// @notice Destroys `amount_` tokens from `from_`. Tokens must be matured to burn them.
  function _burn(address from_, uint256 amount_) internal virtual override {
    _assertSufficientMaturedBalance(from_, amount_);
    super._burn(from_, amount_);
  }

  /// @dev Mints `amount_` tokens to `to_`.
  function _mintTokens(address to_, uint216 amount_) internal {
    mints[to_].push(MintData({amount: amount_, time: uint40(block.timestamp)}));
    uint256[] storage cumulativeMinted_ = cumulativeMinted[to_];
    uint256 numMints_ = cumulativeMinted_.length;
    uint256 cumulativeMintedPrior_ = numMints_ > 0 ? cumulativeMinted_[numMints_ - 1] : 0;
    cumulativeMinted[to_].push(cumulativeMintedPrior_ + amount_);
    super._mint(to_, amount_);
  }

  function _mint(address, uint256) internal pure override {
    // Do not allow calling this function directly.
    revert();
  }

  function _assertSufficientMaturedBalance(address from_, uint256 amount_) internal view {
    if (balanceOfMatured(from_) < amount_) revert InsufficientBalance();
  }
}
