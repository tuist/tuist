package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"strings"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// A Docker data root shares the checkout's window at job start, so a cold or
// slow one never makes a job wait longer than its pulls would.
const dockerAcquireBudget = 15 * time.Second

// dockerUID is the identity's UID: the data root belongs to the root dockerd
// in the job's sidecar, whatever user the job's steps run as.
const dockerUID = 0

type dockerRequest struct {
	PodName string `json:"pod_name"`
	PodUID  string `json:"pod_uid"`
}

func dockerUnavailable(reason string) map[string]any {
	return map[string]any{"error": "unavailable", "reason": reason}
}

// serveDocker answers a runner's request for its job's Docker data root. The
// server decides the repository from the executed job; the runner only asks.
// Every answer but a branch leaves dockerd on the job's ephemeral data root.
func (a *agent) serveDocker(w http.ResponseWriter, r *http.Request) {
	asked := time.Now()
	var input dockerRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&input); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithDeadline(r.Context(), asked.Add(dockerAcquireBudget))
	defer cancel()
	if !a.runnerPod(ctx, r, input.PodName, input.PodUID) {
		http.Error(w, "unavailable", http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	if a.dockerRequests != nil {
		select {
		case a.dockerRequests <- struct{}{}:
			defer func() { <-a.dockerRequests }()
		default:
			_ = json.NewEncoder(w).Encode(dockerUnavailable("busy"))
			return
		}
	}
	done := a.observe.With(cachevolumes.Subject{Pod: input.PodName, Kind: cachevolumes.KindDocker}).Start("docker_acquire", "none")
	response, err := a.docker(ctx, input, asked)
	done(err)
	_ = json.NewEncoder(w).Encode(response)
}

func (a *agent) docker(ctx context.Context, input dockerRequest, asked time.Time) (map[string]any, error) {
	body, _ := json.Marshal(map[string]any{"pod_name": input.PodName, "pod_uid": input.PodUID, "node_name": a.node, "architecture": "amd64", "uid": dockerUID, "max_volume_bytes": cachevolumes.DockerVolumeBytes})
	var identity cachevolumes.Identity
	err := a.allocate(ctx, a.serverURL("/docker"), input.PodUID, asked, body, &identity)
	switch {
	case errors.Is(err, errNotFound):
		// No job of the repository used Docker yet; the runner reports one that does.
		return dockerUnavailable("unseen"), nil
	case errors.Is(err, cachevolumes.ErrExecutionPending) || errors.Is(err, context.DeadlineExceeded):
		return dockerUnavailable("timeout"), err
	case errors.Is(err, cachevolumes.ErrCapacity):
		return dockerUnavailable("capacity"), err
	case err != nil:
		return dockerUnavailable("denied"), err
	}
	identity.Kind = cachevolumes.KindDocker
	warm, err := a.store.Acquire(ctx, identity, input.PodName, input.PodUID)
	// A job that started empty or timed out fetches the saved version in the
	// background for the next job on this host.
	if err == nil || errors.Is(err, context.DeadlineExceeded) {
		a.prefetch.start(identity)
	}
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return dockerUnavailable("timeout"), err
	case errors.Is(err, cachevolumes.ErrCapacity):
		return dockerUnavailable("capacity"), err
	case err != nil:
		return dockerUnavailable("error"), err
	}
	return map[string]any{"id": identity.ID, "directory": identity.Scope, "warm": warm}, nil
}

// serveDockerSeen takes a runner's report, after its job, that a job without a
// Docker data root used Docker, so the repository's next jobs get one.
func (a *agent) serveDockerSeen(w http.ResponseWriter, r *http.Request) {
	var input dockerRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&input); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 15*time.Second)
	defer cancel()
	if !a.runnerPod(ctx, r, input.PodName, input.PodUID) {
		http.Error(w, "unavailable", http.StatusForbidden)
		return
	}
	body, _ := json.Marshal(map[string]any{"pod_name": input.PodName, "pod_uid": input.PodUID, "node_name": a.node, "architecture": "amd64", "uid": dockerUID})
	var ignored struct{}
	status, err := a.allocateOnce(ctx, a.serverURL("/docker-seen"), body, &ignored)
	if err != nil || status != http.StatusNoContent {
		http.Error(w, "unavailable", http.StatusForbidden)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (a *agent) serverURL(path string) string {
	return strings.TrimSuffix(a.authorizeURL, "/authorize") + path
}

// dockerInventory is what a finished Docker data root kept, as its guest
// reported it, for the server to show. Without a readable report there is none.
func (a *agent) dockerInventory(slot cachevolumes.Slot) map[string]any {
	report, err := cachevolumes.ReadDockerReport(filepath.Join(a.root, "pods", slot.PodUID, slot.Scope))
	if err != nil {
		return nil
	}
	images := report.Images
	if images == nil {
		images = []cachevolumes.DockerImage{}
	}
	return map[string]any{"images": images, "build_cache_bytes": report.BuildCacheBytes, "reset": report.Reset}
}
