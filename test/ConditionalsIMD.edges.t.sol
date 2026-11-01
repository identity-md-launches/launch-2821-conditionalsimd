// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsIMD} from "../src/ConditionalsIMD.sol";

/// @notice Edge values and failure paths not covered by ConditionalsIMD.t.sol: the full supply,
/// one wei, the maximum allowance, the zero address on every side, owner-as-spender, approval
/// overwrite, value sent to the token, and fuzzed revert conditions.
contract ConditionalsIMDEdgesTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    ConditionalsIMD internal token;
    address internal deployer;
    address internal alice;
    address internal bob;
    address internal carol;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        deployer = makeAddr("deployer");
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        carol = makeAddr("carol");
        vm.prank(deployer);
        token = new ConditionalsIMD();
    }

    // ---------------------------------------------------------------- supply edges

    function test_supplyIsExactlyOneBillionWithEighteenDecimals() public view {
        assertEq(token.totalSupply(), 1_000_000_000_000_000_000_000_000_000);
        assertEq(token.totalSupply(), 1_000_000_000 * 10 ** uint256(token.decimals()));
        assertEq(token.balanceOf(deployer), token.totalSupply());
    }

    function test_twoDeploymentsAreIndependent() public {
        vm.prank(alice);
        ConditionalsIMD second = new ConditionalsIMD();
        assertEq(second.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_wholeSupplyTransfersInOneCall() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(deployer), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhen_TransferOneWeiMoreThanWholeSupply() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, SUPPLY + 1)
        );
        vm.prank(deployer);
        token.transfer(alice, SUPPLY + 1);
    }

    function test_RevertWhen_TransferMaxUint() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, deployer, SUPPLY, type(uint256).max)
        );
        vm.prank(deployer);
        token.transfer(alice, type(uint256).max);
    }

    function test_oneWeiTransfer() public {
        vm.prank(deployer);
        token.transfer(alice, 1);
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_RevertWhen_EmptyHolderSendsOneWei() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
    }

    function test_failedTransferChangesNothing() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeCall(token.transfer, (bob, 11)));
        assertFalse(ok);
        assertEq(token.balanceOf(alice), 10);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    // ---------------------------------------------------------------- the zero address

    function test_RevertWhen_ZeroAddressSends() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        vm.prank(address(0));
        token.transfer(alice, 0);
    }

    function test_RevertWhen_ZeroAddressApproves() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(address(0));
        token.approve(alice, 1);
    }

    function test_RevertWhen_TransferFromZeroAddressOwnerWithZeroAmount() public {
        // Zero allowance covers a zero amount; OZ v5 then re-writes the allowance for the zero owner,
        // and the approver check rejects it before any balance is touched.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(alice);
        token.transferFrom(address(0), bob, 0);
    }

    function test_RevertWhen_TransferFromZeroAddressOwnerWithAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(address(0), bob, 1);
    }

    function test_RevertWhen_TransferFromToZeroAddress() public {
        vm.prank(deployer);
        token.approve(alice, 5);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transferFrom(deployer, address(0), 5);
        assertEq(token.allowance(deployer, alice), 5, "a failed transferFrom spent the allowance");
    }

    function test_RevertWhen_TransferZeroAmountToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(deployer);
        token.transfer(address(0), 0);
    }

    // ---------------------------------------------------------------- allowances

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(deployer);
        token.approve(alice, 100);
        token.approve(alice, 30);
        vm.stopPrank();
        assertEq(token.allowance(deployer, alice), 30);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 30, 31));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 31);
    }

    function test_approveZeroRevokes() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(deployer, alice, 0);
        vm.prank(deployer);
        token.approve(alice, 0);
        assertEq(token.allowance(deployer, alice), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
    }

    function test_allowanceIsPerSpender() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        assertEq(token.allowance(deployer, bob), 0);
        assertEq(token.allowance(alice, deployer), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(deployer, bob, 1);
    }

    function test_RevertWhen_OwnerUsesTransferFromWithoutSelfAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, deployer, 0, 1));
        vm.prank(deployer);
        token.transferFrom(deployer, alice, 1);
    }

    function test_maxMinusOneAllowanceIsSpent() public {
        uint256 allowed = type(uint256).max - 1;
        vm.prank(deployer);
        token.approve(alice, allowed);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 7);
        assertEq(token.allowance(deployer, alice), allowed - 7);
    }

    function test_allowanceExhaustedExactly() public {
        vm.prank(deployer);
        token.approve(alice, 50);
        vm.prank(alice);
        token.transferFrom(deployer, bob, 50);
        assertEq(token.allowance(deployer, alice), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(deployer, bob, 1);
    }

    function test_allowanceLargerThanBalanceIsCappedByBalance() public {
        vm.prank(deployer);
        token.transfer(alice, 10);
        vm.prank(alice);
        token.approve(bob, 1_000);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 10, 11));
        vm.prank(bob);
        token.transferFrom(alice, carol, 11);
        assertEq(token.allowance(alice, bob), 1_000, "a failed transferFrom spent the allowance");
    }

    function test_transferFromEmitsTransferOnlyNoApproval() public {
        vm.prank(deployer);
        token.approve(alice, 100);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(deployer, bob, 40);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], Transfer.selector);
        assertEq(logs[0].topics[1], bytes32(uint256(uint160(deployer))));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(bob))));
        assertEq(abi.decode(logs[0].data, (uint256)), 40);
    }

    function test_transferFromToSelfKeepsBalanceButSpendsAllowance() public {
        vm.prank(deployer);
        token.transfer(alice, 100);
        vm.prank(alice);
        token.approve(bob, 60);
        vm.prank(bob);
        token.transferFrom(alice, alice, 60);
        assertEq(token.balanceOf(alice), 100);
        assertEq(token.allowance(alice, bob), 0);
    }

    function test_zeroAmountTransferFromNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(deployer, bob, 0);
        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 0));
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    // ---------------------------------------------------------------- calls the token does not have

    function test_RevertWhen_EtherSentToToken() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_RevertWhen_UnknownSelector() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("burn(uint256)", 1));
        assertFalse(ok);
        (ok,) = address(token).call(hex"deadbeef");
        assertFalse(ok);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevertWhen_ApproveSentWithValue() public {
        vm.deal(deployer, 1 ether);
        vm.prank(deployer);
        (bool ok,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (alice, 1)));
        assertFalse(ok, "non-payable function accepted ether");
    }

    // ---------------------------------------------------------------- fuzz

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferRevertsExactlyWhenOverBalance(uint256 held, uint256 amount) public {
        held = bound(held, 0, SUPPLY);
        vm.prank(deployer);
        token.transfer(alice, held);
        vm.prank(alice);
        if (amount > held) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, held, amount));
            token.transfer(bob, amount);
            assertEq(token.balanceOf(alice), held);
        } else {
            assertTrue(token.transfer(bob, amount));
            assertEq(token.balanceOf(alice), held - amount);
            assertEq(token.balanceOf(bob), amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_approveSetsAnyValue(address spender, uint256 amount) public {
        vm.prank(alice);
        if (spender == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
            token.approve(spender, amount);
        } else {
            vm.expectEmit(true, true, false, true, address(token));
            emit Approval(alice, spender, amount);
            assertTrue(token.approve(spender, amount));
            assertEq(token.allowance(alice, spender), amount);
        }
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotMoveAHolder(address stranger, uint256 amount) public {
        vm.assume(stranger != deployer);
        amount = bound(amount, 1, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        vm.prank(stranger);
        token.transferFrom(deployer, stranger, amount);
        assertEq(token.balanceOf(deployer), SUPPLY);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromSpendsAllowanceAndMovesExactly(uint256 allowed, uint256 amount, address to) public {
        vm.assume(to != address(0) && to != deployer);
        allowed = bound(allowed, 1, type(uint256).max);
        amount = bound(amount, 1, SUPPLY);
        vm.prank(deployer);
        token.approve(alice, allowed);
        uint256 toBefore = token.balanceOf(to);
        vm.prank(alice);
        if (amount > allowed) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, allowed, amount)
            );
            token.transferFrom(deployer, to, amount);
            assertEq(token.allowance(deployer, alice), allowed);
        } else {
            assertTrue(token.transferFrom(deployer, to, amount));
            assertEq(token.balanceOf(to), toBefore + amount);
            assertEq(token.balanceOf(deployer), SUPPLY - amount);
            assertEq(token.allowance(deployer, alice), allowed == type(uint256).max ? allowed : allowed - amount);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }
}
