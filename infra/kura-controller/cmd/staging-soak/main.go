// staging-soak holds HTTP/1.1 and HTTP/2 REAPI clients across a staging outage.
package main

import (
	"bytes"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptrace"
	"os"
	"strings"
	"sync"
	"time"

	"golang.org/x/net/http2"
	"google.golang.org/protobuf/encoding/protowire"
)

const host = "kura-spec95-e2e-staging.cache.tuist.dev"

var boxes = []string{"195.154.155.12", "144.217.252.35"}
var output sync.Mutex

func emit(event string, v map[string]any) {
	output.Lock()
	defer output.Unlock()
	v["event"] = event
	v["at"] = time.Now().UTC().Format(time.RFC3339Nano)
	_ = json.NewEncoder(os.Stdout).Encode(v)
}
func field(n protowire.Number, value []byte) []byte {
	return protowire.AppendBytes(protowire.AppendTag(nil, n, protowire.BytesType), value)
}
func values(data []byte, wanted protowire.Number) ([][]byte, error) {
	var result [][]byte
	for len(data) > 0 {
		n, t, k := protowire.ConsumeTag(data)
		if k < 0 {
			return nil, errors.New("invalid protobuf tag")
		}
		data = data[k:]
		if t == protowire.BytesType {
			b, k := protowire.ConsumeBytes(data)
			if k < 0 {
				return nil, errors.New("invalid protobuf bytes")
			}
			if n == wanted {
				result = append(result, b)
			}
			data = data[k:]
		} else {
			k := protowire.ConsumeFieldValue(n, t, data)
			if k < 0 {
				return nil, errors.New("invalid protobuf value")
			}
			data = data[k:]
		}
	}
	return result, nil
}
func frame(b []byte) []byte {
	h := make([]byte, 5)
	binary.BigEndian.PutUint32(h[1:], uint32(len(b)))
	return append(h, b...)
}
func rpcBody(b []byte) ([]byte, error) {
	if len(b) < 5 || b[0] != 0 || int(binary.BigEndian.Uint32(b[1:5])) != len(b)-5 {
		return nil, errors.New("invalid unary gRPC frame")
	}
	return b[5:], nil
}
func client(protocol, ip string) *http.Client {
	dial := func(ctx context.Context, network, address string) (net.Conn, error) {
		if ip != "" {
			address = net.JoinHostPort(ip, "443")
		}
		return (&net.Dialer{Timeout: 5 * time.Second}).DialContext(ctx, network, address)
	}
	var transport http.RoundTripper
	if protocol == "grpc" {
		transport = &http2.Transport{TLSClientConfig: &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}, DialTLSContext: func(ctx context.Context, network, address string, cfg *tls.Config) (net.Conn, error) {
			conn, err := dial(ctx, network, address)
			if err != nil {
				return nil, err
			}
			t := tls.Client(conn, cfg)
			if err = t.HandshakeContext(ctx); err != nil {
				conn.Close()
				return nil, err
			}
			return t, nil
		}}
	} else {
		transport = &http.Transport{DialContext: dial, TLSClientConfig: &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}, IdleConnTimeout: 90 * time.Second}
	}
	return &http.Client{Transport: transport, Timeout: 8 * time.Second, CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
}
func request(c *http.Client, protocol, method, path, token string, payload []byte) ([]byte, map[string]any, error) {
	data := map[string]any{"protocol": protocol, "method": method}
	req, err := http.NewRequest(method, "https://"+host+path, bytes.NewReader(payload))
	if err != nil {
		return nil, data, err
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	if protocol == "grpc" {
		req.Header.Set("Content-Type", "application/grpc")
		req.Header.Set("TE", "trailers")
	}
	req = req.WithContext(httptrace.WithClientTrace(req.Context(), &httptrace.ClientTrace{GotConn: func(info httptrace.GotConnInfo) {
		data["connection"] = info.Conn.LocalAddr().String() + "->" + info.Conn.RemoteAddr().String()
		data["reused"] = info.Reused
	}}))
	start := time.Now()
	resp, err := c.Do(req)
	data["seconds"] = time.Since(start).Seconds()
	if err != nil {
		return nil, data, err
	}
	defer resp.Body.Close()
	data["status"] = resp.StatusCode
	data["http_version"] = resp.Proto
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1024*1024))
	if err != nil {
		return nil, data, err
	}
	if resp.StatusCode != 200 && resp.StatusCode != 201 {
		return nil, data, fmt.Errorf("HTTP status %d", resp.StatusCode)
	}
	if protocol == "grpc" {
		status := resp.Trailer.Get("Grpc-Status")
		if status == "" {
			status = resp.Header.Get("Grpc-Status")
		}
		data["grpc_status"] = status
		if status != "0" {
			return nil, data, fmt.Errorf("gRPC status %s", status)
		}
		body, err = rpcBody(body)
	}
	return body, data, err
}
func dns(resolver *net.Resolver) ([]string, string) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	ips, err := resolver.LookupHost(ctx, host)
	if err != nil {
		return nil, err.Error()
	}
	return ips, ""
}
func main() {
	tokenPath := flag.String("token-file", "", "Fixture token file")
	origin := flag.String("origin", "", "Measurement origin")
	duration := flag.Duration("duration", time.Hour, "Bounded observation duration")
	latencyOnly := flag.Bool("latency-only", false, "Compare DNS with CLI-path /up latency without authenticated traffic")
	flag.Parse()
	if *origin == "" || *duration <= 0 || *duration > 2*time.Hour {
		panic("origin and duration up to two hours required")
	}
	if *latencyOnly {
		ctx, cancel := context.WithTimeout(context.Background(), *duration)
		defer cancel()
		emit("start", map[string]any{"origin": *origin, "duration": duration.String(), "path": "/up"})
		measure(ctx, *origin, "/up")
		emit("finished", map[string]any{"origin": *origin})
		return
	}
	tokenBytes, err := os.ReadFile(*tokenPath)
	if err != nil {
		panic(err)
	}
	token := strings.TrimSpace(string(tokenBytes))
	if token == "" {
		panic("empty token")
	}
	payload := []byte("spec95 persistent connection recovery fixture v1\n")
	hash := fmt.Sprintf("%x", sha256.Sum256(payload))
	digest := append(field(1, []byte(hash)), protowire.AppendVarint(protowire.AppendTag(nil, 2, protowire.VarintType), uint64(len(payload)))...)
	path := "/api/cache/gradle/" + hash + "?tenant_id=kura-spec95-e2e&namespace_id=probe"
	base := "/build.bazel.remote.execution.v2.ContentAddressableStorage/"
	update := frame(append(field(1, []byte("probe")), field(2, append(field(1, digest), field(2, payload)...))...))
	read := frame(append(field(1, []byte("probe")), field(2, digest)...))
	for _, ip := range boxes {
		for _, protocol := range []string{"http", "grpc"} {
			c := client(protocol, ip)
			method, p, b := "PUT", path, payload
			if protocol == "grpc" {
				method, p, b = "POST", base+"BatchUpdateBlobs", update
			}
			_, v, err := request(c, protocol, method, p, token, b)
			c.CloseIdleConnections()
			v["ip"] = ip
			if err != nil {
				v["error"] = err.Error()
				emit("seed_failed", v)
				os.Exit(1)
			}
			emit("seed", v)
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), *duration)
	defer cancel()
	emit("start", map[string]any{"origin": *origin, "duration": duration.String(), "pid": os.Getpid()})
	var wg sync.WaitGroup
	for _, protocol := range []string{"http", "grpc"} {
		wg.Add(1)
		go func(protocol string) {
			defer wg.Done()
			c := client(protocol, "")
			defer c.CloseIdleConnections()
			ticker := time.NewTicker(2 * time.Second)
			defer ticker.Stop()
			for {
				method, p, b := "GET", path, []byte(nil)
				if protocol == "grpc" {
					method, p, b = "POST", base+"BatchReadBlobs", read
				}
				body, v, err := request(c, protocol, method, p, token, b)
				if err == nil && protocol == "grpc" {
					var entries [][]byte
					entries, err = values(body, 1)
					if err == nil && len(entries) != 1 {
						err = errors.New("expected one blob")
					}
					if err == nil {
						var blobs [][]byte
						blobs, err = values(entries[0], 2)
						if err == nil && len(blobs) == 1 {
							body = blobs[0]
						} else {
							err = errors.New("missing blob data")
						}
					}
				}
				if err == nil && !bytes.Equal(body, payload) {
					err = errors.New("blob bytes differ")
				}
				v["origin"] = *origin
				v["ok"] = err == nil
				if err != nil {
					v["error"] = strings.ReplaceAll(err.Error(), token, "[redacted]")
				}
				emit("persistent", v)
				select {
				case <-ctx.Done():
					return
				case <-ticker.C:
				}
			}
		}(protocol)
	}
	measure(ctx, *origin, "/ready")
	wg.Wait()
	emit("finished", map[string]any{"origin": *origin})
}

func measure(ctx context.Context, origin, path string) {
	authority := &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
		return (&net.Dialer{Timeout: 3 * time.Second}).DialContext(ctx, network, "205.251.192.200:53")
	}}
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		system, se := dns(net.DefaultResolver)
		auth, ae := dns(authority)
		v := map[string]any{"origin": origin, "path": path, "system_dns": system, "system_error": se, "authoritative_dns": auth, "authoritative_error": ae}
		latencies := map[string]any{}
		for _, ip := range boxes {
			samples := []map[string]any{}
			for i := 0; i < 3; i++ {
				c := client("http", ip)
				_, r, e := request(c, "http", "GET", path, "", nil)
				c.CloseIdleConnections()
				if e != nil {
					r["error"] = e.Error()
				}
				samples = append(samples, r)
			}
			latencies[ip] = samples
		}
		v["latencies"] = latencies
		emit("steering", v)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}
