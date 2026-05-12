# Infinite Drive — software upgrade `infinite_v0.2.x_to_v0.3.0`


## Scope

This release line (**Infinite Drive v0.3.0**) aligns the codebase with **Cosmos EVM v0.7.0**, including its dependency stack, modules, and operational notes.

The upstream migration guide ([Cosmos EVM v0.6.x → v0.7.0](./v0.6.x_to_v0.7.0.md)) contains the detailed technical information on the key implementations (Krakatoa, BlockSTM, store migrations, etc.).

This document provides the **official governance plan**, validator configuration requirements, and all chain-specific operational steps required exclusively for the Infinite Drive chain.

## On-chain plan name

Copy the following string **exactly** (verbatim) into `MsgSoftwareUpgrade` proposals:

```text
infinite_v0.2.x_to_v0.3.0
```

Registered in code as `UpgradeNameInfiniteV02xToV030` and **`UpgradeName`** in [`infinited/upgrades.go`](../../infinited/upgrades.go). The system test [`tests/systemtests/chainupgrade/v0_2_0_to_v0_3_0.go`](../../tests/systemtests/chainupgrade/v0_2_0_to_v0_3_0.go) uses the same string.

## What the handler does

- **`SetUpgradeHandler`:** runs `ModuleManager.RunMigrations`.
- **`UpgradeStoreLoader`:** no new mountable store keys are added for this plan versus fork **v0.2.x**; Hyperlane stores were introduced under the earlier plan `infinite-v0.1.10-to-v0.2.0`.

## Required Configuration Update for Each Validator Node
⚠️ Each validator must set mempool.type = "app" in config.toml.

```text
[mempool]
type = "app"
```

The default is "flood"; Krakatoa errors out at startup if it's left as the default. This one-line change must be applied at the same time as the binary upgrade.

## Plan Upgrade Process

- A governance proposal is submitted with the exact plan name and target block height.
- Validators review and vote on the proposal.
- Once the proposal passes, the chain continues normally until the defined upgrade height.
- At the upgrade height the chain halts.
- Validators replace the `infinited` binary, apply the required change in their `config.toml`, and restart the node.

## References

- Upstream migration: [v0.6.x → v0.7.0](./v0.6.x_to_v0.7.0.md)
- Previous fork upgrade: [infinite_v0.1.10_to_v0.2.0.md](./infinite_v0.1.10_to_v0.2.0.md)
- System test / Makefile: [`tests/systemtests/README.md`](../../tests/systemtests/README.md), root `Makefile` (`SYSTEMTEST_LEGACY_TAG`, `build-legacy-systemtest-binary`)
