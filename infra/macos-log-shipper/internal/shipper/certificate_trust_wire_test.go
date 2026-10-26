package shipper

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"io"
	"log"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestActualTLS12And13ResumedAnchorIsDenied(t *testing.T) {
	for _, version := range []uint16{tls.VersionTLS12, tls.VersionTLS13} {
		t.Run(tls.VersionName(version), func(t *testing.T) {
			fixture := makeTrustFixture(t, nil)
			var requests atomic.Int32
			server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { requests.Add(1); w.WriteHeader(204) }))
			server.Config.ErrorLog = log.New(io.Discard, "", 0)
			server.TLS = &tls.Config{Certificates: []tls.Certificate{fixture.server}, MinVersion: version, MaxVersion: version}
			server.StartTLS()
			defer server.Close()
			roots := x509.NewCertPool()
			roots.AddCert(fixture.root)
			var resumed atomic.Bool
			config := &tls.Config{RootCAs: roots, MinVersion: version, MaxVersion: version, ClientSessionCache: tls.NewLRUClientSessionCache(2), VerifyConnection: func(state tls.ConnectionState) error {
				if state.DidResume {
					resumed.Store(true)
				}
				return nil
			}}
			base := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{TLSClientConfig: config, DisableKeepAlives: true}}
			defer base.CloseIdleConnections()
			response, err := base.Get(server.URL)
			if err != nil {
				t.Fatal(err)
			}
			io.Copy(io.Discard, response.Body)
			response.Body.Close()
			protected, err := certificateTrustClient(base, []string{spkiHash(fixture.root)})
			if err != nil {
				t.Fatal(err)
			}
			defer protected.CloseIdleConnections()
			err = push(t, fixtureShipper(server.URL, protected))
			if !errors.Is(err, errDistrustedKey) || !resumed.Load() || requests.Load() != 1 {
				t.Fatal("resumed anchor not checked before log delivery", err, resumed.Load(), requests.Load())
			}
		})
	}
}

func TestActualHTTPSProxyAndOriginHaveIndependentProtectedPaths(t *testing.T) {
	proxyPKI, targetPKI := makeTrustFixture(t, nil), makeTrustFixture(t, nil)
	var connects, delivered atomic.Int32
	origin := fixtureServer(t, targetPKI, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Proxy-Authorization") != "" {
			t.Error("proxy credential at origin")
		}
		delivered.Add(1)
		io.Copy(io.Discard, r.Body)
		w.WriteHeader(204)
	}))
	address := strings.TrimPrefix(origin.URL, "https://")
	proxy := fixtureServer(t, proxyPKI, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodConnect || r.Host != address || r.Header.Get("Proxy-Authorization") != "Basic cHJveHk6c2VjcmV0" {
			t.Error("invalid CONNECT routing or credential")
			w.WriteHeader(400)
			return
		}
		connects.Add(1)
		target, err := net.DialTimeout("tcp", address, time.Second)
		if err != nil {
			t.Error(err)
			w.WriteHeader(502)
			return
		}
		defer target.Close()
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
		go func() { io.Copy(target, client); target.Close(); close(done) }()
		io.Copy(client, target)
		client.Close()
		<-done
	}))
	proxyURL, err := url.Parse(proxy.URL)
	if err != nil {
		t.Fatal(err)
	}
	proxyURL.User = url.UserPassword("proxy", "secret")
	roots := x509.NewCertPool()
	roots.AddCert(proxyPKI.root)
	roots.AddCert(targetPKI.root)
	base := &http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{Proxy: http.ProxyURL(proxyURL), TLSClientConfig: &tls.Config{RootCAs: roots}}}
	defer base.CloseIdleConnections()
	for phase, certificates := range [][]*x509.Certificate{nil, {proxyPKI.root}, {proxyPKI.issuer}, {proxyPKI.leaf}, {targetPKI.root}, {targetPKI.issuer}, {targetPKI.leaf}, nil} {
		var blocked []string
		for _, certificate := range certificates {
			blocked = append(blocked, spkiHash(certificate))
		}
		client, err := certificateTrustClient(base, blocked)
		if err != nil {
			t.Fatal(err)
		}
		beforeConnects, beforeDelivered := connects.Load(), delivered.Load()
		err = push(t, fixtureShipper(origin.URL, client))
		client.CloseIdleConnections()
		if phase == 0 || phase == 7 {
			if err != nil || delivered.Load() != beforeDelivered+1 {
				t.Fatal("ordinary proxy/target acceptance", err)
			}
			continue
		}
		if !errors.Is(err, errDistrustedKey) || delivered.Load() != beforeDelivered {
			t.Fatal("denied path accepted logs", err)
		}
		if phase <= 3 && connects.Load() != beforeConnects {
			t.Fatal("denied proxy accepted credential")
		}
		if phase >= 4 && connects.Load() != beforeConnects+1 {
			t.Fatal("target refusal was not through CONNECT")
		}
	}
}

func TestCancellationRemainsRetryableWithoutOffsetDrop(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	client := &Client{URL: "http://127.0.0.1:1/"}
	defer client.CloseIdleConnections()
	err := client.Push(ctx, map[string]string{}, []Entry{{Timestamp: time.Now(), Line: "private-line"}})
	if !errors.Is(err, context.Canceled) || errors.Is(err, ErrRejected) {
		t.Fatal("cancel cause or rejection semantics changed", err)
	}
}
