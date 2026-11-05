package macosandbox

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"embed"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

//go:generate sh -c "cd ../../../sandbox-image && GOWORK=off CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -o ../tart-kubelet/internal/macosandbox/bundle/sbx-macos ./cmd/sbx-macos && GOWORK=off CGO_ENABLED=0 GOOS=darwin GOARCH=arm64 go build -trimpath -o ../tart-kubelet/internal/macosandbox/bundle/sbx-worker ./cmd/sbx-worker"
//go:embed bundle/*
var guestTools embed.FS

// ampCLIBase is where Amp publishes its CLI (`cli-version.txt`, then
// `<version>/amp-darwin-arm64.gz` and `<version>/darwin-arm64-amp.sha256`),
// the same files Amp's installer fetches.
var ampCLIBase = "https://static.ampcode.com/cli"

// provisionAmpCLI keeps a checksum-verified Amp CLI in the tools directory,
// so an Orb's first bootstrap copies it from the share instead of running
// Amp's installer in every new guest (about 10 s per Orb on staging). Only a
// missing binary is fetched; the guest CLI updates itself after install.
func provisionAmpCLI(ctx context.Context, tools string, client *http.Client) error {
	path := filepath.Join(tools, "amp")
	if _, err := os.Stat(path); err == nil {
		return nil
	}
	get := func(url string, limit int64) ([]byte, error) {
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
		if err != nil {
			return nil, err
		}
		resp, err := client.Do(req)
		if err != nil {
			return nil, err
		}
		defer resp.Body.Close()
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("GET %s: %s", url, resp.Status)
		}
		return io.ReadAll(io.LimitReader(resp.Body, limit))
	}
	version, err := get(ampCLIBase+"/cli-version.txt", 256)
	if err != nil {
		return err
	}
	v := strings.TrimSpace(string(version))
	if !regexp.MustCompile(`^[A-Za-z0-9._-]{1,64}$`).MatchString(v) {
		return errors.New("invalid Amp CLI version")
	}
	sum, err := get(ampCLIBase+"/"+v+"/darwin-arm64-amp.sha256", 256)
	if err != nil {
		return err
	}
	expected := strings.Fields(string(sum))
	if len(expected) == 0 {
		return errors.New("empty Amp CLI checksum")
	}
	compressed, err := get(ampCLIBase+"/"+v+"/amp-darwin-arm64.gz", 512<<20)
	if err != nil {
		return err
	}
	reader, err := gzip.NewReader(bytes.NewReader(compressed))
	if err != nil {
		return err
	}
	binary, err := io.ReadAll(io.LimitReader(reader, 1<<30))
	if err != nil {
		return err
	}
	if fmt.Sprintf("%x", sha256.Sum256(binary)) != strings.ToLower(expected[0]) {
		return errors.New("Amp CLI checksum mismatch")
	}
	// Make it executable before it appears under its shared name.
	staged := path + ".partial"
	if err = atomicFile(staged, binary); err != nil {
		return err
	}
	if err = os.Chmod(staged, 0755); err != nil {
		return err
	}
	return os.Rename(staged, path)
}

// keepAmpCLI retries the download until it succeeds. Guests bootstrap with
// Amp's installer meanwhile, so a failure only costs Orb startup time.
func keepAmpCLI(ctx context.Context, tools string) {
	client := &http.Client{Timeout: 10 * time.Minute}
	for {
		err := provisionAmpCLI(ctx, tools, client)
		if err == nil {
			return
		}
		slog.Warn("macOS sandbox Amp CLI download", "error", err)
		select {
		case <-ctx.Done():
			return
		case <-time.After(10 * time.Minute):
		}
	}
}

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
