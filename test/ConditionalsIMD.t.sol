// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsIMD} from "../src/ConditionalsIMD.sol";
import {DeployConditionalsIMD} from "../script/DeployConditionalsIMD.s.sol";

/// @dev Deploys the token with CREATE2 the way a launch factory does, so the supply lands on it.
contract FactoryLike {
    function deploy(bytes32 salt) external returns (ConditionalsIMD token) {
        token = new ConditionalsIMD{salt: salt}();
    }

    function move(IERC20 token, address to, uint256 amount) external returns (bool) {
        return token.transfer(to, amount);
    }
}

contract ConditionalsIMDTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    ConditionalsIMD internal token;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new ConditionalsIMD();
        assertTrue(token.transfer(ALICE, 1_000 ether));
    }

    // ---------------------------------------------------------------- deployment

    function test_metadata() public view {
        assertEq(token.name(), "ConditionalsIMD");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
        assertEq(token.TOTAL_SUPPLY(), SUPPLY);
    }

    function test_constructorMintsWholeSupplyToDeployer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        ConditionalsIMD fresh = new ConditionalsIMD();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), SUPPLY);
    }

    function test_create2FactoryReceivesWholeSupply() public {
        FactoryLike factory = new FactoryLike();
        ConditionalsIMD fresh = factory.deploy(bytes32(uint256(7)));
        assertEq(fresh.balanceOf(address(factory)), SUPPLY);
        assertEq(fresh.balanceOf(address(this)), 0);
        assertEq(fresh.totalSupply(), SUPPLY);
        // The factory's launch flows move exact amounts: no fee, no burn on transfer.
        assertTrue(factory.move(fresh, CAROL, SUPPLY / 10));
        assertEq(fresh.balanceOf(CAROL), SUPPLY / 10);
        assertEq(fresh.totalSupply(), SUPPLY);
    }

    function test_deployScriptDeploysToken() public {
        DeployConditionalsIMD script = new DeployConditionalsIMD();
        ConditionalsIMD deployed = script.deploy();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(address(script)), SUPPLY);
    }

    // ---------------------------------------------------------------- transfers

    function test_transferMovesExactAmount() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(ALICE, BOB, 400 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 400 ether));
        assertEq(token.balanceOf(ALICE), 600 ether);
        assertEq(token.balanceOf(BOB), 400 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(ALICE, 500 ether));
        assertEq(token.balanceOf(ALICE), 1_000 ether);
    }

    function test_zeroTransferSucceeds() public {
        vm.prank(BOB);
        assertTrue(token.transfer(ALICE, 0));
        assertEq(token.balanceOf(ALICE), 1_000 ether);
    }

    function test_RevertWhen_TransferExceedsBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1_000 ether, 1_001 ether)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 1_001 ether);
    }

    function test_RevertWhen_TransferToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transfer(address(0), 1 ether);
    }

    // ---------------------------------------------------------------- allowances

    function test_approveAndTransferFrom() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(ALICE, BOB, 300 ether);
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 300 ether));
        assertEq(token.allowance(ALICE, BOB), 300 ether);

        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 200 ether));
        assertEq(token.balanceOf(CAROL), 200 ether);
        assertEq(token.balanceOf(ALICE), 800 ether);
        assertEq(token.allowance(ALICE, BOB), 100 ether);
    }

    function test_infiniteAllowanceIsNotSpent() public {
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 1_000 ether);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max);
    }

    function test_RevertWhen_TransferFromWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 1 ether));
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1 ether);
    }

    function test_RevertWhen_TransferFromExceedsAllowance() public {
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 10 ether, 11 ether)
        );
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 11 ether);
    }

    function test_RevertWhen_TransferFromExceedsBalance() public {
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1_000 ether, 1_001 ether)
        );
        vm.prank(BOB);
        token.transferFrom(ALICE, BOB, 1_001 ether);
    }

    function test_RevertWhen_ApproveZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 1 ether);
    }

    // ---------------------------------------------------------------- no privileged powers

    function test_noMintOrAdminEntryPoints() public {
        string[14] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "owner()",
            "upgradeTo(address)",
            "initialize(address)",
            "pause()",
            "unpause()",
            "setMinter(address)",
            "blacklist(address)",
            "burnFrom(address,uint256)"
        ];
        address[2] memory callers = [address(this), BOB];
        for (uint256 c; c < callers.length; ++c) {
            for (uint256 i; i < signatures.length; ++i) {
                vm.prank(callers[c]);
                (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], BOB, type(uint128).max));
                assertFalse(ok, signatures[i]);
            }
        }
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.balanceOf(ALICE), 1_000 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 1 ether));
    }

    function test_runtimeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        bool reachable = true;
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += op - 0x5F;
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4 && op != 0xF2 && op != 0xFF, "forbidden opcode");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE) reachable = false;
        }
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != ALICE);
        amount = bound(amount, 0, 1_000 ether);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(ALICE);
        token.transfer(to, amount);
        assertEq(token.balanceOf(ALICE), 1_000 ether - amount);
        assertEq(token.balanceOf(to), toBefore + amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromSpendsAllowanceExactly(uint256 allowance_, uint256 amount) public {
        allowance_ = bound(allowance_, 0, type(uint256).max - 1);
        amount = bound(amount, 0, 1_000 ether);
        vm.prank(ALICE);
        token.approve(BOB, allowance_);
        vm.prank(BOB);
        if (amount > allowance_) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, allowance_, amount)
            );
            token.transferFrom(ALICE, CAROL, amount);
        } else {
            assertTrue(token.transferFrom(ALICE, CAROL, amount));
            assertEq(token.allowance(ALICE, BOB), allowance_ - amount);
            assertEq(token.balanceOf(CAROL), amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
