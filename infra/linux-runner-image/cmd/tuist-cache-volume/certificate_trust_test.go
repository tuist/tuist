package main

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"errors"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"reflect"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
)

type trustFixture struct {
	root, issuer, leaf *x509.Certificate
	server             tls.Certificate
}

func makeTrustFixture(t *testing.T, change func(*x509.Certificate)) trustFixture {
	t.Helper()
	makeKey := func() (ed25519.PublicKey, ed25519.PrivateKey) {
		public, private, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		return public, private
	}
	issue := func(template, parent *x509.Certificate, key ed25519.PublicKey, signer ed25519.PrivateKey) *x509.Certificate {
		der, err := x509.CreateCertificate(rand.Reader, template, parent, key, signer)
		if err != nil {
			t.Fatal(err)
		}
		certificate, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatal(err)
		}
		return certificate
	}
	rootPublic, rootKey := makeKey()
	now := time.Now()
	rootTemplate := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "unrelated test root"}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	root := issue(rootTemplate, rootTemplate, rootPublic, rootKey)
	issuerPublic, issuerKey := makeKey()
	issuerTemplate := &x509.Certificate{SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "unrelated test issuer"}, NotBefore: root.NotBefore, NotAfter: root.NotAfter, IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	issuer := issue(issuerTemplate, root, issuerPublic, rootKey)
	leafPublic, leafKey := makeKey()
	leafTemplate := &x509.Certificate{SerialNumber: big.NewInt(3), Subject: pkix.Name{CommonName: "localhost"}, NotBefore: root.NotBefore, NotAfter: root.NotAfter, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, KeyUsage: x509.KeyUsageDigitalSignature}
	if change != nil {
		change(leafTemplate)
	}
	leaf := issue(leafTemplate, issuer, leafPublic, issuerKey)
	return trustFixture{root, issuer, leaf, tls.Certificate{Certificate: [][]byte{leaf.Raw, issuer.Raw}, PrivateKey: leafKey}}
}

func fixtureClient(t *testing.T, fixture trustFixture, blocked []string) *http.Client {
	t.Helper()
	roots := x509.NewCertPool()
	roots.AddCert(fixture.root)
	client, err := cacheHTTPClient(5*time.Second, &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots}}, blocked)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(client.CloseIdleConnections)
	return client
}

func fixtureServer(t *testing.T, fixture trustFixture, handler http.Handler) *httptest.Server {
	t.Helper()
	server := httptest.NewUnstartedServer(handler)
	server.Config.ErrorLog = log.New(io.Discard, "", 0)
	server.TLS = &tls.Config{Certificates: []tls.Certificate{fixture.server}}
	server.StartTLS()
	t.Cleanup(server.Close)
	return server
}

func cacheOperations(t *testing.T, endpoint string) map[string]func(*http.Client) error {
	t.Helper()
	t.Setenv("TUIST_CACHE_VOLUME_URL", endpoint)
	t.Setenv("TUIST_CACHE_VOLUME_POD", "fixture-pod-private")
	t.Setenv("TUIST_CACHE_VOLUME_UID", "fixture-uid-private")
	return map[string]func(*http.Client) error{
		"acquire": func(client *http.Client) error { _, _, _, err := acquire(client, "fixture-key-private", 0); return err },
		"checkout": func(client *http.Client) error {
			_, err := (&linuxCheckoutClient{endpoint: endpoint, pod: "fixture-pod-private", uid: "fixture-uid-private", http: client}).request(context.Background())
			return err
		},
		"export": func(client *http.Client) error {
			return (&linuxCheckoutClient{endpoint: endpoint, pod: "fixture-pod-private", uid: "fixture-uid-private", http: client}).upload(context.Background(), strings.NewReader("fixture-export-private"))
		},
	}
}

func TestCacheTrustRealTwelveKeys(t *testing.T) {
	seen := map[string]bool{}
	for _, path := range []string{"issuer-roots.pem", "distrusted-intermediates.pem"} {
		data, err := os.ReadFile("testdata/certificate-trust/" + path)
		if err != nil {
			t.Fatal(err)
		}
		for len(data) > 0 {
			var block *pem.Block
			block, data = pem.Decode(data)
			if block == nil {
				t.Fatal("invalid fixture")
			}
			certificate, err := x509.ParseCertificate(block.Bytes)
			if err != nil {
				t.Fatal(err)
			}
			seen[certificateSPKIHash(certificate)] = true
			if !errors.Is(requireAllowedCertificates([]*x509.Certificate{certificate}, nil), errDistrustedPublicKey) {
				t.Fatal("accepted incident key")
			}
		}
	}
	if len(seen) != 12 {
		t.Fatalf("checked %d keys, want twelve", len(seen))
	}
	for _, material := range [][]*x509.Certificate{nil, {nil}, {{}}} {
		if requireAllowedCertificates(material, nil) == nil {
			t.Fatal("accepted absent SPKI")
		}
	}
}

func TestCacheTrustAllHTTPPathsDenyAcceptedKeysBeforeSendingData(t *testing.T) {
	fixture := makeTrustFixture(t, nil)
	var hits atomic.Int32
	server := fixtureServer(t, fixture, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		if r.Header.Get("Authorization") != "" {
			t.Error("helper acquired a workflow credential")
		}
		io.Copy(io.Discard, r.Body)
		if strings.HasPrefix(r.URL.Path, "/checkout-export") {
			w.WriteHeader(http.StatusAccepted)
			return
		}
		io.WriteString(w, `{"directory":"`+strings.Repeat("a", 64)+`","id":"fixture-lease","warm":true}`)
	}))
	for operation, call := range cacheOperations(t, server.URL) {
		t.Run(operation, func(t *testing.T) {
			if err := call(fixtureClient(t, fixture, nil)); err != nil {
				t.Fatal(err)
			}
			for kind, certificate := range map[string]*x509.Certificate{"leaf": fixture.leaf, "intermediate": fixture.issuer, "absent-peer-root": fixture.root} {
				t.Run(kind, func(t *testing.T) {
					before := hits.Load()
					err := call(fixtureClient(t, fixture, []string{certificateSPKIHash(certificate)}))
					if !errors.Is(err, errDistrustedPublicKey) {
						t.Fatalf("not application key denial: %v", err)
					}
					if hits.Load() != before {
						t.Fatal("sent a request/body to the rejected chain")
					}
				})
			}
		})
	}
}

func TestCacheTrustOrdinaryVerificationRemainsAuthoritative(t *testing.T) {
	for _, kind := range []string{"unknown-ca", "hostname", "expiry", "signature", "usage", "critical-extension"} {
		t.Run(kind, func(t *testing.T) {
			fixture := makeTrustFixture(t, func(leaf *x509.Certificate) {
				switch kind {
				case "expiry":
					leaf.NotAfter = time.Now().Add(-time.Minute)
				case "usage":
					leaf.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth}
				case "critical-extension":
					leaf.ExtraExtensions = []pkix.Extension{{Id: []int{1, 2, 3, 99}, Critical: true, Value: []byte{5, 0}}}
				}
			})
			if kind == "signature" {
				der := append([]byte(nil), fixture.leaf.Raw...)
				der[len(der)-1] ^= 1
				fixture.server.Certificate[0] = der
			}
			var hits atomic.Int32
			server := fixtureServer(t, fixture, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { hits.Add(1) }))
			client := fixtureClient(t, fixture, nil)
			config := client.Transport.(*http.Transport).TLSClientConfig
			if kind == "unknown-ca" {
				config.RootCAs = x509.NewCertPool()
			}
			if kind == "hostname" {
				config.ServerName = "wrong.invalid"
			}
			for operation, call := range cacheOperations(t, server.URL) {
				err := call(client)
				var native *tls.CertificateVerificationError
				if !errors.As(err, &native) || errors.Is(err, errDistrustedPublicKey) {
					t.Fatalf("%s: not native rejection: %v", operation, err)
				}
			}
			if hits.Load() != 0 {
				t.Fatal("delivered an unverified request")
			}
		})
	}
}

func TestCacheTrustFactoryPreservesConfigurationAndNeverRedirects(t *testing.T) {
	client, err := newCacheHTTPClient(20 * time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer client.CloseIdleConnections()
	transport := client.Transport.(*http.Transport)
	original := http.DefaultTransport.(*http.Transport)
	if client.Timeout != 20*time.Second || transport == original || transport.TLSClientConfig.RootCAs != nil || transport.TLSClientConfig.ClientSessionCache != nil {
		t.Fatal("changed native roots/session/default ownership")
	}
	if reflect.ValueOf(transport.Proxy).Pointer() != reflect.ValueOf(original.Proxy).Pointer() || transport.TLSHandshakeTimeout != original.TLSHandshakeTimeout || transport.ForceAttemptHTTP2 != original.ForceAttemptHTTP2 || transport.IdleConnTimeout != original.IdleConnTimeout {
		t.Fatal("changed proxy/HTTP2/timeouts")
	}
	for _, timeout := range []time.Duration{20 * time.Second, 3 * time.Minute} {
		checkout, err := newLinuxCheckoutClient(timeout)
		if err != nil {
			t.Fatal(err)
		}
		if checkout.http.Timeout != timeout || checkout.http.Transport.(*http.Transport).TLSClientConfig.VerifyConnection == nil {
			t.Fatal("unprotected checkout/export factory")
		}
		checkout.http.CloseIdleConnections()
	}
	fixture := makeTrustFixture(t, nil)
	var destinationHits atomic.Int32
	destination := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { destinationHits.Add(1) }))
	defer destination.Close()
	for _, status := range []int{301, 302, 303, 307, 308} {
		server := fixtureServer(t, fixture, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			http.Redirect(w, r, destination.URL+"?credential=fixture-secret", status)
		}))
		for operation, call := range cacheOperations(t, server.URL) {
			if err := call(fixtureClient(t, fixture, nil)); err == nil {
				t.Fatalf("%s accepted redirect %d", operation, status)
			}
		}
	}
	if destinationHits.Load() != 0 {
		t.Fatal("followed redirect or downgrade")
	}
}

func TestCacheTrustCallbacksAndUnsafeConfigurations(t *testing.T) {
	fixture := makeTrustFixture(t, nil)
	state := tls.ConnectionState{VerifiedChains: [][]*x509.Certificate{{fixture.leaf, fixture.issuer, fixture.root}}, PeerCertificates: []*x509.Certificate{fixture.leaf, fixture.issuer}, DidResume: true}
	originalError := errors.New("original callback refused")
	calls := 0
	base := &http.Transport{TLSClientConfig: &tls.Config{VerifyConnection: func(tls.ConnectionState) error { calls++; return originalError }}}
	protected, err := certificateTrustTransport(base, nil)
	if err != nil {
		t.Fatal(err)
	}
	if !errors.Is(protected.TLSClientConfig.VerifyConnection(state), originalError) || calls != 1 {
		t.Fatal("lost original callback")
	}
	if base.TLSClientConfig == protected.TLSClientConfig {
		t.Fatal("mutated caller's TLS config")
	}
	blocked := []string{certificateSPKIHash(fixture.root)}
	protected, err = certificateTrustTransport(&http.Transport{}, blocked)
	if err != nil {
		t.Fatal(err)
	}
	blocked[0] = "changed-after-construction"
	if !errors.Is(protected.TLSClientConfig.VerifyConnection(state), errDistrustedPublicKey) {
		t.Fatal("lost copied anchor deny on resumed callback state")
	}
	state.VerifiedChains = nil
	if protected.TLSClientConfig.VerifyConnection(state) == nil {
		t.Fatal("accepted absent verified path")
	}
	for _, unsafe := range []*http.Transport{nil, {TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}, {DialTLS: func(string, string) (net.Conn, error) { t.Fatal("used unsafe dialer"); return nil, nil }}, {DialTLSContext: func(context.Context, string, string) (net.Conn, error) {
		t.Fatal("used unsafe dialer")
		return nil, nil
	}}} {
		if _, err := certificateTrustTransport(unsafe, nil); err == nil {
			t.Fatal("accepted unsafe transport")
		}
	}
}

func TestCacheTrustDiagnosticsCancellationAndJSON(t *testing.T) {
	secret := "fixture-credential-private"
	for _, cause := range []error{errDistrustedPublicKey, &tls.CertificateVerificationError{Err: errors.New(secret)}, context.Canceled, context.DeadlineExceeded, errors.New(secret), &url.Error{Op: "parse", URL: "https://user:" + secret + "@example.invalid/" + secret, Err: errors.New(secret)}} {
		err := cacheRequestError{&url.Error{Op: "Post", URL: "https://example.invalid/?secret=" + secret, Err: cause}}
		if strings.Contains(err.Error(), secret) || !errors.Is(err, cause) {
			t.Fatal("leaked diagnostic or lost typed cause")
		}
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { io.WriteString(w, `{"`+secret+`":[]}`) }))
	defer server.Close()
	req, _ := http.NewRequest("GET", server.URL, nil)
	var result map[string]string
	err := requestJSON(server.Client(), req, &result)
	var jsonError *json.UnmarshalTypeError
	if !errors.As(err, &jsonError) || strings.Contains(err.Error(), secret) {
		t.Fatal("JSON diagnostic is not typed/private")
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	client := fixtureClient(t, makeTrustFixture(t, nil), nil)
	checkout := &linuxCheckoutClient{endpoint: "https://user:" + secret + "@127.0.0.1:1", pod: secret, uid: secret, http: client}
	if err := checkout.upload(ctx, strings.NewReader(secret)); !errors.Is(err, context.Canceled) || strings.Contains(err.Error(), secret) {
		t.Fatal("upload cancellation not private/typed", err)
	}
	for operation, call := range cacheOperations(t, "http://[invalid-"+secret) {
		if err := call(client); err == nil || strings.Contains(err.Error(), secret) {
			t.Fatalf("%s exposed invalid endpoint", operation)
		}
	}
}

func TestCacheTrustNetworkDiagnosticsKeepUsefulCategories(t *testing.T) {
	for _, test := range []struct {
		cause   error
		message string
	}{
		{&net.DNSError{Name: "private-host-fixture", Err: "private-resolver-fixture"}, "cache service DNS lookup failed"},
		{&net.OpError{Op: "dial", Err: syscall.ECONNREFUSED}, "cache service connection refused"},
		{context.Canceled, "cache service request canceled"},
		{context.DeadlineExceeded, "cache service request timed out"},
	} {
		err := cacheRequestError{test.cause}
		if err.Error() != test.message || !errors.Is(err, test.cause) {
			t.Fatal("lost fixed diagnostic category or typed cause")
		}
	}
}

func TestCacheTrustPublicControls(t *testing.T) {
	if os.Getenv("TUIST_TRUST_LIVE") != "1" {
		t.Skip("credential-free public controls are opt-in")
	}
	client, err := newCacheHTTPClient(20 * time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer client.CloseIdleConnections()
	for _, issuer := range []string{"emudhra", "aaa-emudhra"} {
		for _, prefix := range []string{"dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"} {
			response, err := client.Get("https://" + prefix + "-" + issuer + ".we-have-a-problem.com/")
			if response != nil {
				response.Body.Close()
			}
			var native *tls.CertificateVerificationError
			if !errors.Is(err, errDistrustedPublicKey) && !errors.As(err, &native) {
				t.Fatalf("%s/%s: not certificate-specific failure", issuer, prefix)
			}
			t.Logf("%s/%s native_verifier=%t application_key_deny=%t", issuer, prefix, errors.As(err, &native), errors.Is(err, errDistrustedPublicKey))
		}
	}
	response, err := client.Get("https://letsencrypt.org/")
	if err != nil {
		t.Fatal(cacheRequestError{err})
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		t.Fatalf("unrelated positive status %d", response.StatusCode)
	}
}
