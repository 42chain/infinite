// Los subdirectorios bank/, bech32/, … replican la estructura de evmd/tests/integration/precompiles/ en cosmos/evm.
//
// Infinite fork: los wrappers finos llaman a github.com/cosmos/evm/tests/integration/precompiles/* con
// integration.CreateEvmd. La red de integración (testutil/integration/evm/network) prefunde también el
// denom extendido (atest*) cuando difiere del denom nativo (utest, …), porque BankWrapper / ante cobran gas en ese denom.
// Las suites compartidas pueden omitir comprobaciones de delta de saldo en cadenas 6/12 dec (werc20) donde la vista
// gRPC del denom entero no coincide con la vista EVM unificada en subunidades extendidas.
//
// Paridad de árbol: infinite-handbook/scripts/merge-upstream/compare_infinited_upstream_evmd.py.
package precompiles
