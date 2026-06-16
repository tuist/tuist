// Measurement client for the Kura gRPC upload-throughput e2e test.
//
// It programs toxiproxy with symmetric WAN latency, then uploads an identical
// blob via the REAPI google.bytestream.ByteStream/Write RPC through three
// paths under the SAME injected RTT:
//
//	baseline    client -> toxiproxy -> nginx (default window)        -> kura
//	patched     client -> toxiproxy -> nginx (raised window, from chart) -> kura
//	direct_kura client -> toxiproxy -> kura (kura's own stream window)
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
	"strconv"
	"time"

	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

// Reference points used only for the informational ceilings printed below —
// NOT chart values, so they are not read from helm: the baseline path inherits
// nginx's default 64KB HTTP/2 request-body window, and the direct path is
// bounded by the 4MB HTTP/2 stream window kura's tonic/hyper server now
// advertises (REAPI_HTTP2_STREAM_WINDOW_BYTES in kura/src/reapi/mod.rs, raised
// from the old 1MB tonic default — keep in sync). The patched window IS a chart
// value and arrives via PATCHED_WINDOW_BYTES.
const (
	nginxDefaultWindowBytes = 64 * 1024
	kuraStreamWindowBytes   = 4 * 1024 * 1024
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

func main() {
	toxAPI := env("TOXIPROXY_API", "http://toxiproxy:8474")
	toxHost := env("TOXIPROXY_HOST", "toxiproxy")
	latencyMs := envInt("LATENCY_MS", 50) // one-way; injected on both streams => RTT ~= 2x
	sizeMB := envInt("SIZE_MB", 24)
	chunkKB := envInt("CHUNK_KB", 256)
	minSpeedup := float64(envInt("MIN_SPEEDUP", 4))
	// Patched window comes from the chart (via generate-confs.sh + run.sh), so
	// even the printed expectation tracks helm, not a hardcoded value.
	patchedWindowBytes := envInt("PATCHED_WINDOW_BYTES", 4*1024*1024)
	patchedWindowLabel := env("PATCHED_WINDOW_LABEL", "4m")

	sizeBytes := sizeMB * 1024 * 1024
	chunk := chunkKB * 1024
	rttMs := latencyMs * 2

	targets := []target{
		{"baseline", "0.0.0.0:21001", toxHost + ":21001", "nginx-baseline:8443"},
		{"patched", "0.0.0.0:21002", toxHost + ":21002", "nginx-patched:8443"},
		{"direct_kura", "0.0.0.0:21003", toxHost + ":21003", "kura:50051"},
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
	fmt.Printf("  direct   kura   window (kura code)         -> ~%6.2f MB/s\n\n", mbpsCeiling(kuraStreamWindowBytes, rttMs))

	results := map[string]float64{}
	for i, t := range targets {
		got, dur, err := measure(t.dial, sizeBytes, chunk, i+1)
		if err != nil {
			fmt.Printf("[%-11s] ERROR: %v\n", t.name, err)
			os.Exit(2)
		}
		results[t.name] = got
		fmt.Printf("[%-11s] %7.2f MB/s   (%dMB in %s)   via %s\n",
			t.name, got, sizeMB, dur.Round(time.Millisecond), t.upstream)
	}

	base := results["baseline"]
	patched := results["patched"]
	speedup := 0.0
	if base > 0 {
		speedup = patched / base
	}

	fmt.Printf("\nspeedup (patched / baseline) = %.1fx   (threshold >= %.0fx)\n", speedup, minSpeedup)
	out, _ := json.Marshal(map[string]any{
		"payload_mb":       sizeMB,
		"rtt_ms":           rttMs,
		"baseline_mbps":    round2(base),
		"patched_mbps":     round2(patched),
		"direct_kura_mbps": round2(results["direct_kura"]),
		"speedup":          round2(speedup),
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
