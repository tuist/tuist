// Package volumekeys fetches Kura volume passphrases from the Tuist server.
// Each request carries a fresh X25519 public key; the server seals the
// passphrase to it, so the key never crosses the wire in a form a TLS
// terminator or proxy could read.
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
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"time"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	Path          = "/_internal/kura/volume-keys"
	TransportInfo = "kura-volume-key-transport/v1"
	KeySize       = 32

	requestTimeout   = 15 * time.Second
	maxResponseBytes = 64 << 10
)

type Client struct {
	endpoint  string
	tokenPath string
	http      *http.Client
	attempts  int
	backoff   time.Duration
	logger    *slog.Logger
}

type Option func(*Client)

func WithHTTPClient(c *http.Client) Option { return func(cl *Client) { cl.http = c } }

func WithRetry(attempts int, backoff time.Duration) Option {
	return func(cl *Client) { cl.attempts, cl.backoff = attempts, backoff }
}

func WithLogger(l *slog.Logger) Option { return func(cl *Client) { cl.logger = l } }

func New(baseURL, tokenPath string, opts ...Option) *Client {
	c := &Client{
		endpoint:  strings.TrimRight(baseURL, "/") + Path,
		tokenPath: tokenPath,
		http:      &http.Client{},
		attempts:  4,
		backoff:   time.Second,
		logger:    slog.New(slog.DiscardHandler),
	}
	for _, opt := range opts {
		opt(c)
	}
	return c
}

type request struct {
	VolumeID   string `json:"volume_id"`
	PublicKey  string `json:"public_key"`
	KeyVersion int    `json:"key_version,omitempty"`
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

// Fetch returns the volume's 32-byte passphrase and the key version it was
// derived under. version 0 asks for the account's active key; any other value
// pins that version. Callers zero the passphrase after use.
func (c *Client) Fetch(ctx context.Context, volumeID string, version int) ([]byte, int, error) {
	if version < 0 {
		return nil, 0, status.Errorf(codes.InvalidArgument, "key version %d is negative", version)
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
	token, err := os.ReadFile(c.tokenPath)
	if err != nil {
		return nil, 0, retryableError{fmt.Errorf("read service account token: %w", err)}
	}
	bearer := strings.TrimSpace(string(token))
	if bearer == "" {
		return nil, 0, retryableError{errors.New("service account token is empty")}
	}

	private, err := ecdh.X25519().GenerateKey(rand.Reader)
	if err != nil {
		return nil, 0, status.Errorf(codes.Internal, "generate ephemeral key: %v", err)
	}
	body, err := json.Marshal(request{
		VolumeID:   volumeID,
		PublicKey:  base64.StdEncoding.EncodeToString(private.PublicKey().Bytes()),
		KeyVersion: version,
	})
	if err != nil {
		return nil, 0, status.Errorf(codes.Internal, "encode request: %v", err)
	}

	ctx, cancel := context.WithTimeout(ctx, requestTimeout)
	defer cancel()
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
	key, err := open(private, volumeID, sealed)
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

func open(private *ecdh.PrivateKey, volumeID string, sealed response) ([]byte, error) {
	serverPublicBytes, err := base64.StdEncoding.DecodeString(sealed.EphemeralPublicKey)
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
	serverPublic, err := ecdh.X25519().NewPublicKey(serverPublicBytes)
	if err != nil {
		return nil, fmt.Errorf("ephemeral_public_key: %w", err)
	}
	shared, err := private.ECDH(serverPublic)
	if err != nil {
		return nil, err
	}
	defer clear(shared)
	sealingKey, err := SealingKey(shared, serverPublicBytes, private.PublicKey().Bytes())
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
	key, err := gcm.Open(nil, nonce, ciphertext, []byte(volumeID))
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
// HKDF-SHA256(shared, salt = server ephemeral public || client public).
func SealingKey(shared, serverPublic, clientPublic []byte) ([]byte, error) {
	salt := make([]byte, 0, len(serverPublic)+len(clientPublic))
	salt = append(append(salt, serverPublic...), clientPublic...)
	return hkdf.Key(sha256.New, shared, salt, TransportInfo, 32)
}
