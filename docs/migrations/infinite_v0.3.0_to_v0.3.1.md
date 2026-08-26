# Infinite Drive — software upgrade `infinite_v0.3.0_to_v0.3.1`

## Scope

This release line (**Infinite Drive v0.3.1**) integrates the **Cosmos EVM v0.7.2** security patch on top of the v0.3.0 line (upstream base **v0.7.0**). The upstream release notes describe this patch as **state-breaking** and recommend a coordinated software upgrade.

There is **no** upstream migration document for `v0.7.0 → v0.7.2`; see the [Cosmos EVM v0.7.2 release](https://github.com/cosmos/evm/releases/tag/v0.7.2) and CHANGELOG entries for **v0.7.1** and **v0.7.2** (StateDB balance hardening, mempool base-fee rejection, IBC v2 ack validation).

This document provides the **official governance plan**, validator steps, and fork-specific notes for Infinite Drive.

## On-chain plan name

Copy the following string **exactly** (verbatim) into `MsgSoftwareUpgrade` proposals:

```text
infinite_v0.3.0_to_v0.3.1
```

Registered in code as `UpgradeNameInfiniteV030ToV031` and **`UpgradeName`** in [`infinited/upgrades.go`](../../infinited/upgrades.go). The system test [`tests/systemtests/chainupgrade/v0_3_0_to_v0_3_1.go`](../../tests/systemtests/chainupgrade/v0_3_0_to_v0_3_1.go) uses the same string.

## What the handler does

- **`SetUpgradeHandler`:** runs `ModuleManager.RunMigrations`.
- **`UpgradeStoreLoader`:** not used — no new mountable store keys versus **v0.3.0**. Hyperlane stores were added under the historical plan `infinite-v0.1.10-to-v0.2.0`.

## Required configuration (validators already on v0.3.0)

No **new** `config.toml` changes versus v0.3.0. Keep:

```text
[mempool]
type = "app"
```

Operators upgrading from **v0.3.0** already applied this when moving from v0.2.x (see [`infinite_v0.2.x_to_v0.3.0.md`](./infinite_v0.2.x_to_v0.3.0.md)).

## Plan upgrade process

- Submit a governance proposal with the exact plan name and target block height.
- Validators vote; once passed, the chain continues until the upgrade height.
- At the upgrade height the chain halts.
- Validators replace the `infinited` binary with **v0.3.1** and restart (same data dir and keys).

## References

- Previous fork upgrade: [`infinite_v0.2.x_to_v0.3.0.md`](./infinite_v0.2.x_to_v0.3.0.md)
- Upstream base for v0.3.0: [`v0.6.x_to_v0.7.0.md`](./v0.6.x_to_v0.7.0.md)
- System test: [`tests/systemtests/README.md`](../../tests/systemtests/README.md), `infinite-handbook` **CHAIN_UPGRADE_SYSTEM_TEST.md**, root `Makefile` (`SYSTEMTEST_LEGACY_TAG=v0.3.0`)
