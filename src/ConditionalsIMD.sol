// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ConditionalsIMD (COND)
/// @notice Fixed-supply ERC-20. The whole supply of 1,000,000,000 COND (18 decimals) is minted
/// exactly once, in the constructor, to the deployer (`msg.sender`). There is no owner, no minter,
/// no pause, no blacklist, no fee and no upgrade path: after construction the supply can never grow,
/// and only a holder (or a spender the holder approved) can move that holder's tokens.
contract ConditionalsIMD is ERC20 {
    /// @notice Token name returned by `name()`.
    string public constant TOKEN_NAME = "ConditionalsIMD";
    /// @notice Token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "COND";
    /// @notice Whole supply in minor units: 1,000,000,000 * 10**18.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
