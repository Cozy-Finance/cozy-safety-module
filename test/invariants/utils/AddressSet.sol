// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

struct AddressSet {
  address[] addrs;
  mapping(address => bool) saved;
}

library AddressSetLib {
  function add(AddressSet storage s, address addr) internal {
    if (!s.saved[addr]) {
      s.addrs.push(addr);
      s.saved[addr] = true;
    }
  }

  function contains(AddressSet storage s, address addr) internal view returns (bool) {
    return s.saved[addr];
  }

  function count(AddressSet storage s) internal view returns (uint256) {
    return s.addrs.length;
  }

  function forEach(AddressSet storage s, function(address) external func) internal {
    for (uint256 i; i < s.addrs.length; ++i) {
      func(s.addrs[i]);
    }
  }

  function rand(AddressSet storage s, uint256 seed) internal returns (address) {
    if (s.addrs.length > 0) {
      return s.addrs[seed % s.addrs.length];
    } else {
      address defaultAddress_ = address(0xc0ffee);
      add(s, defaultAddress_);
      return defaultAddress_;
    }
  }

  function reduce(AddressSet storage s, uint256 acc, function(uint256,address) external returns (uint256) func)
    internal
    returns (uint256)
  {
    for (uint256 i; i < s.addrs.length; ++i) {
      acc = func(acc, s.addrs[i]);
    }
    return acc;
  }
}
