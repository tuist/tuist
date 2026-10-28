package macosandbox

import (
	"crypto/sha256"
	"embed"
	"fmt"
	"os"
	"path/filepath"
)

//go:generate sh -c "cd ../../../sandbox-image && GOWORK=off CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -o ../tart-kubelet/internal/macosandbox/bundle/sbx-macos ./cmd/sbx-macos && GOWORK=off CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -o ../tart-kubelet/internal/macosandbox/bundle/sbx-worker ./cmd/sbx-worker"
//go:embed bundle/*
var guestTools embed.FS

// installTools never overwrites a shared executable: paused guests retain their
// original mount path through kubelet upgrades and checkpoint restoration.
func installTools(root string) (string, error) {
	bridge, err := guestTools.ReadFile("bundle/sbx-macos")
	if err != nil {
		return "", fmt.Errorf("missing embedded guest bridge: run go generate: %w", err)
	}
	worker, err := guestTools.ReadFile("bundle/sbx-worker")
	if err != nil {
		return "", err
	}
	hash := sha256.New()
	hash.Write(bridge)
	hash.Write(worker)
	directory := filepath.Join(root, fmt.Sprintf("%x", hash.Sum(nil)[:16]))
	if err = os.MkdirAll(directory, 0755); err != nil {
		return "", err
	}
	for name, data := range map[string][]byte{"sbx-macos": bridge, "sbx-worker": worker} {
		path := filepath.Join(directory, name)
		if current, err := os.ReadFile(path); err == nil && sha256.Sum256(current) == sha256.Sum256(data) {
			continue
		}
		if err = atomicFile(path, data); err != nil {
			return "", err
		}
		if err = os.Chmod(path, 0755); err != nil {
			return "", err
		}
	}
	return directory, nil
}
