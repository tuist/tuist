package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// Sandbox cache images: sandboxd asks for a copy of a cache volume's saved
// master to attach to a Firecracker guest as a private drive. sandboxd's data
// lives on another filesystem, so the agent reflinks the master under its
// lineage lock and streams the clone as a sparse archive
// (cachevolumes.WriteImage); sandboxd writes it into its own directory. The
// copy is one way: nothing a sandbox writes comes back. The grant names the
// saved head the server chose, as a checkout grant names its master, and the
// agent authorizes the caller as it does for checkouts. A node whose prefetch
// still holds an older master of the head's lineage lends that one, as it
// would to a job, and the sandboxCacheGeneration header names the generation
// it lent. sandboxd names its copies by generation and lists the ones it has
// in held, so the agent answers 204 instead of streaming a copy it already has.

const (
	sandboxCacheDir        = ".sandbox-cache"
	sandboxCacheGeneration = "Tuist-Cache-Generation"
)

type sandboxCacheGrant struct {
	ID             string `json:"id"`
	Scope          string `json:"scope"`
	BaseGeneration int64  `json:"base_generation"`
	ImageDigest    string `json:"image_digest"`
	ContentDigest  string `json:"content_digest"`
}

type sandboxCacheRequest struct {
	PodName string            `json:"pod_name"`
	Grant   sandboxCacheGrant `json:"grant"`
	Held    []int64           `json:"held,omitempty"`
}

// serveSandboxCacheImage answers 200 with the master as a sparse archive, 204
// when the caller holds the generation it would lend, 404 {"error":"cold"}
// when this node holds no master of the lineage, or another status with
// {"error": reason}. It never fetches a master for the request.
func (a *agent) serveSandboxCacheImage(w http.ResponseWriter, r *http.Request) {
	var input sandboxCacheRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 8192)).Decode(&input); err != nil {
		sandboxError(w, http.StatusBadRequest, "invalid request")
		return
	}
	authorizing, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	allowed := a.sandboxdPod(authorizing, r, input.PodName)
	cancel()
	if !allowed {
		sandboxError(w, http.StatusForbidden, "forbidden")
		return
	}
	grant := input.Grant
	if !sandboxUse.MatchString(grant.ID) {
		sandboxError(w, http.StatusBadRequest, "invalid grant")
		return
	}
	if a.cloneMaster == nil {
		sandboxError(w, http.StatusServiceUnavailable, "unavailable")
		return
	}
	if a.sandboxSeeds != nil {
		select {
		case a.sandboxSeeds <- struct{}{}:
			defer func() { <-a.sandboxSeeds }()
		default:
			sandboxError(w, http.StatusServiceUnavailable, "busy")
			return
		}
	}
	identity := cachevolumes.Identity{ID: grant.ID, Scope: grant.Scope, BaseGeneration: grant.BaseGeneration, ImageDigest: grant.ImageDigest, ContentDigest: grant.ContentDigest}
	ctx, cancel := context.WithTimeout(r.Context(), sandboxSeedBudget)
	defer cancel()
	done := a.observe.With(cachevolumes.SubjectOf(cachevolumes.Slot{Identity: identity})).Start("sandbox_cache_image", "local")
	streaming, err := a.streamSandboxCacheImage(ctx, w, identity, input.Held)
	done(err)
	switch {
	case err == nil:
	case streaming:
		// Only a complete archive ends with its terminator; cutting the
		// response tells sandboxd the copy failed.
		a.logger().Warn("sandbox cache image interrupted", "use", grant.ID, "error", err)
		panic(http.ErrAbortHandler)
	case errors.Is(err, cachevolumes.ErrNoMaster):
		sandboxError(w, http.StatusNotFound, "cold")
	case errors.Is(err, cachevolumes.ErrInvalidMaster):
		sandboxError(w, http.StatusBadRequest, "invalid grant")
	default:
		a.logger().Warn("sandbox cache image failed", "use", grant.ID, "error", err)
		sandboxError(w, http.StatusServiceUnavailable, "unavailable")
	}
}

// streamSandboxCacheImage clones the master beside the masters, so a later
// eviction cannot pull it from under the stream, and writes the clone. It
// reports whether the response had started.
func (a *agent) streamSandboxCacheImage(ctx context.Context, w http.ResponseWriter, identity cachevolumes.Identity, held []int64) (bool, error) {
	parent := filepath.Join(a.root, sandboxCacheDir)
	if err := os.MkdirAll(parent, 0o700); err != nil {
		return false, err
	}
	dir := filepath.Join(parent, identity.ID)
	// A use copies once; a second request for it while the first runs is refused.
	if err := os.Mkdir(dir, 0o700); err != nil {
		return false, err
	}
	defer os.RemoveAll(dir)
	clone := filepath.Join(dir, "master.img")
	generation, cloned, err := a.cloneMaster(ctx, identity, clone, func(g int64) bool { return slices.Contains(held, g) })
	if err != nil {
		return false, err
	}
	w.Header().Set(sandboxCacheGeneration, strconv.FormatInt(generation, 10))
	if !cloned {
		w.WriteHeader(http.StatusNoContent)
		return false, nil
	}
	image, err := os.Open(clone)
	if err != nil {
		return false, err
	}
	defer image.Close()
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(sandboxSeedBudget))
	w.Header().Set("Content-Type", "application/octet-stream")
	w.WriteHeader(http.StatusOK)
	return true, cachevolumes.WriteImage(w, image)
}

// abandonSandboxCacheImages removes the clones a previous agent left mid-copy.
func abandonSandboxCacheImages(root string) {
	_ = os.RemoveAll(filepath.Join(root, sandboxCacheDir))
}
