package rackseed

import (
	"crypto/rsa"
	"crypto/x509"
	"errors"
	"fmt"

	"github.com/google/go-attestation/attest"
)

// TPM is what a machine's TPM does for a seed request.
type TPM interface {
	// EK is its RSA endorsement key, PKIX DER.
	EK() ([]byte, error)
	// NewAK makes an attestation key for the request.
	NewAK() (attest.AttestationParameters, error)
	// ActivateCredential undoes a credential sealed to its endorsement key for
	// the attestation key NewAK made.
	ActivateCredential(attest.EncryptedCredential) ([]byte, error)
	Close() error
}

// ErrNoTPM is a machine without a TPM, or with one that has no RSA
// endorsement key.
var ErrNoTPM = errors.New("no TPM with an RSA endorsement key")

type device struct {
	tpm *attest.TPM
	ek  attest.EK
	ak  *attest.AK
}

// Open opens the machine's TPM, returning ErrNoTPM when it has none.
func Open() (TPM, error) {
	tpm, err := attest.OpenTPM(nil)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrNoTPM, err)
	}
	eks, err := tpm.EKs()
	if err != nil {
		tpm.Close()
		return nil, fmt.Errorf("read the TPM's endorsement keys: %w", err)
	}
	for _, ek := range eks {
		if _, ok := ek.Public.(*rsa.PublicKey); ok {
			return &device{tpm: tpm, ek: ek}, nil
		}
	}
	tpm.Close()
	return nil, ErrNoTPM
}

func (d *device) EK() ([]byte, error) { return x509.MarshalPKIXPublicKey(d.ek.Public) }

func (d *device) NewAK() (attest.AttestationParameters, error) {
	ak, err := d.tpm.NewAK(nil)
	if err != nil {
		return attest.AttestationParameters{}, err
	}
	d.ak = ak
	return ak.AttestationParameters(), nil
}

func (d *device) ActivateCredential(c attest.EncryptedCredential) ([]byte, error) {
	if d.ak == nil {
		return nil, errors.New("no attestation key made")
	}
	return d.ak.ActivateCredentialWithEK(d.tpm, c, d.ek)
}

func (d *device) Close() error {
	if d.ak != nil {
		_ = d.ak.Close(d.tpm)
	}
	return d.tpm.Close()
}
