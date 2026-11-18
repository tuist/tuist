package main

import (
	"archive/tar"
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"syscall"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// Sandbox sessions (sandboxd's Firecracker guests on this node) use the same
// checkout masters as CI. sandboxd relays the server's grant from its
// start_worker: the agent streams a read-only clone of the master as a tar
// (seed) and takes the guest's export back under the CI export's admission
// (export). The guest itself never reaches the agent; sandboxd fences this
// port from its guests.

const (
	sandboxdLabel   = "tuist.dev/sandboxd"
	sandboxSeedsDir = ".sandbox-seeds"
	// A seed clones, attaches and streams one master; the stream gets its own
	// write deadline in place of the server's.
	sandboxSeedBudget   = 10 * time.Minute
	sandboxExportBudget = 5 * time.Minute
)

// A use names the clone and the export on disk, so it must be one path component.
var sandboxUse = regexp.MustCompile(`^[a-f0-9-]{36}$`)

// sandboxCheckoutRequest is the JSON sandboxd sends first: its own Pod, which
// must be the caller, and the grant the server gave the session. On export the
// export's tar stream follows it after a newline.
type sandboxCheckoutRequest struct {
	PodName string        `json:"pod_name"`
	Grant   checkoutGrant `json:"grant"`
}

func sandboxAnswer(w http.ResponseWriter, status int, body map[string]any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}

func sandboxError(w http.ResponseWriter, status int, reason string) {
	sandboxAnswer(w, status, map[string]any{"error": reason})
}

// sandboxdPod reports whether the request comes from the live sandboxd Pod it
// names on this node: the caller's address must be that Pod's. sandboxd is not
// on the host network, and it drops its guests' traffic to this port.
func (a *agent) sandboxdPod(ctx context.Context, r *http.Request, name string) bool {
	if a.sandboxNamespace == "" || name == "" {
		return false
	}
	pod, err := a.kube.CoreV1().Pods(a.sandboxNamespace).Get(ctx, name, metav1.GetOptions{})
	ip, _, _ := net.SplitHostPort(r.RemoteAddr)
	return err == nil && pod.Spec.NodeName == a.node && pod.Status.PodIP == ip && ip != "" && pod.Labels[sandboxdLabel] == "true" && pod.DeletionTimestamp == nil && pod.Status.Phase == corev1.PodRunning
}

// authorizeSandbox checks the caller and the grant's use, answering the
// refusal itself.
func (a *agent) authorizeSandbox(w http.ResponseWriter, r *http.Request, input sandboxCheckoutRequest) bool {
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	if !a.sandboxdPod(ctx, r, input.PodName) {
		sandboxError(w, http.StatusForbidden, "forbidden")
		return false
	}
	if !sandboxUse.MatchString(input.Grant.ID) {
		sandboxError(w, http.StatusBadRequest, "invalid grant")
		return false
	}
	return true
}

// serveSandboxSeed answers 200 with a tar of the master's repository directory,
// or 404 {"error":"cold"} when this node holds no master, or another status
// with {"error": reason}. The use ends with the request either way: what the
// session got is a copy, not a branch the agent keeps.
func (a *agent) serveSandboxSeed(w http.ResponseWriter, r *http.Request) {
	var input sandboxCheckoutRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&input); err != nil {
		sandboxError(w, http.StatusBadRequest, "invalid request")
		return
	}
	if !a.authorizeSandbox(w, r, input) {
		return
	}
	grant, warm := input.Grant, false
	defer func() { a.endUse(grant.ID, warm) }()
	if a.sandboxSeeds != nil {
		select {
		case a.sandboxSeeds <- struct{}{}:
			defer func() { <-a.sandboxSeeds }()
		default:
			sandboxError(w, http.StatusServiceUnavailable, "busy")
			return
		}
	}
	if !a.checkouts.Ready() {
		sandboxError(w, http.StatusServiceUnavailable, "unavailable")
		return
	}
	task := grant.task()
	a.checkouts.Track(task)
	if a.checkouts.Master(grant.Scope, grant.Generation) == "" {
		if task.BaseGeneration > 0 {
			a.checkouts.Enqueue(task)
		}
		sandboxError(w, http.StatusNotFound, "cold")
		return
	}
	done := a.observe.With(task.Subject()).Start("sandbox_checkout_seed", "local")
	streaming, err := a.seedSandbox(r.Context(), w, grant)
	done(err)
	switch {
	case err == nil:
		warm = true
	case streaming:
		// Only a complete tree ends with the end-of-archive blocks; cutting the
		// response tells sandboxd the stream failed.
		a.logger().Warn("sandbox checkout seed interrupted", "use", grant.ID, "error", err)
		panic(http.ErrAbortHandler)
	default:
		a.logger().Warn("sandbox checkout seed failed", "use", grant.ID, "error", err)
		sandboxError(w, http.StatusServiceUnavailable, "unavailable")
	}
}

// seedSandbox clones the master under its scope lock, attaches the clone
// read-only and streams its repository, then detaches and deletes the clone.
// It reports whether the response had started.
func (a *agent) seedSandbox(ctx context.Context, w http.ResponseWriter, grant checkoutGrant) (bool, error) {
	ctx, cancel := context.WithTimeout(ctx, sandboxSeedBudget)
	defer cancel()
	parent := filepath.Join(a.checkouts.Root, sandboxSeedsDir)
	if err := os.MkdirAll(parent, 0o700); err != nil {
		return false, err
	}
	dir := filepath.Join(parent, grant.ID)
	// A use seeds once; a second request for it while the first runs is refused.
	if err := os.Mkdir(dir, 0o700); err != nil {
		return false, err
	}
	defer os.RemoveAll(dir)
	image, mount := filepath.Join(dir, "clone"+filepath.Ext(a.checkouts.Images.MasterName())), filepath.Join(dir, "mnt")
	if err := os.Mkdir(mount, 0o700); err != nil {
		return false, err
	}
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: grant.ID, Scope: grant.Scope, Kind: cachevolumes.KindCheckout, Generation: grant.Generation}}
	if err := a.checkouts.Seed(ctx, slot, image); err != nil {
		return false, err
	}
	cleanup := func() {
		ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), time.Minute)
		defer cancel()
		if err := a.checkouts.Images.Detach(ctx, image, mount); err != nil {
			a.checkouts.Images.Abandon(ctx, image, mount)
		}
	}
	if err := a.checkouts.Images.Attach(ctx, image, mount, true); err != nil {
		cleanup()
		return false, err
	}
	defer cleanup()
	repo := a.checkouts.Images.Repository(mount)
	if info, err := os.Lstat(repo); err != nil || !info.IsDir() {
		return false, errors.Join(errors.New("checkout clone holds no repository"), err)
	}
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(sandboxSeedBudget))
	w.Header().Set("Content-Type", "application/x-tar")
	w.WriteHeader(http.StatusOK)
	return true, writeRepository(w, repo)
}

// writeRepository writes repo as a tar: paths relative to it, directories,
// regular files and symlinks with their permission bits, no owners. It never
// follows a link the checkout contains.
func writeRepository(w io.Writer, repo string) error {
	archive := tar.NewWriter(w)
	err := filepath.WalkDir(repo, func(path string, entry fs.DirEntry, err error) error {
		if err != nil || path == repo {
			return err
		}
		rel, err := filepath.Rel(repo, path)
		if err != nil {
			return err
		}
		info, err := entry.Info()
		if err != nil {
			return err
		}
		header := &tar.Header{Name: filepath.ToSlash(rel), Mode: int64(info.Mode().Perm()), ModTime: info.ModTime()}
		switch {
		case info.IsDir():
			header.Typeflag, header.Name = tar.TypeDir, header.Name+"/"
		case info.Mode().IsRegular():
			header.Typeflag, header.Size = tar.TypeReg, info.Size()
		case info.Mode()&fs.ModeSymlink != 0:
			if header.Linkname, err = os.Readlink(path); err != nil {
				return err
			}
			header.Typeflag = tar.TypeSymlink
		default:
			// Sockets, pipes and devices are no part of a checkout.
			return nil
		}
		if err := archive.WriteHeader(header); err != nil {
			return err
		}
		if header.Typeflag != tar.TypeReg {
			return nil
		}
		file, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
		if err != nil {
			return err
		}
		defer file.Close()
		_, err = io.CopyN(archive, file, header.Size)
		return err
	})
	if err != nil {
		return err
	}
	return archive.Close()
}

// serveSandboxExport takes a session's export, streamed by sandboxd after the
// request line, and queues a build from it as the CI export path does. It
// answers 202 {"ok":true} once the export is queued, or {"error": reason}.
func (a *agent) serveSandboxExport(w http.ResponseWriter, r *http.Request) {
	body := bufio.NewReaderSize(http.MaxBytesReader(w, r.Body, checkoutExportLimit+8192), 8192)
	line, err := body.ReadSlice('\n')
	var input sandboxCheckoutRequest
	if err != nil || json.Unmarshal(line, &input) != nil {
		sandboxError(w, http.StatusBadRequest, "invalid request")
		return
	}
	if !a.authorizeSandbox(w, r, input) {
		return
	}
	select {
	case a.exports <- struct{}{}:
		defer func() { <-a.exports }()
	default:
		sandboxError(w, http.StatusServiceUnavailable, "busy")
		return
	}
	if !a.checkouts.Ready() {
		sandboxError(w, http.StatusServiceUnavailable, "unavailable")
		return
	}
	// One export per use at a time: it is received into a directory the use names.
	if _, running := a.sandboxExports.LoadOrStore(input.Grant.ID, true); running {
		sandboxError(w, http.StatusConflict, "export in progress")
		return
	}
	defer a.sandboxExports.Delete(input.Grant.ID)
	task := input.Grant.task()
	a.checkouts.Track(task)
	_ = http.NewResponseController(w).SetReadDeadline(time.Now().Add(sandboxExportBudget))
	done := a.observe.With(task.Subject()).Start("checkout_export", "local")
	dst := a.checkouts.Incoming("sandbox-" + input.Grant.ID)
	var admit func(int64) (func(), error)
	if a.space != nil {
		admit = a.space.intake(dst)
	}
	err = cachevolumes.ReceiveCheckoutExport(body, dst, admit)
	done(err)
	if errors.Is(err, cachevolumes.ErrCapacity) {
		sandboxError(w, http.StatusInsufficientStorage, "no room")
		return
	}
	if err != nil {
		sandboxError(w, http.StatusBadRequest, "invalid export")
		return
	}
	task.Export = dst
	if !a.checkouts.Enqueue(task) {
		sandboxError(w, http.StatusServiceUnavailable, "not queued")
		return
	}
	sandboxAnswer(w, http.StatusAccepted, map[string]any{"ok": true})
}

// abandonSandboxSeeds removes the clones a previous agent left mid-seed.
func abandonSandboxSeeds(checkouts *cachevolumes.Checkouts) {
	dirs, _ := filepath.Glob(filepath.Join(checkouts.Root, sandboxSeedsDir, "*"))
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	for _, dir := range dirs {
		checkouts.Images.Abandon(ctx, filepath.Join(dir, "clone"+filepath.Ext(checkouts.Images.MasterName())), filepath.Join(dir, "mnt"))
		_ = os.RemoveAll(dir)
	}
}

func (a *agent) logger() *slog.Logger {
	if a.log != nil {
		return a.log
	}
	return slog.Default()
}
