package shipper

import (
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"errors"
	"net"
	"net/http"
	"syscall"
)

const certificateTrustPolicy = "emudhra-2026-10-19-v2"

var blockedSPKIHashes = [...]string{
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

var (
	errDistrustedKey    = errors.New("certificate key is distrusted")
	errTLSConfiguration = errors.New("unsupported TLS configuration")
	errSecureRedirect   = errors.New("secure redirect refused")
)

func certificateTrustClient(base *http.Client, additional []string) (*http.Client, error) {
	if base == nil {
		base = http.DefaultClient
	}
	client := *base
	roundTripper := base.Transport
	if roundTripper == nil {
		roundTripper = http.DefaultTransport
	}
	original, ok := roundTripper.(*http.Transport)
	if !ok || original == nil || original.DialTLS != nil || original.DialTLSContext != nil {
		return nil, errTLSConfiguration
	}
	transport := original.Clone()
	config := &tls.Config{}
	if transport.TLSClientConfig != nil {
		config = transport.TLSClientConfig.Clone()
	}
	if config.InsecureSkipVerify {
		return nil, errTLSConfiguration
	}
	blocked := make(map[[32]byte]struct{}, len(blockedSPKIHashes)+len(additional))
	for _, value := range append(append([]string(nil), blockedSPKIHashes[:]...), additional...) {
		decoded, err := hex.DecodeString(value)
		if err != nil || len(decoded) != sha256.Size {
			return nil, errTLSConfiguration
		}
		blocked[[32]byte(decoded)] = struct{}{}
	}
	previous := config.VerifyConnection
	config.VerifyConnection = func(state tls.ConnectionState) error {
		if len(state.VerifiedChains) == 0 {
			return errTLSConfiguration
		}
		if previous != nil {
			if err := previous(state); err != nil {
				return err
			}
		}
		check := func(certificates []*x509.Certificate) error {
			if len(certificates) == 0 {
				return errTLSConfiguration
			}
			for _, certificate := range certificates {
				if certificate == nil || len(certificate.RawSubjectPublicKeyInfo) == 0 {
					return errTLSConfiguration
				}
				if _, denied := blocked[sha256.Sum256(certificate.RawSubjectPublicKeyInfo)]; denied {
					return errDistrustedKey
				}
			}
			return nil
		}
		for _, chain := range state.VerifiedChains {
			if err := check(chain); err != nil {
				return err
			}
		}
		return check(state.PeerCertificates)
	}
	transport.TLSClientConfig = config
	client.Transport = transport
	redirect := base.CheckRedirect
	client.CheckRedirect = func(request *http.Request, via []*http.Request) error {
		for _, previous := range via {
			if previous.URL.Scheme == "https" && request.URL.Scheme != "https" {
				return errSecureRedirect
			}
		}
		if redirect != nil {
			return redirect(request, via)
		}
		if len(via) >= 10 {
			return errSecureRedirect
		}
		return nil
	}
	return &client, nil
}

type pushFailure struct {
	category string
	cause    error
}

func (failure *pushFailure) Error() string { return "log push failed: " + failure.category }
func (failure *pushFailure) Unwrap() error { return failure.cause }
func safeDialCause(err error) string {
	var dns *net.DNSError
	var network net.Error
	switch {
	case errors.Is(err, context.Canceled):
		return "cancelled"
	case errors.As(err, &dns):
		if dns.IsTimeout {
			return "dns_timeout"
		}
		if dns.IsNotFound {
			return "dns_not_found"
		}
		if dns.IsTemporary {
			return "dns_temporary"
		}
		return "dns_failure"
	case errors.Is(err, context.DeadlineExceeded):
		return "timeout"
	case errors.As(err, &network) && network.Timeout():
		return "timeout"
	case errors.Is(err, syscall.ECONNREFUSED):
		return "connection_refused"
	case errors.Is(err, syscall.ECONNRESET):
		return "connection_reset"
	case errors.Is(err, syscall.ENETUNREACH), errors.Is(err, syscall.EHOSTUNREACH):
		return "network_unreachable"
	default:
		return "connection_failed"
	}
}

func privatePushFailure(err error) error {
	var resolvers *resolverFailures
	if errors.As(err, &resolvers) {
		return &pushFailure{category: "dial magicdns=" + safeDialCause(resolvers.primary) + " system=" + safeDialCause(resolvers.system), cause: err}
	}
	category := "request_failed"
	var verification *tls.CertificateVerificationError
	var unknown x509.UnknownAuthorityError
	var hostname x509.HostnameError
	var invalid x509.CertificateInvalidError
	var dns *net.DNSError
	var network net.Error
	var record tls.RecordHeaderError
	switch {
	case errors.Is(err, errDistrustedKey):
		category = "key_policy"
	case errors.Is(err, errTLSConfiguration):
		category = "tls_configuration"
	case errors.Is(err, errSecureRedirect):
		category = "secure_redirect"
	case errors.As(err, &verification), errors.As(err, &unknown), errors.As(err, &hostname), errors.As(err, &invalid):
		category = "certificate_validation"
	case errors.As(err, &record):
		category = "tls_protocol"
	case errors.Is(err, context.Canceled):
		category = "cancelled"
	case errors.Is(err, context.DeadlineExceeded):
		category = "timeout"
	case errors.As(err, &dns):
		category = safeDialCause(err)
	case errors.As(err, &network) && network.Timeout():
		category = "timeout"
	}
	return &pushFailure{category: category, cause: err}
}
