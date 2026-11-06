package podagent

import (
	"archive/zip"
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"time"
)

// The git-lfs the checkout populator runs, pinned and verified before it is used.
const (
	gitLFSURL    = "https://github.com/git-lfs/git-lfs/releases/download/v3.8.0/git-lfs-darwin-arm64-v3.8.0.zip"
	gitLFSSHA256 = "caff76a7d070d8160c89bc39b6e85d98f24135b6fed038a3b4de2590d25102d8"
	gitLFSEntry  = "git-lfs-3.8.0/git-lfs"
)

// GitLFS installs the pinned git-lfs into <root>/.bin, which is first on the
// populator's PATH. Hosts have no git-lfs of their own, and the populator never
// runs whatever else is on PATH.
func GitLFS(root string, download func(context.Context) ([]byte, error)) func(context.Context) error {
	if download == nil {
		download = downloadGitLFS
	}
	return func(ctx context.Context) error { return ensureGitLFS(ctx, root, download) }
}

func ensureGitLFS(ctx context.Context, root string, download func(context.Context) ([]byte, error)) error {
	bin := filepath.Join(root, ".bin")
	marker := filepath.Join(bin, "git-lfs.sha256")
	if installed, err := os.ReadFile(marker); err == nil && string(installed) == gitLFSSHA256 {
		if _, err := os.Stat(filepath.Join(bin, "git-lfs")); err == nil {
			return nil
		}
	}
	archive, err := download(ctx)
	if err != nil {
		return err
	}
	sum := sha256.Sum256(archive)
	if hex.EncodeToString(sum[:]) != gitLFSSHA256 {
		return errors.New("git-lfs archive checksum mismatch")
	}
	reader, err := zip.NewReader(bytes.NewReader(archive), int64(len(archive)))
	if err != nil {
		return err
	}
	for _, file := range reader.File {
		if file.Name != gitLFSEntry {
			continue
		}
		if err := os.MkdirAll(bin, 0700); err != nil {
			return err
		}
		in, err := file.Open()
		if err != nil {
			return err
		}
		defer in.Close()
		tmp := filepath.Join(bin, "git-lfs.tmp")
		out, err := os.OpenFile(tmp, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0755)
		if err != nil {
			return err
		}
		_, err = io.Copy(out, io.LimitReader(in, 64<<20))
		if closeErr := out.Close(); err == nil {
			err = closeErr
		}
		if err != nil {
			return err
		}
		if err := os.Rename(tmp, filepath.Join(bin, "git-lfs")); err != nil {
			return err
		}
		return os.WriteFile(marker, []byte(gitLFSSHA256), 0600)
	}
	return errors.New("git-lfs archive has no binary")
}

func downloadGitLFS(ctx context.Context) ([]byte, error) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Minute)
	defer cancel()
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, gitLFSURL, nil)
	if err != nil {
		return nil, err
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("git-lfs download status %d", response.StatusCode)
	}
	return io.ReadAll(io.LimitReader(response.Body, 64<<20))
}
