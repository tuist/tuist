package volumekeys

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"maps"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/tuist/tuist/infra/kura-volumes-csi/internal/kubeapi"
)

const testVolumeID = "pvc-0b5a7f7e-3c1d-4b8e-9f2a-6d4c1e2b3a59"

// rfc5869 is an independent HKDF-SHA256, matching the server's
// Tuist.Kura.VolumeKeys.HKDF, so the test does not reuse SealingKey.
func rfc5869(ikm, salt, info []byte, length int) []byte {
	extract := hmac.New(sha256.New, salt)
	extract.Write(ikm)
	prk := extract.Sum(nil)
	var okm, previous []byte
	for counter := byte(1); len(okm) < length; counter++ {
		expand := hmac.New(sha256.New, prk)
		expand.Write(previous)
		expand.Write(info)
		expand.Write([]byte{counter})
		previous = expand.Sum(nil)
		okm = append(okm, previous...)
	}
	return okm[:length]
}

func TestRFC5869Vector(t *testing.T) {
	ikm := bytes.Repeat([]byte{0x0b}, 22)
	salt, _ := hex.DecodeString("000102030405060708090a0b0c")
	info, _ := hex.DecodeString("f0f1f2f3f4f5f6f7f8f9")
	want := "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
	if got := hex.EncodeToString(rfc5869(ikm, salt, info, 42)); got != want {
		t.Fatalf("hkdf = %s, want %s", got, want)
	}
}

func TestSealingKeyMatchesServerDerivation(t *testing.T) {
	ephemeralShared := bytes.Repeat([]byte{7}, 32)
	staticShared := bytes.Repeat([]byte{8}, 32)
	ephemeral := bytes.Repeat([]byte{1}, 32)
	client := bytes.Repeat([]byte{2}, 32)
	static := bytes.Repeat([]byte{3}, 32)
	got, err := SealingKey(ephemeralShared, staticShared, ephemeral, client, static)
	if err != nil {
		t.Fatal(err)
	}
	want := rfc5869(concat(ephemeralShared, staticShared), concat(ephemeral, client, static), []byte(TransportInfo), 32)
	if !bytes.Equal(got, want) {
		t.Fatalf("sealing key mismatch")
	}
}

func concat(parts ...[]byte) []byte {
	var out []byte
	for _, part := range parts {
		out = append(out, part...)
	}
	return out
}

// sealed mirrors the server with an independent HKDF: it seals key to the
// client public key with the static key and AAD = volume id and key version.
type sealed struct {
	static     *ecdh.PrivateKey
	volumeID   string
	keyVersion int
}

func (s sealed) seal(t *testing.T, clientPublicB64 string, key []byte) response {
	t.Helper()
	clientPublicBytes, err := base64.StdEncoding.DecodeString(clientPublicB64)
	if err != nil {
		t.Fatalf("decode client public key: %v", err)
	}
	clientPublic, err := ecdh.X25519().NewPublicKey(clientPublicBytes)
	if err != nil {
		t.Fatalf("client public key: %v", err)
	}
	ephemeral, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	ephemeralShared, _ := ephemeral.ECDH(clientPublic)
	staticShared, _ := s.static.ECDH(clientPublic)
	ephemeralPublic := ephemeral.PublicKey().Bytes()
	sealingKey := rfc5869(concat(ephemeralShared, staticShared), concat(ephemeralPublic, clientPublicBytes, s.static.PublicKey().Bytes()), []byte(TransportInfo), 32)
	block, _ := aes.NewCipher(sealingKey)
	gcm, _ := cipher.NewGCM(block)
	nonce := make([]byte, 12)
	_, _ = rand.Read(nonce)
	return response{
		KeyVersion:         s.keyVersion,
		EphemeralPublicKey: base64.StdEncoding.EncodeToString(ephemeralPublic),
		Nonce:              base64.StdEncoding.EncodeToString(nonce),
		Ciphertext:         base64.StdEncoding.EncodeToString(gcm.Seal(nil, nonce, key, []byte(s.volumeID+"\x00"+strconv.Itoa(s.keyVersion)))),
	}
}

// fakeTokens issues "token-for:<audience>" and records the audiences.
type fakeTokens struct {
	mu        sync.Mutex
	audiences []string
	err       error
}

func (f *fakeTokens) Token(_ context.Context, audience string) (string, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.audiences = append(f.audiences, audience)
	if f.err != nil {
		return "", f.err
	}
	return "token-for:" + audience, nil
}

func newStatic(t *testing.T) *ecdh.PrivateKey {
	t.Helper()
	key, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	return key
}

func TestFetch(t *testing.T) {
	key := bytes.Repeat([]byte{0xa5}, KeySize)
	static := newStatic(t)

	tests := []struct {
		name     string
		handler  func(t *testing.T, w http.ResponseWriter, req request)
		wantCode codes.Code
		wantKey  []byte
		wantHits int32
	}{
		{
			name: "opens the sealed key",
			handler: func(t *testing.T, w http.ResponseWriter, req request) {
				_ = json.NewEncoder(w).Encode(sealed{static, req.VolumeID, 3}.seal(t, req.PublicKey, key))
			},
			wantCode: codes.OK,
			wantKey:  key,
			wantHits: 1,
		},
		{
			name: "rejects a key sealed for another volume",
			handler: func(t *testing.T, w http.ResponseWriter, req request) {
				_ = json.NewEncoder(w).Encode(sealed{static, "pvc-00000000-0000-0000-0000-000000000000", 3}.seal(t, req.PublicKey, key))
			},
			wantCode: codes.Internal,
			wantHits: 1,
		},
		{
			name: "rejects a response forged without the pinned static key",
			handler: func(t *testing.T, w http.ResponseWriter, req request) {
				_ = json.NewEncoder(w).Encode(sealed{newStatic(t), req.VolumeID, 3}.seal(t, req.PublicKey, key))
			},
			wantCode: codes.Internal,
			wantHits: 1,
		},
		{
			name: "rejects a rewritten key version",
			handler: func(t *testing.T, w http.ResponseWriter, req request) {
				response := sealed{static, req.VolumeID, 3}.seal(t, req.PublicKey, key)
				response.KeyVersion = 4
				_ = json.NewEncoder(w).Encode(response)
			},
			wantCode: codes.Internal,
			wantHits: 1,
		},
		{
			name: "rejects a key of the wrong length",
			handler: func(t *testing.T, w http.ResponseWriter, req request) {
				_ = json.NewEncoder(w).Encode(sealed{static, req.VolumeID, 3}.seal(t, req.PublicKey, key[:16]))
			},
			wantCode: codes.Internal,
			wantHits: 1,
		},
		{
			name: "maps 403 to PermissionDenied without retrying",
			handler: func(_ *testing.T, w http.ResponseWriter, _ request) {
				w.WriteHeader(http.StatusForbidden)
				_, _ = w.Write([]byte(`{"error":"volume belongs to another node"}`))
			},
			wantCode: codes.PermissionDenied,
			wantHits: 1,
		},
		{
			name: "maps 401 to PermissionDenied",
			handler: func(_ *testing.T, w http.ResponseWriter, _ request) {
				w.WriteHeader(http.StatusUnauthorized)
			},
			wantCode: codes.PermissionDenied,
			wantHits: 1,
		},
		{
			name: "maps 404 to NotFound",
			handler: func(_ *testing.T, w http.ResponseWriter, _ request) {
				w.WriteHeader(http.StatusNotFound)
				_, _ = w.Write([]byte(`{"error":"unknown volume"}`))
			},
			wantCode: codes.NotFound,
			wantHits: 1,
		},
		{
			name: "retries 5xx and gives up as Unavailable",
			handler: func(_ *testing.T, w http.ResponseWriter, _ request) {
				w.WriteHeader(http.StatusServiceUnavailable)
			},
			wantCode: codes.Unavailable,
			wantHits: 3,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var hits atomic.Int32
			tokens := &fakeTokens{}
			server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				hits.Add(1)
				if r.Method != http.MethodPost || r.URL.Path != Path {
					t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
				}
				var req request
				if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
					t.Errorf("decode request: %v", err)
				}
				clientPublic, err := base64.StdEncoding.DecodeString(req.PublicKey)
				if err != nil || len(clientPublic) != 32 {
					t.Errorf("public_key = %q is not 32 raw bytes in base64", req.PublicKey)
				}
				if got, want := r.Header.Get("Authorization"), "Bearer token-for:"+Audience(clientPublic); got != want {
					t.Errorf("Authorization = %q, want %q", got, want)
				}
				if req.ServerPublicKey != base64.StdEncoding.EncodeToString(static.PublicKey().Bytes()) {
					t.Errorf("server_public_key = %q", req.ServerPublicKey)
				}
				if req.VolumeID != testVolumeID {
					t.Errorf("volume_id = %q", req.VolumeID)
				}
				tt.handler(t, w, req)
			}))
			defer server.Close()

			client := New(server.URL+"/", static.PublicKey(), tokens,
				WithHTTPClient(server.Client()), WithRetry(3, time.Millisecond))
			got, _, err := client.Fetch(context.Background(), testVolumeID, 0)
			if status.Code(err) != tt.wantCode {
				t.Fatalf("code = %v (%v), want %v", status.Code(err), err, tt.wantCode)
			}
			if !bytes.Equal(got, tt.wantKey) {
				t.Fatalf("key = %x, want %x", got, tt.wantKey)
			}
			if hits.Load() != tt.wantHits {
				t.Fatalf("hits = %d, want %d", hits.Load(), tt.wantHits)
			}
		})
	}
}

func TestFetchMintsATokenPerRequestKey(t *testing.T) {
	static := newStatic(t)
	var publicKeys []string
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req request
		_ = json.NewDecoder(r.Body).Decode(&req)
		publicKeys = append(publicKeys, req.PublicKey)
		w.WriteHeader(http.StatusBadGateway)
	}))
	defer server.Close()

	tokens := &fakeTokens{}
	client := New(server.URL, static.PublicKey(), tokens, WithHTTPClient(server.Client()), WithRetry(2, time.Millisecond))
	_, _, _ = client.Fetch(context.Background(), testVolumeID, 0)
	if len(publicKeys) != 2 || publicKeys[0] == publicKeys[1] {
		t.Fatalf("public keys = %v, want two distinct", publicKeys)
	}
	for i, encoded := range publicKeys {
		raw, _ := base64.StdEncoding.DecodeString(encoded)
		if tokens.audiences[i] != Audience(raw) {
			t.Fatalf("audience %d = %q, want %q", i, tokens.audiences[i], Audience(raw))
		}
	}
}

func TestFetchTokenFailures(t *testing.T) {
	static := newStatic(t)
	tests := []struct {
		name     string
		err      error
		wantCode codes.Code
		wantMint int
	}{
		{name: "retries a transient token failure", err: Retryable(errors.New("apiserver unavailable")), wantCode: codes.Unavailable, wantMint: 2},
		{name: "denies a refused token request", err: errors.New("forbidden"), wantCode: codes.PermissionDenied, wantMint: 1},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tokens := &fakeTokens{err: tt.err}
			client := New("https://key-service.invalid", static.PublicKey(), tokens, WithRetry(2, time.Millisecond))
			_, _, err := client.Fetch(context.Background(), testVolumeID, 0)
			requireCode(t, err, tt.wantCode)
			if len(tokens.audiences) != tt.wantMint {
				t.Fatalf("minted %d tokens, want %d", len(tokens.audiences), tt.wantMint)
			}
		})
	}
}

func TestFetchRecoversAfterTransientFailure(t *testing.T) {
	key := bytes.Repeat([]byte{0x3c}, KeySize)
	static := newStatic(t)
	var hits atomic.Int32
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) == 1 {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		var req request
		_ = json.NewDecoder(r.Body).Decode(&req)
		_ = json.NewEncoder(w).Encode(sealed{static, req.VolumeID, 3}.seal(t, req.PublicKey, key))
	}))
	defer server.Close()

	client := New(server.URL, static.PublicKey(), &fakeTokens{},
		WithHTTPClient(server.Client()), WithRetry(3, time.Millisecond))
	got, _, err := client.Fetch(context.Background(), testVolumeID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, key) || hits.Load() != 2 {
		t.Fatalf("key = %x after %d hits", got, hits.Load())
	}
}

func TestFetchKeyVersion(t *testing.T) {
	key := bytes.Repeat([]byte{0x11}, KeySize)
	static := newStatic(t)
	tests := []struct {
		name          string
		requested     int
		served        int
		wantSent      any
		wantCode      codes.Code
		wantVersion   int
		wantKeyResult bool
	}{
		{name: "omits key_version for the active key", requested: 0, served: 3, wantSent: nil, wantVersion: 3, wantKeyResult: true},
		{name: "pins a stored key_version", requested: 2, served: 2, wantSent: float64(2), wantVersion: 2, wantKeyResult: true},
		{name: "rejects a different served version", requested: 2, served: 3, wantSent: float64(2), wantCode: codes.Internal},
		{name: "rejects a missing served version", requested: 0, served: 0, wantSent: nil, wantCode: codes.Internal},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				var raw map[string]any
				if err := json.NewDecoder(r.Body).Decode(&raw); err != nil {
					t.Errorf("decode request: %v", err)
				}
				sent, present := raw["key_version"]
				if tt.wantSent == nil && present {
					t.Errorf("key_version %v sent, want it omitted", sent)
				}
				if tt.wantSent != nil && sent != tt.wantSent {
					t.Errorf("key_version = %v, want %v", sent, tt.wantSent)
				}
				_ = json.NewEncoder(w).Encode(sealed{static, testVolumeID, tt.served}.seal(t, raw["public_key"].(string), key))
			}))
			defer server.Close()

			client := New(server.URL, static.PublicKey(), &fakeTokens{}, WithHTTPClient(server.Client()), WithRetry(1, time.Millisecond))
			got, version, err := client.Fetch(context.Background(), testVolumeID, tt.requested)
			requireCode(t, err, tt.wantCode)
			if version != tt.wantVersion || bytes.Equal(got, key) != tt.wantKeyResult {
				t.Fatalf("version = %d, key returned = %v", version, got != nil)
			}
		})
	}
}

func TestPodTokenSource(t *testing.T) {
	tests := []struct {
		name          string
		status        int
		body          string
		wantToken     string
		wantRetryable bool
	}{
		{name: "returns the minted token", status: http.StatusCreated, body: `{"status":{"token":"minted"}}`, wantToken: "minted"},
		{name: "refusal is final", status: http.StatusForbidden, body: `{"message":"denied by policy"}`},
		{name: "apiserver errors retry", status: http.StatusServiceUnavailable, wantRetryable: true},
		{name: "throttling retries", status: http.StatusTooManyRequests, wantRetryable: true},
		{name: "an empty token retries", status: http.StatusCreated, body: `{"status":{}}`, wantRetryable: true},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Method != http.MethodPost || r.URL.Path != "/api/v1/namespaces/kura-volumes/serviceaccounts/kura-volumes-csi-node/token" {
					t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
				}
				if got := r.Header.Get("Authorization"); got != "Bearer own-token" {
					t.Errorf("Authorization = %q", got)
				}
				var request struct {
					Spec struct {
						Audiences         []string          `json:"audiences"`
						ExpirationSeconds int               `json:"expirationSeconds"`
						BoundObjectRef    map[string]string `json:"boundObjectRef"`
					} `json:"spec"`
				}
				_ = json.NewDecoder(r.Body).Decode(&request)
				want := map[string]string{"apiVersion": "v1", "kind": "Pod", "name": "csi-node-abc", "uid": "pod-uid"}
				if len(request.Spec.Audiences) != 1 || request.Spec.Audiences[0] != "aud" ||
					request.Spec.ExpirationSeconds != 600 || !maps.Equal(request.Spec.BoundObjectRef, want) {
					t.Errorf("spec = %+v", request.Spec)
				}
				w.WriteHeader(tt.status)
				_, _ = w.Write([]byte(tt.body))
			}))
			defer server.Close()

			tokenPath := filepath.Join(t.TempDir(), "token")
			if err := os.WriteFile(tokenPath, []byte("own-token\n"), 0o600); err != nil {
				t.Fatal(err)
			}
			source := PodTokenSource{
				API:            kubeapi.New(server.URL, tokenPath, server.Client()),
				Namespace:      "kura-volumes",
				ServiceAccount: "kura-volumes-csi-node",
				PodName:        "csi-node-abc",
				PodUID:         "pod-uid",
			}
			token, err := source.Token(context.Background(), "aud")
			if token != tt.wantToken {
				t.Fatalf("token = %q, want %q (err %v)", token, tt.wantToken, err)
			}
			var retryable retryableError
			if tt.wantToken == "" && (err == nil || errors.As(err, &retryable) != tt.wantRetryable) {
				t.Fatalf("err = %v, want retryable %v", err, tt.wantRetryable)
			}
		})
	}
}

func requireCode(t *testing.T, err error, want codes.Code) {
	t.Helper()
	if got := status.Code(err); got != want {
		t.Fatalf("code = %v (%v), want %v", got, err, want)
	}
}

func TestFetchRequiresAPinnedServerKey(t *testing.T) {
	tokens := &fakeTokens{}
	client := New("https://key-service.invalid", nil, tokens, WithRetry(1, time.Millisecond))
	_, _, err := client.Fetch(context.Background(), testVolumeID, 0)
	requireCode(t, err, codes.FailedPrecondition)
	if len(tokens.audiences) != 0 {
		t.Fatalf("minted %d tokens without a pinned key", len(tokens.audiences))
	}
}

func TestPodTokenSourceRequiresItsPodIdentity(t *testing.T) {
	source := PodTokenSource{Namespace: "kura-volumes", ServiceAccount: "kura-volumes-csi-node", PodName: "csi-node-abc"}
	if _, err := source.Token(context.Background(), "aud"); err == nil {
		t.Fatal("minted a token without the pod UID")
	}
}
