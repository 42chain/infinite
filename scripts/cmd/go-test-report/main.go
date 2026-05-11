// Command go-test-report reads go test -json lines from stdin and prints an enriched report:
// optional banner, per-test table (PASS/FAIL/SKIP + elapsed), package-level outcomes, captured FAIL output,
// and a summary. Same invocation recipe as test-unit-cover-* when Makefile pipes coverage-enabled go test -json here.
// Flags only (no environment variables). Optional -jsonl-out preserves the raw JSON stream for debugging.
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
	"time"
)

type event struct {
	Action  string  `json:"Action"`
	Package string  `json:"Package"`
	Test    string  `json:"Test"`
	Elapsed float64 `json:"Elapsed"`
	Output  string  `json:"Output"`
	Time    string  `json:"Time"` // RFC3339 from go test -json; used for wall-clock duration in summary
}

type testResult struct {
	status  string
	elapsed float64
	pkg     string
	test    string
	failOut string
}

type pkgOutcome struct {
	status  string
	elapsed float64
	pkg     string
}

type filterStats struct {
	blankLines       int
	nonJSONLines     int
	jsonOtherPkgLine int // package-level JSON not classified as package outcome (start/output/etc.)
	jsonOtherAction  int // named Test set but action not pass/fail/skip/output-to-buffer
}

var safeLogBasename = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9_.-]*$`)

func validateJSONLOutPath(name string) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil
	}
	if strings.Contains(name, "..") {
		return fmt.Errorf(`-jsonl-out cannot contain ".."`)
	}
	clean := filepath.Clean(name)
	if filepath.IsAbs(clean) {
		return fmt.Errorf("-jsonl-out must be a relative path")
	}
	return nil
}

func main() {
	logName := flag.String("log", "", "basename only: write report to logs/<name>.log under cwd")
	jsonlOut := flag.String("jsonl-out", "", "optional relative path: append each stdin line (raw JSON) for debugging")
	banner := flag.String("banner", "", "optional text printed once at the top of the report")
	bannerFile := flag.String("banner-file", "", "optional file whose contents are printed as banner (overrides -banner if set)")
	tee := flag.Bool("tee", false, "echo each stdin line to stderr as it arrives (live JSON stream)")
	flag.Parse()

	if err := validateJSONLOutPath(*jsonlOut); err != nil {
		fmt.Fprintf(os.Stderr, "go-test-report: %v\n", err)
		os.Exit(1)
	}

	bannerText := strings.TrimSpace(*banner)
	if strings.TrimSpace(*bannerFile) != "" {
		b, err := os.ReadFile(*bannerFile)
		if err != nil {
			fmt.Fprintf(os.Stderr, "go-test-report: read banner file: %v\n", err)
			os.Exit(1)
		}
		bannerText = strings.TrimSuffix(string(b), "\n")
	}

	var jsonlFile io.Writer
	if strings.TrimSpace(*jsonlOut) != "" {
		if dir := filepath.Dir(*jsonlOut); dir != "." && dir != "" {
			if err := os.MkdirAll(dir, 0750); err != nil {
				fmt.Fprintf(os.Stderr, "go-test-report: mkdir: %v\n", err)
				os.Exit(1)
			}
		}
		f, err := os.Create(*jsonlOut)
		if err != nil {
			fmt.Fprintf(os.Stderr, "go-test-report: create jsonl: %v\n", err)
			os.Exit(1)
		}
		defer f.Close()
		jsonlFile = f
	}

	var buf strings.Builder
	if err := run(os.Stdin, &buf, *tee, os.Stderr, jsonlFile, bannerText); err != nil {
		fmt.Fprintf(os.Stderr, "go-test-report: %v\n", err)
		os.Exit(1)
	}
	data := buf.String()
	if _, err := io.WriteString(os.Stdout, data); err != nil {
		fmt.Fprintf(os.Stderr, "go-test-report: write stdout: %v\n", err)
		os.Exit(1)
	}
	if err := writeReportLog(*logName, data); err != nil {
		fmt.Fprintf(os.Stderr, "go-test-report: %v\n", err)
		os.Exit(1)
	}
}

func writeReportLog(name, content string) error {
	name = strings.TrimSpace(name)
	if name == "" {
		return nil
	}
	if !safeLogBasename.MatchString(name) {
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

func run(in io.Reader, out io.Writer, tee bool, teeOut io.Writer, jsonlOut io.Writer, banner string) error {
	type bufKey struct {
		pkg  string
		test string
	}
	outBuf := make(map[bufKey]*strings.Builder)

	sc := bufio.NewScanner(in)
	bufSize := 4 << 20
	sc.Buffer(make([]byte, 64*1024), bufSize)

	var nPass, nFail, nSkip int
	var results []testResult
	var pkgResults []pkgOutcome
	var st filterStats
	var wallFirst, wallLast time.Time
	var wallSeen bool

	for sc.Scan() {
		raw := sc.Text()
		if jsonlOut != nil {
			if _, err := fmt.Fprintln(jsonlOut, raw); err != nil {
				return err
			}
		}
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

		if t, ok := parseEventTime(ev.Time); ok {
			if !wallSeen {
				wallFirst, wallLast = t, t
				wallSeen = true
			} else {
				if t.Before(wallFirst) {
					wallFirst = t
				}
				if t.After(wallLast) {
					wallLast = t
				}
			}
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

		if ev.Test == "" && ev.Package != "" && (ev.Action == "pass" || ev.Action == "fail") {
			stTxt := "PASS"
			if ev.Action == "fail" {
				stTxt = "FAIL"
			}
			pkgResults = append(pkgResults, pkgOutcome{pkg: ev.Package, status: stTxt, elapsed: ev.Elapsed})
			continue
		}

		if ev.Test == "" {
			st.jsonOtherPkgLine++
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

	if banner != "" {
		_, _ = fmt.Fprintf(out, "--- banner ---\n%s\n--- end banner ---\n\n", banner)
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
		_, _ = fmt.Fprintln(out)
	}

	if len(pkgResults) > 0 {
		tw := tabwriter.NewWriter(out, 0, 0, 2, ' ', 0)
		_, _ = fmt.Fprintln(tw, "--- package outcomes ---")
		_, _ = fmt.Fprintln(tw, "STATUS\tSECONDS\tPACKAGE")
		for _, p := range pkgResults {
			_, _ = fmt.Fprintf(tw, "%s\t%s\t%s\n", p.status, formatSeconds(p.elapsed), p.pkg)
		}
		if err := tw.Flush(); err != nil {
			return err
		}
		_, _ = fmt.Fprintln(out)
	}

	for _, r := range results {
		if r.status != "FAIL" || r.failOut == "" {
			continue
		}
		_, _ = fmt.Fprintf(out, "\n---- %s / %s ----\n", r.pkg, r.test)
		_, _ = out.Write([]byte(indentBlock(r.failOut, "  ")))
	}

	var wallDur time.Duration
	wallOK := wallSeen
	if wallOK {
		wallDur = wallLast.Sub(wallFirst)
		if wallDur < 0 {
			wallDur = 0
		}
	}
	writeSummary(out, nPass, nFail, nSkip, pkgResults, st, wallDur, wallOK)
	return nil
}

func parseEventTime(s string) (time.Time, bool) {
	s = strings.TrimSpace(s)
	if s == "" {
		return time.Time{}, false
	}
	for _, layout := range []string{time.RFC3339Nano, time.RFC3339} {
		if t, err := time.Parse(layout, s); err == nil {
			return t, true
		}
	}
	return time.Time{}, false
}

func formatWallClockDuration(d time.Duration) string {
	if d < 0 {
		d = 0
	}
	base := fmt.Sprintf("%.2f s", d.Seconds())
	if d < time.Minute {
		return base
	}
	mins := int(d / time.Minute)
	secs := int((d % time.Minute) / time.Second)
	return fmt.Sprintf("%s (~%dm %ds)", base, mins, secs)
}

func writeSummary(out io.Writer, pass, fail, skip int, pkgResults []pkgOutcome, st filterStats, wallDur time.Duration, wallOK bool) {
	pkgN := len(pkgResults)
	pkgPass, pkgFail := 0, 0
	for _, p := range pkgResults {
		switch p.status {
		case "PASS":
			pkgPass++
		case "FAIL":
			pkgFail++
		}
	}
	namedTotal := pass + fail + skip

	_, _ = fmt.Fprintf(out, "\n--- summary ---\n\n")
	_, _ = fmt.Fprintf(out, "Tests listados por nombre (tabla superior STATUS / PACKAGE / TEST):\n")
	_, _ = fmt.Fprintf(out, "  Son eventos JSON de go test -json con campo Test no vacío y acción pass, fail o skip.\n")
	_, _ = fmt.Fprintf(out, "  passed:   %d\n", pass)
	_, _ = fmt.Fprintf(out, "  failed:   %d\n", fail)
	_, _ = fmt.Fprintf(out, "  skipped:  %d\n", skip)
	if namedTotal == 0 && pkgN > 0 {
		_, _ = fmt.Fprintf(out, "\n")
		_, _ = fmt.Fprintf(out, "  Nota: los tres contadores son 0 pero hay resultados por paquete más arriba\n")
		_, _ = fmt.Fprintf(out, "  («package outcomes»). Las pruebas pueden haber corrido dentro de una suite\n")
		_, _ = fmt.Fprintf(out, "  (p. ej. un solo Test que ejecuta Ginkgo) sin una fila nombrada por caso;\n")
		_, _ = fmt.Fprintf(out, "  revisa esa sección y, si hace falta, el archivo .jsonl de -jsonl-out.\n")
	} else if namedTotal > 0 {
		_, _ = fmt.Fprintf(out, "\n")
		_, _ = fmt.Fprintf(out, "  Nota: estos números no incluyen el resultado solo agregado a nivel de paquete;\n")
		_, _ = fmt.Fprintf(out, "  combina con «package outcomes» y el detalle del stream más abajo.\n")
	}
	_, _ = fmt.Fprintf(out, "\n")
	if wallOK {
		_, _ = fmt.Fprintf(out, "Duración total (entre primera y última marca temporal del stream; no suma en paralelo):\n")
		_, _ = fmt.Fprintf(out, "  %s\n", formatWallClockDuration(wallDur))
	} else {
		_, _ = fmt.Fprintf(out, "Duración total (tiempo de reloj):\n")
		_, _ = fmt.Fprintf(out, "  (no disponible: entradas sin marca temporal)\n")
	}
	_, _ = fmt.Fprintf(out, "\n")
	if pkgN > 0 {
		_, _ = fmt.Fprintf(out, "Resultados por paquete (sección «package outcomes» más arriba):\n")
		_, _ = fmt.Fprintf(out, "  paquetes PASS:  %d\n", pkgPass)
		_, _ = fmt.Fprintf(out, "  paquetes FAIL:  %d\n", pkgFail)
		_, _ = fmt.Fprintf(out, "  total listados: %d\n", pkgN)
		_, _ = fmt.Fprintf(out, "\n")
	}
	_, _ = fmt.Fprintf(out, "Detalle del stream (no suma a passed/failed/skipped de la tabla nombrada):\n")
	_, _ = fmt.Fprintf(out, "  líneas vacías:               %d\n", st.blankLines)
	_, _ = fmt.Fprintf(out, "  líneas no JSON:              %d  (p. ej. stderr mezclado)\n", st.nonJSONLines)
	_, _ = fmt.Fprintf(out, "  otros eventos de paquete:    %d  (compilación, inicio, salida…)\n", st.jsonOtherPkgLine)
	_, _ = fmt.Fprintf(out, "  acciones de test sin fila:   %d  (run/start antes del pass/fail por nombre)\n", st.jsonOtherAction)
	_, _ = fmt.Fprintf(out, "--- end summary ---\n")
}

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
