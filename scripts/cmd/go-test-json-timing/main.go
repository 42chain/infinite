// Command go-test-json-timing reads go test -json lines from stdin and prints a column-aligned
// table of each completed test (PASS / FAIL / SKIP) with elapsed time; on FAIL it prints
// captured output for that test after the table. Package-level noise and non-JSON lines are ignored
// but counted in the summary. Optional -log <basename> writes the same stdout report to logs/<name>.log.
// With -tee (default true), each stdin line is echoed live to stderr so you see the raw stream while tests run.
package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"text/tabwriter"
)

type event struct {
	Action  string  `json:"Action"`
	Package string  `json:"Package"`
	Test    string  `json:"Test"`
	Elapsed float64 `json:"Elapsed"`
	Output  string  `json:"Output"`
}

type testResult struct {
	status  string
	elapsed float64
	pkg     string
	test    string
	failOut string
}

type filterStats struct {
	blankLines      int
	nonJSONLines    int
	jsonNoTest      int // valid JSON with empty Test (package-level events, etc.)
	jsonOtherAction int // Test set but action not pass/fail/skip/output-to-buffer (e.g. run, pause)
}

var safeLogPattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`)

func main() {
	logName := flag.String("log", "", "basename only: write the same stdout report to logs/<name>.log under the current directory (omit for stdin-only use)")
	tee := flag.Bool("tee", true, "echo each stdin line to stderr as it arrives (raw go test -json stream); set false for report-only stdout")
	flag.Parse()

	var buf strings.Builder
	if err := run(os.Stdin, &buf, *tee, os.Stderr); err != nil {
		fmt.Fprintf(os.Stderr, "go-test-json-timing: %v\n", err)
		os.Exit(1)
	}
	data := buf.String()
	if _, err := io.WriteString(os.Stdout, data); err != nil {
		fmt.Fprintf(os.Stderr, "go-test-json-timing: write stdout: %v\n", err)
		os.Exit(1)
	}
	if err := writeTimingLog(*logName, data); err != nil {
		fmt.Fprintf(os.Stderr, "go-test-json-timing: %v\n", err)
		os.Exit(1)
	}
}

func writeTimingLog(name, content string) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil
	}
	if !safeLogPattern.MatchString(name) {
		return fmt.Errorf("invalid -log %q (use letters, digits, ._- only; no path separators)", name)
	}
	dir := "logs"
	if err := os.MkdirAll(dir, 0750); err != nil {
		return fmt.Errorf("create logs dir: %w", err)
	}
	path := filepath.Join(dir, name+".log")
	if err := os.WriteFile(path, []byte(content), 0644); err != nil {
		return fmt.Errorf("write %s: %w", path, err)
	}
	return nil
}

func run(in io.Reader, out io.Writer, tee bool, teeOut io.Writer) error {
	type bufKey struct {
		pkg  string
		test string
	}
	outBuf := make(map[bufKey]*strings.Builder)

	sc := bufio.NewScanner(in)
	sc.Buffer(make([]byte, 64*1024), 1024*1024)

	var nPass, nFail, nSkip int
	var results []testResult
	var st filterStats

	for sc.Scan() {
		raw := sc.Text()
		if tee && teeOut != nil {
			if _, err := fmt.Fprintln(teeOut, raw); err != nil {
				return err
			}
		}

		line := strings.TrimSpace(raw)
		if line == "" {
			st.blankLines++
			continue
		}

		var ev event
		if err := json.Unmarshal([]byte(line), &ev); err != nil {
			st.nonJSONLines++
			continue
		}

		if ev.Action == "output" && ev.Test != "" {
			k := bufKey{pkg: ev.Package, test: ev.Test}
			b := outBuf[k]
			if b == nil {
				b = &strings.Builder{}
				outBuf[k] = b
			}
			b.WriteString(ev.Output)
			continue
		}

		if ev.Test == "" {
			st.jsonNoTest++
			continue
		}

		k := bufKey{pkg: ev.Package, test: ev.Test}
		switch ev.Action {
		case "pass":
			results = append(results, testResult{status: "PASS", elapsed: ev.Elapsed, pkg: ev.Package, test: ev.Test})
			delete(outBuf, k)
			nPass++
		case "skip":
			results = append(results, testResult{status: "SKIP", elapsed: ev.Elapsed, pkg: ev.Package, test: ev.Test})
			delete(outBuf, k)
			nSkip++
		case "fail":
			tr := testResult{status: "FAIL", elapsed: ev.Elapsed, pkg: ev.Package, test: ev.Test}
			if b := outBuf[k]; b != nil && b.Len() > 0 {
				tr.failOut = b.String()
			}
			results = append(results, tr)
			delete(outBuf, k)
			nFail++
		default:
			st.jsonOtherAction++
			continue
		}
	}
	if err := sc.Err(); err != nil {
		return err
	}

	if len(results) > 0 {
		tw := tabwriter.NewWriter(out, 0, 0, 2, ' ', 0)
		_, _ = fmt.Fprintln(tw, "STATUS\tSECONDS\tPACKAGE\tTEST")
		for _, r := range results {
			_, _ = fmt.Fprintf(tw, "%s\t%s\t%s\t%s\n", r.status, formatSeconds(r.elapsed), r.pkg, r.test)
		}
		if err := tw.Flush(); err != nil {
			return err
		}

		for _, r := range results {
			if r.status != "FAIL" || r.failOut == "" {
				continue
			}
			_, _ = fmt.Fprintf(out, "\n---- %s / %s ----\n", r.pkg, r.test)
			_, _ = out.Write([]byte(indentBlock(r.failOut, "  ")))
		}
	}

	writeSummary(out, nPass, nFail, nSkip, st)
	return nil
}

func writeSummary(out io.Writer, pass, fail, skip int, st filterStats) {
	_, _ = fmt.Fprintf(out, "\n--- summary ---\n")
	_, _ = fmt.Fprintf(out, "Tests finished: %d passed, %d failed, %d skipped (each row in the table above is one named test).\n",
		pass, fail, skip)
	_, _ = fmt.Fprintf(out, "Not shown as table rows (counts only): %d empty lines; %d lines not in test-result form "+
		"(e.g. compiler or stderr text mixed into the stream); %d package-level messages without a test name "+
		"(e.g. whole-package skip or “no test files”); %d per-test lifecycle lines before pass/fail "+
		"(e.g. run/start — informational only).\n",
		st.blankLines, st.nonJSONLines, st.jsonNoTest, st.jsonOtherAction)
	_, _ = fmt.Fprintf(out, "--- end summary ---\n")
}

// formatSeconds fixes the time column width so STATUS and SECONDS do not visually merge.
func formatSeconds(sec float64) string {
	return fmt.Sprintf("%10s", fmt.Sprintf("%.3fs", sec))
}

func indentBlock(s, prefix string) string {
	if s == "" {
		return ""
	}
	var b strings.Builder
	for _, line := range strings.Split(strings.TrimSuffix(s, "\n"), "\n") {
		b.WriteString(prefix)
		b.WriteString(line)
		b.WriteByte('\n')
	}
	return b.String()
}
