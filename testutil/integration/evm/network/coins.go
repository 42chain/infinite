// Infinite fork (integration test network): cuando ExampleChainCoinInfo usa Denom distinto de ExtendedDenom
// (p. ej. utest + atest), el ante y BankWrapper de x/vm debitan gas/msg.value en el denom extendido; hay que
// prefundear ese denom en genesis además del nativo o MsgEthereumTx falla con insufficient funds. Ver WithChainID en config.go.
package network

import (
	testconstants "github.com/cosmos/evm/testutil/constants"
	evmtypes "github.com/cosmos/evm/x/vm/types"
)

type CoinInfo struct {
	Denom    string
	Decimals evmtypes.Decimals
}

// ChainCoins information for the coins required from the chian to operate:
// - baseCoin: represents the base coin used to pay gas fees and staking in the
// Cosmos context.
// - evmCoin: represents the evm coin used to pay Ethereum
// transactions fees.
type ChainCoins struct {
	// TODO: not sure if this is an overkill. Do we want to customize the
	// decimals of the base denom? Maybe not..
	baseCoin *CoinInfo
	evmCoin  *CoinInfo
	// Infinite fork: denom extendido del VM (contabilidad en subunidades de 18 dec) cuando difiere del denom
	// nativo EVM; createBalances debe incluirlo en DenomDecimalsMap para que el valor económico coincida con upstream.
	extendedPrefundDenom string
}

// DefaultChainCoins returns the default values used for the ChainCoins in which
// base and evm denom are the same.
func DefaultChainCoins() ChainCoins {
	baseCoinInfo := testconstants.ExampleChainCoinInfo[defaultChain]

	// baseCoin is used for both base and evm coin as default..
	baseCoin := getCoinInfo(baseCoinInfo)
	evmCoin := getCoinInfo(baseCoinInfo)

	return ChainCoins{
		baseCoin: &baseCoin,
		evmCoin:  &evmCoin,
	}
}

func getCoinInfo(coinInfo evmtypes.EvmCoinInfo) CoinInfo {
	return CoinInfo{
		Denom:    coinInfo.Denom,
		Decimals: evmtypes.Decimals(coinInfo.Decimals),
	}
}

func (cc ChainCoins) BaseCoin() CoinInfo {
	return *cc.baseCoin
}

func (cc ChainCoins) EVMCoin() CoinInfo {
	return *cc.evmCoin
}

func (cc ChainCoins) BaseDenom() string {
	return cc.baseCoin.Denom
}

func (cc ChainCoins) EVMDenom() string {
	return cc.evmCoin.Denom
}

func (cc ChainCoins) BaseDecimals() evmtypes.Decimals {
	return cc.baseCoin.Decimals
}

func (cc ChainCoins) EVMDecimals() evmtypes.Decimals {
	return cc.evmCoin.Decimals
}

func (cc ChainCoins) IsBaseEqualToEVM() bool {
	return cc.BaseDenom() == cc.EVMDenom()
}

// DenomDecimalsMap returns a map of unique Denom -> Decimals for the chain
// coins.
func (cc ChainCoins) DenomDecimalsMap() map[string]evmtypes.Decimals {
	chainDenomDecimals := map[string]evmtypes.Decimals{
		cc.BaseDenom(): cc.BaseDecimals(),
	}

	// Insert the evm denom if base and evm denom are different.
	if !cc.IsBaseEqualToEVM() {
		chainDenomDecimals[cc.EVMDenom()] = cc.EVMDecimals()
	}
	// Infinite fork: mismo valor nominal que el prefund nativo, expresado en 18 dec para ExtendedDenom.
	if cc.extendedPrefundDenom != "" {
		if _, ok := chainDenomDecimals[cc.extendedPrefundDenom]; !ok {
			chainDenomDecimals[cc.extendedPrefundDenom] = evmtypes.EighteenDecimals
		}
	}
	return chainDenomDecimals
}
