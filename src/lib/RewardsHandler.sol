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
import {
  UserRewardsData,
  PreviewClaimableRewardsData,
  PreviewClaimableRewards,
  ClaimableRewardsData
} from "./structs/Rewards.sol";
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
    if (safetyModuleState == SafetyModuleState.PAUSED) return;

    uint256 numRewardAssets_ = undrippedRewardPools.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      _dripRewardPool(undrippedRewardPools[i]);
    }
  }

  function dripRewardPool(uint16 rewardPoolId_) external {
    _dripRewardPool(undrippedRewardPools[rewardPoolId_]);
  }

  function claimRewards(uint16 reservePoolId_, address receiver_) public override {
    SafetyModuleState safetyModuleState_ = safetyModuleState;

    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    uint256 userStkTokenBalance_ = reservePool_.stkToken.balanceOf(msg.sender);
    uint256 totalStkTokenSupply_ = reservePool_.stkToken.totalSupply();
    uint256 rewardsWeight_ = reservePool_.rewardsPoolsWeight;

    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewardsIndices[reservePoolId_];
    UserRewardsData[] storage userRewards_ = userRewards[reservePoolId_][msg.sender];

    uint256 numRewardAssets_ = undrippedRewardPools.length;
    uint256 numUserRewardAssets_ = userRewards_.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      UndrippedRewardPool storage undrippedRewardPool_ = undrippedRewardPools[i];
      if (safetyModuleState_ != SafetyModuleState.PAUSED) _dripRewardPool(undrippedRewardPool_);

      {
        ClaimableRewardsData memory newClaimableRewardsData_ = _previewNextClaimableRewardsData(
          claimableRewards_[i],
          _computeUnclaimedDrippedRewards(
            undrippedRewardPool_.cumulativeDrippedRewards, claimableRewards_[i].cumulativeClaimedRewards, rewardsWeight_
          ),
          totalStkTokenSupply_
        );

        _transferClaimedRewards(
          reservePoolId_,
          undrippedRewardPool_.asset,
          receiver_,
          _getUserAccruedRewards(
            userStkTokenBalance_,
            newClaimableRewardsData_.indexSnapshot,
            i < numUserRewardAssets_ ? userRewards_[i].indexSnapshot : 0
          )
        );

        claimableRewards_[i] = newClaimableRewardsData_;
        UserRewardsData memory newUserRewardsData_ =
          UserRewardsData({accruedRewards: 0, indexSnapshot: newClaimableRewardsData_.indexSnapshot});
        // A new UserRewardsData struct is pushed to the array in the case a new reward pool was added since rewards
        // were last claimed for this user.
        if (i < numUserRewardAssets_) userRewards_[i] = newUserRewardsData_;
        else userRewards_.push(newUserRewardsData_);
      }
    }
  }

  function previewClaimableRewards(uint16[] calldata reservePoolIds_, address owner_)
    external
    view
    returns (PreviewClaimableRewards[] memory previewClaimableRewards_)
  {
    uint256 numRewardAssets_ = undrippedRewardPools.length;

    RewardDrip[] memory nextRewardDrips_ = new RewardDrip[](numRewardAssets_);
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      nextRewardDrips_[i] = _previewNextRewardDrip(undrippedRewardPools[i]);
    }

    previewClaimableRewards_ = new PreviewClaimableRewards[](reservePoolIds_.length);
    for (uint256 i = 0; i < reservePoolIds_.length; i++) {
      previewClaimableRewards_[i] = _previewClaimableRewards(reservePoolIds_[i], owner_, nextRewardDrips_);
    }
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
    mapping(uint16 => ClaimableRewardsData) storage claimableRewardsIndices_ = claimableRewardsIndices[reservePoolId_];

    // Fully accure historical rewards for both users given their current stkToken balances. Moving forward all rewards
    // will accrue based on: (1) the stkToken balances of the `from_` and `to_` address after the transfer, (2) the
    // current claimable reward index snapshots.
    _updateUserRewards(stkToken_.balanceOf(from_), claimableRewardsIndices_, userRewards[reservePoolId_][from_]);
    _updateUserRewards(stkToken_.balanceOf(to_), claimableRewardsIndices_, userRewards[reservePoolId_][to_]);
  }

  function _dripRewardPool(UndrippedRewardPool storage undrippedRewardPool_) internal override {
    if (safetyModuleState == SafetyModuleState.PAUSED) return;

    RewardDrip memory rewardDrip_ = _previewNextRewardDrip(undrippedRewardPool_);
    if (rewardDrip_.amount > 0) {
      undrippedRewardPool_.amount -= rewardDrip_.amount;
      undrippedRewardPool_.cumulativeDrippedRewards += rewardDrip_.amount;
    }
    undrippedRewardPool_.lastDripTime = uint128(block.timestamp);
  }

  function _previewNextClaimableRewardsData(
    ClaimableRewardsData memory claimableRewardsData_,
    uint256 unclaimedDrippedRewards_,
    uint256 totalStkTokenSupply_
  ) internal pure returns (ClaimableRewardsData memory nextClaimableRewardsData_) {
    nextClaimableRewardsData_.cumulativeClaimedRewards = claimableRewardsData_.cumulativeClaimedRewards;
    nextClaimableRewardsData_.indexSnapshot = claimableRewardsData_.indexSnapshot;
    // If `totalStkTokenSupply_ == 0`, then we get a divide by zero error if we try to update the index snapshot. To
    // avoid this, we wait until the `totalStkTokenSupply_ > 0`, to apply all accumualted unclaimed dripped rewards to
    // the claimable rewards data. We have to update the index snapshot and cumulative claimed rewards at the same time
    // to keep accounting correct.
    if (totalStkTokenSupply_ > 0) {
      nextClaimableRewardsData_.cumulativeClaimedRewards += unclaimedDrippedRewards_;
      // Round down, in favor of leaving assets in the claimable reward pool.
      nextClaimableRewardsData_.indexSnapshot +=
        unclaimedDrippedRewards_.divWadDown(totalStkTokenSupply_).safeCastTo128();
    }
  }

  function _transferClaimedRewards(uint16 reservePoolId_, IERC20 rewardAsset_, address receiver_, uint256 amount_)
    internal
  {
    if (amount_ == 0) return;
    assetPools[rewardAsset_].amount -= amount_;
    rewardAsset_.safeTransfer(receiver_, amount_);
    emit ClaimedRewards(reservePoolId_, rewardAsset_, amount_, msg.sender, receiver_);
  }

  function _computeUnclaimedDrippedRewards(
    uint256 cumulativeDrippedRewards_,
    uint256 cumulativeClaimedRewards_,
    uint256 rewardsWeight_
  ) internal pure returns (uint256) {
    // Round down, in favor of leaving assets in the undripped pool.
    uint256 scaledCumulativeDrippedRewards_ = cumulativeDrippedRewards_.mulDivDown(rewardsWeight_, MathConstants.ZOC);
    return scaledCumulativeDrippedRewards_ - cumulativeClaimedRewards_;
  }

  function _previewNextRewardDrip(UndrippedRewardPool storage undrippedRewardPool_)
    internal
    view
    returns (RewardDrip memory)
  {
    return RewardDrip({
      rewardAsset: undrippedRewardPool_.asset,
      amount: _getNextDripAmount(
        undrippedRewardPool_.amount,
        undrippedRewardPool_.dripModel,
        undrippedRewardPool_.lastDripTime,
        block.timestamp - undrippedRewardPool_.lastDripTime
        )
    });
  }

  function _previewClaimableRewards(uint16 reservePoolId_, address owner_, RewardDrip[] memory nextRewardDrips_)
    internal
    view
    returns (PreviewClaimableRewards memory)
  {
    ReservePool storage reservePool_ = reservePools[reservePoolId_];
    uint256 totalStkTokenSupply_ = reservePool_.stkToken.totalSupply();
    uint256 ownerStkTokenBalance_ = reservePool_.stkToken.balanceOf(owner_);

    // Compute preview user accrued rewards accounting for any pending rewards drips.
    PreviewClaimableRewardsData[] memory claimableRewardsData_ =
      new PreviewClaimableRewardsData[](nextRewardDrips_.length);
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_ = claimableRewardsIndices[reservePoolId_];
    UserRewardsData[] storage userRewards_ = userRewards[reservePoolId_][owner_];
    uint256 numUserRewardAssets_ = userRewards[reservePoolId_][owner_].length;

    for (uint16 i = 0; i < nextRewardDrips_.length; i++) {
      UndrippedRewardPool storage undrippedRewardPool_ = undrippedRewardPools[i];
      ClaimableRewardsData memory previewNextClaimableRewardsData_ = _previewNextClaimableRewardsData(
        claimableRewards_[i],
        _computeUnclaimedDrippedRewards(
          undrippedRewardPool_.cumulativeDrippedRewards + nextRewardDrips_[i].amount,
          claimableRewards_[i].cumulativeClaimedRewards,
          reservePool_.rewardsPoolsWeight
        ),
        totalStkTokenSupply_
      );
      claimableRewardsData_[i] = PreviewClaimableRewardsData({
        rewardPoolId: i,
        asset: nextRewardDrips_[i].rewardAsset,
        amount: i < numUserRewardAssets_
          ? _previewUpdateUserRewardsData(
            ownerStkTokenBalance_, previewNextClaimableRewardsData_.indexSnapshot, userRewards_[i]
          ).accruedRewards
          : _previewAddUserRewardsData(ownerStkTokenBalance_, previewNextClaimableRewardsData_.indexSnapshot).accruedRewards
      });
    }

    return PreviewClaimableRewards({reservePoolId: reservePoolId_, claimableRewardsData: claimableRewardsData_});
  }

  function _getNextDripAmount(uint256 totalBaseAmount_, IDripModel dripModel_, uint256 lastDripTime_, uint256 deltaT_)
    internal
    view
    override
    returns (uint256)
  {
    if (deltaT_ == 0) return 0;
    uint256 dripFactor_ = dripModel_.dripFactor(lastDripTime_, deltaT_);
    if (dripFactor_ > MathConstants.WAD) revert InvalidDripFactor();

    return _computeNextDripAmount(totalBaseAmount_, dripFactor_);
  }

  function _computeNextDripAmount(uint256 totalBaseAmount_, uint256 dripFactor_)
    internal
    pure
    override
    returns (uint256)
  {
    return totalBaseAmount_.mulWadDown(dripFactor_);
  }

  function applyPendingDrippedRewards_(
    ReservePool storage reservePool_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_
  ) internal override {
    uint256 numRewardAssets_ = undrippedRewardPools.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      UndrippedRewardPool storage undrippedRewardPool_ = undrippedRewardPools[i];
      claimableRewards_[i] = _previewNextClaimableRewardsData(
        claimableRewards_[i],
        _computeUnclaimedDrippedRewards(
          undrippedRewardPool_.cumulativeDrippedRewards,
          claimableRewards_[i].cumulativeClaimedRewards,
          reservePool_.rewardsPoolsWeight
        ),
        reservePool_.stkToken.totalSupply()
      );
    }
  }

  function _updateUserRewards(
    uint256 userStkTokenBalance_,
    mapping(uint16 => ClaimableRewardsData) storage claimableRewards_,
    UserRewardsData[] storage userRewards_
  ) internal override {
    uint256 numRewardAssets_ = undrippedRewardPools.length;
    uint256 numUserRewardAssets_ = userRewards_.length;
    for (uint16 i = 0; i < numRewardAssets_; i++) {
      if (i < numUserRewardAssets_) {
        userRewards_[i] =
          _previewUpdateUserRewardsData(userStkTokenBalance_, claimableRewards_[i].indexSnapshot, userRewards_[i]);
      } else {
        userRewards_.push(_previewAddUserRewardsData(userStkTokenBalance_, claimableRewards_[i].indexSnapshot));
      }
    }
  }

  function _previewUpdateUserRewardsData(
    uint256 userStkTokenBalance_,
    uint128 newIndexSnapshot_,
    UserRewardsData storage userRewardsData_
  ) internal view returns (UserRewardsData memory newUserRewardsData_) {
    newUserRewardsData_.accruedRewards = userRewardsData_.accruedRewards
      + _getUserAccruedRewards(userStkTokenBalance_, newIndexSnapshot_, userRewardsData_.indexSnapshot).safeCastTo128();
    newUserRewardsData_.indexSnapshot = newIndexSnapshot_;
  }

  function _previewAddUserRewardsData(uint256 userStkTokenBalance_, uint128 newIndexSnapshot_)
    internal
    pure
    returns (UserRewardsData memory newUserRewardsData_)
  {
    newUserRewardsData_.accruedRewards =
      _getUserAccruedRewards(userStkTokenBalance_, newIndexSnapshot_, 0).safeCastTo128();
    newUserRewardsData_.indexSnapshot = newIndexSnapshot_;
  }

  function _getUserAccruedRewards(uint256 stkTokenAmount_, uint128 newRewardPoolIndex, uint128 oldRewardPoolIndex)
    internal
    pure
    returns (uint256)
  {
    // Round down, in favor of leaving assets in the rewards pool.
    return stkTokenAmount_.mulWadDown(newRewardPoolIndex - oldRewardPoolIndex);
  }
}
