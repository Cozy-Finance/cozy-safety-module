import {TestBase} from "./utils/TestBase.sol";
import {CozyRouter} from "../src/CozyRouter.sol";
import {IERC20} from "cozy-safety-module-shared/interfaces/IERC20.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {console2} from "forge-std/console2.sol";

contract BalancerPermitTest is TestBase {
  uint256 forkId;

  CozyRouter router = CozyRouter(payable(0xC58F8634E085243CC661b1623B3bC3224D80B439));
  address jacob = address(0x1216FB4fcde507DF25e17a6f1525fd41c19dc638);
  address balancerToken = address(0x3A2819B07981234F825E952f32Cf977db5EDBf7C);
  address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
  // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
  bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

  struct Permit {
    address owner;
    address spender;
    uint256 value;
    uint256 nonce;
    uint256 deadline;
  }

  function setUp() public {
    uint256 mainnetForkBlock = 20_233_653; // The mainnet block number one block prior to failed tx.
    forkId = vm.createSelectFork(vm.envString("ETH_RPC_URL"), mainnetForkBlock);

    vm.label(address(router), "CozyRouter");
    vm.label(jacob, "Jacob");
    vm.label(balancerToken, "BalancerToken");
  }

  // computes the hash of a permit
  function getStructHash(Permit memory permit_) internal pure returns (bytes32) {
    return keccak256(
      abi.encode(PERMIT_TYPEHASH, permit_.owner, permit_.spender, permit_.value, permit_.nonce, permit_.deadline)
    );
  }

  // computes the hash of the fully encoded EIP-712 message for the domain, which can be used to recover the signer
  function getTypedDataHash(Permit memory permit_, bytes32 domainSeparator_) public view returns (bytes32) {
    return keccak256(abi.encodePacked("\x19\x01", domainSeparator_, getStructHash(permit_)));
  }

  function test_usdcTx() public {
    (address alice, uint256 alicePk) = makeAddrAndKey("alice");
    address spender = address(router);
    uint256 deadline = block.timestamp + 1 days;
    uint256 amount = 1e18;

    Permit memory permit = Permit({owner: alice, spender: spender, value: amount, nonce: 0, deadline: deadline});
    bytes32 domainSeparator = ERC20(address(usdc)).DOMAIN_SEPARATOR();
    bytes32 digest = getTypedDataHash(permit, domainSeparator);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

    vm.startPrank(alice);
    router.permitRouter(IERC20(usdc), amount, deadline, v, r, s);
    vm.stopPrank();
  }

  function test_balancerTokenTx() public {
    (address alice, uint256 alicePk) = makeAddrAndKey("alice");
    address spender = address(router);
    uint256 deadline = block.timestamp + 1 days;
    uint256 amount = 1e18;

    Permit memory permit = Permit({owner: alice, spender: spender, value: amount, nonce: 0, deadline: deadline});
    bytes32 domainSeparator = ERC20(address(balancerToken)).DOMAIN_SEPARATOR();
    bytes32 digest = getTypedDataHash(permit, domainSeparator);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

    vm.startPrank(alice);
    router.permitRouter(IERC20(balancerToken), amount, deadline, v, r, s);
    vm.stopPrank();
  }
}
