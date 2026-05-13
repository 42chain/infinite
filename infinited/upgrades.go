// Infinite fork: governance MsgSoftwareUpgrade names and Hyperlane store loaders differ from upstream
// evmd/upgrades.go at merged tags; compare via infinite-handbook/scripts/merge-upstream/compare_infinited_upstream_evmd.py.
package evmd

import (
	"context"
	hyperlanetypes "github.com/bcp-innovations/hyperlane-cosmos/x/core/types"
	warptypes "github.com/bcp-innovations/hyperlane-cosmos/x/warp/types"

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/module"
	upgradetypes "github.com/cosmos/cosmos-sdk/x/upgrade/types"
)

const (
	// UpgradeNameInfiniteV0110ToV020 is the historical software-upgrade plan (chain replay / nodes
	// catching up through that height). MsgSoftwareUpgrade name must match exactly.
	UpgradeNameInfiniteV0110ToV020 = "infinite-v0.1.10-to-v0.2.0"

	// UpgradeNameInfiniteV02xToV030 is the active plan for operators moving from fork line v0.2.x
	// to v0.3.0 (cosmos-evm base aligned with upstream v0.7.0). Use in governance and TestChainUpgrade.
	UpgradeNameInfiniteV02xToV030 = "infinite_v0.2.x_to_v0.3.0"

	// UpgradeName is the current governance-facing plan string (same as UpgradeNameInfiniteV02xToV030).
	// Historical plan UpgradeNameInfiniteV0110ToV020 remains registered for state replay.
	UpgradeName = UpgradeNameInfiniteV02xToV030
)

func (app EVMD) RegisterUpgradeHandlers() {
	upgradeHandler := func(ctx context.Context, _ upgradetypes.Plan, fromVM module.VersionMap) (module.VersionMap, error) {
		sdkCtx := sdk.UnwrapSDKContext(ctx)
		sdkCtx.Logger().Debug("this is a debug level message to test that verbose logging mode has properly been enabled during a chain upgrade")
		return app.ModuleManager.RunMigrations(ctx, app.Configurator(), fromVM)
	}

	app.UpgradeKeeper.SetUpgradeHandler(UpgradeNameInfiniteV0110ToV020, upgradeHandler)
	app.UpgradeKeeper.SetUpgradeHandler(UpgradeNameInfiniteV02xToV030, upgradeHandler)

	upgradeInfo, err := app.UpgradeKeeper.ReadUpgradeInfoFromDisk()
	if err != nil {
		panic(err)
	}

	if upgradeInfo.Name == UpgradeNameInfiniteV0110ToV020 && !app.UpgradeKeeper.IsSkipHeight(upgradeInfo.Height) {
		storeUpgrades := storetypes.StoreUpgrades{
			Added: []string{
				hyperlanetypes.ModuleName,
				warptypes.ModuleName,
			},
		}
		app.SetStoreLoader(upgradetypes.UpgradeStoreLoader(upgradeInfo.Height, &storeUpgrades))
	}
	// UpgradeNameInfiniteV02xToV030: no new KVStoreKey mounts vs fork v0.2.x; only RunMigrations in the handler.
}
