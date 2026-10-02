// Package rackseed hands a rack host the seed of its install, which carries
// its tailnet join key and SSH host key. For a host whose TPM is pinned, the
// boot server seals the seed to that TPM's endorsement key through credential
// activation, which only that TPM can undo, so a machine that answers for the
// host's MAC gets nothing it can read.
package rackseed

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"

	"github.com/google/go-attestation/attest"
)

// sealInfo binds the key the seed is encrypted under to this use of the
// activation secret.
const sealInfo = "tuist rack seed"

var (
	// ErrNotPublished is a boot server with no install published under the
	// MAC asked for.
	ErrNotPublished = errors.New("no install is published for this MAC")
	// ErrNotAttested is a request without the TPM's attestation, for a host
	// whose TPM is pinned.
	ErrNotAttested = errors.New("the host's TPM is pinned, and the request carries no attestation from it")
)

// Request is a machine's ask for its seed. From a machine with a TPM, it
// carries the TPM's endorsement key and an attestation key the TPM made for
// the request.
type Request struct {
	EK []byte                        `json:"ek,omitempty"`
	AK *attest.AttestationParameters `json:"ak,omitempty"`
}

// Answer is the seed: sealed to the machine's TPM for a host whose TPM is
// pinned, and as it is for one whose is not.
type Answer struct {
	Seed   []byte  `json:"seed,omitempty"`
	Sealed *Sealed `json:"sealed,omitempty"`
}

// Sealed is a seed encrypted under a secret that credential activation hands
// only the TPM holding the pinned endorsement key, and only for the
// attestation key the request carried.
type Sealed struct {
	Credential []byte `json:"credential"`
	Secret     []byte `json:"secret"`
	Nonce      []byte `json:"nonce"`
	Ciphertext []byte `json:"ciphertext"`
}

// Fingerprint is how an endorsement key (PKIX DER) is shown.
func Fingerprint(ek []byte) string {
	sum := sha256.Sum256(ek)
	return "SHA256:" + base64.RawStdEncoding.EncodeToString(sum[:])
}

// Seal seals seed to the TPM whose endorsement key (PKIX DER) the host
// pinned, for the attestation key the request carries, refusing a request
// from another TPM and an attestation key that is not a TPM's restricted
// signing key.
func Seal(pinned []byte, req Request, seed []byte) (*Sealed, error) {
	if req.AK == nil || len(req.EK) == 0 {
		return nil, ErrNotAttested
	}
	if !bytes.Equal(req.EK, pinned) {
		return nil, fmt.Errorf("the request comes from the TPM %s, not the host's %s", Fingerprint(req.EK), Fingerprint(pinned))
	}
	ek, err := x509.ParsePKIXPublicKey(pinned)
	if err != nil {
		return nil, fmt.Errorf("read the host's endorsement key: %w", err)
	}
	params := attest.ActivationParameters{EK: ek, AK: *req.AK}
	secret, credential, err := params.Generate()
	if err != nil {
		return nil, fmt.Errorf("the request's attestation key: %w", err)
	}
	gcm, err := sealCipher(secret)
	if err != nil {
		return nil, err
	}
	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}
	return &Sealed{
		Credential: credential.Credential,
		Secret:     credential.Secret,
		Nonce:      nonce,
		Ciphertext: gcm.Seal(nil, nonce, seed, nil),
	}, nil
}

// Unseal opens a sealed seed with the secret its TPM activated.
func Unseal(activated []byte, s *Sealed) ([]byte, error) {
	gcm, err := sealCipher(activated)
	if err != nil {
		return nil, err
	}
	if len(s.Nonce) != gcm.NonceSize() {
		return nil, fmt.Errorf("a nonce of %d bytes", len(s.Nonce))
	}
	seed, err := gcm.Open(nil, s.Nonce, s.Ciphertext, nil)
	if err != nil {
		return nil, fmt.Errorf("open the sealed seed: %w", err)
	}
	return seed, nil
}

func sealCipher(secret []byte) (cipher.AEAD, error) {
	key, err := hkdf.Key(sha256.New, secret, nil, sealInfo, 32)
	if err != nil {
		return nil, err
	}
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	return cipher.NewGCM(block)
}

// Asker asks a site's boot server for seeds. It opens the machine's TPM only
// once a host's pinned TPM asks for it, and makes one attestation key for
// every request after.
type Asker struct {
	Client *http.Client
	// Server is the boot server's http:// address.
	Server string
	// OpenTPM opens the machine's TPM.
	OpenTPM func() (TPM, error)

	tpm TPM
	req *Request
}

// Ask asks for the seed published under mac (hyphenated), returning
// ErrNotPublished when nothing is.
func (a *Asker) Ask(ctx context.Context, mac string) ([]byte, error) {
	status, payload, err := a.post(ctx, mac, Request{})
	if err == nil && status == http.StatusUnauthorized {
		var req Request
		if req, err = a.attestation(); err != nil {
			return nil, err
		}
		status, payload, err = a.post(ctx, mac, req)
	}
	if err != nil {
		return nil, err
	}
	switch status {
	case http.StatusOK:
	case http.StatusNotFound:
		return nil, ErrNotPublished
	default:
		return nil, fmt.Errorf("the boot server answered %d: %s", status, strings.TrimSpace(string(payload)))
	}
	var answer Answer
	if err := json.Unmarshal(payload, &answer); err != nil {
		return nil, fmt.Errorf("read the boot server's answer: %w", err)
	}
	if answer.Sealed == nil {
		return answer.Seed, nil
	}
	if a.tpm == nil {
		return nil, errors.New("the seed is sealed to a TPM the request did not attest with")
	}
	secret, err := a.tpm.ActivateCredential(attest.EncryptedCredential{Credential: answer.Sealed.Credential, Secret: answer.Sealed.Secret})
	if err != nil {
		return nil, fmt.Errorf("the TPM did not activate the seed's credential: %w", err)
	}
	return Unseal(secret, answer.Sealed)
}

// attestation is the TPM's endorsement key and an attestation key it made,
// made once.
func (a *Asker) attestation() (Request, error) {
	if a.req != nil {
		return *a.req, nil
	}
	if a.tpm == nil {
		tpm, err := a.OpenTPM()
		if err != nil {
			return Request{}, fmt.Errorf("the host's TPM is pinned: %w", err)
		}
		a.tpm = tpm
	}
	ek, err := a.tpm.EK()
	if err != nil {
		return Request{}, fmt.Errorf("read the TPM's endorsement key: %w", err)
	}
	ak, err := a.tpm.NewAK()
	if err != nil {
		return Request{}, fmt.Errorf("make an attestation key: %w", err)
	}
	a.req = &Request{EK: ek, AK: &ak}
	return *a.req, nil
}

func (a *Asker) post(ctx context.Context, mac string, req Request) (int, []byte, error) {
	body, err := json.Marshal(req)
	if err != nil {
		return 0, nil, err
	}
	httpReq, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimSuffix(a.Server, "/")+"/hosts/"+mac+"/seed", bytes.NewReader(body))
	if err != nil {
		return 0, nil, err
	}
	httpReq.Header.Set("Content-Type", "application/json")
	resp, err := a.Client.Do(httpReq)
	if err != nil {
		return 0, nil, err
	}
	defer resp.Body.Close()
	payload, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	return resp.StatusCode, payload, err
}

// Close closes the TPM, when it was opened.
func (a *Asker) Close() error {
	if a.tpm == nil {
		return nil
	}
	return a.tpm.Close()
}
