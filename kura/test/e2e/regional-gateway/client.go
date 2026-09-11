// Standalone staging benchmark. Build using the adjacent grpc-upload-throughput
// client's pinned Go module; no changes to the Kura runtime are required.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
)

type payload struct {
	data []byte
	hash string
}
type sample struct {
	ms         float64
	err        error
	completedS float64
}

type bearerToken string

func (token bearerToken) GetRequestMetadata(context.Context, ...string) (map[string]string, error) {
	return map[string]string{"authorization": "Bearer " + string(token)}, nil
}

func (bearerToken) RequireTransportSecurity() bool { return true }

func main() {
	address := flag.String("address", "", "gateway IP:port")
	host := flag.String("host", "a.benchmark.test", "TLS SNI and HTTP authority")
	ca := flag.String("ca", "/tls/tls.crt", "benchmark CA")
	tokenFile := flag.String("token-file", "", "optional file containing a scoped staging cache token")
	account := flag.String("account", "", "use the account-scoped Gradle HTTP API with project bench")
	protocol := flag.String("protocol", "grpc", "grpc or http2")
	operation := flag.String("operation", "read", "read or write")
	size := flag.Int("size", 4096, "bytes per blob")
	count := flag.Int("count", 200, "requests")
	concurrency := flag.Int("concurrency", 1, "workers sharing one HTTP/2 connection")
	label := flag.String("label", "", "measurement label")
	routingAddresses := flag.String("routing-addresses", "", "comma-separated gateways for an HTTP account-isolation smoke check")
	warmupRequests := flag.Int("warmup-requests", 0, "additional untimed requests at measurement concurrency")
	streamFixtures := flag.Bool("stream-fixtures", false, "generate unique write fixtures in bounded per-worker buffers; generation is included in batch wall time")
	flag.Parse()
	if *address == "" || *size < 1 || *size > 64<<20 || *count < 1 || *count > 10000 || *concurrency < 1 || *concurrency > 64 || (*protocol != "grpc" && *protocol != "http2") || (*operation != "read" && *operation != "write") {
		panic("invalid benchmark parameters")
	}
	if *warmupRequests < 0 || *warmupRequests > 1000 || (*streamFixtures && (*size < 16 || int64(*size)*int64(*concurrency) > 256<<20)) {
		panic("invalid warmup or fixture budget")
	}
	pool, err := x509.SystemCertPool()
	must(err)
	if *ca != "" {
		cert, err := os.ReadFile(*ca)
		must(err)
		pool = x509.NewCertPool()
		if !pool.AppendCertsFromPEM(cert) {
			panic("invalid CA")
		}
	}
	token := ""
	if *tokenFile != "" {
		data, err := os.ReadFile(*tokenFile)
		must(err)
		token = strings.TrimSpace(string(data))
	}
	if *routingAddresses != "" {
		must(checkRouting(strings.Split(*routingAddresses, ","), pool))
		fmt.Println(`{"routing_check":"passed","accounts":2}`)
		return
	}
	tlsConfig := &tls.Config{RootCAs: pool, ServerName: *host, MinVersion: tls.VersionTLS12}
	options := []grpc.DialOption{grpc.WithTransportCredentials(credentials.NewTLS(tlsConfig)), grpc.WithAuthority(*host)}
	if token != "" {
		options = append(options, grpc.WithPerRPCCredentials(bearerToken(token)))
	}
	conn, err := grpc.NewClient(*address, options...)
	must(err)
	defer conn.Close()
	grpcClient := bs.NewByteStreamClient(conn)
	transport := &http.Transport{TLSClientConfig: tlsConfig, ForceAttemptHTTP2: true, MaxConnsPerHost: 1,
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{Timeout: 10 * time.Second}).DialContext(ctx, "tcp", *address)
		}}
	defer transport.CloseIdleConnections()
	httpClient := &http.Client{Transport: transport, Timeout: 60 * time.Second}

	transfer := func(p payload, write bool) error {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()
		if *protocol == "http2" {
			method := "GET"
			var body io.Reader
			if write {
				method = "PUT"
				body = bytes.NewReader(p.data)
			}
			path := "/v1/cache/" + p.hash
			if *account != "" {
				path = "/api/cache/gradle/" + p.hash + "?account_handle=" + url.QueryEscape(*account) + "&project_handle=bench"
			}
			req, err := http.NewRequestWithContext(ctx, method, "https://"+*host+path, body)
			if err != nil {
				return err
			}
			if token != "" {
				req.Header.Set("Authorization", "Bearer "+token)
			}
			resp, err := httpClient.Do(req)
			if err != nil {
				return err
			}
			defer resp.Body.Close()
			if resp.ProtoMajor != 2 || resp.StatusCode < 200 || resp.StatusCode >= 300 {
				return fmt.Errorf("HTTP %s status %d", resp.Proto, resp.StatusCode)
			}
			if write {
				_, err = io.Copy(io.Discard, resp.Body)
				return err
			}
			h := sha256.New()
			n, err := io.Copy(h, resp.Body)
			if err != nil {
				return err
			}
			if n != int64(len(p.data)) || hex.EncodeToString(h.Sum(nil)) != p.hash {
				return fmt.Errorf("HTTP response content mismatch")
			}
			return nil
		}
		resource := fmt.Sprintf("bench/blobs/%s/%d", p.hash, len(p.data))
		if write {
			stream, err := grpcClient.Write(ctx)
			if err != nil {
				return err
			}
			for offset := 0; offset < len(p.data); {
				end := offset + 65536
				if end > len(p.data) {
					end = len(p.data)
				}
				req := &bs.WriteRequest{WriteOffset: int64(offset), Data: p.data[offset:end], FinishWrite: end == len(p.data)}
				if offset == 0 {
					req.ResourceName = fmt.Sprintf("bench/uploads/%s/blobs/%s/%d", p.hash, p.hash, len(p.data))
				}
				if err := stream.Send(req); err != nil {
					return err
				}
				offset = end
			}
			resp, err := stream.CloseAndRecv()
			if err != nil {
				return err
			}
			if resp.CommittedSize != int64(len(p.data)) {
				return fmt.Errorf("gRPC committed-size mismatch")
			}
			return nil
		}
		stream, err := grpcClient.Read(ctx, &bs.ReadRequest{ResourceName: resource})
		if err != nil {
			return err
		}
		h := sha256.New()
		n := 0
		for {
			resp, err := stream.Recv()
			if err == io.EOF {
				break
			}
			if err != nil {
				return err
			}
			n += len(resp.Data)
			h.Write(resp.Data)
		}
		if n != len(p.data) || hex.EncodeToString(h.Sum(nil)) != p.hash {
			return fmt.Errorf("gRPC response content mismatch")
		}
		return nil
	}
	newPayload := func() payload {
		data := make([]byte, *size)
		_, err := rand.Read(data)
		must(err)
		sum := sha256.Sum256(data)
		return payload{data, hex.EncodeToString(sum[:])}
	}
	// Allocate random fixtures before timing. Streaming mode makes each write
	// unique in the worker below. Reads deliberately use a seeded warm object.
	objects := []payload{newPayload()}
	if *operation == "write" {
		fixtureCount := *count
		if *streamFixtures {
			fixtureCount = *concurrency
		}
		if int64(fixtureCount)*int64(*size) > 256<<20 {
			panic("write fixtures exceed 256 MiB")
		}
		for len(objects) < fixtureCount {
			objects = append(objects, newPayload())
		}
	}
	warm := newPayload()
	// Endpoint replacement can leave an old idle proxy connection behind. Retry
	// only the readiness request; measured requests are never retried here.
	for attempt := 0; ; attempt++ {
		err := transfer(warm, true)
		if err == nil {
			break
		}
		if attempt == 9 {
			must(err)
		}
		time.Sleep(200 * time.Millisecond)
	}
	must(transfer(warm, false))
	if *operation == "read" {
		must(transfer(objects[0], true))
		must(transfer(objects[0], false))
	}
	runBatch := func(n int, warming bool) ([]sample, float64) {
		jobs := make(chan int, n)
		results := make(chan sample, n)
		start := make(chan struct{})
		var wg sync.WaitGroup
		for i := 0; i < n; i++ {
			jobs <- i
		}
		close(jobs)
		var batchStarted time.Time
		for i := 0; i < *concurrency; i++ {
			worker := i
			wg.Add(1)
			go func() {
				defer wg.Done()
				<-start
				for j := range jobs {
					p := objects[j%len(objects)]
					if *operation == "write" && (*streamFixtures || warming) {
						if *streamFixtures {
							p = objects[worker]
						} else {
							p = newPayload()
						}
						_, err := rand.Read(p.data[:min(16, len(p.data))])
						must(err)
						sum := sha256.Sum256(p.data)
						p.hash = hex.EncodeToString(sum[:])
					}
					began := time.Now()
					err := transfer(p, *operation == "write")
					results <- sample{float64(time.Since(began).Nanoseconds()) / 1e6, err, time.Since(batchStarted).Seconds()}
				}
			}()
		}
		batchStarted = time.Now()
		close(start)
		wg.Wait()
		wall := time.Since(batchStarted).Seconds()
		close(results)
		all := make([]sample, 0, n)
		for s := range results {
			all = append(all, s)
		}
		return all, wall
	}
	if *warmupRequests > 0 {
		warmResults, _ := runBatch(*warmupRequests, true)
		for _, s := range warmResults {
			must(s.err)
		}
	}
	before := diagnostics()
	results, wall := runBatch(*count, false)
	after := diagnostics()
	latencies := []float64{}
	failures := []string{}
	buckets := map[int]int{}
	for _, s := range results {
		latencies = append(latencies, s.ms)
		if s.err == nil {
			buckets[int(s.completedS)]++
		}
		if s.err != nil {
			failures = append(failures, s.err.Error())
		}
	}
	sort.Float64s(latencies)
	percentile := func(p int) float64 { return latencies[(len(latencies)*p+99)/100-1] }
	firstError := ""
	if len(failures) > 0 {
		firstError = failures[0]
	}
	out := map[string]any{"label": *label, "protocol": *protocol, "operation": *operation, "size_bytes": *size, "requests": *count, "concurrency": *concurrency, "wall_s": wall, "p50_ms": percentile(50), "p95_ms": percentile(95), "p99_ms": percentile(99), "successful_mbps": float64((*count-len(failures))**size) * 8 / wall / 1e6, "errors": len(failures), "first_error": firstError}
	out["warmup_requests"] = *warmupRequests
	out["stream_fixtures"] = *streamFixtures
	out["completed_requests_by_second"] = buckets
	out["diagnostics_before"] = before
	out["diagnostics_after"] = after
	must(json.NewEncoder(os.Stdout).Encode(out))
	if len(failures) > 0 {
		os.Exit(1)
	}
}

func diagnostics() map[string]string {
	out := map[string]string{}
	for _, path := range []string{"/proc/net/snmp", "/proc/net/netstat", "/proc/net/dev", "/sys/fs/cgroup/cpu.stat", "/sys/fs/cgroup/memory.current", "/sys/fs/cgroup/memory.peak"} {
		data, err := os.ReadFile(path)
		if err == nil {
			out[path] = string(data)
		} else {
			out[path] = err.Error()
		}
	}
	return out
}

func must(err error) {
	if err != nil {
		panic(err)
	}
}

// Write different bytes under the same key in two accounts through gateway A,
// then verify both values through every gateway. Merely checking that both
// hostnames return 200 would miss a configuration routing both to one backend.
func checkRouting(addresses []string, pool *x509.CertPool) error {
	keyBytes := make([]byte, 32)
	if _, err := rand.Read(keyBytes); err != nil {
		return err
	}
	key := hex.EncodeToString(keyBytes)
	for i, address := range addresses {
		for _, host := range []string{"a.benchmark.test", "b.benchmark.test"} {
			transport := &http.Transport{ForceAttemptHTTP2: true, TLSClientConfig: &tls.Config{RootCAs: pool, ServerName: host, MinVersion: tls.VersionTLS12},
				DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
					return (&net.Dialer{Timeout: 10 * time.Second}).DialContext(ctx, "tcp", address)
				}}
			defer transport.CloseIdleConnections()
			client := &http.Client{Transport: transport, Timeout: 30 * time.Second}
			url := "https://" + host + "/v1/cache/" + key
			if i == 0 {
				req, err := http.NewRequest("PUT", url, strings.NewReader(host))
				if err != nil {
					return err
				}
				resp, err := client.Do(req)
				if err != nil {
					return err
				}
				io.Copy(io.Discard, resp.Body)
				resp.Body.Close()
				if resp.StatusCode != 200 {
					return fmt.Errorf("routing seed: %s status %d", host, resp.StatusCode)
				}
			}
		}
	}
	for _, address := range addresses {
		for _, host := range []string{"a.benchmark.test", "b.benchmark.test"} {
			transport := &http.Transport{ForceAttemptHTTP2: true, TLSClientConfig: &tls.Config{RootCAs: pool, ServerName: host, MinVersion: tls.VersionTLS12},
				DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
					return (&net.Dialer{Timeout: 10 * time.Second}).DialContext(ctx, "tcp", address)
				}}
			defer transport.CloseIdleConnections()
			client := &http.Client{Transport: transport, Timeout: 30 * time.Second}
			resp, err := client.Get("https://" + host + "/v1/cache/" + key)
			if err != nil {
				return err
			}
			data, err := io.ReadAll(resp.Body)
			resp.Body.Close()
			if err != nil {
				return err
			}
			if resp.StatusCode != 200 || resp.ProtoMajor != 2 || string(data) != host {
				return fmt.Errorf("routing isolation mismatch for %s through %s: status=%d body=%q", host, address, resp.StatusCode, data)
			}
		}
	}
	return nil
}
