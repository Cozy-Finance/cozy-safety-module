// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";

struct UserRewardsData {
  uint128 accruedRewards;
  uint128 indexSnapshot;
}

struct ClaimableRewardsData {
  /// @dev The cumulative amount of claimed rewards since the last weight change. On a call to `finalizeConfigUpdates`,
  /// if the associated config update changes the rewards weights, this value is reset to 0.
  uint256 cumulativeClaimedRewards;
  uint128 indexSnapshot;
}

struct PreviewClaimableRewards {
  uint16 reservePoolId;
  PreviewClaimableRewardsData[] claimableRewardsData;
}

struct PreviewClaimableRewardsData {
  uint16 rewardPoolId;
  uint256 amount;
  IERC20 asset;
}
