package main

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/url"
	"syscall"
	"time"
)

// Embedded in the independently distributed helper, not loaded from the checkout.
var blockedCertificateSPKIHashes = [...]string{
	"8d417db2dd8bf5e3084d1e3f196d583849d81bdd4c00c70b9d39369e96b8c782",
	"bd153ed7b0434f6886b17bce8bbe84ed340c7132d702a8f4fa318f756ecbd6f3",
	"ebed6475c2c2d80fcb199f3fe8dd6e6b3ce60b77eb15d4e42c3dec0c6f5b5105",
	"49dd353dc2b919a3770645117d0e60c16115e7d1bc259eefe734b00ea434fe5f",
	"e0254c7fcdc265e2f0f8a428dabb75ab4ae039b4872d62f5ee57f0877d5a8a41",
	"5c0660a2b164910d8ff589c18e14552e9e0ec237dcefe2cb736d41a4811f81a0",
	"43bffa19d6ef651451f6841e019931e96f6f2eaeff28ab4b6f1ce4576de2717b",
	"63ecefee431d49523bc1136c4e72d0206a477086caf606cd5cf025686c109cf8",
	"ec4ffa1ad0ac88081314b7aaffef6a91f97cd57291bb5ba686c5415f5eb4f6b6",
	"92c063d67e8f14db71d288e11266ffdaf69cbf115f7bab14f3bc2f68d25e0e30",
	"c619e4780ed8e0abeda24ad732567de4383a7ea941338f6d1a7d1b49ac792fe9",
	"0a6c2b2ca5b364207954171987ac9d2178561569d8205457e77ca90c32ede282",
}

var errDistrustedPublicKey = errors.New("certificate chain contains a distrusted public key")

func certificateSPKIHash(certificate *x509.Certificate) string {
	return fmt.Sprintf("%x", sha256.Sum256(certificate.RawSubjectPublicKeyInfo))
}

func requireAllowedCertificates(certificates []*x509.Certificate, additional map[string]bool) error {
	if len(certificates) == 0 {
		return errors.New("no verified TLS certificates")
	}
	for _, certificate := range certificates {
		if certificate == nil || len(certificate.RawSubjectPublicKeyInfo) == 0 {
			return errors.New("invalid TLS certificate")
		}
		hash := certificateSPKIHash(certificate)
		if additional[hash] {
			return errDistrustedPublicKey
		}
		for _, blocked := range blockedCertificateSPKIHashes {
			if blocked == hash {
				return errDistrustedPublicKey
			}
		}
	}
	return nil
}

func certificateTrustTransport(base *http.Transport, additionalBlocked []string) (*http.Transport, error) {
	if base == nil || base.DialTLS != nil || base.DialTLSContext != nil {
		return nil, errors.New("unsupported custom TLS transport")
	}
	transport := base.Clone()
	if transport.TLSClientConfig == nil {
		transport.TLSClientConfig = &tls.Config{}
	} else {
		transport.TLSClientConfig = transport.TLSClientConfig.Clone()
	}
	if transport.TLSClientConfig.InsecureSkipVerify {
		return nil, errors.New("TLS certificate verification must remain enabled")
	}
	additional := make(map[string]bool, len(additionalBlocked))
	for _, hash := range additionalBlocked {
		additional[hash] = true
	}
	original := transport.TLSClientConfig.VerifyConnection
	transport.TLSClientConfig.VerifyConnection = func(state tls.ConnectionState) error {
		if original != nil {
			if err := original(state); err != nil {
				return err
			}
		}
		// The ordinary verifier builds these chains, including absent peer anchors.
		// VerifyConnection also runs if a configured session cache resumes a connection.
		if len(state.VerifiedChains) == 0 {
			return errors.New("no verified TLS certificate chain")
		}
		for _, chain := range state.VerifiedChains {
			if err := requireAllowedCertificates(chain, additional); err != nil {
				return err
			}
		}
		return requireAllowedCertificates(state.PeerCertificates, additional)
	}
	return transport, nil
}

func cacheHTTPClient(timeout time.Duration, base *http.Transport, additionalBlocked []string) (*http.Client, error) {
	transport, err := certificateTrustTransport(base, additionalBlocked)
	if err != nil {
		return nil, cacheRequestError{err}
	}
	return &http.Client{
		Transport: transport, Timeout: timeout,
		CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
	}, nil
}

func newCacheHTTPClient(timeout time.Duration) (*http.Client, error) {
	base, ok := http.DefaultTransport.(*http.Transport)
	if !ok {
		return nil, cacheRequestError{errors.New("unsupported default HTTP transport")}
	}
	return cacheHTTPClient(timeout, base, nil)
}

// Retain typed causes without printing endpoint queries, pod identities or bodies.
type cacheRequestError struct{ cause error }

func (e cacheRequestError) Error() string {
	var certificateError *tls.CertificateVerificationError
	var networkError net.Error
	var dnsError *net.DNSError
	var urlError *url.Error
	switch {
	case errors.Is(e.cause, errDistrustedPublicKey):
		return "cache service TLS certificate rejected by trust policy"
	case errors.As(e.cause, &certificateError):
		return "cache service TLS certificate verification failed"
	case errors.Is(e.cause, context.Canceled):
		return "cache service request canceled"
	case errors.Is(e.cause, context.DeadlineExceeded), errors.As(e.cause, &networkError) && networkError.Timeout():
		return "cache service request timed out"
	case errors.As(e.cause, &dnsError):
		return "cache service DNS lookup failed"
	case errors.Is(e.cause, syscall.ECONNREFUSED):
		return "cache service connection refused"
	case errors.As(e.cause, &urlError) && urlError.Op == "parse":
		return "cache service endpoint URL is invalid"
	default:
		return "cache service request failed"
	}
}
func (e cacheRequestError) Unwrap() error { return e.cause }

type cacheResponseError struct{ cause error }

func (cacheResponseError) Error() string   { return "cache service returned an invalid JSON response" }
func (e cacheResponseError) Unwrap() error { return e.cause }
