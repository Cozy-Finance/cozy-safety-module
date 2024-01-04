// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {IERC20} from "../interfaces/IERC20.sol";
import {ReservePool, AssetPool} from "./structs/Pools.sol";
import {Ownable} from "./Ownable.sol";
import {MathConstants} from "./MathConstants.sol";
import {SafetyModuleCommon} from "./SafetyModuleCommon.sol";
import {SafeCastLib} from "./SafeCastLib.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafetyModuleState} from "./SafetyModuleStates.sol";
import {SafetyModuleCalculationsLib} from "./SafetyModuleCalculationsLib.sol";
import {UserRewardsData, PreviewClaimableRewardsData, PreviewClaimableRewards} from "./structs/Rewards.sol";
import {UndrippedRewardPool, IdLookup} from "./structs/Pools.sol";
import {IReceiptToken} from "../interfaces/IReceiptToken.sol";
import {IDripModel} from "../interfaces/IDripModel.sol";

abstract contract RewardsHandler is SafetyModuleCommon {
  using FixedPointMathLib for uint256;
  using SafeERC20 for IERC20;
  using SafeCastLib for uint256;

  event ClaimedRewards(
    uint16 indexed reservePoolId,
    IERC20 indexed rewardAsset_,
    uint256 amount_,
    address indexed owner_,
    address receiver_
  );

  struct RewardDrip {
    IERC20 rewardAsset;
    uint256 amount;
  }

  function dripRewards() public override {
    uint256 deltaT_ = block.timestamp - dripTimes.lastRewardsDripTime;
    if (deltaT_ == 0 || safetyModuleState == SafetyModuleState.PAUSED) return;

    _dripRewards(deltaT_);
  }

  function claimRewards(uint16 reservePoolId_, address receiver_) public override {
    dripRewards();

    UserRewardsData[] storage userRewards_ = userRewards[reservePoolId_][msg.sender];
    mapping(uint16 => uint256) storage claimableRewardsIndices_ = claimableRewardsIndices[reservePoolId_];
    // Update user rewards using user's full stkToken balance.
    _updateUserRewards(
      reservePools[reservePoolId_].stkToken.balanceOf(msg.sender), claimableRewardsIndices_, userRewards_
    );

    uint256 numRewardAssets_ = userRewards_.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      UserRewardsData storage userRewardsData_ = userRewards_[i];
      uint256 accruedRewards_ = userRewardsData_.accruedRewards;
      if (accruedRewards_ > 0) {
        IERC20 rewardAsset_ = undrippedRewardPools[i].asset;
        userRewardsData_.accruedRewards = 0;
        userRewardsData_.indexSnapshot = claimableRewardsIndices_[i].safeCastTo128();
        assetPools[rewardAsset_].amount -= accruedRewards_;
        rewardAsset_.safeTransfer(receiver_, accruedRewards_);

        emit ClaimedRewards(reservePoolId_, rewardAsset_, accruedRewards_, msg.sender, receiver_);
      }
    }
  }

  function previewClaimableRewards(uint16[] calldata reservePoolIds_, address owner_)
    external
    view
    returns (PreviewClaimableRewards[] memory previewClaimableRewards_)
  {
    uint256 lastRewardsDripTime_ = dripTimes.lastRewardsDripTime;
    uint256 numRewardAssets_ = undrippedRewardPools.length;

    RewardDrip[] memory nextRewardDrips_ = new RewardDrip[](numRewardAssets_);
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      nextRewardDrips_[i] =
        _previewNextRewardDrip(undrippedRewardPools[i], lastRewardsDripTime_, block.timestamp - lastRewardsDripTime_);
    }

    previewClaimableRewards_ = new PreviewClaimableRewards[](reservePoolIds_.length);
    for (uint256 i = 0; i < reservePoolIds_.length; i++) {
      previewClaimableRewards_[i] = _previewClaimableRewards(reservePoolIds_[i], owner_, nextRewardDrips_);
    }
  }
  
  function _previewClaimableRewards(uint16 reservePoolId_, address owner_, RewardDrip[] memory nextRewardDrips_)
    internal
    view
    returns (PreviewClaimableRewards memory)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    uint256 totalStkTokenSupply_ = reservePool_.stkToken.totalSupply();
    uint256 ownerStkTokenBalance_ = reservePool_.stkToken.balanceOf(owner_);
    uint256 rewardsWeight_ = reservePool_.rewardsPoolsWeight;

    // Compute preview user accrued rewards accounting for any pending rewards drips.
    PreviewClaimableRewardsData[] memory claimableRewardsData_ =
      new PreviewClaimableRewardsData[](nextRewardDrips_.length);
    mapping(uint16 => uint256) storage claimableRewardsIndices_ = claimableRewardsIndices[reservePoolId_];
    UserRewardsData[] storage userRewards_ = userRewards[reservePoolId_][owner_];

    for (uint16 i = 0; i < nextRewardDrips_.length; i++) {
      uint256 previewIndexSnapshot_ = _previewNextClaimableRewardIndex(
        claimableRewardsIndices_[i], nextRewardDrips_[i].amount, rewardsWeight_, totalStkTokenSupply_
      );
      claimableRewardsData_[i] = PreviewClaimableRewardsData({
        rewardPoolId: i,
        asset: nextRewardDrips_[i].rewardAsset,
        amount: _previewUserRewardsData(
          i, ownerStkTokenBalance_, previewIndexSnapshot_, userRewards_.length, userRewards_
          ).accruedRewards
      });
    }

    return PreviewClaimableRewards({reservePoolId: reservePoolId_, claimableRewardsData: claimableRewardsData_});
  }

  /// @notice stkTokens are expected to call this before the actual underlying ERC-20 transfer (e.g.
  /// `super.transfer(address to, uint256 amount_)`). Otherwise, the `from_` user will not accrue less historical
  /// rewards they are entitled to as their new balance is smaller after the transfer. Also, the `to_` user will accure
  /// more historical rewards than they are entitled to as their new balance is larger after the transfer.
  function updateUserRewardsForStkTokenTransfer(address from_, address to_) external {
    // Check that only a registered stkToken can call this function.
    IdLookup memory idLookup_ = stkTokenToReservePoolIds[IReceiptToken(msg.sender)];
    if (!idLookup_.exists) revert Ownable.Unauthorized();

    uint16 reservePoolId_ = idLookup_.index;
    IReceiptToken stkToken_ = reservePools[reservePoolId_].stkToken;
    mapping(uint16 => uint256) storage claimableRewardsIndices_ = claimableRewardsIndices[reservePoolId_];

    // Fully accure historical rewards for both users given their current stkToken balances. Moving forward all rewards
    // will accrue based on: (1) the stkToken balances of the `from_` and `to_` address after the transfer, (2) the
    // current claimable reward index snapshots.
    _updateUserRewards(stkToken_.balanceOf(from_), claimableRewardsIndices_, userRewards[reservePoolId_][from_]);
    _updateUserRewards(stkToken_.balanceOf(to_), claimableRewardsIndices_, userRewards[reservePoolId_][to_]);
  }

  function _dripRewards(uint256 deltaT_) internal {
    // Pull full reservePools array into memory to save SLOADs in `_executeNextRewardDrip` internal loop.
    ReservePool[] memory reservePools_ = reservePools;

    uint256 lastRewardsDripTime_ = dripTimes.lastRewardsDripTime;
    uint256 numRewardAssets_ = undrippedRewardPools.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      _executeNextRewardDrip(i, lastRewardsDripTime_, deltaT_, reservePools_);
    }

    dripTimes.lastRewardsDripTime = uint128(block.timestamp);
  }

  function _executeNextRewardDrip(
    uint16 rewardPoolId_,
    uint256 lastDripTime_,
    uint256 deltaT_,
    ReservePool[] memory reservePools_
  ) internal {
    UndrippedRewardPool storage undrippedRewardPool_ = undrippedRewardPools[rewardPoolId_];
    RewardDrip memory rewardDrip_ = _previewNextRewardDrip(undrippedRewardPool_, lastDripTime_, deltaT_);

    if (rewardDrip_.amount > 0) {
      for (uint16 i = 0; i < reservePools_.length; i++) {
        claimableRewardsIndices[i][rewardPoolId_] = _previewNextClaimableRewardIndex(
          claimableRewardsIndices[i][rewardPoolId_],
          rewardDrip_.amount,
          reservePools_[i].rewardsPoolsWeight,
          reservePools_[i].stkToken.totalSupply()
        );
      }
      undrippedRewardPool_.amount -= rewardDrip_.amount;
    }
  }

  function _previewNextRewardDrip(
    UndrippedRewardPool storage undrippedRewardPool_,
    uint256 lastDripTime_,
    uint256 deltaT_
  ) internal view returns (RewardDrip memory) {
    return RewardDrip({
      rewardAsset: undrippedRewardPool_.asset,
      amount: _getNextDripAmount(undrippedRewardPool_.amount, undrippedRewardPool_.dripModel, lastDripTime_, deltaT_)
    });
  }

  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_, uint256 deltaT_)
    internal
    view
    override
    returns (uint256)
  {
    if (deltaT_ == 0) return 0;
    return _computeNextDripAmount(totalBaseAmount_, dripModel_.dripFactor(lastDripTime_, deltaT_));
  }

  function _computeNextDripAmount(uint256 totalBaseAmount_, uint256 dripFactor_)
    internal
    pure
    override
    returns (uint256)
  {
    return totalBaseAmount_.mulWadDown(dripFactor_);
  }

  function _previewNextClaimableRewardIndex(
    uint256 currentClaimableRewardIndex_,
    uint256 totalDrippedRewards_,
    uint256 rewardsPoolsWeight_,
    uint256 totalStkTokenSupply_
  ) internal pure returns (uint256) {
    // Round down, in favor of leaving assets in the undripped pool.
    uint256 scaledDrippedRewards_ = totalDrippedRewards_.mulDivDown(rewardsPoolsWeight_, MathConstants.ZOC);
    // Round down, in favor of leaving assets in the claimable reward pool.
    return currentClaimableRewardIndex_ + scaledDrippedRewards_.divWadDown(totalStkTokenSupply_);
  }

  function _updateUserRewards(
    uint256 userStkTokenBalance_,
    mapping(uint16 => uint256) storage claimableRewardsIndices_,
    UserRewardsData[] storage userRewards_
  ) internal override {
    uint256 numRewardAssets_ = undrippedRewardPools.length;
    uint256 numOldRewardAssets_ = userRewards_.length;

    for (uint16 i = 0; i < numRewardAssets_; i++) {
      UserRewardsData memory userRewardsData_ =
        _previewUserRewardsData(i, userStkTokenBalance_, claimableRewardsIndices_[i], numOldRewardAssets_, userRewards_);

      if (i < numOldRewardAssets_) userRewards_[i] = userRewardsData_;
      else userRewards_.push(userRewardsData_);
    }
  }

  function _previewUserRewardsData(
    uint16 rewardPoolId_,
    uint256 userStkTokenBalance_,
    uint256 newIndexSnapshot_,
    uint256 userNumRewardAssets_,
    UserRewardsData[] storage userRewards_
  ) internal view returns (UserRewardsData memory userRewardsData_) {
    if (rewardPoolId_ < userNumRewardAssets_) {
      UserRewardsData storage oldUserRewardsData_ = userRewards_[rewardPoolId_];
      userRewardsData_.accruedRewards = oldUserRewardsData_.accruedRewards
        + _getUserAccruedRewards(userStkTokenBalance_, newIndexSnapshot_, oldUserRewardsData_.indexSnapshot).safeCastTo128(
        );
      userRewardsData_.indexSnapshot = newIndexSnapshot_.safeCastTo128();
    } else {
      userRewardsData_.accruedRewards =
        _getUserAccruedRewards(userStkTokenBalance_, newIndexSnapshot_, 0).safeCastTo128();
      userRewardsData_.indexSnapshot = newIndexSnapshot_.safeCastTo128();
    }
  }

  function _getUserAccruedRewards(uint256 stkTokenAmount_, uint256 newRewardPoolIndex, uint256 oldRewardPoolIndex)
    internal
    pure
    returns (uint256)
  {
    // Round down, in favor of leaving assets in the rewards pool.
    return stkTokenAmount_.mulWadDown(newRewardPoolIndex - oldRewardPoolIndex);
  }
}
