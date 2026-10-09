package egress

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"syscall"

	"golang.org/x/crypto/curve25519"
)

const (
	privateKeyFile = "private.key"
	publicKeyFile  = "public.key"
	keyLockFile    = ".lock"
)

// Key is a WireGuard Curve25519 key.
type Key [32]byte

// ParseKey parses the base64 form `wg` uses.
func ParseKey(value string) (Key, error) {
	var key Key
	raw, err := base64.StdEncoding.DecodeString(strings.TrimSpace(value))
	if err != nil || len(raw) != len(key) {
		return key, fmt.Errorf("invalid WireGuard key")
	}
	copy(key[:], raw)
	return key, nil
}

func (k Key) String() string { return base64.StdEncoding.EncodeToString(k[:]) }

// Hex is the form the WireGuard UAPI expects.
func (k Key) Hex() string { return hex.EncodeToString(k[:]) }

// PublicKey derives the public half of a private key.
func (k Key) PublicKey() (Key, error) {
	var public Key
	out, err := curve25519.X25519(k[:], curve25519.Basepoint)
	if err != nil {
		return public, err
	}
	copy(public[:], out)
	return public, nil
}

func generatePrivateKey() (Key, error) {
	var key Key
	if _, err := rand.Read(key[:]); err != nil {
		return key, err
	}
	key[0] &= 248
	key[31] = (key[31] & 127) | 64
	return key, nil
}

// EnsureHostKey loads the host's private key from dir, creating it on first
// use. Every gateway's tunnel daemon calls this, so creation is serialized
// with a lock file. The private key is root-only; the public key is
// world-readable for tart-kubelet to publish.
func EnsureHostKey(dir string) (Key, error) {
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return Key{}, err
	}
	if err := os.Chmod(dir, 0o755); err != nil {
		return Key{}, err
	}
	lock, err := os.OpenFile(filepath.Join(dir, keyLockFile), os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return Key{}, err
	}
	defer func() { _ = lock.Close() }()
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return Key{}, err
	}
	defer func() { _ = syscall.Flock(int(lock.Fd()), syscall.LOCK_UN) }()

	privatePath := filepath.Join(dir, privateKeyFile)
	var private Key
	data, err := os.ReadFile(privatePath)
	switch {
	case err == nil:
		private, err = ParseKey(string(data))
		if err != nil {
			return Key{}, fmt.Errorf("%s: %w", privatePath, err)
		}
	case errors.Is(err, os.ErrNotExist):
		private, err = generatePrivateKey()
		if err != nil {
			return Key{}, err
		}
		if err := writeFileAtomic(privatePath, private.String()+"\n", 0o600); err != nil {
			return Key{}, err
		}
	default:
		return Key{}, err
	}

	public, err := private.PublicKey()
	if err != nil {
		return Key{}, err
	}
	if err := writeFileAtomic(filepath.Join(dir, publicKeyFile), public.String()+"\n", 0o644); err != nil {
		return Key{}, err
	}
	return private, nil
}

func writeFileAtomic(path, content string, mode os.FileMode) error {
	tmp, err := os.CreateTemp(filepath.Dir(path), "."+filepath.Base(path)+".*")
	if err != nil {
		return err
	}
	defer func() { _ = os.Remove(tmp.Name()) }()
	if err := tmp.Chmod(mode); err != nil {
		_ = tmp.Close()
		return err
	}
	if _, err := tmp.WriteString(content); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Sync(); err != nil {
		_ = tmp.Close()
		return err
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), path)
}
