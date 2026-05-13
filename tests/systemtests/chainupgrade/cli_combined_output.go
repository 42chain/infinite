//go:build system_test

package chainupgrade

import (
	"regexp"
	"strings"
	"testing"

	systest "github.com/cosmos/cosmos-sdk/tools/systemtests"
	"github.com/stretchr/testify/require"
	"github.com/tidwall/gjson"
)

// stripLeadingNoiseBeforeJSON drops stderr lines that precede JSON when CLIWrapper uses
// exec.Command.CombinedOutput() (duplicate proto registration, etc.).
func stripLeadingNoiseBeforeJSON(s string) string {
	s = strings.TrimSpace(s)
	for i := 0; i < len(s); i++ {
		if s[i] == '{' || s[i] == '[' {
			return strings.TrimSpace(s[i:])
		}
	}
	return s
}

// parseKeysShowAddress returns the account bech32 address line from `keys show -a` output.
func parseKeysShowAddress(out string) string {
	re := regexp.MustCompile(`^[a-z]+1[qpzry9x8gf2tvdw0s3jn54khce6mua7l]{20,}$`)
	var last string
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(line)
		if re.MatchString(line) {
			last = line
		}
	}
	return last
}

// awaitTxCommittedWithStrip mirrors systemtests.CLIWrapper.AwaitTxCommitted but sanitizes
// CombinedOutput before RequireTxSuccess / gjson (needed for query tx results too).
func awaitTxCommittedWithStrip(t *testing.T, cli *systest.CLIWrapper, sut *systest.SystemUnderTest, submitResp string) (string, bool) {
	t.Helper()
	clean := stripLeadingNoiseBeforeJSON(submitResp)
	systest.RequireTxSuccess(t, clean)
	txHash := gjson.Get(clean, "txhash")
	require.True(t, txHash.Exists())
	var txResult string
	for range 3 {
		txResult = cli.WithRunErrorsIgnored().CustomQuery("q", "tx", txHash.String())
		txResult = stripLeadingNoiseBeforeJSON(txResult)
		if code := gjson.Get(txResult, "code"); code.Exists() {
			if code.Int() != 0 {
				t.Logf("+++ got error response code: %s\n", txResult)
			}
			return txResult, true
		}
		sut.AwaitNextBlock(t)
	}
	return "", false
}
