// Measurement client for the Kura gRPC upload-throughput e2e test.
//
// It programs toxiproxy with symmetric WAN latency, then uploads an identical
// blob via the REAPI google.bytestream.ByteStream/Write RPC through five paths
// under the SAME injected RTT:
//
//	baseline     client -> toxiproxy -> nginx (default window)            -> kura combined port (8080)
//	patched      client -> toxiproxy -> nginx (raised window, from chart) -> kura combined port (8080)
//	direct_kura  client -> toxiproxy -> kura combined port (8080, co-hosted HTTP+gRPC)
//	patched_grpc client -> toxiproxy -> nginx (raised window, from chart) -> kura dedicated gRPC port (50051)
//	direct_grpc  client -> toxiproxy -> kura dedicated gRPC port (50051)
//
// The primary comparison is patched vs baseline (the nginx window). The
// *_grpc paths mirror `patched` and `direct_kura` against kura's dedicated
// REAPI gRPC listener instead of the combined port, so the run also reports
// combined-vs-dedicated backend throughput under an identical nginx window and
// direct — a control that co-hosting HTTP + gRPC on one port does not regress
// large REAPI uploads. Both listeners advertise the same 4MB HTTP/2 window.
//
// It prints per-path throughput and asserts that the patched path is at least
// MIN_SPEEDUP times faster than baseline — i.e. that raising nginx's HTTP/2
// request-body window actually removes the upload-throughput cap under latency.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"gopkg.in/yaml.v3"
)

// Reference points used only for the informational ceilings printed below —
// NOT chart values, so they are not read from helm: the baseline path inherits
// nginx's default 64KB HTTP/2 request-body window, and the direct path (now the
// co-hosted combined HTTP+gRPC listener) is bounded by the 4MB HTTP/2 stream
// window kura advertises on that port (COMBINED_HTTP2_STREAM_WINDOW_BYTES in
// kura/src/app.rs, matching REAPI's window — keep in sync). The patched window
// IS a chart value and arrives via PATCHED_WINDOW_BYTES.
const (
	nginxDefaultWindowBytes = 64 * 1024
	kuraStreamWindowBytes   = 4 * 1024 * 1024
)

// Kura backends the paths dial. The combined listener co-hosts HTTP + h2c gRPC;
// the *_grpc variants dial the dedicated REAPI gRPC port so the run can compare
// combined-vs-dedicated throughput both direct and behind the patched nginx
// window. Both listeners advertise the same 4MB HTTP/2 stream window.
const (
	kuraCombinedUpstream = "kura:8080"
	kuraGrpcUpstream     = "kura:50051"
)

type target struct {
	name     string
	listen   string // address toxiproxy listens on, inside its own container
	dial     string // address this client dials (toxiproxy:port)
	upstream string // where toxiproxy forwards
}

func env(name, def string) string {
	if v := os.Getenv(name); v != "" {
		return v
	}
	return def
}

func envInt(name string, def int) int {
	if v := os.Getenv(name); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return def
}

func mbpsCeiling(windowBytes, rttMs int) float64 {
	return (float64(windowBytes) / (float64(rttMs) / 1000.0)) / (1024 * 1024)
}

var preReadSizeRe = regexp.MustCompile(`http2_body_preread_size\s+([0-9]+[kKmMgG]?)`)

// genConfs renders generated/{baseline,patched}.conf from the nginx template
// and writes generated/window.env, pulling the HTTP/2 upload-window values from
// the live platform chart. It replaces a shell + yq-in-docker step: the same Go
// binary that measures throughput also reads the chart (with anchor/alias
// resolution), so the harness needs no third-party image to parse YAML.
//
// It reads the window keys from EVERY regional gateway block and requires them
// to agree rather than trusting the shared YAML anchor — so a future per-region
// override that unwinds the anchor fails loudly here instead of silently
// rendering one region's config.
//
//	patched.conf  = template + window directives derived from values.yaml
//	baseline.conf = template with the window directives removed (nginx defaults)
func genConfs() error {
	chartValues := env("CHART_VALUES", "../../../../infra/helm/platform/values.yaml")
	tmplPath := env("TEMPLATE_PATH", "nginx/nginx.conf.tmpl")
	outDir := env("OUT_DIR", "generated")

	raw, err := os.ReadFile(chartValues)
	if err != nil {
		return fmt.Errorf("read chart values %s: %w", chartValues, err)
	}
	var doc map[string]any
	if err := yaml.Unmarshal(raw, &doc); err != nil {
		return fmt.Errorf("parse chart values: %w", err)
	}
	cfg, regions, err := agreedGatewayWindow(doc)
	if err != nil {
		return err
	}

	cbb := cfg["client-body-buffer-size"]
	streams := cfg["http2-max-concurrent-streams"]
	snippet := cfg["http-snippet"]

	var directives strings.Builder
	if cbb != "" {
		fmt.Fprintf(&directives, "    client_body_buffer_size %s;\n", cbb)
	}
	if streams != "" {
		fmt.Fprintf(&directives, "    http2_max_concurrent_streams %s;\n", streams)
	}
	if snippet != "" {
		// http-snippet is already raw nginx (e.g. "http2_body_preread_size 4m;").
		fmt.Fprintf(&directives, "    %s\n", snippet)
	}

	tmpl, err := os.ReadFile(tmplPath)
	if err != nil {
		return fmt.Errorf("read template %s: %w", tmplPath, err)
	}
	if err := os.MkdirAll(outDir, 0o755); err != nil {
		return fmt.Errorf("mkdir %s: %w", outDir, err)
	}
	// baseline/patched proxy to the combined port; patched-grpc reuses the
	// patched window but proxies to the dedicated gRPC port, so the client can
	// isolate the backend-port effect under an identical nginx window.
	confs := []struct{ name, directives, upstream string }{
		{"patched.conf", directives.String(), kuraCombinedUpstream},
		{"baseline.conf", "", kuraCombinedUpstream},
		{"patched-grpc.conf", directives.String(), kuraGrpcUpstream},
	}
	for _, c := range confs {
		if err := os.WriteFile(filepath.Join(outDir, c.name), renderConf(tmpl, c.directives, c.upstream), 0o644); err != nil {
			return err
		}
	}

	// Reference ceiling for the client: the advertised window from the chart,
	// falling back to nginx's default when the override is absent.
	windowLabel, windowBytes := "nginx-default", 65536
	if size := preReadSize(snippet); size != "" {
		windowLabel, windowBytes = size, toBytes(size)
	}
	windowEnv := fmt.Sprintf("PATCHED_WINDOW_LABEL=%s\nPATCHED_WINDOW_BYTES=%d\n", windowLabel, windowBytes)
	if err := os.WriteFile(filepath.Join(outDir, "window.env"), []byte(windowEnv), 0o644); err != nil {
		return err
	}

	fmt.Printf("genconfs: from %s [%d gateway blocks: %s]\n", chartValues, len(regions), strings.Join(regions, ", "))
	fmt.Printf("  client-body-buffer-size=%s  http2-max-concurrent-streams=%s  http-snippet=%q\n", cbb, streams, snippet)
	return nil
}

// windowKeys are the gateway config keys this harness renders into the patched
// nginx conf. We only require these to agree across regions; the full
// controller-vs-chart drift guard over every shared key lives in the
// infra/kura-controller unit test (TestGatewayNginxConfigMatchesChart).
var windowKeys = []string{
	"client-body-buffer-size",
	"http2-max-concurrent-streams",
	"http-snippet",
}

// agreedGatewayWindow reads windowKeys from every kura-*-ingress-nginx block
// that defines a controller.config and returns the agreed values plus the
// blocks consulted. It fails if a key diverges across regions or is set in some
// but not all of them (the shared anchor was unwound), or if no gateway block
// is found. A key absent from every region is simply omitted (e.g. the fix was
// reverted), matching nginx defaults.
func agreedGatewayWindow(doc map[string]any) (map[string]string, []string, error) {
	var regions []string
	for name := range doc {
		if strings.HasPrefix(name, "kura-") && strings.HasSuffix(name, "-ingress-nginx") {
			if len(gatewayConfig(doc, name)) > 0 {
				regions = append(regions, name)
			}
		}
	}
	sort.Strings(regions)
	if len(regions) == 0 {
		return nil, nil, fmt.Errorf("no kura-*-ingress-nginx block with controller.config found; chart layout changed")
	}

	agreed := map[string]string{}
	for _, key := range windowKeys {
		var setIn []string
		var value string
		for _, name := range regions {
			v, ok := gatewayConfig(doc, name)[key]
			if !ok {
				continue
			}
			if len(setIn) > 0 && v != value {
				return nil, nil, fmt.Errorf(
					"regional gateway config diverged on %q: %s=%q vs %s=%q — the shared anchor was unwound; update every kura-*-ingress-nginx block together",
					key, setIn[0], value, name, v)
			}
			setIn = append(setIn, name)
			value = v
		}
		switch len(setIn) {
		case 0:
			// Key used by no region (e.g. fix reverted) — leave it unset.
		case len(regions):
			agreed[key] = value
		default:
			return nil, nil, fmt.Errorf(
				"gateway config key %q is set in %d of %d regional blocks (%s) — diverged; update every kura-*-ingress-nginx block together",
				key, len(setIn), len(regions), strings.Join(setIn, ", "))
		}
	}
	return agreed, regions, nil
}

// gatewayConfig returns <gatewayKey>.controller.config as string->string,
// tolerating a missing block.
func gatewayConfig(doc map[string]any, gatewayKey string) map[string]string {
	out := map[string]string{}
	gw, _ := doc[gatewayKey].(map[string]any)
	ctrl, _ := gw["controller"].(map[string]any)
	cfg, _ := ctrl["config"].(map[string]any)
	for k, v := range cfg {
		out[k] = fmt.Sprintf("%v", v)
	}
	return out
}

// renderConf emits the template with the window marker line replaced by
// directives (patched) or removed (baseline), and the __KURA_UPSTREAM__ marker
// substituted with the backend the config proxies to (combined vs dedicated
// gRPC port).
func renderConf(tmpl []byte, directives, upstream string) []byte {
	var out strings.Builder
	for _, line := range strings.Split(strings.TrimRight(string(tmpl), "\n"), "\n") {
		if strings.Contains(line, "__WINDOW_DIRECTIVES__") {
			out.WriteString(directives)
			continue
		}
		out.WriteString(strings.ReplaceAll(line, "__KURA_UPSTREAM__", upstream))
		out.WriteByte('\n')
	}
	return []byte(out.String())
}

func preReadSize(snippet string) string {
	if m := preReadSizeRe.FindStringSubmatch(snippet); len(m) == 2 {
		return m[1]
	}
	return ""
}

// toBytes converts an nginx size token (e.g. 4m, 64k) to bytes.
func toBytes(v string) int {
	if v == "" {
		return 0
	}
	mult, num := 1, v
	switch v[len(v)-1] {
	case 'k', 'K':
		mult, num = 1024, v[:len(v)-1]
	case 'm', 'M':
		mult, num = 1024*1024, v[:len(v)-1]
	case 'g', 'G':
		mult, num = 1024*1024*1024, v[:len(v)-1]
	}
	n, err := strconv.Atoi(num)
	if err != nil {
		return 0
	}
	return n * mult
}

func main() {
	// Subcommand: render the nginx confs from the chart. run.sh invokes this
	// via the same image before `up`.
	if len(os.Args) > 1 && os.Args[1] == "genconfs" {
		if err := genConfs(); err != nil {
			fmt.Fprintln(os.Stderr, "genconfs:", err)
			os.Exit(1)
		}
		return
	}

	toxAPI := env("TOXIPROXY_API", "http://toxiproxy:8474")
	toxHost := env("TOXIPROXY_HOST", "toxiproxy")
	latencyMs := envInt("LATENCY_MS", 50) // one-way; injected on both streams => RTT ~= 2x
	sizeMB := envInt("SIZE_MB", 16)       // matches docker-compose / run.sh / README default
	chunkKB := envInt("CHUNK_KB", 256)
	minSpeedup := float64(envInt("MIN_SPEEDUP", 4))
	// Patched window comes from the chart (via the confgen step + run.sh), so
	// even the printed expectation tracks helm, not a hardcoded value.
	patchedWindowBytes := envInt("PATCHED_WINDOW_BYTES", 4*1024*1024)
	patchedWindowLabel := env("PATCHED_WINDOW_LABEL", "4m")

	sizeBytes := sizeMB * 1024 * 1024
	chunk := chunkKB * 1024
	rttMs := latencyMs * 2

	targets := []target{
		{"baseline", "0.0.0.0:21001", toxHost + ":21001", "nginx-baseline:8443"},
		{"patched", "0.0.0.0:21002", toxHost + ":21002", "nginx-patched:8443"},
		{"direct_kura", "0.0.0.0:21003", toxHost + ":21003", kuraCombinedUpstream},
		{"patched_grpc", "0.0.0.0:21004", toxHost + ":21004", "nginx-patched-grpc:8443"},
		{"direct_grpc", "0.0.0.0:21005", toxHost + ":21005", kuraGrpcUpstream},
	}

	waitToxiproxy(toxAPI, 60*time.Second)
	for _, t := range targets {
		programProxy(toxAPI, t, latencyMs)
	}

	fmt.Printf("=== Kura gRPC upload throughput e2e ===\n")
	fmt.Printf("payload=%dMB chunk=%dKB injected RTT=%dms (%dms each direction)\n\n", sizeMB, chunkKB, rttMs, latencyMs)
	fmt.Printf("window-bound throughput ceilings at %dms RTT (1 stream):\n", rttMs)
	fmt.Printf("  baseline nginx  default ~64KB window      -> ~%6.2f MB/s\n", mbpsCeiling(nginxDefaultWindowBytes, rttMs))
	fmt.Printf("  patched  nginx  %-5s window (from chart)   -> ~%6.2f MB/s\n", patchedWindowLabel, mbpsCeiling(patchedWindowBytes, rttMs))
	fmt.Printf("  direct   kura   combined port (kura code)  -> ~%6.2f MB/s\n\n", mbpsCeiling(kuraStreamWindowBytes, rttMs))

	results := map[string]float64{}
	for i, t := range targets {
		got, dur, err := measure(t.dial, sizeBytes, chunk, i+1)
		if err != nil {
			fmt.Printf("[%-12s] ERROR: %v\n", t.name, err)
			os.Exit(2)
		}
		results[t.name] = got
		fmt.Printf("[%-12s] %7.2f MB/s   (%dMB in %s)   via %s\n",
			t.name, got, sizeMB, dur.Round(time.Millisecond), t.upstream)
	}

	base := results["baseline"]
	patched := results["patched"]
	speedup := 0.0
	if base > 0 {
		speedup = patched / base
	}

	fmt.Printf("\nspeedup (patched / baseline) = %.1fx   (threshold >= %.0fx)\n", speedup, minSpeedup)
	// Combined vs dedicated gRPC backend under an identical window — the two
	// comparison pairs the extra paths exist for. Both should be within noise if
	// co-hosting doesn't regress REAPI throughput.
	fmt.Printf("combined vs dedicated-gRPC backend (same window):\n")
	fmt.Printf("  patched : combined %6.2f MB/s   vs   grpc %6.2f MB/s\n", results["patched"], results["patched_grpc"])
	fmt.Printf("  direct  : combined %6.2f MB/s   vs   grpc %6.2f MB/s\n", results["direct_kura"], results["direct_grpc"])
	out, _ := json.Marshal(map[string]any{
		"payload_mb":        sizeMB,
		"rtt_ms":            rttMs,
		"baseline_mbps":     round2(base),
		"patched_mbps":      round2(patched),
		"patched_grpc_mbps": round2(results["patched_grpc"]),
		"direct_kura_mbps":  round2(results["direct_kura"]),
		"direct_grpc_mbps":  round2(results["direct_grpc"]),
		"speedup":           round2(speedup),
	})
	fmt.Printf("RESULT_JSON %s\n", string(out))

	if speedup < minSpeedup {
		fmt.Printf("\nFAIL: patched did not improve upload throughput by >= %.0fx\n", minSpeedup)
		os.Exit(1)
	}
	fmt.Printf("\nPASS: raising the nginx HTTP/2 upload window improved throughput %.1fx under %dms RTT\n", speedup, rttMs)
}

func round2(f float64) float64 { return float64(int(f*100+0.5)) / 100 }

// measure warms the connection (and waits out backend startup) with a tiny
// upload, then times a full-size upload on the same warm connection.
func measure(dial string, size, chunk, seed int) (float64, time.Duration, error) {
	conn, err := grpc.NewClient(dial,
		grpc.WithTransportCredentials(insecure.NewCredentials()),
		grpc.WithDefaultCallOptions(grpc.MaxCallSendMsgSize(64<<20)),
	)
	if err != nil {
		return 0, 0, err
	}
	defer conn.Close()
	client := bs.NewByteStreamClient(conn)

	var lastErr error
	for attempt := 0; attempt < 60; attempt++ {
		if err := uploadBlob(client, 4096, chunk, seed*100000+attempt); err == nil {
			lastErr = nil
			break
		} else {
			lastErr = err
			time.Sleep(time.Second)
		}
	}
	if lastErr != nil {
		return 0, 0, fmt.Errorf("warmup/readiness failed: %w", lastErr)
	}

	start := time.Now()
	if err := uploadBlob(client, size, chunk, seed); err != nil {
		return 0, 0, err
	}
	dur := time.Since(start)
	return float64(size) / (1024 * 1024) / dur.Seconds(), dur, nil
}

func uploadBlob(client bs.ByteStreamClient, size, chunk, seed int) error {
	data := make([]byte, size)
	for i := range data {
		data[i] = byte((i*1103515245 + seed*12345 + 7) >> 3)
	}
	sum := sha256.Sum256(data)
	resource := fmt.Sprintf("e2e/uploads/seed-%d/blobs/%s/%d", seed, hex.EncodeToString(sum[:]), size)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Minute)
	defer cancel()
	stream, err := client.Write(ctx)
	if err != nil {
		return err
	}

	off := 0
	first := true
	for off < size {
		end := off + chunk
		if end > size {
			end = size
		}
		req := &bs.WriteRequest{
			WriteOffset: int64(off),
			Data:        data[off:end],
			FinishWrite: end == size,
		}
		if first {
			req.ResourceName = resource
			first = false
		}
		if err := stream.Send(req); err != nil {
			return fmt.Errorf("send: %w", err)
		}
		off = end
	}
	resp, err := stream.CloseAndRecv()
	if err != nil {
		return fmt.Errorf("close: %w", err)
	}
	if resp.GetCommittedSize() != int64(size) {
		return fmt.Errorf("committed %d != %d", resp.GetCommittedSize(), size)
	}
	return nil
}

func waitToxiproxy(api string, timeout time.Duration) {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if resp, err := http.Get(api + "/version"); err == nil {
			resp.Body.Close()
			if resp.StatusCode == http.StatusOK {
				return
			}
		}
		time.Sleep(500 * time.Millisecond)
	}
	panic("toxiproxy control API not reachable at " + api)
}

func programProxy(api string, t target, latencyMs int) {
	// Remove any stale proxy from a previous run, then recreate it.
	req, _ := http.NewRequest(http.MethodDelete, api+"/proxies/"+t.name, nil)
	if resp, err := http.DefaultClient.Do(req); err == nil {
		resp.Body.Close()
	}
	body, _ := json.Marshal(map[string]any{
		"name": t.name, "listen": t.listen, "upstream": t.upstream, "enabled": true,
	})
	mustPost(api+"/proxies", body)

	// Latency is unidirectional per toxic; inject it on both streams so the
	// simulated round trip is ~2x the one-way value.
	for _, stream := range []string{"upstream", "downstream"} {
		tox, _ := json.Marshal(map[string]any{
			"name": "lat_" + stream, "type": "latency", "stream": stream,
			"attributes": map[string]any{"latency": latencyMs, "jitter": 0},
		})
		mustPost(api+"/proxies/"+t.name+"/toxics", tox)
	}
}

func mustPost(url string, body []byte) {
	resp, err := http.Post(url, "application/json", bytes.NewReader(body))
	if err != nil {
		panic(fmt.Sprintf("POST %s: %v", url, err))
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		panic(fmt.Sprintf("POST %s -> %d: %s", url, resp.StatusCode, string(b)))
	}
}
