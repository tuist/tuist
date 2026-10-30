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

// dockerMergeBudget bounds offering a finished job the saved head, which may
// download it. It runs after the job, so it delays only the pod's end.
const dockerMergeBudget = 5 * time.Minute

// serveDockerMerge offers a finished job's guest the lineage's saved head when
// another job saved one since this job's data root was mounted, so the guest
// merges its images with it and the host publishes the union instead of
// withholding a superseded data root. Any other answer leaves the guest to
// tear down as before.
func (a *agent) serveDockerMerge(w http.ResponseWriter, r *http.Request) {
	var input dockerRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&input); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), dockerMergeBudget)
	defer cancel()
	if !a.runnerPod(ctx, r, input.PodName, input.PodUID) {
		http.Error(w, "unavailable", http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	none := map[string]any{"merge": false}
	slot, ok := a.dockerSlot(input.PodUID)
	if !ok || a.dockerHeads == nil || a.exposeDockerHead == nil {
		_ = json.NewEncoder(w).Encode(none)
		return
	}
	a.awaitDockerPublications(ctx, slot)
	if a.dockerMerges != nil {
		select {
		case a.dockerMerges <- struct{}{}:
			defer func() { <-a.dockerMerges }()
		default:
			_ = json.NewEncoder(w).Encode(none)
			return
		}
	}
	head, err := a.dockerHeads(slot)
	// Allocation pins the server's head, not necessarily the copy on this host.
	// An older local clone must merge even when HEAD has not moved since dispatch.
	mounted := slot.BaseGeneration
	if slot.MountedGeneration > 0 {
		mounted = slot.MountedGeneration
	} else if !slot.Warm {
		mounted = 0
	}
	if err != nil || head.BaseGeneration <= mounted {
		_ = json.NewEncoder(w).Encode(none)
		return
	}
	done := a.observe.For(slot).Start("docker_merge_offer", "none")
	err = a.exposeDockerHead(ctx, slot, filepath.Join(a.root, "pods", slot.PodUID, slot.Scope), head)
	done(err)
	if err != nil {
		_ = json.NewEncoder(w).Encode(none)
		return
	}
	_ = json.NewEncoder(w).Encode(map[string]any{"merge": true, "source": slot.Scope + "/" + cachevolumes.DockerMergeImageName, "generation": head.BaseGeneration})
}

// dockerPublicationWait bounds waiting for another job's data root of the same
// lineage to publish, leaving the rest of the merge budget to clone or download
// the head it saves.
const dockerPublicationWait = 2 * time.Minute

var dockerPublicationPoll = time.Second

// awaitDockerPublications waits while another job of the slot's lineage on this
// host has finished with a changed data root that is not yet published. The
// head only moves once that upload completes; reading it earlier offers no
// merge and this job's data root is then withheld as superseded.
func (a *agent) awaitDockerPublications(ctx context.Context, slot cachevolumes.Slot) {
	if !a.dockerPublicationPending(slot) {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, dockerPublicationWait)
	defer cancel()
	done := a.observe.For(slot).Start("docker_merge_wait", "none")
	for {
		select {
		case <-ctx.Done():
			done(ctx.Err())
			return
		case <-time.After(dockerPublicationPoll):
		}
		if !a.dockerPublicationPending(slot) {
			done(nil)
			return
		}
	}
}

func (a *agent) dockerPublicationPending(slot cachevolumes.Slot) bool {
	slots, err := a.store.Snapshot()
	if err != nil {
		return false
	}
	for _, other := range slots {
		if other.PodUID == slot.PodUID || other.Scope != slot.Scope || other.Kind != cachevolumes.KindDocker || other.State != "active" || !other.CanPublish {
			continue
		}
		report, err := cachevolumes.ReadDockerReport(filepath.Join(a.root, "pods", other.PodUID, other.Scope))
		if err == nil && report.Clean && report.Changed {
			return true
		}
	}
	return false
}

// dockerSlot is the pod's Docker data root while its job may still publish it.
func (a *agent) dockerSlot(podUID string) (cachevolumes.Slot, bool) {
	slots, err := a.store.Snapshot()
	if err != nil {
		return cachevolumes.Slot{}, false
	}
	for _, slot := range slots {
		if slot.PodUID == podUID && slot.Kind == cachevolumes.KindDocker && slot.State == "active" && slot.CanPublish {
			return slot, true
		}
	}
	return cachevolumes.Slot{}, false
}
