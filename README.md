# ConditionalsIMD (COND)

A fixed-supply ERC-20 token for an IMD custom-token launch on Ethereum (chain id 1).

| Property        | Value                                                     |
| --------------- | --------------------------------------------------------- |
| Solidity name   | `ConditionalsIMD` (`src/ConditionalsIMD.sol`)             |
| `name()`        | `ConditionalsIMD`                                         |
| `symbol()`      | `COND`                                                    |
| `decimals()`    | `18`                                                      |
| `totalSupply()` | `1000000000000000000000000000` (1,000,000,000 × 10^18)   |
| Constructor     | no arguments                                              |

## Behaviour

- The constructor mints the whole supply, once, to `msg.sender`. On the launch that is the
  launch factory, which pays all of it out (swarm share to the MerkleDistributor, the pool seed,
  and the requester's remainder).
- There is no other mint path, so the supply can never grow.
- It is a standard OpenZeppelin v5.4.0 `ERC20` with no fees, burns, taxes or hooks on transfer.
  Every transfer moves exactly the amount requested, so the factory, distributor and Uniswap v4
  PoolManager flows arrive whole. That is why the token needs no exemption list and no launch
  addresses as constructor arguments.
- There is no owner and no admin: no pause, blacklist, freeze, seize, `burnFrom`, upgrade or proxy.
  Only a holder, or a spender the holder approved through `approve`/`transferFrom`, can move a
  holder's tokens.
- The runtime contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`, and the token calls no
  external libraries.

## Deployment parameters

- No constructor arguments. The launch manifest's `token.constructorArgs` is empty.
- `token.totalSupply` = `1000000000000000000000000000`, `token.decimals` = `18`.
- Compiler: solc `0.8.26`, optimizer on (200 runs), EVM `cancun`, `bytecode_hash = "none"`
  (all pinned in `foundry.toml`).
- No application contracts are deployed with this token.
- The launch policy sets the pool (IMD pair, fee 12500, tick spacing 60) and the economics.
  The manifest step copies them into `launch.json`. This repository has no `launch.json`, on purpose.

## After launch

There is nothing to configure. The token has no owner-settable values and no outside addresses.

## Assumptions and operational responsibilities

- IMD's deployer deploys the token through the launch factory. This repository does not deploy,
  broadcast or hold keys. `script/DeployConditionalsIMD.s.sol` is a reference deployment for local
  or test networks only.
- Once the factory has distributed the supply, nobody has any control over the token. There are no
  privileged operations to run, monitor or hand to a multisig.
- Listings, explorer source verification and any off-chain metadata (logo, website) are the
  requester's to handle after the launch.
- Tests passing is not a security audit. The token is unmodified, widely reviewed OpenZeppelin
  code with no custom transfer logic, but an independent review is still advised before any
  further contracts are built on it.

## Development

Dependencies are vendored as plain files in `lib/`: forge-std v1.11.0 and OpenZeppelin Contracts
v5.4.0 (only `contracts/` is kept).

```sh
forge build
forge test
forge fmt --check
```

The tests (`test/ConditionalsIMD.t.sol`) cover the metadata, minting the whole supply to the
deployer (including a CREATE2 factory deployer), exact transfers and allowances, the revert cases
(insufficient balance or allowance, zero receiver or spender), the absence of any mint or admin
entry point, a runtime opcode scan, and fuzz tests of supply conservation and allowance accounting.
