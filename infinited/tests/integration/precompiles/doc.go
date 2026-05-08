// Los subdirectorios bank/, bech32/, … replican la estructura de evmd/tests/integration/precompiles/ en cosmos/evm.
//
// Infinite fork: en upstream v0.7.0 existen además diez ficheros precompile_*_test.go (wrappers finos que
// llaman a github.com/cosmos/evm/tests/integration/precompiles/* con integration.CreateEvmd). No están
// copiados aquí todavía porque las suites compartidas bajo el módulo raíz tests/integration/precompiles/
// tienen expectativas de cantidades/denoms que difieren del fork (p. ej. 18 decimales, x/bank Infinite).
// Tras alinear esas expectativas o segregar constantes de test, portar los wrappers desde el tag upstream
// documentado en la bitácora de merge. Paridad de árbol: infinite-handbook/scripts/merge-upstream/compare_infinited_upstream_evmd.py.
package precompiles
