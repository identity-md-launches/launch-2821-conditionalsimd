// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ConditionalsIMD} from "../src/ConditionalsIMD.sol";

/// @dev Drives the token with random, bounded calls from a fixed set of actors and keeps an
/// independent ledger (ghost balances and allowances) of what the token should report.
/// Calls that must fail are made too, and the handler checks they revert and change nothing.
contract CondHandler is Test {
    ConditionalsIMD public immutable token;
    address[] public actors;

    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    uint256 public calls;
    uint256 public successfulMoves;
    uint256 public expectedReverts;
    /// @dev Set if a call that must revert succeeded, or a call that must succeed reverted.
    bool public unexpected;

    constructor(ConditionalsIMD token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i; i < actors_.length; ++i) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ------------------------------------------------------------ valid operations

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        ++calls;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok) unexpected = true;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++successfulMoves;
        } catch {
            unexpected = true;
        }
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        ++calls;
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        // Mix exact edge values in with random ones.
        uint256 pick = amount % 4;
        if (pick == 0) amount = type(uint256).max;
        else if (pick == 1) amount = 0;
        else amount = bound(amount, 0, 1_000_000_000 ether);
        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            if (!ok) unexpected = true;
            ghostAllowance[owner][spender] = amount;
        } catch {
            unexpected = true;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        ++calls;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        amount = bound(amount, 0, cap);
        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!ok) unexpected = true;
            if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
            ghostBalance[from] -= amount;
            ghostBalance[to] += amount;
            ++successfulMoves;
        } catch {
            unexpected = true;
        }
    }

    // ------------------------------------------------------------ operations that must fail

    function transferMoreThanBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        ++calls;
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 bal = ghostBalance[from];
        uint256 amount = bal + bound(excess, 1, type(uint256).max - bal);
        vm.prank(from);
        try token.transfer(to, amount) {
            unexpected = true;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, bal, amount)
                    )
            ) unexpected = true;
            ++expectedReverts;
        }
    }

    function transferFromOverAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        ++calls;
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return; // an infinite allowance cannot be exceeded
        uint256 amount = allowed + bound(excess, 1, type(uint256).max - allowed);
        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            unexpected = true;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(
                            IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount
                        )
                    )
            ) unexpected = true;
            ++expectedReverts;
        }
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        ++calls;
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);
        vm.prank(from);
        try token.transfer(address(0), amount) {
            unexpected = true;
        } catch {
            ++expectedReverts;
        }
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        ++calls;
        vm.prank(_actor(ownerSeed));
        try token.approve(address(0), amount) {
            unexpected = true;
        } catch {
            ++expectedReverts;
        }
    }

    /// @dev Tries the usual privileged entry points from a random actor (the deployer included).
    /// None exists, so every one must revert and nothing may change.
    function tryPrivileged(uint256 callerSeed, uint256 sigSeed, uint256 amount) external {
        ++calls;
        string[8] memory sigs = [
            "mint(address,uint256)",
            "burn(uint256)",
            "burnFrom(address,uint256)",
            "transferOwnership(address)",
            "pause()",
            "blacklist(address)",
            "freeze(address)",
            "seize(address)"
        ];
        address caller = _actor(callerSeed);
        address victim = _actor(callerSeed >> 8);
        bytes memory data = abi.encodeWithSignature(sigs[sigSeed % sigs.length], victim, amount);
        vm.prank(caller);
        (bool ok,) = address(token).call(data);
        if (ok) unexpected = true;
        else ++expectedReverts;
    }
}

/// @notice Invariants for ConditionalsIMD over random call sequences: the supply is fixed, it is
/// fully accounted for by the holders, every balance and allowance matches an independent ledger,
/// and no call path can mint, burn or move a holder's tokens without the holder's consent.
contract ConditionalsIMDInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    ConditionalsIMD internal token;
    CondHandler internal handler;
    address[] internal actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        token = new ConditionalsIMD();

        actors.push(deployer);
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        handler = new CondHandler(token, actors);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](8);
        selectors[0] = CondHandler.transfer.selector;
        selectors[1] = CondHandler.approve.selector;
        selectors[2] = CondHandler.transferFrom.selector;
        selectors[3] = CondHandler.transferMoreThanBalance.selector;
        selectors[4] = CondHandler.transferFromOverAllowance.selector;
        selectors[5] = CondHandler.transferToZero.selector;
        selectors[6] = CondHandler.approveZeroSpender.selector;
        selectors[7] = CondHandler.tryPrivileged.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_totalSupplyNeverChanges() public view {
        assertEq(token.totalSupply(), SUPPLY);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_holdersAccountForWholeSupply() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, SUPPLY, "tokens appeared or vanished outside the actors");
        assertEq(token.balanceOf(address(0)), 0, "tokens reached the zero address");
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_balancesAndAllowancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "balance drifted");
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance drifted"
                );
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_noUnexpectedOutcome() public view {
        assertFalse(handler.unexpected(), "a call that must fail succeeded, or one that must succeed failed");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_metadataIsFixed() public view {
        assertEq(token.name(), "ConditionalsIMD");
        assertEq(token.symbol(), "COND");
        assertEq(token.decimals(), 18);
    }

    /// @dev Guards against a vacuous campaign: the handler was actually exercised.
    function test_handlerIsReachable() public {
        handler.transfer(0, 1, 5 ether);
        handler.approve(1, 2, 2);
        handler.transferFrom(2, 1, 3, 1 ether);
        handler.transferMoreThanBalance(1, 2, 1);
        handler.transferFromOverAllowance(2, 1, 3, 1);
        handler.transferToZero(1, 1);
        handler.approveZeroSpender(1, 1);
        handler.tryPrivileged(0, 0, 1);
        assertFalse(handler.unexpected());
        assertEq(handler.successfulMoves(), 2);
        assertEq(handler.expectedReverts(), 5);
        invariant_balancesAndAllowancesMatchLedger();
        invariant_holdersAccountForWholeSupply();
    }
}
