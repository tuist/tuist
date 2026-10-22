package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestCacheTrustProtectsBothHTTPSProxyLegs(t *testing.T) {
	proxyPKI, targetPKI := makeTrustFixture(t, nil), makeTrustFixture(t, nil)
	var requests, connects atomic.Int32
	destination := fixtureServer(t, targetPKI, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.Header.Get("Proxy-Authorization") != "" {
			t.Error("proxy credential reached origin")
		}
		io.Copy(io.Discard, r.Body)
		if r.URL.Path == "/checkout-export" {
			w.WriteHeader(http.StatusAccepted)
			return
		}
		io.WriteString(w, `{}`)
	}))
	address := strings.TrimPrefix(destination.URL, "https://")
	proxy := fixtureServer(t, proxyPKI, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect || r.Host != address {
			http.Error(w, "invalid fixture target", http.StatusBadRequest)
			return
		}
		if r.Header.Get("Proxy-Authorization") != "Basic Zml4dHVyZTpmaXh0dXJlLXByb3h5LXNlY3JldA==" {
			t.Error("lost proxy authentication")
		}
		connects.Add(1)
		upstream, err := net.Dial("tcp", address)
		if err != nil {
			t.Error(err)
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		defer upstream.Close()
		client, _, err := w.(http.Hijacker).Hijack()
		if err != nil {
			t.Error(err)
			return
		}
		defer client.Close()
		if _, err := io.WriteString(client, "HTTP/1.1 200 Connection Established\r\n\r\n"); err != nil {
			return
		}
		done := make(chan struct{})
		go func() { io.Copy(upstream, client); upstream.Close(); close(done) }()
		io.Copy(client, upstream)
		client.Close()
		<-done
	}))
	proxyURL, err := url.Parse(proxy.URL)
	if err != nil {
		t.Fatal(err)
	}
	proxyURL.User = url.UserPassword("fixture", "fixture-proxy-secret")
	roots := x509.NewCertPool()
	roots.AddCert(proxyPKI.root)
	roots.AddCert(targetPKI.root)
	base := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots}, Proxy: http.ProxyURL(proxyURL)}
	for operation, call := range cacheOperations(t, destination.URL) {
		t.Run(operation, func(t *testing.T) {
			for phase, deny := range [][]string{nil, {certificateSPKIHash(proxyPKI.root)}, {certificateSPKIHash(targetPKI.root)}} {
				client, err := cacheHTTPClient(5*time.Second, base, deny)
				if err != nil {
					t.Fatal(err)
				}
				beforeConnects, beforeRequests := connects.Load(), requests.Load()
				err = call(client)
				client.CloseIdleConnections()
				if phase == 0 {
					if err != nil || requests.Load() != beforeRequests+1 {
						t.Fatal("native private proxy/target failed", err)
					}
				} else {
					if !errors.Is(err, errDistrustedPublicKey) || requests.Load() != beforeRequests {
						t.Fatal("protected proxy/target path was bypassed", err)
					}
					if phase == 1 && connects.Load() != beforeConnects {
						t.Fatal("rejected proxy received CONNECT credentials")
					}
					if phase == 2 && connects.Load() != beforeConnects+1 {
						t.Fatal("did not exercise TLS within a clean CONNECT tunnel")
					}
				}
			}
		})
	}
}

func TestCacheTrustConfiguredWireResumptionStillChecksAnchor(t *testing.T) {
	for _, version := range []uint16{tls.VersionTLS12, tls.VersionTLS13} {
		t.Run(tls.VersionName(version), func(t *testing.T) {
			fixture := makeTrustFixture(t, nil)
			var resumed atomic.Bool
			var hits atomic.Int32
			server := fixtureServer(t, fixture, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { hits.Add(1); io.WriteString(w, `{}`) }))
			roots := x509.NewCertPool()
			roots.AddCert(fixture.root)
			base := &http.Transport{DisableKeepAlives: true, TLSClientConfig: &tls.Config{
				RootCAs: roots, MinVersion: version, MaxVersion: version,
				ClientSessionCache: tls.NewLRUClientSessionCache(1),
				VerifyConnection:   func(state tls.ConnectionState) error { resumed.Store(state.DidResume); return nil },
			}}
			call := cacheOperations(t, server.URL)["acquire"]
			first, err := cacheHTTPClient(5*time.Second, base, nil)
			if err != nil {
				t.Fatal(err)
			}
			defer first.CloseIdleConnections()
			if err := call(first); err != nil {
				t.Fatal(err)
			}
			second, err := cacheHTTPClient(5*time.Second, base, []string{certificateSPKIHash(fixture.root)})
			if err != nil {
				t.Fatal(err)
			}
			defer second.CloseIdleConnections()
			if err := call(second); !errors.Is(err, errDistrustedPublicKey) || !resumed.Load() {
				t.Fatal("did not reject the accepted cached anchor on wire resumption", err)
			}
			if hits.Load() != 1 {
				t.Fatal("resumed rejected session delivered a request")
			}
		})
	}
}

func TestCacheTrustFailurePreservesColdAndCheckoutGrantSemantics(t *testing.T) {
	fixture := makeTrustFixture(t, nil)
	var hits atomic.Int32
	server := fixtureServer(t, fixture, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { hits.Add(1); io.WriteString(w, `{}`) }))
	client := fixtureClient(t, fixture, []string{certificateSPKIHash(fixture.root)})
	t.Setenv("TUIST_CACHE_VOLUME_URL", server.URL)
	t.Setenv("GITHUB_OUTPUT", filepath.Join(t.TempDir(), "output"))
	if err := os.WriteFile(os.Getenv("GITHUB_OUTPUT"), nil, 0600); err != nil {
		t.Fatal(err)
	}
	work := t.TempDir()
	cache := filepath.Join(work, "_tuist_cache")
	workspace := filepath.Join(work, "repo", "repo")
	target := filepath.Join(work, "dependencies")
	if err := attachWithMounter("fixture-key", []string{target}, cache, 0, client, func(string, string, string) error { t.Fatal("mounted after TLS failure"); return nil }); err != nil {
		t.Fatal(err)
	}
	entries, err := os.ReadDir(target)
	if err != nil || len(entries) != 0 {
		t.Fatal("did not retain empty-directory fallback", err)
	}
	output, err := os.ReadFile(os.Getenv("GITHUB_OUTPUT"))
	if err != nil || string(output) != "cache-hit=false\n" {
		t.Fatal("reported a cache hit after rejected TLS", err)
	}
	state := filepath.Join(work, "checkout-state.json")
	checkout := &linuxCheckoutClient{endpoint: server.URL, pod: "fixture-pod", uid: "fixture-uid", http: client}
	if status := checkoutLinuxAt(context.Background(), workspace, cache, state, checkout.request, func(string, string, string, string) error { t.Fatal("mounted checkout after TLS failure"); return nil }); status != "unavailable (request)" {
		t.Fatal(status)
	}
	if _, err := os.Stat(state); !os.IsNotExist(err) {
		t.Fatal("recorded export permission without a verified host grant")
	}
	if hits.Load() != 0 {
		t.Fatal("rejected host received job metadata")
	}
}
