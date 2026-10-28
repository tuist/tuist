package main

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// On Linux the host loop-mounts the job's clone under the pod's cache directory,
// and the mount broker binds its working tree at the workspace.
const linuxCacheRoot = "/home/runner/work/_tuist_cache"
const linuxCheckoutStatePath = "/home/runner/.tuist-checkout.json"

// The export is assembled on the work volume, so a cold job's LFS objects are
// hard-linked into it rather than copied.
const linuxExportScratch = "/home/runner/work/_tuist_checkout_export"

type linuxCheckoutClient struct {
	endpoint, pod, uid string
	http               *http.Client
}

func newLinuxCheckoutClient(timeout time.Duration) *linuxCheckoutClient {
	return &linuxCheckoutClient{
		endpoint: os.Getenv("TUIST_CACHE_VOLUME_URL"), pod: os.Getenv("TUIST_CACHE_VOLUME_POD"), uid: os.Getenv("TUIST_CACHE_VOLUME_UID"),
		http: &http.Client{Timeout: timeout, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
	}
}

func (c *linuxCheckoutClient) request(ctx context.Context) (macResponse, error) {
	var response macResponse
	if c.endpoint == "" {
		return response, errors.New("cache volumes disabled")
	}
	body, _ := json.Marshal(map[string]any{"pod_name": c.pod, "pod_uid": c.uid, "uid": os.Getuid()})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint+"/checkout", bytes.NewReader(body))
	if err != nil {
		return response, err
	}
	req.Header.Set("Content-Type", "application/json")
	err = requestJSON(c.http, req, &response)
	return response, err
}

// checkoutLinux mounts the job's cached checkout at its workspace before the
// first step. Every failure leaves the workspace untouched, so actions/checkout
// clones exactly as it does without a cached checkout.
func checkoutLinux(workspace string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	client := newLinuxCheckoutClient(20 * time.Second)
	return checkoutLinuxAt(ctx, workspace, linuxCacheRoot, linuxCheckoutStatePath, client.request, bindCheckout)
}

func checkoutLinuxAt(ctx context.Context, workspace, root, statePath string, request func(context.Context) (macResponse, error), mount func(socket, source, workspace, target string) error) string {
	if !filepath.IsAbs(workspace) || filepath.Clean(workspace) != workspace {
		return "skipped (workspace is not an absolute path)"
	}
	work := filepath.Dir(root)
	relative, err := filepath.Rel(work, workspace)
	if err != nil || relative == "." || strings.HasPrefix(relative, "..") || containsPath(root, workspace) {
		return "skipped (workspace is outside the work directory)"
	}
	if err := emptyTarget(workspace); err != nil {
		return "skipped (workspace is not empty)"
	}
	response, err := request(ctx)
	if err != nil {
		return "unavailable (request)"
	}
	if response.Error != "" || !directoryPattern.MatchString(response.Directory) || response.ID == "" {
		reason := response.Reason
		if !reasonPattern.MatchString(reason) {
			reason = "error"
		}
		// Only these answers come with a grant, so only they let the host build
		// from what this job exports. A timeout is mostly the server still waiting
		// for GitHub to report the job, before anything was granted.
		if reason == "cold" || reason == "capacity" {
			_ = recordCheckout(statePath, workspace, false)
		}
		return "unavailable (" + reason + ")"
	}
	base := filepath.Join(root, response.Directory)
	if proof, err := os.ReadFile(filepath.Join(base, ".tuist-volume")); err != nil || string(proof) != response.ID {
		return "unavailable (not mounted)"
	}
	if info, err := os.Lstat(filepath.Join(base, "checkout")); err != nil || !info.IsDir() {
		return "unavailable (no working tree)"
	}
	if err := os.MkdirAll(workspace, 0755); err != nil {
		return "unavailable (workspace)"
	}
	if err := mount(filepath.Join(work, ".tuist-cache-mount.sock"), response.Directory+"/checkout", relative, workspace); err != nil {
		fmt.Fprintf(os.Stderr, "Tuist cached checkout mount failed: %v\n", err)
		return "unavailable (mount)"
	}
	_ = recordCheckout(statePath, workspace, true)
	return "reused"
}

// exportCheckoutLinux hands the host what the job's checkout added, after the
// job. The host verifies all of it and builds the next master from it. A cold
// job streams the whole repository and its LFS objects, so the budget covers a
// few gigabytes; it only delays the pod's teardown, never the job.
func exportCheckoutLinux() string {
	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Minute)
	defer cancel()
	client := newLinuxCheckoutClient(3 * time.Minute)
	return exportCheckoutLinuxAt(ctx, linuxCheckoutStatePath, linuxExportScratch, gitCommand, client.upload)
}

func exportCheckoutLinuxAt(ctx context.Context, statePath, scratch string, git func(context.Context, string, io.Reader, io.Writer, ...string) error, upload func(context.Context, io.Reader) error) string {
	defer os.RemoveAll(scratch)
	status := exportCheckoutAt(ctx, statePath, scratch, git)
	if !strings.HasPrefix(status, "exported") {
		return status
	}
	reader, writer := io.Pipe()
	go func() { writer.CloseWithError(tarDirectory(filepath.Join(scratch, "checkout-export"), writer)) }()
	err := upload(ctx, reader)
	reader.CloseWithError(err)
	if err != nil {
		return "failed (" + err.Error() + ")"
	}
	return status
}

func (c *linuxCheckoutClient) upload(ctx context.Context, body io.Reader) error {
	if c.endpoint == "" {
		return errors.New("cache volumes disabled")
	}
	query := url.Values{"pod_name": {c.pod}, "pod_uid": {c.uid}}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint+"/checkout-export?"+query.Encode(), body)
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/x-tar")
	response, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusAccepted {
		return fmt.Errorf("host returned %d", response.StatusCode)
	}
	return nil
}

// tarDirectory streams the export's regular files, named relative to dir.
func tarDirectory(dir string, w io.Writer) error {
	archive := tar.NewWriter(w)
	err := filepath.WalkDir(dir, func(path string, entry fs.DirEntry, err error) error {
		if err != nil || !entry.Type().IsRegular() {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		name, err := filepath.Rel(dir, path)
		if err != nil {
			return err
		}
		if err := archive.WriteHeader(&tar.Header{Name: filepath.ToSlash(name), Mode: 0644, Size: info.Size(), Typeflag: tar.TypeReg}); err != nil {
			return err
		}
		file, err := os.Open(path)
		if err != nil {
			return err
		}
		defer file.Close()
		_, err = io.Copy(archive, file)
		return err
	})
	if err != nil {
		return err
	}
	return archive.Close()
}
