// Package rackseedtest is a TPM in software for tests: an RSA endorsement key,
// attestation keys shaped as a TPM makes them, and credential activation as a
// TPM does it.
package rackseedtest

import (
	"bytes"
	"crypto"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hmac"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/binary"
	"errors"
	"fmt"

	"github.com/google/go-attestation/attest"
	"github.com/google/go-tpm/legacy/tpm2"
)

// createdByTPM is the magic a TPM puts on the structures it generates.
const createdByTPM = 0xff544347

// TPM is a TPM in software.
type TPM struct {
	ek     *rsa.PrivateKey
	akName *tpm2.HashValue
	Closed bool
}

// New returns a TPM with a fresh endorsement key.
func New() *TPM {
	ek, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		panic(err)
	}
	return &TPM{ek: ek}
}

func (f *TPM) EK() ([]byte, error) { return x509.MarshalPKIXPublicKey(&f.ek.PublicKey) }

// NewAK makes a restricted signing key and its creation attestation, signed
// by itself, as TPM2_CreateKey and TPM2_CertifyCreation do.
func (f *TPM) NewAK() (attest.AttestationParameters, error) {
	ak, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return attest.AttestationParameters{}, err
	}
	pub := tpm2.Public{
		Type:    tpm2.AlgRSA,
		NameAlg: tpm2.AlgSHA256,
		Attributes: tpm2.FlagFixedTPM | tpm2.FlagFixedParent | tpm2.FlagSensitiveDataOrigin |
			tpm2.FlagUserWithAuth | tpm2.FlagRestricted | tpm2.FlagSign,
		RSAParameters: &tpm2.RSAParams{
			Sign:       &tpm2.SigScheme{Alg: tpm2.AlgRSASSA, Hash: tpm2.AlgSHA256},
			KeyBits:    2048,
			ModulusRaw: ak.N.Bytes(),
		},
	}
	public, err := pub.Encode()
	if err != nil {
		return attest.AttestationParameters{}, err
	}
	name, err := pub.Name()
	if err != nil {
		return attest.AttestationParameters{}, err
	}
	creation := tpm2.CreationData{
		PCRSelection:  tpm2.PCRSelection{Hash: tpm2.AlgSHA256},
		PCRDigest:     make([]byte, sha256.Size),
		Locality:      1,
		ParentNameAlg: tpm2.AlgSHA256,
	}
	createData, err := creation.EncodeCreationData()
	if err != nil {
		return attest.AttestationParameters{}, err
	}
	digest := sha256.Sum256(createData)
	attestation, err := tpm2.AttestationData{
		Magic:                createdByTPM,
		Type:                 tpm2.TagAttestCreation,
		QualifiedSigner:      name,
		AttestedCreationInfo: &tpm2.CreationInfo{Name: name, OpaqueDigest: digest[:]},
	}.Encode()
	if err != nil {
		return attest.AttestationParameters{}, err
	}
	signed := sha256.Sum256(attestation)
	raw, err := rsa.SignPKCS1v15(rand.Reader, ak, crypto.SHA256, signed[:])
	if err != nil {
		return attest.AttestationParameters{}, err
	}
	signature, err := tpm2.Signature{Alg: tpm2.AlgRSASSA, RSA: &tpm2.SignatureRSA{HashAlg: tpm2.AlgSHA256, Signature: raw}}.Encode()
	if err != nil {
		return attest.AttestationParameters{}, err
	}
	f.akName = name.Digest
	return attest.AttestationParameters{Public: public, CreateData: createData, CreateAttestation: attestation, CreateSignature: signature}, nil
}

// ActivateCredential undoes a credential sealed to its endorsement key for
// the attestation key NewAK made last, as TPM2_ActivateCredential does:
// decrypt the seed, check the credential's integrity against the key's name,
// and decrypt the secret.
func (f *TPM) ActivateCredential(c attest.EncryptedCredential) ([]byte, error) {
	if f.akName == nil {
		return nil, errors.New("no attestation key made")
	}
	encSeed, err := sized(c.Secret)
	if err != nil {
		return nil, fmt.Errorf("secret: %w", err)
	}
	seed, err := rsa.DecryptOAEP(sha256.New(), nil, f.ek, encSeed, []byte("IDENTITY\x00"))
	if err != nil {
		return nil, fmt.Errorf("the seed is not sealed to this TPM's endorsement key: %w", err)
	}
	idObject, err := sized(c.Credential)
	if err != nil {
		return nil, fmt.Errorf("credential: %w", err)
	}
	integrity, err := sized(idObject)
	if err != nil {
		return nil, fmt.Errorf("credential's integrity: %w", err)
	}
	encIdentity := idObject[2+len(integrity):]
	name, err := f.akName.Encode()
	if err != nil {
		return nil, err
	}
	macKey, err := tpm2.KDFa(tpm2.AlgSHA256, seed, "INTEGRITY", nil, nil, sha256.Size*8)
	if err != nil {
		return nil, err
	}
	mac := hmac.New(sha256.New, macKey)
	mac.Write(encIdentity)
	mac.Write(name)
	if !hmac.Equal(mac.Sum(nil), integrity) {
		return nil, errors.New("the credential is not for this TPM's attestation key")
	}
	symKey, err := tpm2.KDFa(tpm2.AlgSHA256, seed, "STORAGE", name, nil, 128)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(symKey)
	if err != nil {
		return nil, err
	}
	cv := make([]byte, len(encIdentity))
	cipher.NewCFBDecrypter(block, make([]byte, len(symKey))).XORKeyStream(cv, encIdentity)
	return sized(cv)
}

func (f *TPM) Close() error {
	f.Closed = true
	return nil
}

// sized reads a TPM2B: two bytes of length, then that many bytes.
func sized(b []byte) ([]byte, error) {
	if len(b) < 2 {
		return nil, errors.New("too short")
	}
	n := int(binary.BigEndian.Uint16(b))
	if len(b) < 2+n {
		return nil, errors.New("shorter than its size")
	}
	return bytes.Clone(b[2 : 2+n]), nil
}
