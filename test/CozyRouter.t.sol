// SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.22;

import {CozyRouter} from "../src/CozyRouter.sol";
import {SafetyModule} from "../src/SafetyModule.sol";
import {MathConstants} from "../src/lib/MathConstants.sol";
import {Ownable} from "../src/lib/Ownable.sol";
import {TriggerState} from "../src/lib/SafetyModuleStates.sol";
import {
  ReservePoolConfig,
  TriggerConfig,
  UndrippedRewardPoolConfig,
  UpdateConfigsCalldataParams
} from "../src/lib/structs/Configs.sol";
import {Delays} from "../src/lib/structs/Delays.sol";
import {ReservePool, UndrippedRewardPool} from "../src/lib/structs/Pools.sol";
import {IERC20} from "../src/interfaces/IERC20.sol";
import {IDripModel} from "../src/interfaces/IDripModel.sol";
import {IOwnableTriggerFactory} from "../src/interfaces/IOwnableTriggerFactory.sol";
import {ISafetyModule} from "../src/interfaces/ISafetyModule.sol";
import {IStETH} from "../src/interfaces/IStETH.sol";
import {ITrigger} from "../src/interfaces/ITrigger.sol";
import {IUMATriggerFactory} from "../src/interfaces/IUMATriggerFactory.sol";
import {IWeth} from "../src/interfaces/IWeth.sol";
import {IWstETH} from "../src/interfaces/IWstETH.sol";
import {MockConnector} from "./utils/MockConnector.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {MockDeployProtocol} from "./utils/MockDeployProtocol.sol";
import {MockDripModel} from "./utils/MockDripModel.sol";
import {MockTrigger} from "./utils/MockTrigger.sol";

abstract contract CozyRouterTestSetup is MockDeployProtocol {
  CozyRouter router;
  ISafetyModule safetyModule;
  IStETH stEth;
  IWstETH wstEth;
  IOwnableTriggerFactory ownableTriggerFactory;
  IUMATriggerFactory umaTriggerFactory;

  IERC20 reserveAssetA = IERC20(address(new MockERC20("Mock Reserve Asset", "MOCKRES", 6)));
  IERC20 rewardAssetA = IERC20(address(new MockERC20("Mock Reward Asset", "MOCKREW", 6)));
  ITrigger trigger = ITrigger(new MockTrigger(TriggerState.ACTIVE));

  address alice = address(0xABCD);
  address bob = address(0xDCBA);
  address self = address(this);

  // For calculating the per-second decay/drip rate, we use the exponential decay formula A = P * (1 - r) ^ t
  // where A is final amount, P is principal (starting) amount, r is the per-second decay rate, and t is the number of
  // elapsed seconds.
  // For example, for an annual decay rate of 25%:
  // A = P * (1 - r) ^ t
  // 0.75 = 1 * (1 - r) ^ 31557600
  // -r = 0.75^(1/31557600) - 1
  // -r = -9.116094732822280932149636651070655494101566187385032e-9
  // Multiplying r by -1e18 to calculate the scaled up per-second value required by decay/drip model constructors ~=
  // 9116094774
  uint256 constant DECAY_RATE_PER_SECOND = 9_116_094_774; // Per-second decay rate of 25% annually.

  uint16 wethReservePoolId;
  uint16 wethRewardPoolId;

  /// @dev Emitted by ERC20s when `amount` tokens are moved from `from` to `to`.
  event Transfer(address indexed from, address indexed to, uint256 amount);

  function setUp() public virtual override {
    super.setUp();

    ReservePoolConfig[] memory reservePoolConfigs_ = new ReservePoolConfig[](2);
    reservePoolConfigs_[0] = ReservePoolConfig({
      maxSlashPercentage: 0,
      asset: reserveAssetA,
      rewardsPoolsWeight: uint16(MathConstants.ZOC) / 2
    });
    reservePoolConfigs_[1] = ReservePoolConfig({
      maxSlashPercentage: 0,
      asset: IERC20(address(weth)),
      rewardsPoolsWeight: uint16(MathConstants.ZOC) / 2
    });
    wethReservePoolId = 1;

    UndrippedRewardPoolConfig[] memory undrippedRewardPoolConfigs_ = new UndrippedRewardPoolConfig[](2);
    undrippedRewardPoolConfigs_[0] = UndrippedRewardPoolConfig({
      asset: rewardAssetA,
      dripModel: IDripModel(address(new MockDripModel(DECAY_RATE_PER_SECOND)))
    });
    undrippedRewardPoolConfigs_[1] = UndrippedRewardPoolConfig({
      asset: IERC20(address(weth)),
      dripModel: IDripModel(address(new MockDripModel(DECAY_RATE_PER_SECOND)))
    });
    wethRewardPoolId = 1;

    Delays memory delaysConfig_ =
      Delays({unstakeDelay: 2 days, withdrawDelay: 2 days, configUpdateDelay: 15 days, configUpdateGracePeriod: 1 days});

    TriggerConfig[] memory triggerConfig_ = new TriggerConfig[](1);
    triggerConfig_[0] = TriggerConfig({trigger: trigger, payoutHandler: _randomAddress(), exists: true});

    safetyModule = ISafetyModule(
      address(
        SafetyModule(
          address(
            manager.createSafetyModule(
              self,
              self,
              UpdateConfigsCalldataParams({
                reservePoolConfigs: reservePoolConfigs_,
                undrippedRewardPoolConfigs: undrippedRewardPoolConfigs_,
                triggerConfigUpdates: triggerConfig_,
                delaysConfig: delaysConfig_
              }),
              _randomBytes32()
            )
          )
        )
      )
    );

    router = new CozyRouter(manager, weth, stEth, wstEth, ownableTriggerFactory, umaTriggerFactory);
  }
}

// TODO Why does this test hang?
// contract CozyRouterAggregateTest is CozyRouterTestSetup {
//   // TODO This just a single example of how the router might be used. We should have more tests of this behavior.
//   function testFuzz_BatchesCalls(uint88 amount_) public {
//     vm.assume(amount_ > 100);
//     uint256 ethAmount_ = uint256(amount_);
//     deal(address(this), ethAmount_);

//     bytes[] memory calls_ = new bytes[](2);
//     uint256 reservePoolId_ = 1; // The weth reserve pool ID.

//     calls_[0] = abi.encodeWithSelector(bytes4(keccak256(bytes("wrapWeth(address)"))), (address(safetyModule)));
//     calls_[1] = abi.encodeWithSelector(
//       router.depositReserveAssetsWithoutTransfer.selector, address(safetyModule), reservePoolId_, ethAmount_,
// address(this), ethAmount_
//     );

//     router.aggregate{value: ethAmount_}(calls_);

//     ReservePool memory reservePoolB_ = getReservePool(safetyModule, reservePoolId_);

//     assertEq(reservePoolB_.depositToken.balanceOf(address(this)), ethAmount_);
//     assertEq(weth.balanceOf(address(safetyModule)), ethAmount_);
//     assertEq(weth.balanceOf(address(router)), 0);
//     assertEq(address(router).balance, 0);
//     assertEq(address(this).balance, 0);
//   }

//   function test_RevertsWithFailureData() public {}
//   function test_SweepEthUsingAggregate() public {
//     // Sweep ETH out by wrapping ETH and sending to router then unwrapping to recipient.
//   }
// }

// Abstract test contract base with some helpers for
// manipulating WEth token balance in the Router.
abstract contract CozyWEthHelperTest is CozyRouterTestSetup {
  function dealAndDepositEth(uint128 _amount) public {
    vm.startPrank(address(router));
    vm.deal(address(router), _amount);
    weth.deposit{value: _amount}();
    assertEq(weth.balanceOf(address(router)), _amount);
    vm.stopPrank();
  }
}

contract CozyRouterPermitTest is CozyRouterTestSetup {
  bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  function computeDomainSeparator(IERC20 _token) public view returns (bytes32) {
    return keccak256(
      abi.encode(
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
        keccak256(bytes(_token.name())),
        keccak256("1"),
        block.chainid,
        address(_token)
      )
    );
  }

  function _testPermitIERC20Token(IERC20 token_, uint256 privateKey_, uint256 amount_, uint256 deadline_) internal {
    address _owner = vm.addr(privateKey_);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      privateKey_,
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          computeDomainSeparator(token_),
          keccak256(abi.encode(PERMIT_TYPEHASH, _owner, address(router), amount_, 0, deadline_))
        )
      )
    );

    vm.prank(_owner);
    router.permitRouter(token_, amount_, deadline_, v, r, s);

    assertEq(token_.allowance(_owner, address(router)), amount_);
    assertEq(token_.nonces(_owner), 1);
  }

  // TODO: Implement 2612 and dai permit tests.
  // USDC uses ERC-2612 for permit, DAI uses a slightly different format, but we this method should work for both.
  function test_PermitsErc2612() public {}
  function test_PermitsDai() public {}

  function test_PermitRouterDepositAndStakeTokens(uint248 privKey, uint256 amount, uint256 deadline) public {
    uint256 privateKey = privKey;
    if (deadline < block.timestamp) deadline = block.timestamp;
    if (privateKey == 0) privateKey = 1;

    ReservePool memory reservePool_ = getReservePool(safetyModule, 0);
    IERC20 depositToken_ = reservePool_.depositToken;
    IERC20 stakeToken_ = reservePool_.stkToken;

    _testPermitIERC20Token(depositToken_, privateKey, amount, deadline);
    _testPermitIERC20Token(stakeToken_, privateKey, amount, deadline);
  }
}

contract CozyRouterPullTokenTest is CozyRouterTestSetup {
  error InvalidAddress();

  function test_PullsTokensToRecipient() public {
    deal(address(reserveAssetA), self, 100e6);
    address recipient_ = makeAddr("recipient");
    reserveAssetA.approve(address(router), type(uint256).max);

    router.pullToken(reserveAssetA, recipient_, 25e6);
    assertEq(reserveAssetA.balanceOf(self), 75e6);
    assertEq(reserveAssetA.balanceOf(recipient_), 25e6);

    router.pullToken(reserveAssetA, recipient_, 75e6);
    assertEq(reserveAssetA.balanceOf(self), 0);
    assertEq(reserveAssetA.balanceOf(recipient_), 100e6);
  }

  function testFuzz_PullsTokensToRecipient(uint128 amount_) public {
    uint256 initBal_ = type(uint128).max;
    deal(address(reserveAssetA), self, initBal_);
    address recipient_ = makeAddr("recipient");
    reserveAssetA.approve(address(router), type(uint256).max);

    router.pullToken(reserveAssetA, recipient_, amount_);
    assertEq(reserveAssetA.balanceOf(self), initBal_ - amount_);
    assertEq(reserveAssetA.balanceOf(recipient_), amount_);
  }

  function test_RevertsWhenRecipientIsZeroAddress() public {
    vm.expectRevert(InvalidAddress.selector);
    router.pullToken(reserveAssetA, address(0), 1);
  }
}

contract CozyRouterSweepTokenTest is CozyWEthHelperTest {
  function test_SweepToken() public {
    testFuzz_SweepToken(5, 10);
  }

  function testFuzz_SweepToken(uint128 amountMin_, uint128 routerBalance_) public {
    amountMin_ = uint128(bound(amountMin_, 0, type(uint128).max));
    routerBalance_ = uint128(bound(routerBalance_, amountMin_, type(uint128).max));
    dealAndDepositEth(routerBalance_);
    router.sweepToken(IERC20(address(weth)), address(alice), amountMin_);
    assertEq(weth.balanceOf(address(alice)), routerBalance_);
    assertEq(weth.balanceOf(address(router)), 0);
  }

  function test_AmountMinIsRespected() public {
    testFuzz_AmountMinIsRespected(10, 5);
  }

  function testFuzz_AmountMinIsRespected(uint128 amountMin_, uint128 invalidBalance_) public {
    amountMin_ = uint128(bound(amountMin_, 1, type(uint128).max));
    invalidBalance_ = uint128(bound(invalidBalance_, 0, amountMin_ - 1));
    dealAndDepositEth(invalidBalance_);
    vm.expectRevert(CozyRouter.InsufficientBalance.selector);
    router.sweepToken(IERC20(address(weth)), address(alice), amountMin_);
  }

  function test_SweepTokenRevertsIfZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.sweepToken(IERC20(address(weth)), address(0), 10);
  }
}

contract CozyRouterTransferTokensTest is CozyWEthHelperTest {
  function test_TransferTokens() public {
    testFuzz_TransferTokens(5, 10);
  }

  function testFuzz_TransferTokens(uint128 _amount, uint128 _routerBalance) public {
    _amount = uint128(bound(_amount, 0, type(uint128).max));
    _routerBalance = uint128(bound(_routerBalance, _amount, type(uint128).max));
    dealAndDepositEth(_routerBalance);
    router.transferTokens(IERC20(address(weth)), address(alice), _amount);
    assertEq(weth.balanceOf(address(alice)), _amount);
    assertEq(weth.balanceOf(address(router)), _routerBalance - _amount);
  }

  function test_TransferTokensRevertsIfRecipientIsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.transferTokens(IERC20(address(weth)), address(0), 10);
  }
}

contract CozyRouterWrapStEthSetup is CozyRouterTestSetup {
  uint256 forkId;

  function setUp() public virtual override {
    super.setUp();

    uint256 mainnetForkBlock = 15_770_305; // The mainnet block number at the time this test was written.
    forkId = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), mainnetForkBlock);

    stEth = IStETH(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    vm.label(address(stEth), "stETH");
    wstEth = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    vm.label(address(wstEth), "wstETH");

    // We need to redeploy the router because it's not on mainnet.
    router = new CozyRouter(manager, weth, stEth, wstEth, ownableTriggerFactory, umaTriggerFactory);

    // Rather than redeploying *all* of Cozy Safety Module on mainnet for this fork test, we can get by with just this
    // mock safety module.
    safetyModule = ISafetyModule(address(0xBEEF));
    vm.mockCall(address(manager), abi.encodeWithSelector(manager.isSafetyModule.selector), abi.encode(true));
  }
}

contract CozyRouterWrapStEthTest is CozyRouterWrapStEthSetup {
  function testFork_WrapStEth1() public {
    _testWrapStEth(type(uint256).max, false);
  }

  function testFork_WrapStEth2() public {
    _testWrapStEth(100 ether, false);
  }

  function testFork_WrapStEth3() public {
    _testWrapStEth(20 ether, true);
  }

  function testFork_WrapStEthWithAmount1() public {
    _testWrapStEthWithAmount(10 ether, type(uint256).max, false);
  }

  function testFork_WrapStEthWithAmount2() public {
    _testWrapStEthWithAmount(10 ether, 10 ether, false);
  }

  function testFork_WrapStEthWithAmount3() public {
    _testWrapStEthWithAmount(10 ether, 20 ether, false);
  }

  function testFork_WrapStEthWithAmount4() public {
    _testWrapStEthWithAmount(10 ether, 2 ether, true);
  }

  function test_wstETHConstructorStEThAllowance() public {
    assertEq(stEth.allowance(address(router), address(router.wstEth())), type(uint256).max);
  }

  function test_WrapStEthRevertsIfRecipientIsNotValidSafetyModule() public {
    vm.mockCall(address(manager), abi.encodeWithSelector(manager.isSafetyModule.selector), abi.encode(false));

    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.wrapStEth(address(0));

    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.wrapStEth(address(0), 10);
  }

  function _testWrapStEth(uint256 approvalAmount_, bool shouldRevert_) public {
    // deal(stETh, address, uint) won't work here because stETH is a proxy and deal isn't able to correctly infer the
    // storage location of the balance it needs to update.
    deal(address(this), 100 ether);
    stEth.submit{value: 100 ether}(address(42)); // Get some stETH.
    uint256 initStEthBalance_ = stEth.balanceOf(address(this));

    stEth.approve(address(router), approvalAmount_);

    if (shouldRevert_) vm.expectRevert();
    router.wrapStEth(address(safetyModule));
    if (shouldRevert_) return ();

    assertApproxEqAbs(wstEth.balanceOf(address(safetyModule)), stEth.getSharesByPooledEth(initStEthBalance_), 1);
  }

  function _testWrapStEthWithAmount(uint256 amount_, uint256 approvalAmount_, bool shouldRevert_) public {
    // deal(stETh, address, uint) won't work here because stETH is a proxy and deal isn't able to correctly infer the
    // storage location of the balance it needs to update.
    deal(address(this), 100 ether);
    stEth.submit{value: 100 ether}(address(42)); // Get some stETH.

    stEth.approve(address(router), approvalAmount_);
    if (shouldRevert_) vm.expectRevert();
    router.wrapStEth(address(safetyModule), amount_);
    if (shouldRevert_) return;

    uint256 wstEthAmount_ = stEth.getSharesByPooledEth(amount_);
    assertApproxEqAbs(wstEth.balanceOf(address(safetyModule)), wstEthAmount_, 1);
  }
}

contract CozyRouterUnwrapStEthTest is CozyRouterWrapStEthSetup {
  function testFork_UnwrapStEth() public {
    uint256 wstETHAmount_ = 100 ether;
    deal(address(wstEth), address(router), wstETHAmount_);
    uint256 stETHAmount_ = stEth.getPooledEthByShares(wstETHAmount_);
    uint256 initBalance_ = stEth.balanceOf(address(this));

    router.unwrapStEth(address(this));

    assertApproxEqAbs(stEth.balanceOf(address(this)), initBalance_ + stETHAmount_, 1);
  }

  function test_UnwrapStEthRevertsIfRecipientIsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.unwrapStEth(address(0));
  }
}

contract CozyRouterWrapWethTest is CozyRouterTestSetup {
  function test_wrapWethAllEthHeldByRouter() public {
    uint256 ethAmount_ = 1 ether;
    deal(address(router), ethAmount_); // Simulate sending eth to the router before wrapWeth.

    vm.prank(alice);
    _expectEmit();
    emit Transfer(address(router), address(safetyModule), ethAmount_);
    router.wrapWeth(address(safetyModule));
    assertEq(address(router).balance, 0);
    assertEq(weth.balanceOf(address(router)), 0);
    assertEq(weth.balanceOf(address(safetyModule)), ethAmount_);
  }

  function test_wrapWethSomeEthHeldByRouter() public {
    uint256 ethAmount_ = 1 ether;
    deal(address(router), ethAmount_); // Simulate sending eth to the router before wrapWeth.

    vm.prank(alice);
    _expectEmit();
    emit Transfer(address(router), address(safetyModule), ethAmount_ / 2);
    router.wrapWeth(address(safetyModule), ethAmount_ / 2);
    assertEq(address(router).balance, ethAmount_ / 2);
    assertEq(weth.balanceOf(address(router)), 0);
    assertEq(weth.balanceOf(address(safetyModule)), ethAmount_ / 2);
  }

  function test_WrapsWethRevertsIfRecipientIsNotValidSafetyModule() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.wrapWeth(_randomAddress());

    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.wrapWeth(_randomAddress(), 10);
  }
}

contract CozyRouterUnwrapWethTest is CozyWEthHelperTest {
  function test_UnwrapsWeth() public {
    testFuzz_UnwrapsWeth(10 ether, 1 ether);
  }

  function testFuzz_UnwrapsWeth(uint128 depositAmount_, uint128 withdrawAmount_) public {
    dealAndDepositEth(depositAmount_);
    withdrawAmount_ = uint128(bound(withdrawAmount_, 0, depositAmount_));

    router.unwrapWeth(address(alice), withdrawAmount_);
    assertEq(weth.balanceOf(address(router)), depositAmount_ - withdrawAmount_);
    assertEq(alice.balance, withdrawAmount_);
  }

  function test_UnwrapsMaxWeth() public {
    testFuzz_UnwrapsMaxWeth(1 ether);
  }

  function testFuzz_UnwrapsMaxWeth(uint128 amount_) public {
    dealAndDepositEth(amount_);

    router.unwrapWeth(address(alice));
    assertEq(weth.balanceOf(address(router)), 0);
    assertEq(alice.balance, amount_);
  }

  function test_RespectsAmount() public {}
  function test_RespectsRecipient() public {}

  function test_UnwrapsWethRevertsIfRecipientIsZeroAddress() public {
    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.unwrapWeth(address(0));

    vm.expectRevert(Ownable.InvalidAddress.selector);
    router.unwrapWeth(address(0), 10);
  }
}

contract CozyRouterDepositTest is CozyRouterTestSetup {
  function _depositAssets(
    bool isReserveDeposit_,
    ISafetyModule safetyModule_,
    uint16 poolId_,
    address user_,
    uint256 assets_
  ) internal {
    vm.startPrank(user_);

    // Mint some WETH.
    vm.deal(user_, assets_);
    weth.deposit{value: assets_}();
    weth.approve(address(router), assets_);

    // Deposit WETH via the router.
    uint256 shares = isReserveDeposit_
      ? router.depositReserveAssets(safetyModule_, poolId_, assets_, user_, assets_)
      : router.depositRewardAssets(safetyModule_, poolId_, assets_, user_, assets_);

    vm.stopPrank();

    assertEq(weth.balanceOf(address(safetyModule_)), assets_);
    if (isReserveDeposit_) {
      ReservePool memory reservePool_ = getReservePool(safetyModule_, poolId_);
      assertEq(reservePool_.depositToken.balanceOf(user_), shares);
      assertEq(reservePool_.depositAmount, assets_);
    } else {
      UndrippedRewardPool memory undrippedRewardPool_ = getUndrippedRewardPool(safetyModule_, poolId_);
      assertEq(undrippedRewardPool_.depositToken.balanceOf(user_), shares);
      assertEq(undrippedRewardPool_.amount, assets_);
    }
  }

  function _depositReserveAssetsRevertsIfRecipientIsZeroAddress(
    bool isReserveDeposit_,
    ISafetyModule safetyModule_,
    uint16 poolId_
  ) internal {
    vm.startPrank(address(0xBEEF));

    // Deal some weth
    vm.deal(address(0xBEEF), 10);
    weth.deposit{value: 10}();
    weth.approve(address(router), 10);
    vm.expectRevert(Ownable.InvalidAddress.selector);

    if (isReserveDeposit_) router.depositReserveAssets(safetyModule_, poolId_, 10, address(0), 10);
    else router.depositRewardAssets(safetyModule_, poolId_, 10, address(0), 10);

    vm.stopPrank();

    vm.expectRevert(Ownable.InvalidAddress.selector);
    if (isReserveDeposit_) router.depositReserveAssetsWithoutTransfer(safetyModule_, poolId_, 10, address(0), 10);
    else router.depositRewardAssetsWithoutTransfer(safetyModule_, poolId_, 10, address(0), 10);
  }

  function testFuzz_DepositReserveAssets(address user_, uint256 assets_) public {
    vm.assume(user_ != address(0));
    vm.assume(user_ != address(safetyModule));
    assets_ = bound(assets_, 1, type(uint96).max);

    _depositAssets(true, safetyModule, wethReservePoolId, user_, assets_);
  }

  function testFuzz_DepositRewardAssets(address user_, uint256 assets_) public {
    vm.assume(user_ != address(0));
    vm.assume(user_ != address(safetyModule));
    assets_ = bound(assets_, 1, type(uint96).max);

    _depositAssets(false, safetyModule, wethRewardPoolId, user_, assets_);
  }

  function test_DepositReserveAssetsRevertsIfRecipientIsZeroAddress() public {
    _depositReserveAssetsRevertsIfRecipientIsZeroAddress(true, safetyModule, wethReservePoolId);
  }

  function test_DepositRewardAssetsRevertsIfRecipientIsZeroAddress() public {
    _depositReserveAssetsRevertsIfRecipientIsZeroAddress(false, safetyModule, wethRewardPoolId);
  }
}

contract CozyRouterConnectorSetup is CozyRouterTestSetup {
  MockConnector mockConnector;
  // MockERC20 wrappedAsset;
  MockERC20 baseAsset = new MockERC20("Mock Base Asset", "MOCKBASE", 6);

  function setUp() public override {
    super.setUp();
  }
}

contract CozyRouterWrapBaseAssetViaConnectorAndDepositTest is CozyRouterConnectorSetup {
  function _testWrapBaseAssetViaConnectorForDeposit(
    bool isReserveDeposit_,
    MockConnector connector_,
    ISafetyModule safetyModule_,
    uint16 poolId_,
    uint256 wrappedAssetDepositAmount_,
    uint256 baseAssetsNeeded_,
    address owner_
  ) internal {
    // Deal owner sufficient base assets to make purchase.
    deal(address(mockConnector.baseAsset()), owner_, baseAssetsNeeded_, true);

    vm.startPrank(owner_);
    // Owner has to approve the router to transfer the base assets.
    mockConnector.baseAsset().approve(address(router), baseAssetsNeeded_);
    uint256 ownerShares_ = isReserveDeposit_
      ? router.wrapBaseAssetViaConnectorAndDepositReserveAssets(
        connector_, safetyModule_, poolId_, baseAssetsNeeded_, owner_, 0
      )
      : router.wrapBaseAssetViaConnectorAndDepositRewardAssets(
        connector_, safetyModule_, poolId_, baseAssetsNeeded_, owner_, 0
      );
    vm.stopPrank();

    // All base assets needed should have been transferred away from Owner.
    assertEq(mockConnector.baseAsset().balanceOf(owner_), 0);
    // Wrapped assets should have been transferred to safety module.
    assertEq(mockConnector.wrappedAsset().balanceOf(address(safetyModule_)), wrappedAssetDepositAmount_);

    // Owner should have proper number of deposit tokens.
    IERC20 depositToken_ = isReserveDeposit_
      ? getReservePool(safetyModule, poolId_).depositToken
      : getUndrippedRewardPool(safetyModule, poolId_).depositToken;
    assertEq(depositToken_.balanceOf(owner_), ownerShares_);
    assertEq(depositToken_.balanceOf(owner_), wrappedAssetDepositAmount_); // 1:1 exchange rate for initial deposit.
  }

  function _testWrapBaseAssetViaConnectorForDepositSlippage(
    bool isReserveDeposit_,
    MockConnector connector_,
    ISafetyModule safetyModule_,
    uint16 poolId_,
    uint256 wrappedAssetDepositAmount_,
    uint256 baseAssetsNeeded_,
    address owner_
  ) internal {
    // Deal owner sufficient base assets to make purchase.
    deal(address(mockConnector.baseAsset()), owner_, baseAssetsNeeded_, true);

    vm.startPrank(owner_);
    // Owner has to approve the router to transfer the base assets.
    mockConnector.baseAsset().approve(address(router), baseAssetsNeeded_);
    // Should revert because assets_ < minSharesReceived_.
    vm.expectRevert(CozyRouter.SlippageExceeded.selector);
    uint256 minSharesReceived_ = wrappedAssetDepositAmount_ + 1;
    if (isReserveDeposit_) {
      router.wrapBaseAssetViaConnectorAndDepositReserveAssets(
        connector_, safetyModule_, poolId_, baseAssetsNeeded_, owner_, minSharesReceived_
      );
    } else {
      router.wrapBaseAssetViaConnectorAndDepositRewardAssets(
        connector_, safetyModule_, poolId_, baseAssetsNeeded_, owner_, minSharesReceived_
      );
    }
    vm.stopPrank();
  }

  function test_wrapBaseAssetViaConnectorForReserveDeposit() public {
    mockConnector = new MockConnector(MockERC20(address(baseAsset)), MockERC20(address(reserveAssetA)));
    uint256 wrappedAssetDepositAmount_ = 500;
    uint256 baseAssetsNeeded_ = 250; // assetsNeeded_ / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)
    _testWrapBaseAssetViaConnectorForDeposit(
      true, mockConnector, safetyModule, 0, wrappedAssetDepositAmount_, baseAssetsNeeded_, alice
    );
  }

  function test_wrapBaseAssetViaConnectorForRewardDeposit() public {
    mockConnector = new MockConnector(MockERC20(address(baseAsset)), MockERC20(address(rewardAssetA)));
    uint256 wrappedAssetDepositAmount_ = 500;
    uint256 baseAssetsNeeded_ = 250; // assetsNeeded_ / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)
    _testWrapBaseAssetViaConnectorForDeposit(
      false, mockConnector, safetyModule, 0, wrappedAssetDepositAmount_, baseAssetsNeeded_, alice
    );
  }

  function test_WrapBaseAssetViaConnectorForReserveDepositSharesLowerThanMinSharesReceived() public {
    mockConnector = new MockConnector(MockERC20(address(baseAsset)), MockERC20(address(reserveAssetA)));
    uint256 wrappedAssetDepositAmount_ = 500;
    uint256 baseAssetsNeeded_ = 250; // assetsNeeded_ / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)
    _testWrapBaseAssetViaConnectorForDepositSlippage(
      true, mockConnector, safetyModule, 0, wrappedAssetDepositAmount_, baseAssetsNeeded_, alice
    );
  }

  function test_WrapBaseAssetViaConnectorForRewardDepositSharesLowerThanMinSharesReceived() public {
    mockConnector = new MockConnector(MockERC20(address(baseAsset)), MockERC20(address(rewardAssetA)));
    uint256 wrappedAssetDepositAmount_ = 500;
    uint256 baseAssetsNeeded_ = 250; // assetsNeeded_ / assetToWrappedAssetRate = 500 / 2 = 250 (no rounding)
    _testWrapBaseAssetViaConnectorForDepositSlippage(
      false, mockConnector, safetyModule, 0, wrappedAssetDepositAmount_, baseAssetsNeeded_, alice
    );
  }
}
