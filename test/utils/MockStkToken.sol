// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import "./MockERC20.sol";
import "../../src/interfaces/ISafetyModule.sol";

/// @author Solmate
/// https://github.com/transmissions11/solmate/blob/d155ee8d58f96426f57c015b34dee8a410c1eacc/src/test/utils/mocks/MockERC20.sol
/// @dev Note that this version of MockERC20 uses our own version of ERC20 instead of solmate's.
contract MockStkToken is MockERC20 {
  ISafetyModule public safetyModule;

  event Test(uint256 t);

  constructor(string memory _name, string memory _symbol, uint8 _decimals, ISafetyModule _safetyModule)
    MockERC20(_name, _symbol, _decimals)
  {
    safetyModule = _safetyModule;
  }

  function transfer(address to_, uint256 amount_) public override returns (bool) {
    safetyModule.updateUserRewardsForStkTokenTransfer(msg.sender, to_);
    return super.transfer(to_, amount_);
  }

  function transferFrom(address from_, address to_, uint256 amount_) public override returns (bool) {
    safetyModule.updateUserRewardsForStkTokenTransfer(from_, to_);
    return super.transferFrom(from_, to_, amount_);
  }
}
