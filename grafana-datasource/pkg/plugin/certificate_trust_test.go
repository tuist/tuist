package plugin

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"errors"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
)

func TestCertificateTrustRealPolicyDER(t *testing.T) {
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
				t.Fatal("real policy key was not denied")
			}
		}
	}
	if len(seen) != 12 || len(blockedCertificateSPKIHashes) != 12 {
		t.Fatal("expected twelve distinct policy keys")
	}
	if requireAllowedCertificates(nil, nil) == nil || requireAllowedCertificates([]*x509.Certificate{nil}, nil) == nil {
		t.Fatal("empty certificate material must fail closed")
	}
}

type trustTestPKI struct {
	root, issuer, leaf *x509.Certificate
	identity           tls.Certificate
}

func newTrustTestPKI(t *testing.T, mutate func(*x509.Certificate)) trustTestPKI {
	t.Helper()
	key := func() *ecdsa.PrivateKey {
		value, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		return value
	}
	now := time.Now()
	rootKey, issuerKey, leafKey := key(), key(), key()
	root := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "Fixture root"}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	issue := func(template, parent *x509.Certificate, public *ecdsa.PublicKey, signer *ecdsa.PrivateKey) *x509.Certificate {
		der, err := x509.CreateCertificate(rand.Reader, template, parent, public, signer)
		if err != nil {
			t.Fatal(err)
		}
		value, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatal(err)
		}
		return value
	}
	root = issue(root, root, &rootKey.PublicKey, rootKey)
	issuer := issue(&x509.Certificate{SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "Fixture issuer"}, NotBefore: root.NotBefore, NotAfter: root.NotAfter, IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}, root, &issuerKey.PublicKey, rootKey)
	leaf := &x509.Certificate{SerialNumber: big.NewInt(3), Subject: pkix.Name{CommonName: "localhost"}, NotBefore: root.NotBefore, NotAfter: root.NotAfter, DNSNames: []string{"localhost"}, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, KeyUsage: x509.KeyUsageDigitalSignature}
	if mutate != nil {
		mutate(leaf)
	}
	leaf = issue(leaf, issuer, &leafKey.PublicKey, issuerKey)
	return trustTestPKI{root, issuer, leaf, tls.Certificate{Certificate: [][]byte{leaf.Raw, issuer.Raw}, PrivateKey: leafKey}}
}

func trustTestServer(t *testing.T, identity tls.Certificate, handler http.Handler) *httptest.Server {
	t.Helper()
	server := httptest.NewUnstartedServer(handler)
	server.TLS = &tls.Config{Certificates: []tls.Certificate{identity}}
	server.StartTLS()
	t.Cleanup(server.Close)
	return server
}

func trustTestClient(t *testing.T, endpoint string, roots *x509.CertPool, additional []string) *tuistClient {
	t.Helper()
	data, err := json.Marshal(map[string]string{"url": endpoint})
	if err != nil {
		t.Fatal(err)
	}
	client, err := newTuistClient(backend.DataSourceInstanceSettings{JSONData: data})
	if err != nil {
		t.Fatal(err)
	}
	base := http.DefaultTransport.(*http.Transport).Clone()
	base.Proxy = nil
	base.TLSClientConfig = &tls.Config{RootCAs: roots}
	transport, err := certificateTrustTransport(base, additional)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(transport.CloseIdleConnections)
	client.http.Transport = transport
	return client
}

func TestCertificateTrustActualClientAcceptedChainDifferentials(t *testing.T) {
	pki := newTrustTestPKI(t, nil)
	var requests atomic.Int32
	server := trustTestServer(t, pki.identity, http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		requests.Add(1)
		w.WriteHeader(http.StatusOK)
	}))
	roots := x509.NewCertPool()
	roots.AddCert(pki.root)
	if err := trustTestClient(t, server.URL, roots, nil).get(context.Background(), "/", nil, nil); err != nil {
		t.Fatal(err)
	}
	for _, certificate := range []*x509.Certificate{pki.leaf, pki.issuer, pki.root} {
		err := trustTestClient(t, server.URL, roots, []string{certificateSPKIHash(certificate)}).get(context.Background(), "/", nil, nil)
		if !errors.Is(err, errDistrustedPublicKey) {
			t.Fatal("accepted chain key was not denied by the actual HTTP client")
		}
	}
	if requests.Load() != 1 {
		t.Fatal("a denied TLS connection sent an HTTP request")
	}
}

func TestCertificateTrustPreservesOrdinaryVerification(t *testing.T) {
	for _, test := range []struct {
		name    string
		mutate  func(*x509.Certificate)
		unknown bool
		corrupt bool
	}{
		{name: "unknown CA", unknown: true},
		{name: "hostname", mutate: func(leaf *x509.Certificate) { leaf.IPAddresses = nil; leaf.DNSNames = []string{"wrong.invalid"} }},
		{name: "expired", mutate: func(leaf *x509.Certificate) {
			leaf.NotBefore = time.Now().Add(-2 * time.Hour)
			leaf.NotAfter = time.Now().Add(-time.Hour)
		}},
		{name: "wrong usage", mutate: func(leaf *x509.Certificate) { leaf.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth} }},
		{name: "unknown critical extension", mutate: func(leaf *x509.Certificate) {
			leaf.ExtraExtensions = []pkix.Extension{{Id: []int{1, 2, 3, 4, 5}, Critical: true, Value: []byte{5, 0}}}
		}},
		{name: "signature", corrupt: true},
	} {
		t.Run(test.name, func(t *testing.T) {
			pki := newTrustTestPKI(t, test.mutate)
			if test.corrupt {
				pki.identity.Certificate[0] = append([]byte(nil), pki.leaf.Raw...)
				pki.identity.Certificate[0][len(pki.leaf.Raw)-1] ^= 1
			}
			server := trustTestServer(t, pki.identity, http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Error("invalid TLS reached HTTP") }))
			roots := x509.NewCertPool()
			if !test.unknown {
				roots.AddCert(pki.root)
			}
			err := trustTestClient(t, server.URL, roots, nil).get(context.Background(), "/", nil, nil)
			var certificateError *tls.CertificateVerificationError
			if !errors.As(err, &certificateError) {
				t.Fatal("ordinary certificate rejection was not preserved")
			}
		})
	}
}

func TestCertificateTrustOriginalCallbackAndUnsafeConfig(t *testing.T) {
	pki := newTrustTestPKI(t, nil)
	originalError := errors.New("original verifier refusal")
	base := &http.Transport{TLSClientConfig: &tls.Config{VerifyConnection: func(tls.ConnectionState) error { return originalError }}}
	protected, err := certificateTrustTransport(base, nil)
	if err != nil {
		t.Fatal(err)
	}
	if err := protected.TLSClientConfig.VerifyConnection(tls.ConnectionState{VerifiedChains: [][]*x509.Certificate{{pki.leaf, pki.issuer, pki.root}}, PeerCertificates: []*x509.Certificate{pki.leaf, pki.issuer}}); !errors.Is(err, originalError) {
		t.Fatal("original callback was lost")
	}
	for _, unsafe := range []*http.Transport{nil, {TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}, {DialTLSContext: func(context.Context, string, string) (net.Conn, error) { return nil, nil }}} {
		if _, err := certificateTrustTransport(unsafe, nil); err == nil {
			t.Fatal("unsafe TLS configuration was accepted")
		}
	}
	client, err := newTuistClient(backend.DataSourceInstanceSettings{})
	if err != nil {
		t.Fatal(err)
	}
	transport := client.http.Transport.(*http.Transport)
	defer transport.CloseIdleConnections()
	if transport.TLSClientConfig.VerifyConnection == nil || transport.TLSClientConfig.RootCAs != nil || client.http.Timeout != 30*time.Second || client.http.CheckRedirect == nil {
		t.Fatal("production factory is not protected with native defaults")
	}
}

func TestCertificateTrustRedirectAndDiagnosticPrivacy(t *testing.T) {
	pki := newTrustTestPKI(t, nil)
	var insecureRequests atomic.Int32
	insecure := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { insecureRequests.Add(1) }))
	defer insecure.Close()
	secure := trustTestServer(t, pki.identity, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { http.Redirect(w, r, insecure.URL, http.StatusFound) }))
	roots := x509.NewCertPool()
	roots.AddCert(pki.root)
	err := trustTestClient(t, secure.URL, roots, nil).get(context.Background(), "/?private-query=fixture", nil, nil)
	if err == nil || insecureRequests.Load() != 0 || strings.Contains(err.Error(), "private-query") {
		t.Fatal("downgrade refusal or diagnostic privacy failed")
	}
	failure := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte("private-response-fixture"))
	}))
	defer failure.Close()
	client, err := newTuistClient(backend.DataSourceInstanceSettings{})
	if err != nil {
		t.Fatal(err)
	}
	client.baseURL = failure.URL
	err = client.get(context.Background(), "/", nil, nil)
	if err == nil || strings.Contains(err.Error(), "private-response-fixture") {
		t.Fatal("API response body entered diagnostics")
	}
}

func TestCertificateTrustLiveProductionFactory(t *testing.T) {
	if os.Getenv("TUIST_TRUST_LIVE") != "1" {
		t.Skip("set TUIST_TRUST_LIVE=1 for credential-free public controls")
	}
	t.Logf("TUIST_TRUST_LIVE=1: actual Grafana API client, SDK=%s", runtime.Version())
	client, err := newTuistClient(backend.DataSourceInstanceSettings{})
	if err != nil {
		t.Fatal(err)
	}
	defer client.http.CloseIdleConnections()
	for _, issuer := range []string{"emudhra", "aaa-emudhra"} {
		for _, prefix := range []string{"dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"} {
			client.baseURL = "https://" + prefix + "-" + issuer + ".we-have-a-problem.com"
			err := client.get(context.Background(), "/", nil, nil)
			var certificateError *tls.CertificateVerificationError
			if !errors.As(err, &certificateError) && !errors.Is(err, errDistrustedPublicKey) {
				t.Fatalf("%s/%s: not a certificate-specific failure", issuer, prefix)
			}
			t.Logf("%s/%s: certificate rejection, application_key_deny=%t native_verifier=%t", issuer, prefix, errors.Is(err, errDistrustedPublicKey), certificateError != nil)
		}
	}
	client.baseURL = "https://letsencrypt.org"
	if err := client.get(context.Background(), "/", nil, nil); err != nil {
		t.Fatal(err)
	}
}
