// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "../../src/lib/ERC20.sol";

/// @author Solmate
/// https://github.com/transmissions11/solmate/blob/d155ee8d58f96426f57c015b34dee8a410c1eacc/src/test/utils/mocks/MockERC20.sol
/// @dev Note that this version of MockERC20 uses our own version of ERC20 instead of solmate's.
contract MockERC20 is ERC20 {
  constructor(string memory _name, string memory _symbol, uint8 _decimals) {
    __initERC20(_name, _symbol, _decimals);
  }

  function mint(address to, uint256 value) public virtual {
    _mint(to, value);
  }

  function burn(address from, uint256 value) public virtual {
    _burn(from, value);
  }
}
