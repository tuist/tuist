package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"sync"
	"syscall"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// The server's checkout allocation: the volume identity, its HEAD, and what the
// populator needs to build a master from the job's export.
type checkoutGrant struct {
	cachevolumes.Identity
	CloneURL         string `json:"clone_url"`
	DefaultBranch    string `json:"default_branch"`
	Commit           string `json:"commit"`
	DefaultBranchJob bool   `json:"default_branch_job"`
	VolumeKey        string `json:"volume_key"`
}

// A cold or slow checkout never makes a job wait longer than a clone would.
const checkoutAcquireBudget = 15 * time.Second

// An export carries at most half a checkout image, plus the archive's framing.
const checkoutExportLimit = cachevolumes.CheckoutCapacity/2 + 64<<20

// Exports waiting for a build hold at most one maximal export on a host.
const checkoutIncomingLimit = cachevolumes.CheckoutCapacity / 2

type checkoutRequest struct {
	PodName string `json:"pod_name"`
	PodUID  string `json:"pod_uid"`
	UID     int    `json:"uid"`
}

// grants remembers the checkout each pod was granted, so only that pod's export,
// taken once, builds the volume's master.
type checkoutGrants struct {
	mu   sync.Mutex
	jobs map[string]cachevolumes.CheckoutTask
}

func (g *checkoutGrants) remember(podUID string, task cachevolumes.CheckoutTask) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.jobs == nil {
		g.jobs = map[string]cachevolumes.CheckoutTask{}
	}
	g.jobs[podUID] = task
}

func (g *checkoutGrants) take(podUID string) (cachevolumes.CheckoutTask, bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	task, ok := g.jobs[podUID]
	delete(g.jobs, podUID)
	return task, ok
}

// forget drops the grants of pods that are gone.
func (g *checkoutGrants) forget(live map[string]bool) {
	g.mu.Lock()
	defer g.mu.Unlock()
	for uid := range g.jobs {
		if !live[uid] {
			delete(g.jobs, uid)
		}
	}
}

// serveCheckout answers a runner's request for its job's cached checkout. The
// server decides the repository from the executed job; the runner only asks.
// Every answer but a mounted volume leaves the workspace to actions/checkout.
func (a *agent) serveCheckout(w http.ResponseWriter, r *http.Request) {
	var input checkoutRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&input); err != nil {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), checkoutAcquireBudget)
	defer cancel()
	if !a.runnerPod(ctx, r, input.PodName, input.PodUID) {
		http.Error(w, "unavailable", http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	// Checkouts have their own slots: a job cannot flood the agent, and a checkout
	// waiting on GitHub's execution binding never crowds out a volume.
	if a.checkoutRequests != nil {
		select {
		case a.checkoutRequests <- struct{}{}:
			defer func() { <-a.checkoutRequests }()
		default:
			_ = json.NewEncoder(w).Encode(checkoutUnavailable("busy"))
			return
		}
	}
	done := a.observe.Start("checkout_acquire", "none")
	response, err := a.checkout(ctx, input)
	done(err)
	_ = json.NewEncoder(w).Encode(response)
}

func checkoutUnavailable(reason string) map[string]any {
	return map[string]any{"error": "unavailable", "reason": reason}
}

func (a *agent) checkout(ctx context.Context, input checkoutRequest) (map[string]any, error) {
	// Without working git the host builds nothing, so the runner should not export.
	if !a.checkouts.Ready() {
		return checkoutUnavailable("denied"), errors.New("cached checkouts unavailable on this host")
	}
	body, _ := json.Marshal(map[string]any{"pod_name": input.PodName, "pod_uid": input.PodUID, "node_name": a.node, "architecture": "amd64", "uid": input.UID})
	var grant checkoutGrant
	err := a.allocate(ctx, strings.TrimSuffix(a.authorizeURL, "/authorize")+"/checkout", body, &grant)
	switch {
	case errors.Is(err, cachevolumes.ErrExecutionPending) || errors.Is(err, context.DeadlineExceeded):
		return checkoutUnavailable("timeout"), err
	case err != nil:
		return checkoutUnavailable("denied"), err
	}
	task := cachevolumes.CheckoutTask{
		Scope: grant.Scope, Generation: grant.Generation, CloneURL: grant.CloneURL, DefaultBranch: grant.DefaultBranch,
		Commit: grant.Commit, DefaultBranchJob: grant.DefaultBranchJob, Use: grant.ID, VolumeKey: grant.VolumeKey, UID: grant.UID,
		BaseGeneration: grant.BaseGeneration, ImageDigest: grant.ImageDigest, ContentDigest: grant.ContentDigest,
	}
	// The job's branch is a clone of this host's master; the HEAD only restores it.
	identity := grant.Identity
	identity.Kind, identity.CanPublish = cachevolumes.KindCheckout, false
	identity.ParentID, identity.BaseGeneration, identity.ImageDigest, identity.ContentDigest = "", 0, "", ""
	a.grants.remember(input.PodUID, task)
	a.checkouts.Track(task)
	if a.checkouts.Master(grant.Scope, grant.Generation) == "" {
		if task.BaseGeneration > 0 {
			a.checkouts.Enqueue(task)
		}
		// No branch can exist, so nothing is admitted or journaled: the use ends now.
		a.endUse(grant.ID)
		return checkoutUnavailable("cold"), nil
	}
	warm, err := a.store.Acquire(ctx, identity, input.PodName, input.PodUID)
	switch {
	case errors.Is(err, context.DeadlineExceeded):
		return checkoutUnavailable("timeout"), err
	case errors.Is(err, cachevolumes.ErrCapacity):
		return checkoutUnavailable("capacity"), err
	case err != nil:
		return checkoutUnavailable("error"), err
	}
	return map[string]any{"id": grant.ID, "directory": grant.Scope, "warm": warm}, nil
}

// endUse reports a use that never got a branch as deleted, as reconcile does for
// a branch it removed.
func (a *agent) endUse(id string) {
	_, _ = a.report(cachevolumes.Slot{Identity: cachevolumes.Identity{ID: id}, State: "deleted"}, true)
}

// serveCheckoutExport takes what a finished job's checkout added, streamed by
// the runner after its job, and queues a build from it. Everything in it is
// untrusted: it is unpacked into the export's bounded layout and verified again
// when the populator builds from it.
func (a *agent) serveCheckoutExport(w http.ResponseWriter, r *http.Request) {
	name, uid := r.URL.Query().Get("pod_name"), r.URL.Query().Get("pod_uid")
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	allowed := a.runnerPod(ctx, r, name, uid)
	cancel()
	if !allowed {
		http.Error(w, "unavailable", http.StatusForbidden)
		return
	}
	// Only the calling pod's own export waits for a slot; a busy host keeps its grant.
	select {
	case a.exports <- struct{}{}:
		defer func() { <-a.exports }()
	default:
		http.Error(w, "busy", http.StatusServiceUnavailable)
		return
	}
	task, granted := a.grants.take(uid)
	if !granted || !a.checkouts.Ready() {
		http.Error(w, "no checkout granted", http.StatusConflict)
		return
	}
	_ = http.NewResponseController(w).SetReadDeadline(time.Now().Add(5 * time.Minute))
	done := a.observe.Start("checkout_export", "local")
	dst := a.checkouts.Incoming(uid)
	var admit func(int64) (func(), error)
	if a.space != nil {
		admit = a.space.intake(dst)
	}
	err := cachevolumes.ReceiveCheckoutExport(http.MaxBytesReader(w, r.Body, checkoutExportLimit), dst, admit)
	done(err)
	if errors.Is(err, cachevolumes.ErrCapacity) {
		http.Error(w, "no room", http.StatusInsufficientStorage)
		return
	}
	if err != nil {
		http.Error(w, "invalid export", http.StatusBadRequest)
		return
	}
	task.Export = dst
	if !a.checkouts.Enqueue(task) {
		http.Error(w, "not queued", http.StatusServiceUnavailable)
		return
	}
	w.WriteHeader(http.StatusAccepted)
}

// checkoutSpace keeps master builds, received exports and job admission within
// the cache filesystem's reserve together: a build's room and an export entry
// being written are held back from what jobs see as free, and jobs that need
// room evict idle checkout masters after custom-volume masters, before they
// are refused.
type checkoutSpace struct {
	mu       sync.Mutex
	root     string
	reserve  uint64
	reserved uint64
	// incoming is what each received export holds on disk until it is consumed.
	incoming  map[string]uint64
	checkouts *cachevolumes.Checkouts
	freeBytes func(string) (uint64, error)
}

func (s *checkoutSpace) rawFree() (uint64, error) {
	if s.freeBytes != nil {
		return s.freeBytes(s.root)
	}
	return cachevolumes.FreeBytes(s.root)
}

// free is what job admission sees: free space less what builds hold.
func (s *checkoutSpace) free(context.Context, string) (uint64, error) {
	free, err := s.rawFree()
	if err != nil {
		return 0, err
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	if free < s.reserved {
		return 0, nil
	}
	return free - s.reserved, nil
}

// room holds disk for a master build above the job reserve, evicting other
// checkout masters only when that can make the room.
func (s *checkoutSpace) room(_ context.Context, bytes uint64) (func(), error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	need := s.reserve + s.reserved + bytes
	free, err := s.rawFree()
	if err != nil {
		return nil, err
	}
	if free < need && free+s.checkouts.Evictable(allocatedBytes) >= need {
		s.checkouts.Evict(func() bool {
			free, err = s.rawFree()
			return err == nil && free >= need
		})
		if free, err = s.rawFree(); err != nil {
			return nil, err
		}
	}
	if free < need {
		return nil, cachevolumes.ErrCapacity
	}
	s.reserved += bytes
	return func() {
		s.mu.Lock()
		defer s.mu.Unlock()
		s.reserved -= bytes
	}, nil
}

// reclaim evicts idle checkout masters for a job's volume, after custom-volume
// masters. They are rebuilt from the next jobs' exports, so they go before a job
// loses its volume.
func (s *checkoutSpace) reclaim(ctx context.Context, minimum uint64) error {
	s.checkouts.Evict(func() bool {
		free, err := s.free(ctx, s.root)
		return err == nil && free >= minimum
	})
	return nil
}

func allocatedBytes(path string) (uint64, error) {
	var stat syscall.Stat_t
	if err := syscall.Stat(path, &stat); err != nil {
		return 0, err
	}
	return uint64(stat.Blocks) * 512, nil
}

// intake admits the entries of an export being received at path: each must fit
// above the job reserve and within what exports may hold on the host together.
func (s *checkoutSpace) intake(path string) func(int64) (func(), error) {
	return func(size int64) (func(), error) {
		bytes := uint64(size)
		s.mu.Lock()
		defer s.mu.Unlock()
		held := s.heldLocked()
		// Builds waiting for room hold their exports for up to an hour; a newer
		// export takes their place rather than wait behind them.
		if held+bytes > checkoutIncomingLimit && s.checkouts.DiscardWaiting() > 0 {
			held = s.heldLocked()
		}
		if held+bytes > checkoutIncomingLimit {
			return nil, cachevolumes.ErrCapacity
		}
		free, err := s.rawFree()
		if err != nil {
			return nil, err
		}
		if free < s.reserve+s.reserved+bytes {
			return nil, cachevolumes.ErrCapacity
		}
		s.reserved += bytes
		s.incoming[path] += bytes
		return func() {
			s.mu.Lock()
			defer s.mu.Unlock()
			s.reserved -= bytes
		}, nil
	}
}

func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

// The populator runs the git-lfs the agent image pins, first on its PATH.
const checkoutPath = "/usr/local/bin:/usr/bin:/bin"

const gitLFSVersion = "git-lfs/3.8.0 "

func gitLFSCommand(ctx context.Context) ([]byte, error) {
	return exec.CommandContext(ctx, "/usr/local/bin/git-lfs", "version").Output()
}

// pinnedGitLFS refuses to build checkouts with any git-lfs but the pinned
// release: it runs as root on trees from customer repositories.
func pinnedGitLFS(version func(context.Context) ([]byte, error)) func(context.Context) error {
	return func(ctx context.Context) error {
		out, err := version(ctx)
		if err != nil {
			return fmt.Errorf("pinned git-lfs unavailable: %w", err)
		}
		if !strings.HasPrefix(string(out), gitLFSVersion) {
			return fmt.Errorf("git-lfs is %q, not the pinned %s", strings.TrimSpace(string(out)), strings.TrimSpace(gitLFSVersion))
		}
		return nil
	}
}

// heldLocked is what received exports still hold on disk, forgetting those
// whose directory is gone.
func (s *checkoutSpace) heldLocked() uint64 {
	if s.incoming == nil {
		s.incoming = map[string]uint64{}
	}
	var held uint64
	for export, size := range s.incoming {
		if !exists(export) && !exists(export+".part") {
			delete(s.incoming, export)
			continue
		}
		held += size
	}
	return held
}
