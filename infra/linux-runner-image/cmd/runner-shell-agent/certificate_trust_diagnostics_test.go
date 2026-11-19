package main

import (
	"context"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"syscall"
	"testing"
)

func TestRunnerTrustDiagnosticCategories(t *testing.T) {
	for _, test := range []struct {
		name    string
		cause   error
		message string
	}{
		{"policy", errDistrustedPublicKey, "runner TLS certificate rejected by trust policy"},
		{"native", &tls.CertificateVerificationError{Err: errors.New("secret-cause")}, "runner TLS certificate verification failed"},
		{"cancel", context.Canceled, "runner request canceled"},
		{"deadline", context.DeadlineExceeded, "runner request timed out"},
		{"DNS timeout", &net.DNSError{Name: "secret-host", Err: "secret-cause", IsTimeout: true}, "runner request timed out"},
		{"DNS", &net.DNSError{Name: "secret-host", Err: "secret-cause", IsNotFound: true}, "runner DNS lookup failed"},
		{"refused", syscall.ECONNREFUSED, "runner connection refused"},
		{"URL", &url.Error{Op: "parse", URL: "https://user:secret-password@fixture.invalid?token=secret-token", Err: errors.New("secret-cause")}, "runner endpoint URL is invalid"},
		{"other", errors.New("secret-cause"), "runner connection failed"},
	} {
		t.Run(test.name, func(t *testing.T) {
			cause := fmt.Errorf("secret-prefix: %w", test.cause)
			value := runnerConnectionError{cause}
			if value.Error() != test.message || strings.Contains(value.Error(), "secret") || !errors.Is(value, test.cause) {
				t.Fatal("fixed diagnostic category or typed cause lost")
			}
		})
	}
	if runnerTLSConfig().ClientSessionCache != nil || directHTTPTransport.TLSClientConfig.ClientSessionCache != nil {
		t.Fatal("production resumption unexpectedly enabled; qualify resumed wire behavior before enabling it")
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = fmt.Fprint(w, "secret-response-body")
	}))
	defer server.Close()
	err := runnerTestDiscovery(t, server.URL+"?token=secret-token", runnerTLSConfig())
	var syntaxError *json.SyntaxError
	if !errors.As(err, &syntaxError) || err.Error() != "runner received an invalid session response" {
		t.Fatal("JSON response diagnostic lost privacy or typed cause")
	}
}
