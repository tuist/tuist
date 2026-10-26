package shipper

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/asn1"
	"encoding/hex"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
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
	key := func() (ed25519.PublicKey, ed25519.PrivateKey) {
		pub, private, err := ed25519.GenerateKey(rand.Reader)
		if err != nil {
			t.Fatal(err)
		}
		return pub, private
	}
	issue := func(template, parent *x509.Certificate, pub ed25519.PublicKey, signer ed25519.PrivateKey) *x509.Certificate {
		der, err := x509.CreateCertificate(rand.Reader, template, parent, pub, signer)
		if err != nil {
			t.Fatal(err)
		}
		certificate, err := x509.ParseCertificate(der)
		if err != nil {
			t.Fatal(err)
		}
		return certificate
	}
	now := time.Now()
	rootPub, rootKey := key()
	rootTemplate := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: "synthetic root"}, NotBefore: now.Add(-time.Hour), NotAfter: now.Add(time.Hour), IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	root := issue(rootTemplate, rootTemplate, rootPub, rootKey)
	issuerPub, issuerKey := key()
	issuerTemplate := &x509.Certificate{SerialNumber: big.NewInt(2), Subject: pkix.Name{CommonName: "synthetic issuer"}, NotBefore: root.NotBefore, NotAfter: root.NotAfter, IsCA: true, BasicConstraintsValid: true, KeyUsage: x509.KeyUsageCertSign}
	issuer := issue(issuerTemplate, root, issuerPub, rootKey)
	leafPub, leafKey := key()
	leafTemplate := &x509.Certificate{SerialNumber: big.NewInt(3), NotBefore: root.NotBefore, NotAfter: root.NotAfter, IPAddresses: []net.IP{net.ParseIP("127.0.0.1")}, ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}, KeyUsage: x509.KeyUsageDigitalSignature}
	if change != nil {
		change(leafTemplate)
	}
	leaf := issue(leafTemplate, issuer, leafPub, issuerKey)
	return trustFixture{root, issuer, leaf, tls.Certificate{Certificate: [][]byte{leaf.Raw, issuer.Raw}, PrivateKey: leafKey}}
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
func fixtureClient(t *testing.T, fixture trustFixture, additional []string) *http.Client {
	t.Helper()
	roots := x509.NewCertPool()
	roots.AddCert(fixture.root)
	client, err := certificateTrustClient(&http.Client{Timeout: 5 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots}}}, additional)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(client.CloseIdleConnections)
	return client
}
func fixtureShipper(url string, client *http.Client) *Client {
	c := &Client{URL: url}
	c.once.Do(func() { c.http = client })
	return c
}
func push(t *testing.T, client *Client) error {
	t.Helper()
	return client.Push(context.Background(), map[string]string{"job": "synthetic"}, []Entry{{Timestamp: time.Now(), Line: "private-log-line", Level: "info"}})
}
func spkiHash(certificate *x509.Certificate) string {
	hash := sha256.Sum256(certificate.RawSubjectPublicKeyInfo)
	return hex.EncodeToString(hash[:])
}

func TestTrustRejectsAllTwelveRealDERKeys(t *testing.T) {
	client, err := certificateTrustClient(nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer client.CloseIdleConnections()
	verify := client.Transport.(*http.Transport).TLSClientConfig.VerifyConnection
	count := 0
	for _, filename := range []string{"issuer-roots.pem", "distrusted-intermediates.pem"} {
		data, err := os.ReadFile("../../../certificate-trust/controls/" + filename)
		if err != nil {
			t.Fatal(err)
		}
		for len(data) > 0 {
			block, rest := pem.Decode(data)
			if block == nil {
				if strings.TrimSpace(string(data)) != "" {
					t.Fatal("malformed fixture")
				}
				break
			}
			data = rest
			certificate, err := x509.ParseCertificate(block.Bytes)
			if err != nil {
				t.Fatal(err)
			}
			if !errors.Is(verify(tls.ConnectionState{VerifiedChains: [][]*x509.Certificate{{certificate}}, PeerCertificates: []*x509.Certificate{certificate}}), errDistrustedKey) {
				t.Fatal("real incident key accepted")
			}
			count++
		}
	}
	if count != 12 || len(blockedSPKIHashes) != 12 {
		t.Fatal("expected twelve incident certificates")
	}
}
func TestActualPushProtectsCompleteChainBeforeLogDelivery(t *testing.T) {
	fixture := makeTrustFixture(t, nil)
	var delivered atomic.Int32
	server := fixtureServer(t, fixture, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		delivered.Add(1)
		data, _ := io.ReadAll(r.Body)
		if !strings.Contains(string(data), "private-log-line") {
			t.Error("lost log body")
		}
		w.WriteHeader(204)
	}))
	for _, certificate := range []*x509.Certificate{fixture.leaf, fixture.issuer, fixture.root} {
		if err := push(t, fixtureShipper(server.URL, fixtureClient(t, fixture, nil))); err != nil {
			t.Fatal("native acceptance", err)
		}
		before := delivered.Load()
		err := push(t, fixtureShipper(server.URL, fixtureClient(t, fixture, []string{spkiHash(certificate)})))
		if !errors.Is(err, errDistrustedKey) || errors.Is(err, ErrRejected) || delivered.Load() != before {
			t.Fatal("denied key received logs or would drop batch", err)
		}
	}
	if err := push(t, fixtureShipper(server.URL, fixtureClient(t, fixture, nil))); err != nil {
		t.Fatal("restored acceptance", err)
	}
}
func TestOrdinaryTLSRemainsAuthoritative(t *testing.T) {
	for name, change := range map[string]func(*x509.Certificate){
		"hostname":  func(c *x509.Certificate) { c.IPAddresses = nil; c.DNSNames = []string{"wrong.invalid"} },
		"expiry":    func(c *x509.Certificate) { c.NotAfter = time.Now().Add(-time.Minute) },
		"usage":     func(c *x509.Certificate) { c.ExtKeyUsage = []x509.ExtKeyUsage{x509.ExtKeyUsageClientAuth} },
		"signature": nil,
		"critical_extension": func(c *x509.Certificate) {
			c.ExtraExtensions = []pkix.Extension{{Id: asn1.ObjectIdentifier{1, 3, 6, 1, 4, 1, 55555}, Critical: true, Value: []byte{5, 0}}}
		},
	} {
		t.Run(name, func(t *testing.T) {
			fixture := makeTrustFixture(t, change)
			if name == "signature" {
				fixture.server.Certificate[0][len(fixture.server.Certificate[0])-1] ^= 1
			}
			var delivered atomic.Int32
			server := fixtureServer(t, fixture, http.HandlerFunc(func(http.ResponseWriter, *http.Request) { delivered.Add(1) }))
			err := push(t, fixtureShipper(server.URL, fixtureClient(t, fixture, nil)))
			var verify *tls.CertificateVerificationError
			if !errors.As(err, &verify) || delivered.Load() != 0 {
				t.Fatal("ordinary validation bypassed", err)
			}
		})
	}
	fixture := makeTrustFixture(t, nil)
	server := fixtureServer(t, fixture, http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Error("untrusted endpoint received logs") }))
	client, err := certificateTrustClient(&http.Client{Timeout: 5 * time.Second}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer client.CloseIdleConnections()
	var verify *tls.CertificateVerificationError
	if err := push(t, fixtureShipper(server.URL, client)); !errors.As(err, &verify) {
		t.Fatal("unknown CA accepted", err)
	}
}
func TestTrustConfigurationCallbacksAndPrivacy(t *testing.T) {
	for _, config := range []*http.Transport{{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}}, {DialTLSContext: func(context.Context, string, string) (net.Conn, error) { return nil, nil }}} {
		if _, err := certificateTrustClient(&http.Client{Transport: config}, nil); !errors.Is(err, errTLSConfiguration) {
			t.Fatal("unsafe config accepted", err)
		}
	}
	fixture := makeTrustFixture(t, nil)
	server := fixtureServer(t, fixture, http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Error("callback rejection delivered logs") }))
	roots := x509.NewCertPool()
	roots.AddCert(fixture.root)
	marker := errors.New("private-callback-detail")
	transport := &http.Transport{TLSClientConfig: &tls.Config{RootCAs: roots, VerifyConnection: func(tls.ConnectionState) error { return marker }}}
	client, err := certificateTrustClient(&http.Client{Transport: transport, Timeout: 5 * time.Second}, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer client.CloseIdleConnections()
	failure := push(t, fixtureShipper(server.URL+"/?private-query", client))
	if !errors.Is(failure, marker) || strings.Contains(failure.Error(), "private-") {
		t.Fatal("callback/privacy failure", failure)
	}
	if transport.TLSClientConfig.VerifyConnection(tls.ConnectionState{}) != marker {
		t.Fatal("original callback mutated")
	}
	for _, status := range []int{400, 429, 503} {
		t.Run(fmt.Sprint(status), func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(status)
				io.WriteString(w, "private-response-body")
			}))
			defer server.Close()
			c := &Client{URL: strings.Replace(server.URL, "http://", "http://private-user:private-password@", 1) + "/?private-query"}
			defer c.CloseIdleConnections()
			err := push(t, c)
			if err == nil || strings.Contains(err.Error(), "private-") || errors.Is(err, ErrRejected) != (status == 400) {
				t.Fatal("status privacy/classification", err)
			}
		})
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if failure := privatePushFailure(ctx.Err()); !errors.Is(failure, context.Canceled) || !strings.Contains(failure.Error(), "cancelled") {
		t.Fatal(failure)
	}
}
func TestSecureRedirectCannotLeakLogsToPlaintext(t *testing.T) {
	plain := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Error("HTTPS downgrade delivered logs") }))
	defer plain.Close()
	fixture := makeTrustFixture(t, nil)
	secure := fixtureServer(t, fixture, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, plain.URL, http.StatusTemporaryRedirect)
	}))
	err := push(t, fixtureShipper(secure.URL, fixtureClient(t, fixture, nil)))
	if !errors.Is(err, errSecureRedirect) {
		t.Fatal("downgrade not refused", err)
	}
}
func TestPublicTLSControls(t *testing.T) {
	if os.Getenv("TUIST_TRUST_LIVE") != "1" {
		t.Skip("credential-free public opt-in")
	}
	client, err := NewHTTPClient(15 * time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer client.CloseIdleConnections()
	for _, issuer := range []string{"emudhra", "aaa-emudhra"} {
		for _, series := range []string{"dv-g3b", "dv-g3c", "ov-g3b", "ov-g3c", "ev-g3b", "ev-g3c"} {
			response, err := client.Get("https://" + series + "-" + issuer + ".we-have-a-problem.com/")
			if response != nil {
				response.Body.Close()
			}
			var verify *tls.CertificateVerificationError
			if errors.Is(err, errDistrustedKey) {
				t.Log(series, issuer, "key_policy")
			} else if errors.As(err, &verify) {
				t.Log(series, issuer, "native_certificate_validation")
			} else {
				t.Fatal("not a certificate-specific rejection", err)
			}
		}
	}
	response, err := client.Get("https://valid-isrgrootx1.letsencrypt.org/")
	if err != nil {
		t.Fatal(err)
	}
	io.Copy(io.Discard, response.Body)
	response.Body.Close()
	if response.StatusCode != 200 {
		t.Fatal(response.StatusCode)
	}
	if response.TLS == nil || len(response.TLS.VerifiedChains) == 0 || len(response.TLS.VerifiedChains[0]) < 3 {
		t.Fatal("native evaluated leaf/intermediate/root missing")
	}
	if client.Transport.(*http.Transport).TLSClientConfig.RootCAs != nil {
		t.Fatal("native-default roots were replaced")
	}
	chain := response.TLS.VerifiedChains[0]
	for _, peer := range response.TLS.PeerCertificates {
		if spkiHash(peer) == spkiHash(chain[len(chain)-1]) {
			t.Fatal("positive control supplied the root; absent native anchor not qualified")
		}
	}
	for index, certificate := range []*x509.Certificate{chain[0], chain[1], chain[len(chain)-1]} {
		denied, err := certificateTrustClient(client, []string{spkiHash(certificate)})
		if err != nil {
			t.Fatal(err)
		}
		result, err := denied.Get("https://valid-isrgrootx1.letsencrypt.org/")
		if result != nil {
			result.Body.Close()
		}
		denied.CloseIdleConnections()
		if !errors.Is(err, errDistrustedKey) {
			t.Fatal("native-default accepted chain escaped additive deny", err)
		}
		t.Log("native_default_evaluated_chain additive deny", []string{"leaf", "intermediate", "absent_anchor"}[index])
	}
	restored, err := client.Get("https://valid-isrgrootx1.letsencrypt.org/")
	if err != nil {
		t.Fatal("native-default positive did not recover", err)
	}
	defer restored.Body.Close()
	if restored.StatusCode != 200 {
		t.Fatal(restored.StatusCode)
	}
}

func TestResolverDiagnosticsAreUsefulPrivateAndTyped(t *testing.T) {
	primary := &net.DNSError{Name: "private-domain", Err: "private-description", IsNotFound: true}
	system := &net.OpError{Op: "dial private-address", Err: syscall.ECONNREFUSED}
	cause := &resolverFailures{primary: primary, system: system}
	failure := privatePushFailure(cause)
	if !strings.Contains(failure.Error(), "magicdns=dns_not_found system=connection_refused") || strings.Contains(failure.Error(), "private-") || !errors.Is(failure, syscall.ECONNREFUSED) {
		t.Fatal(failure)
	}
	var dns *net.DNSError
	if !errors.As(failure, &dns) || dns != primary {
		t.Fatal("typed resolver cause lost")
	}
	if got := privatePushFailure(&net.DNSError{IsTimeout: true}).Error(); !strings.Contains(got, "dns_timeout") {
		t.Fatal(got)
	}
}

func TestInvalidReceiverFailsBeforeTailing(t *testing.T) {
	for _, endpoint := range []string{"", "/relative", "file:///private-receiver", "https://private-user:private-password@bad%zz/"} {
		client, err := NewClient(endpoint, time.Second)
		if client != nil || err == nil || strings.Contains(err.Error(), "private-") {
			t.Fatal("invalid receiver was not privately refused", err)
		}
	}
}
