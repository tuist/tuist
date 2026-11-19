package plugin

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
)

func TestCertificateTrustHTTPSRedirectUsesProtectedTransport(t *testing.T) {
	first, second := newTrustTestPKI(t, nil), newTrustTestPKI(t, nil)
	var requests atomic.Int32
	destination := trustTestServer(t, second.identity, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { requests.Add(1); w.WriteHeader(http.StatusOK) }))
	origin := trustTestServer(t, first.identity, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, destination.URL, http.StatusFound) }))
	roots := x509.NewCertPool()
	roots.AddCert(first.root)
	roots.AddCert(second.root)
	if err := trustTestClient(t, origin.URL, roots, nil).get(context.Background(), "/", nil, nil); err != nil {
		t.Fatal(err)
	}
	err := trustTestClient(t, origin.URL, roots, []string{certificateSPKIHash(second.leaf)}).get(context.Background(), "/", nil, nil)
	if !errors.Is(err, errDistrustedPublicKey) || requests.Load() != 1 {
		t.Fatal("redirect bypassed the protected verifier")
	}
}

func TestCertificateTrustHTTPSProxyUsesProtectedTransport(t *testing.T) {
	pki, targetPKI := newTrustTestPKI(t, nil), newTrustTestPKI(t, nil)
	var requests, connects atomic.Int32
	destination := trustTestServer(t, targetPKI.identity, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { requests.Add(1); w.WriteHeader(http.StatusOK) }))
	address := strings.TrimPrefix(destination.URL, "https://")
	proxy := trustTestServer(t, pki.identity, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect || r.Host != address {
			http.Error(w, "unexpected fixture destination", http.StatusBadRequest)
			return
		}
		connects.Add(1)
		upstream, err := net.Dial("tcp", address)
		if err != nil {
			t.Error(err)
			http.Error(w, "fixture unavailable", http.StatusBadGateway)
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
		go func() { _, _ = io.Copy(upstream, client); _ = upstream.Close(); close(done) }()
		_, _ = io.Copy(client, upstream)
		_ = client.Close()
		<-done
	}))
	proxyURL, err := url.Parse(proxy.URL)
	if err != nil {
		t.Fatal(err)
	}
	roots := x509.NewCertPool()
	roots.AddCert(pki.root)
	roots.AddCert(targetPKI.root)
	for index, deny := range [][]string{nil, {certificateSPKIHash(pki.root)}, {certificateSPKIHash(targetPKI.root)}} {
		client := trustTestClient(t, destination.URL, roots, deny)
		client.http.Transport.(*http.Transport).Proxy = http.ProxyURL(proxyURL)
		err := client.get(context.Background(), "/", nil, nil)
		client.http.CloseIdleConnections()
		if index == 0 && err != nil {
			t.Fatal("unrelated private HTTPS proxy was rejected")
		}
		if index > 0 && !errors.Is(err, errDistrustedPublicKey) {
			t.Fatal("HTTPS proxy or tunneled destination certificate bypassed policy")
		}
		if index == 1 && connects.Load() != 1 {
			t.Fatal("denied proxy received CONNECT")
		}
	}
	if connects.Load() != 2 || requests.Load() != 1 {
		t.Fatal("proxy or tunneled destination bypassed its certificate deny")
	}
}

func TestCertificateTrustResumedSessionStillDeniesAnchor(t *testing.T) {
	for _, version := range []uint16{tls.VersionTLS12, tls.VersionTLS13} {
		t.Run(tls.VersionName(version), func(t *testing.T) { testCertificateTrustResumedSession(t, version) })
	}
}

func testCertificateTrustResumedSession(t *testing.T, version uint16) {
	pki := newTrustTestPKI(t, nil)
	var resumed atomic.Bool
	server := trustTestServer(t, pki.identity, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) }))
	roots := x509.NewCertPool()
	roots.AddCert(pki.root)
	base := http.DefaultTransport.(*http.Transport).Clone()
	base.Proxy = nil
	base.DisableKeepAlives = true
	base.TLSClientConfig = &tls.Config{
		RootCAs: roots, MinVersion: version, MaxVersion: version,
		ClientSessionCache: tls.NewLRUClientSessionCache(1),
		VerifyConnection:   func(state tls.ConnectionState) error { resumed.Store(state.DidResume); return nil },
	}
	client := trustTestClient(t, server.URL, roots, nil)
	first, err := certificateTrustTransport(base, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer first.CloseIdleConnections()
	client.http.Transport = first
	if err := client.get(context.Background(), "/", nil, nil); err != nil {
		t.Fatal(err)
	}
	second, err := certificateTrustTransport(base, []string{certificateSPKIHash(pki.root)})
	if err != nil {
		t.Fatal(err)
	}
	defer second.CloseIdleConnections()
	client.http.Transport = second
	err = client.get(context.Background(), "/", nil, nil)
	if !resumed.Load() || !errors.Is(err, errDistrustedPublicKey) {
		t.Fatal("session resumption did not enforce the anchor deny")
	}
}
