// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {IERC20} from "./interfaces/IERC20.sol";
import {IManager} from "./interfaces/IManager.sol";
import {IRewardsDripModel} from "./interfaces/IRewardsDripModel.sol";
import {IStkToken} from "./interfaces/IStkToken.sol";
import {IStkTokenFactory} from "./interfaces/IStkTokenFactory.sol";
import {RewardPoolConfig} from "./lib/structs/Configs.sol";
import {Governable} from "./lib/Governable.sol";

/// @dev Multiple asset SafetyModule.
contract SafetyModule is Governable {
  struct ReservePool {
    IERC20 token;
    IStkToken stkToken;
    uint256 amount;
  }

  struct RewardPool {
    IERC20 token;
    uint256 amount;
  }

  struct UndrippedRewardPool {
    IERC20 token;
    uint128 amount;
    IRewardsDripModel dripModel;
    uint128 lastDripTime;
  }

  struct IdLookup {
    uint128 index;
    bool exists;
  }

  struct ClaimedRewards {
    IERC20 token;
    uint128 amount;
  }

  /// @dev reserve pool index in this array is its ID
  ReservePool[] public reservePools;

  /// @dev claimable reward pool index in this array is its ID
  RewardPool[] public claimableRewardPools;

  /// @dev undripped reward pool index in this array is its ID
  UndrippedRewardPool[] public undrippedRewardPools;

  /// @dev claimable and undripped reward pools are mapped 1:1
  mapping(IERC20 asset_ => uint16[] ids_) public rewardPoolIds;

  /// @dev Used when claiming rewards
  mapping(IStkToken stkToken_ => IdLookup reservePoolId_) public stkTokenToReservePoolIds;

  /// @dev Used when depositing
  mapping(IERC20 reserveToken_ => IdLookup reservePoolId_) public reserveTokenToReservePoolIds;

  /// @dev The weighting of each stkToken's claim to all reward pools. Must sum to 1.
  /// e.g. stkTokenA = 10%, means they're eligible for up to 10% of each pool, scaled to their balance of stkTokenA
  /// wrt totalSupply.
  uint16[] public stkTokenRewardPoolWeights;

  /// @dev Two step delay for unstaking.
  /// Need to accomodate for multiple triggers when unstaking
  uint128 public unstakeDelay;

  /// @dev Has config for deposit fee and where to send fees
  IManager public immutable cozyManager;

  /// @notice Address of the Cozy protocol stkTokenFactory.
  IStkTokenFactory public immutable stkTokenFactory;

  constructor(IManager manager_, IStkTokenFactory stkTokenFactory_) {
    _assertAddressNotZero(address(manager_));
    _assertAddressNotZero(address(stkTokenFactory_));
    cozyManager = manager_;
    stkTokenFactory = stkTokenFactory_;
  }

  function initialize(
    address owner_,
    address pauser_,
    IERC20[] calldata reserveAssets_,
    RewardPoolConfig[] calldata rewardPoolConfig_,
    uint128 unstakeDelay_
  ) external {
    // Sets are minimal proxies, so the owner and pauser is set to address(0) in the constructor for the logic
    // contract. When the set is initialized for the minimal proxy, we update the owner and pauser.
    __initGovernable(owner_, pauser_);

    // TODO: Move to configurator lib
    // TODO: Emit event, either like cozy v2 where we use the configuration update event, or maybe specific to init
    for (uint8 i; i < reserveAssets_.length; i++) {
      IStkToken stkToken_ = stkTokenFactory.deployStkToken(i, reserveAssets_[i].decimals());
      reservePools[i] = ReservePool({token: reserveAssets_[i], stkToken: stkToken_, amount: 0});
      stkTokenToReservePoolIds[stkToken_] = IdLookup({index: i, exists: true});
      reserveTokenToReservePoolIds[reserveAssets_[i]] = IdLookup({index: i, exists: true});
    }
    for (uint8 i; i < rewardPoolConfig_.length; i++) {
      claimableRewardPools[i] = RewardPool({token: rewardPoolConfig_[i].token, amount: 0});
      undrippedRewardPools[i] = UndrippedRewardPool({
        token: rewardPoolConfig_[i].token,
        amount: 0,
        dripModel: rewardPoolConfig_[i].dripModel,
        lastDripTime: 0
      });
      stkTokenRewardPoolWeights[i] = rewardPoolConfig_[i].weight;
    }
    unstakeDelay = unstakeDelay_;
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

  function stake(uint16 reservePoolId_, uint256 amount_, address receiver_, address from_)
    external
    returns (uint256 stkTokenAmount_)
  {}

  function stakeWithoutTransfer(uint16 reservePoolId_, uint256 amount_, address receiver_)
    external
    returns (uint256 stkTokenAmount_)
  {}

  function unStake(uint16 reservePoolId_, uint256 amount_, address receiver_, address from_)
    external
    returns (uint256 reserveTokenAmount_)
  {}

  function unStakeWithoutTransfer(uint16 reservePoolId_, uint256 amount_, address receiver_)
    external
    returns (uint256 reserveTokenAmount_)
  {}

  function claimRewards(address owner_) external returns (ClaimedRewards[] memory claimedRewards_) {}
}
