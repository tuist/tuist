// staging-probe verifies public TLS, HTTP cache traffic, and REAPI traffic on staging.
package main

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	_ "embed"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

//go:embed reapi-smoke.proto
var proto []byte

type options struct {
	host, account, project, tokenFile, writeIP, readIP, readHost, grpcurl string
	repeat                                                                int
	interval, replicationTimeout                                          time.Duration
	token, protoDir                                                       string
}

type digest struct {
	Hash string `json:"hash"`
	Size string `json:"sizeBytes"`
}

type blobResult struct {
	Digest digest `json:"digest"`
	Data   []byte `json:"data"`
	Status struct {
		Code int `json:"code"`
	} `json:"status"`
}

func record(event string, fields map[string]any) {
	fields["event"] = event
	fields["at"] = time.Now().UTC().Format(time.RFC3339Nano)
	_ = json.NewEncoder(os.Stdout).Encode(fields)
}

func (o options) request(method, host, ip, path string, body []byte) (int, []byte, error) {
	remote := ""
	transport := &http.Transport{
		TLSClientConfig: &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12},
		DialContext: func(ctx context.Context, network, address string) (net.Conn, error) {
			if ip != "" {
				address = net.JoinHostPort(ip, "443")
			}
			conn, err := (&net.Dialer{Timeout: 5 * time.Second}).DialContext(ctx, network, address)
			if err == nil {
				remote = conn.RemoteAddr().String()
			}
			return conn, err
		},
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 20 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	req, err := http.NewRequest(method, "https://"+host+path, bytes.NewReader(body))
	if err != nil {
		return 0, nil, err
	}
	if o.token != "" {
		req.Header.Set("Authorization", "Bearer "+o.token)
	}
	started := time.Now()
	resp, err := client.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1024*1024))
	record("http", map[string]any{"method": method, "host": host, "pinned_ip": ip,
		"remote_address": remote, "status": resp.StatusCode, "seconds": time.Since(started).Seconds()})
	return resp.StatusCode, data, err
}

func (o options) grpc(method, host, ip string, body any) (blobResult, error) {
	var response struct {
		Responses []blobResult `json:"responses"`
	}
	encoded, err := json.Marshal(body)
	if err != nil {
		return blobResult{}, err
	}
	target := host
	if ip != "" {
		target = ip
	}
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, o.grpcurl, "-max-time", "20", "-authority", host,
		"-import-path", o.protoDir, "-proto", "reapi-smoke.proto", "-expand-headers",
		"-H", "authorization: Bearer ${SPEC95_PROBE_TOKEN}", "-d", "@", net.JoinHostPort(target, "443"),
		"build.bazel.remote.execution.v2.ContentAddressableStorage/"+method)
	cmd.Env = append(os.Environ(), "SPEC95_PROBE_TOKEN="+o.token)
	cmd.Stdin = bytes.NewReader(encoded)
	started := time.Now()
	output, err := cmd.Output()
	if err != nil {
		var failure *exec.ExitError
		if errors.As(err, &failure) {
			return blobResult{}, fmt.Errorf("grpcurl: %s", strings.ReplaceAll(string(failure.Stderr), o.token, "[redacted]"))
		}
		return blobResult{}, err
	}
	if err := json.Unmarshal(output, &response); err != nil {
		return blobResult{}, err
	}
	if len(response.Responses) != 1 {
		return blobResult{}, errors.New("REAPI did not return exactly one blob result")
	}
	entry := response.Responses[0]
	record("grpc", map[string]any{"method": method, "host": host, "pinned_ip": ip,
		"status": entry.Status.Code, "seconds": time.Since(started).Seconds()})
	return entry, nil
}

func (o options) roundtrip() error {
	payload := make([]byte, 64*1024)
	if _, err := rand.Read(payload); err != nil {
		return err
	}
	d := digest{Hash: fmt.Sprintf("%x", sha256.Sum256(payload)), Size: strconv.Itoa(len(payload))}
	query := url.Values{"tenant_id": {o.account}, "namespace_id": {o.project}}
	path := "/api/cache/gradle/" + d.Hash + "?" + query.Encode()
	status, _, err := o.request("PUT", o.host, o.writeIP, path, payload)
	if err != nil {
		return err
	}
	if status != 200 && status != 201 {
		return fmt.Errorf("HTTP upload failed: %d", status)
	}
	deadline := time.Now().Add(o.replicationTimeout)
	for {
		status, data, err := o.request("GET", o.readHost, o.readIP, path, nil)
		if err != nil {
			return err
		}
		if status == 200 {
			if !bytes.Equal(data, payload) {
				return errors.New("HTTP artifact contents differ")
			}
			break
		}
		if status != 404 || !time.Now().Before(deadline) {
			return fmt.Errorf("HTTP download failed: %d", status)
		}
		time.Sleep(time.Second)
	}
	entry, err := o.grpc("BatchUpdateBlobs", o.host, o.writeIP, map[string]any{
		"instanceName": o.project, "requests": []any{map[string]any{"digest": d, "data": payload}},
	})
	if err != nil {
		return err
	}
	if entry.Status.Code != 0 || entry.Digest != d {
		return errors.New("REAPI upload failed or returned a different digest")
	}
	deadline = time.Now().Add(o.replicationTimeout)
	for {
		entry, err = o.grpc("BatchReadBlobs", o.readHost, o.readIP, map[string]any{"instanceName": o.project, "digests": []digest{d}})
		if err != nil {
			return err
		}
		if entry.Status.Code == 0 {
			if entry.Digest != d || !bytes.Equal(entry.Data, payload) {
				return errors.New("REAPI artifact contents differ")
			}
			break
		}
		if entry.Status.Code != 5 || !time.Now().Before(deadline) {
			return fmt.Errorf("REAPI download failed: %d", entry.Status.Code)
		}
		time.Sleep(time.Second)
	}
	record("roundtrip_passed", map[string]any{"sha256": d.Hash, "bytes": len(payload)})
	return nil
}

func run() error {
	if len(os.Args) < 2 || (os.Args[1] != "ready" && os.Args[1] != "roundtrip") {
		return errors.New("usage: staging-probe ready|roundtrip --host HOST --account ACCOUNT [options]")
	}
	mode := os.Args[1]
	var o options
	flags := flag.NewFlagSet("staging-probe", flag.ContinueOnError)
	flags.StringVar(&o.host, "host", "", "Staging cache hostname")
	flags.StringVar(&o.account, "account", "", "Test account handle")
	flags.StringVar(&o.project, "project", "probe", "Project/namespace")
	flags.StringVar(&o.tokenFile, "token-file", "", "Local cache token file")
	flags.StringVar(&o.writeIP, "write-ip", "", "Pin writes/ready to a box with normal TLS verification")
	flags.StringVar(&o.readIP, "read-ip", "", "Pin reads to a box")
	flags.StringVar(&o.readHost, "read-host", "", "Regional baseline read host (defaults to --host)")
	flags.StringVar(&o.grpcurl, "grpcurl", "grpcurl", "grpcurl executable")
	flags.IntVar(&o.repeat, "repeat", 1, "Number of round trips")
	flags.DurationVar(&o.interval, "interval", 5*time.Second, "Delay between round trips")
	flags.DurationVar(&o.replicationTimeout, "replication-timeout", time.Minute, "Maximum replication wait")
	if err := flags.Parse(os.Args[2:]); err != nil {
		return err
	}
	if flags.NArg() != 0 {
		return errors.New("unexpected positional arguments")
	}
	if o.readHost == "" {
		o.readHost = o.host
	}
	for _, host := range []string{o.host, o.readHost} {
		if !regexp.MustCompile(`^[a-z0-9][a-z0-9-]*-staging\.(cache|kura)\.tuist\.dev$`).MatchString(host) || o.account == "" || !strings.HasPrefix(host, o.account+"-") {
			return errors.New("only staging cache/kura hostnames belonging to the supplied test account are allowed")
		}
	}
	if o.repeat < 1 || o.interval < 0 || o.replicationTimeout < 0 {
		return errors.New("repeat must be positive and durations nonnegative")
	}
	if o.tokenFile != "" {
		data, err := os.ReadFile(o.tokenFile)
		if err != nil {
			return err
		}
		o.token = strings.TrimSpace(string(data))
		if !regexp.MustCompile(`^[A-Za-z0-9_.=+/-]+$`).MatchString(o.token) {
			return errors.New("invalid token format")
		}
	}
	if mode == "roundtrip" && o.token == "" {
		return errors.New("roundtrip requires --token-file")
	}
	if mode == "ready" {
		o.token = ""
	}
	var err error
	o.protoDir, err = os.MkdirTemp("", "spec95-proto-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(o.protoDir)
	if err = os.WriteFile(filepath.Join(o.protoDir, "reapi-smoke.proto"), proto, 0600); err != nil {
		return err
	}
	for i := 0; i < o.repeat; i++ {
		if mode == "roundtrip" {
			err = o.roundtrip()
		} else {
			var status int
			status, _, err = o.request("GET", o.host, o.writeIP, "/ready", nil)
			if err == nil && status != 200 {
				err = fmt.Errorf("readiness failed: %d", status)
			}
		}
		if err != nil {
			return err
		}
		if i+1 < o.repeat {
			time.Sleep(o.interval)
		}
	}
	return nil
}

func main() {
	if err := run(); err != nil {
		record("failed", map[string]any{"error": err.Error()})
		os.Exit(1)
	}
}
