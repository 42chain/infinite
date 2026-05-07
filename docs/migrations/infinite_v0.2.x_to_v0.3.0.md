# Infinite Drive — software upgrade `infinite_v0.2.x_to_v0.3.0`

## Scope

This release line (**Infinite Drive v0.3.0**) incorporates the codebase alignment with **Cosmos EVM / `cosmos-evm` tag `v0.7.0`** (dependency stack, modules, and operational notes). The detailed technical migration for that upstream line is documented here:

- [Cosmos EVM v0.6.x → v0.7.0](./v0.6.x_to_v0.7.0.md)

Read that guide end-to-end for Krakatoa, BlockSTM, store migrations, and coordination expectations. This document only records **fork-specific** governance and wiring.

## On-chain plan name (exact string)

Use verbatim in `MsgSoftwareUpgrade` proposals:

```text
infinite_v0.2.x_to_v0.3.0
```

Registered in code as `UpgradeNameInfiniteV02xToV030` and **`UpgradeName`** in [`infinited/upgrades.go`](../../infinited/upgrades.go). The system test [`tests/systemtests/chainupgrade/v0_2_0_to_v0_3_0.go`](../../tests/systemtests/chainupgrade/v0_2_0_to_v0_3_0.go) uses the same string.

## What the handler does

- **`SetUpgradeHandler`:** runs `ModuleManager.RunMigrations` (same pattern as the historical plan).
- **`UpgradeStoreLoader`:** no new mountable store keys are added for this plan versus fork **v0.2.x**; Hyperlane stores were introduced under the earlier plan `infinite-v0.1.10-to-v0.2.0`.

## Historical plan (replay)

The plan **`infinite-v0.1.10-to-v0.2.0`** remains registered for nodes syncing through that upgrade height. See [infinite_v0.1.10_to_v0.2.0.md](./infinite_v0.1.10_to_v0.2.0.md).

## References

- Upstream migration: [v0.6.x → v0.7.0](./v0.6.x_to_v0.7.0.md)
- Previous fork upgrade: [infinite_v0.1.10_to_v0.2.0.md](./infinite_v0.1.10_to_v0.2.0.md)
- System test / Makefile: [`tests/systemtests/README.md`](../../tests/systemtests/README.md), root `Makefile` (`SYSTEMTEST_LEGACY_TAG`, `build-legacy-systemtest-binary`)
