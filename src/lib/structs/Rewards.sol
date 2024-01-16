// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.22;

import {IERC20} from "../../interfaces/IERC20.sol";

struct UserRewardsData {
  uint128 accruedRewards;
  uint128 indexSnapshot;
}

struct ClaimableRewardsData {
  uint256 cumulativeDrippedRewards;
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
