// Package envfile loads the daemon's deploy-varying configuration from a
// mounted ConfigMap file of KEY=VALUE lines, so the daemons read it the same
// way they read their environment. A variable the Pod's spec sets wins: the
// file only fills what the environment leaves unset.
package envfile

import (
	"bufio"
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"os"
	"strings"
)

// Load applies path, when set, to the process environment, and returns the
// SHA-256 of the bytes it applied ("" without a path). The in-place updater
// compares it with the ConfigMap's to tell a daemon running on stale
// configuration.
func Load(path string) (string, error) {
	if path == "" {
		return "", nil
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", err
	}
	sum := sha256.Sum256(data)
	scanner := bufio.NewScanner(bytes.NewReader(data))
	for line := 1; scanner.Scan(); line++ {
		text := strings.TrimSpace(scanner.Text())
		if text == "" || strings.HasPrefix(text, "#") {
			continue
		}
		key, value, ok := strings.Cut(text, "=")
		key = strings.TrimSpace(key)
		if !ok || key == "" {
			return "", fmt.Errorf("%s:%d: want KEY=VALUE", path, line)
		}
		if _, set := os.LookupEnv(key); set {
			continue
		}
		if err := os.Setenv(key, value); err != nil {
			return "", err
		}
	}
	if err := scanner.Err(); err != nil {
		return "", err
	}
	return hex.EncodeToString(sum[:]), nil
}
