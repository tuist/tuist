// Package volumekeys fetches Kura volume passphrases from the Tuist server
// end to end, independent of the TLS terminators on the path:
//
//   - Each request carries a fresh X25519 public key and a pod-bound
//     ServiceAccount token minted for an audience naming that key's hash. A
//     terminator replaying the token with its own key fails authentication.
//   - The server seals the passphrase with its ephemeral key and a static key
//     pinned here, so only the key service can produce a response that opens.
//     The key version is authenticated with the volume id.
package volumekeys

import (
	"bytes"
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdh"
	"crypto/hkdf"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	Path           = "/_internal/kura/volume-keys"
	TransportInfo  = "kura-volume-key-transport/v2"
	AudiencePrefix = "kura-volume-keys.tuist.dev/v2/"
	KeySize        = 32

	requestTimeout   = 15 * time.Second
	maxResponseBytes = 64 << 10
)

// TokenSource mints a ServiceAccount token for exactly one audience.
type TokenSource interface {
	Token(ctx context.Context, audience string) (string, error)
}

type Client struct {
	endpoint     string
	serverPublic *ecdh.PublicKey
	tokens       TokenSource
	http         *http.Client
	attempts     int
	backoff      time.Duration
	logger       *slog.Logger
}

type Option func(*Client)

func WithHTTPClient(c *http.Client) Option { return func(cl *Client) { cl.http = c } }

func WithRetry(attempts int, backoff time.Duration) Option {
	return func(cl *Client) { cl.attempts, cl.backoff = attempts, backoff }
}

func WithLogger(l *slog.Logger) Option { return func(cl *Client) { cl.logger = l } }

// ParseServerPublicKey decodes the pinned base64 X25519 key-service key.
func ParseServerPublicKey(encoded string) (*ecdh.PublicKey, error) {
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(encoded))
	if err != nil {
		return nil, fmt.Errorf("decode key-service public key: %w", err)
	}
	key, err := ecdh.X25519().NewPublicKey(raw)
	if err != nil {
		return nil, fmt.Errorf("key-service public key: %w", err)
	}
	return key, nil
}

func New(baseURL string, serverPublic *ecdh.PublicKey, tokens TokenSource, opts ...Option) *Client {
	c := &Client{
		endpoint:     strings.TrimRight(baseURL, "/") + Path,
		serverPublic: serverPublic,
		tokens:       tokens,
		http:         &http.Client{},
		attempts:     4,
		backoff:      time.Second,
		logger:       slog.New(slog.DiscardHandler),
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

// Audience is the token audience that authorizes a request for clientPublic.
func Audience(clientPublic []byte) string {
	sum := sha256.Sum256(clientPublic)
	return AudiencePrefix + hex.EncodeToString(sum[:])
}

type request struct {
	VolumeID        string `json:"volume_id"`
	PublicKey       string `json:"public_key"`
	ServerPublicKey string `json:"server_public_key"`
	KeyVersion      int    `json:"key_version,omitempty"`
}

type response struct {
	KeyVersion         int    `json:"key_version"`
	EphemeralPublicKey string `json:"ephemeral_public_key"`
	Nonce              string `json:"nonce"`
	Ciphertext         string `json:"ciphertext"`
}

type retryableError struct{ err error }

func (e retryableError) Error() string { return e.err.Error() }
func (e retryableError) Unwrap() error { return e.err }

// Retryable marks a TokenSource failure as transient.
func Retryable(err error) error { return retryableError{err} }

// Fetch returns the volume's 32-byte passphrase and the key version it was
// derived under. version 0 asks for the account's active key; any other value
// pins that version. Callers zero the passphrase after use.
func (c *Client) Fetch(ctx context.Context, volumeID string, version int) ([]byte, int, error) {
	if version < 0 {
		return nil, 0, status.Errorf(codes.InvalidArgument, "key version %d is negative", version)
	}
	if c.serverPublic == nil {
		return nil, 0, status.Error(codes.FailedPrecondition, "no key-service public key is pinned")
	}
	var lastErr error
	delay := c.backoff
	for attempt := 1; attempt <= c.attempts; attempt++ {
		key, keyVersion, err := c.fetchOnce(ctx, volumeID, version)
		if err == nil {
			return key, keyVersion, nil
		}
		var retryable retryableError
		if !errors.As(err, &retryable) {
			return nil, 0, err
		}
		lastErr = retryable.err
		if attempt == c.attempts {
			break
		}
		c.logger.Warn("volume key fetch failed, retrying", "volume_id", volumeID, "attempt", attempt, "error", lastErr)
		select {
		case <-ctx.Done():
			return nil, 0, status.Errorf(codes.Unavailable, "fetch volume key: %v (last error: %v)", ctx.Err(), lastErr)
		case <-time.After(delay):
		}
		delay *= 2
	}
	return nil, 0, status.Errorf(codes.Unavailable, "fetch volume key: %v", lastErr)
}

func (c *Client) fetchOnce(ctx context.Context, volumeID string, version int) ([]byte, int, error) {
	ctx, cancel := context.WithTimeout(ctx, requestTimeout)
	defer cancel()

	private, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return nil, 0, status.Errorf(codes.Internal, "generate ephemeral key: %v", err)
	}
	clientPublic := private.PublicKey().Bytes()
	bearer, err := c.tokens.Token(ctx, Audience(clientPublic))
	if err != nil {
		var retryable retryableError
		if errors.As(err, &retryable) {
			return nil, 0, err
		}
		return nil, 0, status.Errorf(codes.PermissionDenied, "mint key-service token: %v", err)
	}
	body, err := json.Marshal(request{
		VolumeID:        volumeID,
		PublicKey:       base64.StdEncoding.EncodeToString(clientPublic),
		ServerPublicKey: base64.StdEncoding.EncodeToString(c.serverPublic.Bytes()),
		KeyVersion:      version,
	})
	if err != nil {
		return nil, 0, status.Errorf(codes.Internal, "encode request: %v", err)
	}

	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint, bytes.NewReader(body))
	if err != nil {
		return nil, 0, status.Errorf(codes.Internal, "build request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "Bearer "+bearer)

	resp, err := c.http.Do(req)
	if err != nil {
		return nil, 0, retryableError{err}
	}
	defer resp.Body.Close()
	payload, err := io.ReadAll(io.LimitReader(resp.Body, maxResponseBytes))
	if err != nil {
		return nil, 0, retryableError{fmt.Errorf("read response: %w", err)}
	}
	if resp.StatusCode != http.StatusOK {
		return nil, 0, statusError(resp.StatusCode, payload)
	}

	var sealed response
	if err := json.Unmarshal(payload, &sealed); err != nil {
		return nil, 0, status.Errorf(codes.Internal, "decode response: %v", err)
	}
	if sealed.KeyVersion <= 0 {
		return nil, 0, status.Errorf(codes.Internal, "key service returned invalid key_version %d", sealed.KeyVersion)
	}
	if version > 0 && sealed.KeyVersion != version {
		return nil, 0, status.Errorf(codes.Internal, "key service returned key_version %d, requested %d", sealed.KeyVersion, version)
	}
	key, err := open(private, c.serverPublic, volumeID, sealed)
	if err != nil {
		return nil, 0, status.Errorf(codes.Internal, "open volume key: %v", err)
	}
	c.logger.Debug("fetched volume key", "volume_id", volumeID, "key_version", sealed.KeyVersion)
	return key, sealed.KeyVersion, nil
}

func statusError(code int, payload []byte) error {
	var body struct {
		Error string `json:"error"`
	}
	message := http.StatusText(code)
	if json.Unmarshal(payload, &body) == nil && body.Error != "" {
		message = body.Error
	}
	err := fmt.Errorf("key service returned %d: %s", code, message)
	switch {
	case code >= 500:
		return retryableError{err}
	case code == http.StatusUnauthorized || code == http.StatusForbidden:
		return status.Error(codes.PermissionDenied, err.Error())
	case code == http.StatusNotFound:
		return status.Error(codes.NotFound, err.Error())
	default:
		return status.Error(codes.Internal, err.Error())
	}
}

func open(private *ecdh.PrivateKey, serverStatic *ecdh.PublicKey, volumeID string, sealed response) ([]byte, error) {
	ephemeralBytes, err := base64.StdEncoding.DecodeString(sealed.EphemeralPublicKey)
	if err != nil {
		return nil, fmt.Errorf("ephemeral_public_key: %w", err)
	}
	nonce, err := base64.StdEncoding.DecodeString(sealed.Nonce)
	if err != nil {
		return nil, fmt.Errorf("nonce: %w", err)
	}
	ciphertext, err := base64.StdEncoding.DecodeString(sealed.Ciphertext)
	if err != nil {
		return nil, fmt.Errorf("ciphertext: %w", err)
	}
	ephemeral, err := ecdh.X25519().NewPublicKey(ephemeralBytes)
	if err != nil {
		return nil, fmt.Errorf("ephemeral_public_key: %w", err)
	}
	ephemeralShared, err := private.ECDH(ephemeral)
	if err != nil {
		return nil, err
	}
	defer clear(ephemeralShared)
	staticShared, err := private.ECDH(serverStatic)
	if err != nil {
		return nil, err
	}
	defer clear(staticShared)
	sealingKey, err := SealingKey(ephemeralShared, staticShared, ephemeralBytes, private.PublicKey().Bytes(), serverStatic.Bytes())
	if err != nil {
		return nil, err
	}
	defer clear(sealingKey)
	block, err := aes.NewCipher(sealingKey)
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}
	if len(nonce) != gcm.NonceSize() {
		return nil, fmt.Errorf("nonce is %d bytes, want %d", len(nonce), gcm.NonceSize())
	}
	key, err := gcm.Open(nil, nonce, ciphertext, AAD(volumeID, sealed.KeyVersion))
	if err != nil {
		return nil, err
	}
	if len(key) != KeySize {
		clear(key)
		return nil, fmt.Errorf("volume key is %d bytes, want %d", len(key), KeySize)
	}
	return key, nil
}

// SealingKey derives the AES-256-GCM key both sides use:
// HKDF-SHA256(ikm = X25519(ephemeral) || X25519(static),
// salt = server ephemeral public || client public || server static public).
func SealingKey(ephemeralShared, staticShared, serverEphemeral, clientPublic, serverStatic []byte) ([]byte, error) {
	ikm := append(append(make([]byte, 0, 64), ephemeralShared...), staticShared...)
	defer clear(ikm)
	salt := append(append(append(make([]byte, 0, 96), serverEphemeral...), clientPublic...), serverStatic...)
	return hkdf.Key(sha256.New, ikm, salt, TransportInfo, 32)
}

// AAD authenticates the volume and the key version the passphrase belongs to.
func AAD(volumeID string, keyVersion int) []byte {
	return []byte(volumeID + "\x00" + strconv.Itoa(keyVersion))
}
