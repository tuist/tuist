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
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
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
	shared := bytes.Repeat([]byte{7}, 32)
	server := bytes.Repeat([]byte{1}, 32)
	client := bytes.Repeat([]byte{2}, 32)
	got, err := SealingKey(shared, server, client)
	if err != nil {
		t.Fatal(err)
	}
	want := rfc5869(shared, append(append([]byte{}, server...), client...), []byte(TransportInfo), 32)
	if !bytes.Equal(got, want) {
		t.Fatalf("sealing key mismatch")
	}
}

// seal mirrors the server: it seals key to the client's public key with
// AAD = the volume id it was asked for (or aadVolumeID when set).
func seal(t *testing.T, clientPublicB64, aadVolumeID string, key []byte) response {
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
	shared, err := ephemeral.ECDH(clientPublic)
	if err != nil {
		t.Fatal(err)
	}
	ephemeralPublic := ephemeral.PublicKey().Bytes()
	sealingKey := rfc5869(shared, append(append([]byte{}, ephemeralPublic...), clientPublicBytes...), []byte(TransportInfo), 32)
	block, _ := aes.NewCipher(sealingKey)
	gcm, _ := cipher.NewGCM(block)
	nonce := make([]byte, 12)
	_, _ = rand.Read(nonce)
	return response{
		KeyVersion:         3,
		EphemeralPublicKey: base64.StdEncoding.EncodeToString(ephemeralPublic),
		Nonce:              base64.StdEncoding.EncodeToString(nonce),
		Ciphertext:         base64.StdEncoding.EncodeToString(gcm.Seal(nil, nonce, key, []byte(aadVolumeID))),
	}
}

func writeToken(t *testing.T, token string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(path, []byte(token+"\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func TestFetch(t *testing.T) {
	key := bytes.Repeat([]byte{0xa5}, KeySize)

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
				_ = json.NewEncoder(w).Encode(seal(t, req.PublicKey, req.VolumeID, key))
			},
			wantCode: codes.OK,
			wantKey:  key,
			wantHits: 1,
		},
		{
			name: "rejects a key sealed for another volume",
			handler: func(t *testing.T, w http.ResponseWriter, req request) {
				_ = json.NewEncoder(w).Encode(seal(t, req.PublicKey, "pvc-00000000-0000-0000-0000-000000000000", key))
			},
			wantCode: codes.Internal,
			wantHits: 1,
		},
		{
			name: "rejects a key of the wrong length",
			handler: func(t *testing.T, w http.ResponseWriter, req request) {
				_ = json.NewEncoder(w).Encode(seal(t, req.PublicKey, req.VolumeID, key[:16]))
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
			server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				hits.Add(1)
				if r.Method != http.MethodPost || r.URL.Path != Path {
					t.Errorf("unexpected request %s %s", r.Method, r.URL.Path)
				}
				if got := r.Header.Get("Authorization"); got != "Bearer projected-token" {
					t.Errorf("Authorization = %q", got)
				}
				var req request
				if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
					t.Errorf("decode request: %v", err)
				}
				if req.VolumeID != testVolumeID {
					t.Errorf("volume_id = %q", req.VolumeID)
				}
				if raw, err := base64.StdEncoding.DecodeString(req.PublicKey); err != nil || len(raw) != 32 {
					t.Errorf("public_key = %q is not 32 raw bytes in base64", req.PublicKey)
				}
				tt.handler(t, w, req)
			}))
			defer server.Close()

			client := New(server.URL+"/", writeToken(t, "projected-token"),
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

func TestFetchRecoversAfterTransientFailure(t *testing.T) {
	key := bytes.Repeat([]byte{0x3c}, KeySize)
	var hits atomic.Int32
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if hits.Add(1) == 1 {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		var req request
		_ = json.NewDecoder(r.Body).Decode(&req)
		_ = json.NewEncoder(w).Encode(seal(t, req.PublicKey, req.VolumeID, key))
	}))
	defer server.Close()

	client := New(server.URL, writeToken(t, "projected-token"),
		WithHTTPClient(server.Client()), WithRetry(3, time.Millisecond))
	got, _, err := client.Fetch(context.Background(), testVolumeID, 0)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, key) || hits.Load() != 2 {
		t.Fatalf("key = %x after %d hits", got, hits.Load())
	}
}

func TestFetchRereadsTokenEveryRequest(t *testing.T) {
	var tokens []string
	server := httptest.NewTLSServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tokens = append(tokens, r.Header.Get("Authorization"))
		w.WriteHeader(http.StatusNotFound)
	}))
	defer server.Close()

	path := writeToken(t, "first")
	client := New(server.URL, path, WithHTTPClient(server.Client()), WithRetry(1, time.Millisecond))
	_, _, _ = client.Fetch(context.Background(), testVolumeID, 0)
	if err := os.WriteFile(path, []byte("second"), 0o600); err != nil {
		t.Fatal(err)
	}
	_, _, _ = client.Fetch(context.Background(), testVolumeID, 0)
	if len(tokens) != 2 || tokens[0] != "Bearer first" || tokens[1] != "Bearer second" {
		t.Fatalf("tokens = %v", tokens)
	}
}

func TestFetchKeyVersion(t *testing.T) {
	key := bytes.Repeat([]byte{0x11}, KeySize)
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
				sealed := seal(t, raw["public_key"].(string), testVolumeID, key)
				sealed.KeyVersion = tt.served
				_ = json.NewEncoder(w).Encode(sealed)
			}))
			defer server.Close()

			client := New(server.URL, writeToken(t, "projected-token"), WithHTTPClient(server.Client()), WithRetry(1, time.Millisecond))
			got, version, err := client.Fetch(context.Background(), testVolumeID, tt.requested)
			requireCode(t, err, tt.wantCode)
			if version != tt.wantVersion || bytes.Equal(got, key) != tt.wantKeyResult {
				t.Fatalf("version = %d, key returned = %v", version, got != nil)
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
