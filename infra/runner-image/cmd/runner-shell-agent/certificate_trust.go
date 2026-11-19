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
)

// Embedded in each runner-shell-agent binary, independently of guest trust stores.
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

func certificateTrustConfig(base *tls.Config, additionalBlocked []string) (*tls.Config, error) {
	config := &tls.Config{}
	if base != nil {
		config = base.Clone()
	}
	if config.InsecureSkipVerify {
		return nil, errors.New("TLS certificate verification must remain enabled")
	}
	additional := make(map[string]bool, len(additionalBlocked))
	for _, hash := range additionalBlocked {
		additional[hash] = true
	}
	original := config.VerifyConnection
	config.VerifyConnection = func(state tls.ConnectionState) error {
		if original != nil {
			if err := original(state); err != nil {
				return err
			}
		}
		// Ordinary Go verification runs first; VerifyConnection also runs on resumption.
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
	return config, nil
}

func runnerTLSConfig() *tls.Config {
	config, err := certificateTrustConfig(&tls.Config{MinVersion: tls.VersionTLS12}, nil)
	if err != nil {
		panic("invalid runner TLS configuration")
	}
	return config
}

func secureRedirect(request *http.Request, via []*http.Request) error {
	if len(via) >= 10 {
		return errors.New("too many session discovery redirects")
	}
	if len(via) > 0 && via[len(via)-1].URL.Scheme == "https" && request.URL.Scheme != "https" {
		return errors.New("refusing HTTPS redirect downgrade")
	}
	return nil
}

// Preserve causes for classification without printing URLs, credentials or bodies.
type runnerConnectionError struct{ cause error }

func (e runnerConnectionError) Error() string {
	var certificateError *tls.CertificateVerificationError
	var networkError net.Error
	var dnsError *net.DNSError
	var urlError *url.Error
	switch {
	case errors.Is(e.cause, errDistrustedPublicKey):
		return "runner TLS certificate rejected by trust policy"
	case errors.As(e.cause, &certificateError):
		return "runner TLS certificate verification failed"
	case errors.Is(e.cause, context.Canceled):
		return "runner request canceled"
	case errors.Is(e.cause, context.DeadlineExceeded), errors.As(e.cause, &networkError) && networkError.Timeout():
		return "runner request timed out"
	case errors.As(e.cause, &dnsError):
		return "runner DNS lookup failed"
	case errors.Is(e.cause, syscall.ECONNREFUSED):
		return "runner connection refused"
	case errors.As(e.cause, &urlError) && urlError.Op == "parse":
		return "runner endpoint URL is invalid"
	default:
		return "runner connection failed"
	}
}
func (e runnerConnectionError) Unwrap() error { return e.cause }

type runnerResponseError struct{ cause error }

func (runnerResponseError) Error() string   { return "runner received an invalid session response" }
func (e runnerResponseError) Unwrap() error { return e.cause }
