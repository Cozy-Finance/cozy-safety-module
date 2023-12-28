// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "./interfaces/IERC20.sol";
import {IManager} from "./interfaces/IManager.sol";
import {IRewardsDripModel} from "./interfaces/IRewardsDripModel.sol";
import {IReceiptToken} from "./interfaces/IReceiptToken.sol";
import {IReceiptTokenFactory} from "./interfaces/IReceiptTokenFactory.sol";
import {UndrippedRewardPoolConfig, ReservePoolConfig} from "./lib/structs/Configs.sol";
import {Depositor} from "./lib/Depositor.sol";
import {Governable} from "./lib/Governable.sol";
import {Redeemer} from "./lib/Redeemer.sol";
import {Staker} from "./lib/Staker.sol";
import {SafetyModuleBaseStorage} from "./lib/SafetyModuleBaseStorage.sol";
import {ReservePool, AssetPool, IdLookup, UndrippedRewardPool} from "./lib/structs/Pools.sol";
import {SafetyModuleState} from "./lib/SafetyModuleStates.sol";
import {RewardsHandler} from "./lib/RewardsHandler.sol";

/// @dev Multiple asset SafetyModule.
contract SafetyModule is Governable, SafetyModuleBaseStorage, Depositor, Redeemer, Staker, RewardsHandler {
  constructor(IManager manager_, IReceiptTokenFactory receiptTokenFactory_) {
    _assertAddressNotZero(address(manager_));
    _assertAddressNotZero(address(receiptTokenFactory_));
    cozyManager = manager_;
    receiptTokenFactory = receiptTokenFactory_;
  }

  function initialize(
    address owner_,
    address pauser_,
    ReservePoolConfig[] calldata reservePoolConfig_,
    UndrippedRewardPoolConfig[] calldata undrippedRewardPoolConfig_,
    uint128 unstakeDelay_,
    uint128 withdrawDelay_
  ) external {
    // Safety Modules are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the logic
    // contract. When the set is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);

    // TODO: Move to configurator lib
    // TODO: Emit event, either like cozy v2 where we use the configuration update event, or maybe specific to init
    for (uint8 i; i < reservePoolConfig_.length; i++) {
      IReceiptToken stkToken_ = receiptTokenFactory.deployReceiptToken(
        i, IReceiptTokenFactory.PoolType.STAKE, reservePoolConfig_[i].asset.decimals()
      );
      IReceiptToken reserveDepositToken_ = receiptTokenFactory.deployReceiptToken(
        i, IReceiptTokenFactory.PoolType.RESERVE, reservePoolConfig_[i].asset.decimals()
      );
      reservePools[i] = ReservePool({
        asset: reservePoolConfig_[i].asset,
        stkToken: stkToken_,
        depositToken: reserveDepositToken_,
        stakeAmount: 0,
        depositAmount: 0,
        rewardsPoolsWeight: reservePoolConfig_[i].rewardsPoolsWeight
      });
      stkTokenToReservePoolIds[stkToken_] = IdLookup({index: i, exists: true});
    }
    for (uint8 i; i < undrippedRewardPoolConfig_.length; i++) {
      IReceiptToken rewardDepositToken_ = receiptTokenFactory.deployReceiptToken(
        i, IReceiptTokenFactory.PoolType.REWARD, undrippedRewardPoolConfig_[i].asset.decimals()
      );
      undrippedRewardPools[i] = UndrippedRewardPool({
        asset: undrippedRewardPoolConfig_[i].asset,
        amount: 0,
        dripModel: undrippedRewardPoolConfig_[i].dripModel,
        depositToken: rewardDepositToken_
      });
      assetToUndrippedRewardPoolIds[undrippedRewardPoolConfig_[i].asset] = IdLookup({index: i, exists: true});
    }
    unstakeDelay = unstakeDelay_;
    withdrawDelay = withdrawDelay_;
    // TODO: Check if this should be 0, instead?
    lastDripTime = block.timestamp;
  }

  // -------------------------------------------------------------------
  // --------- TODO: Move these functions to abstract contracts --------
  // -------------------------------------------------------------------

  /// @dev Expects `from_` to have approved this SafetyModule for `amount_` of `reservePools[reservePoolId_]` so it can
  /// `transferFrom`
  function depositReserveAssets(uint16 reservePoolId_, address from_, uint256 amount_) external {}

  /// @dev Expects depositer to transfer assets to the SafetyModule beforehand.
  function depositReserveAssetsWithoutTransfer(uint16 reservePoolId_, address from_, uint256 amount_) external {}

  /// @dev Rewards can be any token (not necessarily the same as the reserve asset)
  function depositRewardsAssets(uint16 claimableRewardPoolId_, address from_, uint256 amount_) external {}

  /// @dev Helpful in cases where depositing reserve and rewards asset in single transfer (same token)
  function deposit(
    uint16 reservePoolId_,
    uint16 claimableRewardPoolId_,
    address from_,
    uint256 amount_,
    uint256 rewardsPercentage_,
    uint256 reservePercentage_
  ) external {}
}
