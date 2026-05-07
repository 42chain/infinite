package evmd

import (
	"context"
<<<<<<< HEAD:infinited/upgrades.go

	storetypes "cosmossdk.io/store/types"
	hyperlanetypes "github.com/bcp-innovations/hyperlane-cosmos/x/core/types"
	warptypes "github.com/bcp-innovations/hyperlane-cosmos/x/warp/types"
=======
>>>>>>> v0.7.0:evmd/upgrades.go

	storetypes "github.com/cosmos/cosmos-sdk/store/v2/types"
	sdk "github.com/cosmos/cosmos-sdk/types"
	"github.com/cosmos/cosmos-sdk/types/module"
	upgradetypes "github.com/cosmos/cosmos-sdk/x/upgrade/types"
)

<<<<<<< HEAD:infinited/upgrades.go
// UpgradeName is the software-upgrade plan name for Infinite Drive: use in governance
// (MsgSoftwareUpgrade) and in TestChainUpgrade (tests/systemtests/chainupgrade/v0_1_10_to_v0_2_0.go).
const UpgradeName = "infinite-v0.1.10-to-v0.2.0"
=======
// UpgradeName defines the on-chain upgrade name for the sample EVMD upgrade
// from v0.6.0 to v0.7.0.
//
// NOTE: This upgrade defines a reference implementation of what an upgrade
// could look like when an application is migrating from EVMD version
// v0.6.x to v0.7.0.
const UpgradeName = "v0.6.0-to-v0.7.0"
>>>>>>> v0.7.0:evmd/upgrades.go

func (app EVMD) RegisterUpgradeHandlers() {
	app.UpgradeKeeper.SetUpgradeHandler(
		UpgradeName,
		func(ctx context.Context, _ upgradetypes.Plan, fromVM module.VersionMap) (module.VersionMap, error) {
			sdkCtx := sdk.UnwrapSDKContext(ctx)
			sdkCtx.Logger().Debug("this is a debug level message to test that verbose logging mode has properly been enabled during a chain upgrade")
			return app.ModuleManager.RunMigrations(ctx, app.Configurator(), fromVM)
		},
	)

	upgradeInfo, err := app.UpgradeKeeper.ReadUpgradeInfoFromDisk()
	if err != nil {
		panic(err)
	}

	if upgradeInfo.Name == UpgradeName && !app.UpgradeKeeper.IsSkipHeight(upgradeInfo.Height) {
		storeUpgrades := storetypes.StoreUpgrades{
			Added: []string{
				hyperlanetypes.ModuleName,
				warptypes.ModuleName,
			},
		}
		app.SetStoreLoader(upgradetypes.UpgradeStoreLoader(upgradeInfo.Height, &storeUpgrades))
	}
}
