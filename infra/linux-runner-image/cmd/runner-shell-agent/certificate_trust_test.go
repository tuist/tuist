package main

import (
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"errors"
	"fmt"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/gorilla/websocket"
)

func TestRunnerTrustRealPolicyDER(t *testing.T) {
	seen := map[string]bool{}
	for _, name := range []string{"issuer-roots.pem", "distrusted-intermediates.pem"} {
		data, err := os.ReadFile("testdata/certificate-trust/" + name)
		if err != nil {
			t.Fatal(err)
		}
		for len(data) > 0 {
			block, rest := pem.Decode(data)
			if block == nil || block.Type != "CERTIFICATE" {
				t.Fatal("invalid policy fixture")
			}
			data = rest
			certificate, err := x509.ParseCertificate(block.Bytes)
			if err != nil {
				t.Fatal(err)
			}
			seen[certificateSPKIHash(certificate)] = true
			if !errors.Is(requireAllowedCertificates([]*x509.Certificate{certificate}, nil), errDistrustedPublicKey) {
				t.Fatal("real policy key not denied")
			}
		}
	}
	if len(seen) != 12 || len(blockedCertificateSPKIHashes) != 12 {
		t.Fatal("expected twelve distinct keys")
	}
	for _, certificates := range [][]*x509.Certificate{nil, {nil}, {{}}} {
		if requireAllowedCertificates(certificates, nil) == nil {
			t.Fatal("missing or malformed certificates must fail closed")
		}
	}
}

type runnerTrustPKI struct {
	root, issuer, leaf *x509.Certificate
	identity           tls.Certificate
}

func newRunnerTrustPKI(t *testing.T, mutate func(*x509.Certificate)) runnerTrustPKI {
	t.Helper()
	key := func() *ecdsa.PrivateKey {
		value, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		return value
	}
	rootKey, issuerKey, leafKey := key(), key(), key()
	now := time.Now()
	root := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Fixture root"}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	issue := func(template, parent *x509.Certificate, public *ecdsa.PublicKey, signer *ecdsa.PrivateKey) *x509.Certificate {
		der, err := x509.CreateCertificate(rand.Reader, template, parent, public, signer)
		if err != nil {
			t.Fatal(err)
		}
		certificate, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatal(err)
		}
		return certificate
	}
	root = issue(root, root, &rootKey.PublicKey, rootKey)
	issuer := issue(&x509.Certificate{SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "Fixture issuer"}, NotBefore: root.NotBefore, NotAfter: root.NotAfter, IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}, root, &issuerKey.PublicKey, rootKey)
	leaf := &x509.Certificate{SerialNumber: big.NewInt(3), Subject: pkix.Name{CommonName: "localhost"}, NotBefore: root.NotBefore, NotAfter: root.NotAfter, DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, KeyUsage: x509.KeyUsageDigitalSignature}
	if mutate != nil {
		mutate(leaf)
	}
	leaf = issue(leaf, issuer, &leafKey.PublicKey, issuerKey)
	return runnerTrustPKI{root, issuer, leaf, tls.Certificate{Certificate: [][]byte{leaf.Raw, issuer.Raw}, PrivateKey: leafKey}}
}

func runnerTrustServer(t *testing.T, identity tls.Certificate, handler http.Handler) *httptest.Server {
	t.Helper()
	server := httptest.NewUnstartedServer(handler)
	server.TLS = &tls.Config{Certificates: []tls.Certificate{identity}}
	server.StartTLS()
	t.Cleanup(server.Close)
	return server
}

func runnerTestTLSConfig(t *testing.T, root *x509.Certificate, additional []string) *tls.Config {
	t.Helper()
	roots := x509.NewCertPool()
	if root != nil {
		roots.AddCert(root)
	}
	base := runnerTLSConfig()
	base.RootCAs = roots
	config, err := certificateTrustConfig(base, additional)
	if err != nil {
		t.Fatal(err)
	}
	return config
}

func runnerTestDiscovery(t *testing.T, endpoint string, config *tls.Config) error {
	t.Helper()
	transport := directHTTPTransport.Clone()
	transport.TLSClientConfig = config
	client := *directHTTPClientInstance
	client.Transport = transport
	original := directHTTPClientInstance
	directHTTPClientInstance = &client
	defer func() { directHTTPClientInstance = original; transport.CloseIdleConnections() }()
	_, err := discoverSession(endpoint, "fixture-token")
	return err
}

func TestRunnerTrustActualHTTPAndWSSAcceptedKeyDifferentials(t *testing.T) {
	pki := newRunnerTrustPKI(t, nil)
	var requests atomic.Int32
	server := runnerTrustServer(t, pki.identity, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requests.Add(1)
		if r.Header.Get("Authorization") != "Bearer fixture-token" {
			t.Error("missing fixture authorization")
		}
		if r.URL.Path == "/socket" {
			upgrader := websocket.Upgrader{}
			connection, err := upgrader.Upgrade(w, r, nil)
			if err != nil {
				t.Error("fixture upgrade failed")
				return
			}
			_ = connection.Close()
			return
		}
		_, _ = fmt.Fprint(w, `{"session_id":1,"websocket_url":"wss://fixture.invalid/socket"}`)
	}))
	for _, transport := range []string{"HTTP", "WSS"} {
		t.Run(transport, func(t *testing.T) {
			connect := func(additional []string) error {
				config := runnerTestTLSConfig(t, pki.root, additional)
				if transport == "HTTP" {
					return runnerTestDiscovery(t, server.URL, config)
				}
				connection, err := connectWebSocketWithTLS("wss"+strings.TrimPrefix(server.URL, "https")+"/socket", "fixture-token", config)
				if connection != nil {
					_ = connection.Close()
				}
				return err
			}
			before := requests.Load()
			if err := connect(nil); err != nil {
				t.Fatal(err)
			}
			for _, certificate := range []*x509.Certificate{pki.leaf, pki.issuer, pki.root} {
				if err := connect([]string{certificateSPKIHash(certificate)}); !errors.Is(err, errDistrustedPublicKey) {
					t.Fatal("accepted key not denied by actual transport")
				}
			}
			if requests.Load() != before+1 {
				t.Fatal("denied connection sent an HTTP request or bearer token")
			}
		})
	}
}

func TestRunnerTrustNormalVerification(t *testing.T) {
	for _, test := range []struct {
		name             string
		mutate           func(*x509.Certificate)
		unknown, corrupt bool
	}{
		{name: "unknown CA", unknown: true},
		{name: "hostname", mutate: func(c *x509.Certificate) { c.IPAddresses = nil; c.DNSNames = []string{"wrong.invalid"} }},
		{name: "expiry", mutate: func(c *x509.Certificate) {
			c.NotBefore = time.Now().Add(-2 * time.Hour)
			c.NotAfter = time.Now().Add(-time.Hour)
		}},
		{name: "usage", mutate: func(c *x509.Certificate) { c.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth} }},
		{name: "critical extension", mutate: func(c *x509.Certificate) {
			c.ExtraExtensions = []pkix.Extension{{Id: []int{1, 2, 3, 4, 5}, Critical: true, Value: []byte{5, 0}}}
		}},
		{name: "signature", corrupt: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			pki := newRunnerTrustPKI(t, test.mutate)
			if test.corrupt {
				leaf := append([]byte(nil), pki.identity.Certificate[0]...)
				leaf[len(leaf)-1] ^= 1
				pki.identity.Certificate[0] = leaf
			}
			server := runnerTrustServer(t, pki.identity, http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Error("invalid chain sent request") }))
			root := pki.root
			if test.unknown {
				root = nil
			}
			config := runnerTestTLSConfig(t, root, nil)
			for _, err := range []error{
				runnerTestDiscovery(t, server.URL, config),
				func() error {
					connection, err := connectWebSocketWithTLS("wss"+strings.TrimPrefix(server.URL, "https"), "fixture-token", config)
					if connection != nil {
						_ = connection.Close()
					}
					return err
				}(),
			} {
				var certificateError *tls.CertificateVerificationError
				if !errors.As(err, &certificateError) || errors.Is(err, errDistrustedPublicKey) {
					t.Fatal("normal verifier must reject for a certificate-specific cause")
				}
			}
		})
	}
}

func TestRunnerTrustConfigurationAndPrivacy(t *testing.T) {
	if directHTTPTransport.Proxy != nil || directHTTPTransport.DialTLSContext != nil || directHTTPTransport.DialTLS != nil || directHTTPTransport.TLSClientConfig.RootCAs != nil || directHTTPTransport.TLSClientConfig.MinVersion != tls.VersionTLS12 || directHTTPClientInstance.CheckRedirect == nil {
		t.Fatal("direct/native transport settings changed")
	}
	if _, err := certificateTrustConfig(&tls.Config{InsecureSkipVerify: true}, nil); err == nil {
		t.Fatal("disabled validation accepted")
	}
	if _, err := connectWebSocketWithTLS("wss://fixture.invalid", "fixture-token", &tls.Config{InsecureSkipVerify: true}); err == nil {
		t.Fatal("WSS accepted disabled validation")
	}
	pki := newRunnerTrustPKI(t, nil)
	state := tls.ConnectionState{PeerCertificates: []*x509.Certificate{pki.leaf, pki.issuer}, VerifiedChains: [][]*x509.Certificate{{pki.leaf, pki.issuer, pki.root}}}
	originalError := errors.New("original verifier refused")
	base := &tls.Config{MinVersion: tls.VersionTLS12, VerifyConnection: func(tls.ConnectionState) error { return originalError }}
	config, err := certificateTrustConfig(base, nil)
	if err != nil || !errors.Is(config.VerifyConnection(state), originalError) {
		t.Fatal("original verifier lost")
	}
	additional := []string{certificateSPKIHash(pki.root)}
	config, err = certificateTrustConfig(nil, additional)
	if err != nil {
		t.Fatal(err)
	}
	additional[0] = "changed"
	state.DidResume = true
	if !errors.Is(config.VerifyConnection(state), errDistrustedPublicKey) {
		t.Fatal("resumed chain or immutable deny lost")
	}
	if config.VerifyConnection(tls.ConnectionState{}) == nil {
		t.Fatal("missing verified chain accepted")
	}
	for _, raw := range []string{"https://user:password@[bad]?token=secret", "wss://user:password@[bad]?token=secret"} {
		_, err := connectWebSocket(raw, "fixture-token")
		if err == nil || strings.Contains(err.Error(), "password") || strings.Contains(err.Error(), "secret") {
			t.Fatal("URL leaked")
		}
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = fmt.Fprint(w, "secret-response-body")
	}))
	defer server.Close()
	_, err = connectWebSocket("ws"+strings.TrimPrefix(server.URL, "http"), "fixture-token")
	if err == nil || strings.Contains(err.Error(), "secret-response-body") {
		t.Fatal("handshake body leaked")
	}
	cause := &url.Error{Op: "Get", URL: "https://user:password@fixture.invalid?token=secret", Err: errDistrustedPublicKey}
	if value := (runnerConnectionError{cause}); !errors.Is(value, errDistrustedPublicKey) || strings.Contains(value.Error(), "secret") || strings.Contains(value.Error(), "password") {
		t.Fatal("typed privacy wrapper lost")
	}
}

func TestRunnerTrustRejectsDiscoveryDowngrade(t *testing.T) {
	t.Setenv("TUIST_RUNNER_SHELL_USE_DISCOVERY_ORIGIN", "0")
	if _, err := sessionWebSocketURL(runnerSession{WebSocketURL: "ws://fixture.invalid/socket"}, "https://fixture.invalid/sessions"); err == nil {
		t.Fatal("raw-origin opt-out allowed WSS downgrade")
	}
	if _, err := sessionWebSocketURL(runnerSession{WebSocketURL: "wss://fixture.invalid/socket"}, "https://fixture.invalid/sessions"); err != nil {
		t.Fatal("raw secure origin refused")
	}
	pki := newRunnerTrustPKI(t, nil)
	var requests atomic.Int32
	plain := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { requests.Add(1) }))
	defer plain.Close()
	secure := runnerTrustServer(t, pki.identity, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, plain.URL, http.StatusFound) }))
	if err := runnerTestDiscovery(t, secure.URL, runnerTestTLSConfig(t, pki.root, nil)); err == nil || requests.Load() != 0 {
		t.Fatal("HTTPS downgrade followed")
	}
}

func TestRunnerTrustLive(t *testing.T) {
	if os.Getenv("TUIST_TRUST_LIVE") != "1" {
		t.Skip("set TUIST_TRUST_LIVE=1 for credential-free public controls")
	}
	t.Log("TUIST_TRUST_LIVE=1: actual session-discovery HTTP transport; no bearer credentials")
	for _, prefix := range []string{"dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"} {
		for _, issuer := range []string{"emudhra", "aaa-emudhra"} {
			endpoint := "https://" + prefix + "-" + issuer + ".we-have-a-problem.com/"
			response, err := directHTTPClient().Get(endpoint)
			if response != nil {
				_ = response.Body.Close()
			}
			var native *tls.CertificateVerificationError
			if err == nil || (!errors.Is(err, errDistrustedPublicKey) && !errors.As(err, &native)) {
				t.Fatal("public control did not fail for a certificate-specific cause")
			}
			t.Logf("%s/%s native_verifier=%t application_key_deny=%t", prefix, issuer, errors.As(err, &native), errors.Is(err, errDistrustedPublicKey))
		}
	}
	response, err := directHTTPClient().Get("https://letsencrypt.org/")
	if err != nil {
		t.Fatal("unrelated HTTPS failed")
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatal("unrelated HTTPS not 200")
	}
}
