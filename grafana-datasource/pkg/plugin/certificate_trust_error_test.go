package plugin

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/grafana/grafana-plugin-sdk-go/backend"
)

func TestCertificateTrustDiagnosticCategories(t *testing.T) {
	for _, test := range []struct {
		cause    error
		category string
	}{
		{errDistrustedPublicKey, "rejected by trust policy"},
		{&tls.CertificateVerificationError{Err: x509.UnknownAuthorityError{}}, "certificate verification failed"},
		{context.DeadlineExceeded, "timed out"},
		{context.Canceled, "canceled"},
		{errors.New("fixture-private-message"), "request failed"},
	} {
		cause := &url.Error{Op: "Get", URL: "https://fixture-user:fixture-password@example.invalid/?fixture-query=private", Err: test.cause}
		err := apiRequestError{cause: cause}
		if !strings.Contains(err.Error(), test.category) || strings.Contains(err.Error(), "fixture-") || !errors.Is(err, test.cause) {
			t.Fatal("request category leaked details or lost its typed cause")
		}
	}
}

func TestCertificateTrustHealthDoesNotBlameToken(t *testing.T) {
	pki := newTrustTestPKI(t, nil)
	server := trustTestServer(t, pki.identity, http.HandlerFunc(func(http.ResponseWriter, *http.Request) { t.Error("denied health check reached API") }))
	roots := x509.NewCertPool()
	roots.AddCert(pki.root)
	datasource := &Datasource{client: trustTestClient(t, server.URL, roots, []string{certificateSPKIHash(pki.root)})}
	result, err := datasource.CheckHealth(context.Background(), nil)
	if err != nil || result.Status != backend.HealthStatusError || !strings.Contains(result.Message, "TLS certificate rejected") || strings.Contains(result.Message, "token") {
		t.Fatal("health check did not report the sanitized TLS category")
	}
}

func TestCertificateTrustInvalidJSONDoesNotLeakResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { _, _ = w.Write([]byte("fixture-private-response")) }))
	defer server.Close()
	client, err := newTuistClient(backend.DataSourceInstanceSettings{})
	if err != nil {
		t.Fatal(err)
	}
	defer client.http.CloseIdleConnections()
	client.baseURL = server.URL
	var result any
	err = client.get(context.Background(), "/", nil, &result)
	if err == nil || strings.Contains(err.Error(), "fixture") || !strings.Contains(err.Error(), "invalid JSON response") {
		t.Fatal("JSON response entered diagnostics")
	}
}

type idleConnectionRecorder struct{ closed bool }

func (*idleConnectionRecorder) RoundTrip(*http.Request) (*http.Response, error) {
	return nil, errors.New("unexpected request")
}
func (r *idleConnectionRecorder) CloseIdleConnections() { r.closed = true }

func TestCertificateTrustDatasourceDisposeClosesOnlyIdleConnections(t *testing.T) {
	recorder := &idleConnectionRecorder{}
	datasource := &Datasource{client: &tuistClient{http: &http.Client{Transport: recorder}}}
	datasource.Dispose()
	if !recorder.closed {
		t.Fatal("owned transport idle connections were not closed")
	}
	(&Datasource{}).Dispose()
}
