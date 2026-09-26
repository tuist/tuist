package rackseed_test

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/google/go-attestation/attest"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed/rackseedtest"
)

var seed = []byte("#cloud-config\n# tuist-install-id: kAbC123\n")

func request(t *testing.T, tpm rackseed.TPM) rackseed.Request {
	t.Helper()
	ek, err := tpm.EK()
	if err != nil {
		t.Fatal(err)
	}
	ak, err := tpm.NewAK()
	if err != nil {
		t.Fatal(err)
	}
	return rackseed.Request{EK: ek, AK: &ak}
}

func activate(tpm rackseed.TPM, s *rackseed.Sealed) ([]byte, error) {
	secret, err := tpm.ActivateCredential(attest.EncryptedCredential{Credential: s.Credential, Secret: s.Secret})
	if err != nil {
		return nil, err
	}
	return rackseed.Unseal(secret, s)
}

func TestASeedSealedToTheHostsTPMOpensThere(t *testing.T) {
	host := rackseedtest.New()
	pinned, _ := host.EK()

	sealed, err := rackseed.Seal(pinned, request(t, host), seed)
	if err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(sealed.Ciphertext), "tuist-install-id") {
		t.Fatal("the seed is readable as sealed")
	}
	got, err := activate(host, sealed)
	if err != nil || string(got) != string(seed) {
		t.Fatalf("%q %v", got, err)
	}
}

func TestASeedIsNotSealedForAnotherTPMsRequest(t *testing.T) {
	host, stranger := rackseedtest.New(), rackseedtest.New()
	pinned, _ := host.EK()

	if _, err := rackseed.Seal(pinned, request(t, stranger), seed); err == nil || !strings.Contains(err.Error(), "not the host's") {
		t.Fatalf("sealed for another TPM's request: %v", err)
	}
	if _, err := rackseed.Seal(pinned, rackseed.Request{}, seed); !errors.Is(err, rackseed.ErrNotAttested) {
		t.Fatalf("a request without an attestation: %v", err)
	}
}

// A machine that claims the host's endorsement key, which is no secret, with
// an attestation key of its own TPM, gets a seed it cannot open.
func TestAnotherTPMCannotOpenASeedSealedForTheHost(t *testing.T) {
	host, stranger := rackseedtest.New(), rackseedtest.New()
	pinned, _ := host.EK()
	req := request(t, stranger)
	req.EK = pinned

	sealed, err := rackseed.Seal(pinned, req, seed)
	if err != nil {
		t.Fatal(err)
	}
	if got, err := activate(stranger, sealed); err == nil {
		t.Fatalf("another TPM opened the host's seed: %q", got)
	}
}

func TestAnAttestationKeyWhoseCreationDoesNotVerifyIsRefused(t *testing.T) {
	host := rackseedtest.New()
	pinned, _ := host.EK()
	req := request(t, host)
	req.AK.CreateSignature[len(req.AK.CreateSignature)-1] ^= 0xff

	if _, err := rackseed.Seal(pinned, req, seed); err == nil {
		t.Fatal("sealed for an attestation key whose creation does not verify")
	}
}

// bootServer answers seed requests for the MAC 38-05-25-38-b5-b5 as the boot
// server does: sealed to pinned when it is set, asking for the TPM's
// attestation with 401, and as it is otherwise. It counts the attestations it
// sees.
func bootServer(t *testing.T, pinned []byte, attested *int) *httptest.Server {
	t.Helper()
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost || r.URL.Path != "/hosts/38-05-25-38-b5-b5/seed" {
			http.NotFound(w, r)
			return
		}
		var req rackseed.Request
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}
		answer := rackseed.Answer{Seed: seed}
		if pinned != nil {
			if req.AK == nil {
				http.Error(w, rackseed.ErrNotAttested.Error(), http.StatusUnauthorized)
				return
			}
			*attested++
			sealed, err := rackseed.Seal(pinned, req, seed)
			if err != nil {
				http.Error(w, err.Error(), http.StatusForbidden)
				return
			}
			answer = rackseed.Answer{Sealed: sealed}
		}
		_ = json.NewEncoder(w).Encode(answer)
	}))
	t.Cleanup(srv.Close)
	return srv
}

func asker(srv *httptest.Server, tpm rackseed.TPM, opened *int) *rackseed.Asker {
	return &rackseed.Asker{Client: srv.Client(), Server: srv.URL, OpenTPM: func() (rackseed.TPM, error) {
		*opened++
		if tpm == nil {
			return nil, rackseed.ErrNoTPM
		}
		return tpm, nil
	}}
}

// The TPM is opened, and one attestation key made, only once a pinned TPM
// asks for it.
func TestAskGetsThePinnedHostsSeedThroughItsTPM(t *testing.T) {
	host := rackseedtest.New()
	pinned, _ := host.EK()
	var attested, opened int
	srv := bootServer(t, pinned, &attested)
	a := asker(srv, host, &opened)

	if _, err := a.Ask(context.Background(), "aa-bb-cc-dd-ee-ff"); !errors.Is(err, rackseed.ErrNotPublished) || opened != 0 {
		t.Fatalf("a MAC with nothing published: %v, TPM opened %d times", err, opened)
	}
	for range 2 {
		got, err := a.Ask(context.Background(), "38-05-25-38-b5-b5")
		if err != nil || string(got) != string(seed) {
			t.Fatalf("%q %v", got, err)
		}
	}
	if opened != 1 || attested != 2 {
		t.Fatalf("opened the TPM %d times for %d attestations", opened, attested)
	}
	if err := a.Close(); err != nil || !host.Closed {
		t.Fatalf("the TPM was not closed: %v", err)
	}

	var none int
	if _, err := asker(srv, nil, &none).Ask(context.Background(), "38-05-25-38-b5-b5"); !errors.Is(err, rackseed.ErrNoTPM) {
		t.Fatalf("a machine without a TPM asked for a pinned host's seed: %v", err)
	}
	stranger := rackseedtest.New()
	if _, err := asker(srv, stranger, &none).Ask(context.Background(), "38-05-25-38-b5-b5"); err == nil || !strings.Contains(err.Error(), "403") {
		t.Fatalf("another TPM asked for the pinned host's seed: %v", err)
	}
}

func TestAskGetsTheSeedAsItIsForAHostWithoutAPinnedTPM(t *testing.T) {
	var attested, opened int
	srv := bootServer(t, nil, &attested)
	got, err := asker(srv, rackseedtest.New(), &opened).Ask(context.Background(), "38-05-25-38-b5-b5")
	if err != nil || string(got) != string(seed) || opened != 0 {
		t.Fatalf("%q %v, TPM opened %d times", got, err, opened)
	}
}
