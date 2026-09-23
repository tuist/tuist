// Package simulation compares scheduling policies using a deterministic,
// discrete-event model. It never connects to a database or a cluster.
package simulation

import (
	"container/heap"
	"crypto/sha256"
	"fmt"
	"math"
	"math/rand"
	"sort"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/runners-controller/internal/simulation/assignment"
)

type Policy string

const (
	PullCurrent Policy = "pull_current"
	PushCurrent Policy = "push_current"
	PullFair    Policy = "pull_shadow_policy"
	PushFair    Policy = "push_shadow_policy"
)

var Policies = []Policy{PullCurrent, PushCurrent, PullFair, PushFair}

type Job struct {
	ID, Account                 int64
	Pool, Platform, Repository  string
	Resources                   assignment.Resources
	ArrivalMS, RuntimeMS        int64
	ColdPenaltyMS, ReleaseLagMS int64
}

type Master struct {
	Account    int64
	Repository string
}

// Slot is fixed capacity for a pool on a host. Each job gets a new Pod
// incarnation after RecycleMS; this does not reuse a production runner VM.
// Host provisioning/autoscaling is deliberately outside this model.
type Slot struct {
	Name, Node, Pool, Platform string
	Resources                  assignment.Resources
	AvailableMS, RecycleMS     int64
	AccountMasters             []int64
	RepositoryMasters          []Master
}

type Scenario struct {
	Name, Description string
	Jobs              []Job
	Slots             []Slot
	Accounts          []assignment.Account
}

type Config struct {
	Seed        int64
	PollMS      int64
	PushDelayMS int64
	HorizonMS   int64
}

func DefaultConfig(seed int64) Config {
	return Config{Seed: seed, PollMS: 2000, PushDelayMS: 250, HorizonMS: 86_400_000}
}

type JobResult struct {
	JobID, Account                                    int64
	Platform, Pool, Node, Slot                        string
	ArrivalMS, AssignedMS, FinishedMS                 int64
	CacheHit                                          bool
	QuotaBlockedMS, CapacityBlockedMS, ReadyWaitingMS int64
}

type Metrics struct {
	Jobs                         int     `json:"jobs"`
	QueueMeanSeconds             float64 `json:"queue_mean_s"`
	QueueP95Seconds              float64 `json:"queue_p95_s"`
	QueueMaxSeconds              float64 `json:"queue_max_s"`
	CompletionMeanSeconds        float64 `json:"completion_mean_s"`
	MakespanSeconds              float64 `json:"makespan_s"`
	QuotaBlockedMeanSeconds      float64 `json:"quota_blocked_mean_s"`
	CapacityBlockedMeanSeconds   float64 `json:"capacity_blocked_mean_s"`
	ReadyWaitingMeanSeconds      float64 `json:"ready_waiting_mean_s"`
	CacheEligibleJobs, CacheHits int
}

type Result struct {
	ShadowPolicyVersion int               `json:"shadow_policy_version"`
	Scenario            string            `json:"scenario"`
	Policy              Policy            `json:"policy"`
	Seed                int64             `json:"seed"`
	Metrics             Metrics           `json:"metrics"`
	ByAccount           map[int64]Metrics `json:"by_account"`
	Jobs                []JobResult       `json:"jobs"`
}

type accountKey struct {
	id       int64
	platform string
}

type jobState struct {
	Job
	arrived, assigned, finished, released bool
	pod                                   string
	result                                JobResult
}

type slotState struct {
	Slot
	idle        bool
	incarnation int
	phase       int64
}

func (s *slotState) pod() string { return fmt.Sprintf("%s-%d", s.Name, s.incarnation) }

type event struct {
	at    int64
	kind  int
	index int
	slot  int
	seq   int
}

const (
	arrive = iota
	release
	finish
	ready
	poll
	dispatch
)

type events []event

func (e events) Len() int { return len(e) }
func (e events) Less(i, j int) bool {
	if e[i].at != e[j].at {
		return e[i].at < e[j].at
	}
	if e[i].kind != e[j].kind {
		return e[i].kind < e[j].kind
	}
	return e[i].seq < e[j].seq
}
func (e events) Swap(i, j int) { e[i], e[j] = e[j], e[i] }
func (e *events) Push(x any)   { *e = append(*e, x.(event)) }
func (e *events) Pop() any     { n := len(*e) - 1; x := (*e)[n]; *e = (*e)[:n]; return x }

type engine struct {
	scenario          Scenario
	policy            Policy
	config            Config
	now               int64
	seq, completed    int
	jobs              []jobState
	slots             []slotState
	limits, used      map[accountKey]assignment.Resources
	accountMasters    map[string]map[int64]bool
	repositoryMasters map[string]map[Master]bool
	events            events
	dispatchPending   bool
}

// Run has no duration oracle in either scheduling adapter. Runtime and cold
// materialization cost are used only after a decision, to advance the world.
func Run(s Scenario, policy Policy, cfg Config) (Result, error) {
	if cfg.PollMS <= 0 || cfg.PushDelayMS <= 0 || cfg.HorizonMS <= 0 {
		return Result{}, fmt.Errorf("poll, push delay and horizon must be positive")
	}
	if policy != PullCurrent && policy != PushCurrent && policy != PullFair && policy != PushFair {
		return Result{}, fmt.Errorf("unknown policy %q", policy)
	}
	e := &engine{scenario: s, policy: policy, config: cfg, limits: map[accountKey]assignment.Resources{}, used: map[accountKey]assignment.Resources{}, accountMasters: map[string]map[int64]bool{}, repositoryMasters: map[string]map[Master]bool{}}
	for _, a := range s.Accounts {
		key := accountKey{a.AccountID, a.Platform}
		if _, exists := e.limits[key]; exists || a.Limit.VCPUs <= 0 || a.Limit.MemoryGB <= 0 {
			return Result{}, fmt.Errorf("invalid account limit")
		}
		e.limits[key] = a.Limit
	}
	ids := map[int64]bool{}
	for i, j := range s.Jobs {
		if ids[j.ID] || j.ID <= 0 || j.ArrivalMS < 0 || j.RuntimeMS <= 0 || j.ColdPenaltyMS < 0 || j.ReleaseLagMS < 0 || j.Resources.VCPUs <= 0 || j.Resources.MemoryGB <= 0 {
			return Result{}, fmt.Errorf("invalid job %d", j.ID)
		}
		ids[j.ID] = true
		e.jobs = append(e.jobs, jobState{Job: j, result: JobResult{JobID: j.ID, Account: j.Account, Platform: j.Platform, Pool: j.Pool, ArrivalMS: j.ArrivalMS}})
		e.add(j.ArrivalMS, arrive, i, 0)
	}
	rng := rand.New(rand.NewSource(cfg.Seed))
	names := map[string]bool{}
	for i, r := range s.Slots {
		if names[r.Name] || r.Name == "" || r.Node == "" || r.AvailableMS < 0 || r.RecycleMS < 0 {
			return Result{}, fmt.Errorf("invalid slot")
		}
		names[r.Name] = true
		e.slots = append(e.slots, slotState{Slot: r, phase: rng.Int63n(cfg.PollMS)})
		if e.accountMasters[r.Node] == nil {
			e.accountMasters[r.Node] = map[int64]bool{}
			e.repositoryMasters[r.Node] = map[Master]bool{}
		}
		for _, a := range r.AccountMasters {
			e.accountMasters[r.Node][a] = true
		}
		for _, a := range r.RepositoryMasters {
			e.repositoryMasters[r.Node][a] = true
		}
		e.add(r.AvailableMS, ready, 0, i)
	}
	for e.events.Len() > 0 && e.completed < len(e.jobs) {
		v := heap.Pop(&e.events).(event)
		if v.at > cfg.HorizonMS {
			return Result{}, fmt.Errorf("%s/%s exceeded simulation horizon; %d/%d finished", s.Name, policy, e.completed, len(e.jobs))
		}
		e.accountWaiting(v.at - e.now)
		e.now = v.at
		switch v.kind {
		case arrive:
			e.jobs[v.index].arrived = true
			e.requestDispatch()
		case release:
			j := &e.jobs[v.index]
			j.released = true
			key := accountKey{j.Account, j.Platform}
			u := e.used[key]
			u.VCPUs -= j.Resources.VCPUs
			u.MemoryGB -= j.Resources.MemoryGB
			e.used[key] = u
			e.requestDispatch()
		case finish:
			j := &e.jobs[v.index]
			j.finished = true
			e.completed++
			j.result.FinishedMS = e.now
			if j.Platform == "macos" {
				e.repositoryMasters[e.slots[v.slot].Node][Master{j.Account, j.Repository}] = true
			}
			e.add(e.now+j.ReleaseLagMS, release, v.index, v.slot)
			e.add(e.now+e.slots[v.slot].RecycleMS, ready, 0, v.slot)
		case ready:
			r := &e.slots[v.slot]
			r.idle = true
			r.incarnation++
			if e.isPull() {
				e.add(e.now+r.phase, poll, 0, v.slot)
			} else {
				e.requestDispatch()
			}
		case poll:
			if !e.slots[v.slot].idle {
				continue
			}
			if policy == PullCurrent {
				e.pickCurrent(v.slot)
			} else if err := e.pickShadow([]int{v.slot}); err != nil {
				return Result{}, err
			}
			if e.slots[v.slot].idle {
				e.add(e.now+cfg.PollMS, poll, 0, v.slot)
			}
		case dispatch:
			e.dispatchPending = false
			idle := e.idleSlots()
			if policy == PushCurrent {
				for _, i := range idle {
					e.pickCurrent(i)
				}
			} else if err := e.pickShadow(idle); err != nil {
				return Result{}, err
			}
		}
	}
	if e.completed != len(e.jobs) {
		return Result{}, fmt.Errorf("%s/%s deadlocked", s.Name, policy)
	}
	result := Result{ShadowPolicyVersion: assignment.Version, Scenario: s.Name, Policy: policy, Seed: cfg.Seed, ByAccount: map[int64]Metrics{}}
	byAccount := map[int64][]JobResult{}
	for _, j := range e.jobs {
		result.Jobs = append(result.Jobs, j.result)
		byAccount[j.Account] = append(byAccount[j.Account], j.result)
	}
	result.Metrics = measure(result.Jobs)
	for a, j := range byAccount {
		result.ByAccount[a] = measure(j)
	}
	return result, nil
}

func (e *engine) add(at int64, kind, index, slot int) {
	e.seq++
	heap.Push(&e.events, event{at, kind, index, slot, e.seq})
}
func (e *engine) isPull() bool { return e.policy == PullCurrent || e.policy == PullFair }
func (e *engine) requestDispatch() {
	if !e.isPull() && !e.dispatchPending {
		e.dispatchPending = true
		e.add(e.now+e.config.PushDelayMS, dispatch, 0, 0)
	}
}
func (e *engine) fits(j *jobState) bool {
	k := accountKey{j.Account, j.Platform}
	u, l := e.used[k], e.limits[k]
	return j.Resources.VCPUs <= l.VCPUs-u.VCPUs && j.Resources.MemoryGB <= l.MemoryGB-u.MemoryGB
}
func compatible(j *jobState, r *slotState) bool {
	return j.Pool == r.Pool && j.Platform == r.Platform && j.Resources == r.Resources
}
func (e *engine) resident(j *jobState, r *slotState) bool {
	if j.Platform != "macos" {
		return false
	}
	if e.accountMasters[r.Node][j.Account] {
		return true
	}
	volume := cacheVolume(j.Repository)
	for master, resident := range e.repositoryMasters[r.Node] {
		if resident && master.Account == j.Account && (cacheVolume(master.Repository) == volume || master.Repository == "") {
			return true
		}
	}
	return false
}
func (e *engine) idleSlots() []int {
	var idle []int
	for i := range e.slots {
		if e.slots[i].idle {
			idle = append(idle, i)
		}
	}
	// Use the same seeded host priority for both policies. PushCurrent preserves
	// local decisions and removes polling delay; it does not add global matching.
	sort.Slice(idle, func(i, j int) bool {
		a, b := e.slots[idle[i]], e.slots[idle[j]]
		if a.phase != b.phase {
			return a.phase < b.phase
		}
		return a.Name < b.Name
	})
	return idle
}

// Model of Runners.claim_and_serve: up to 16 attempts, excluding an account
// after a capacity rejection. Linux uses FIFO; macOS scores the oldest 20
// with repository OR account residency until the head's whole-second age >30.
// Database races, authentication and provider/JIT failures are not simulated.
func (e *engine) pickCurrent(slot int) {
	r := &e.slots[slot]
	excluded := map[int64]bool{}
	for attempt := 0; attempt < 16; attempt++ {
		var candidates []int
		for i := range e.jobs {
			j := &e.jobs[i]
			if j.arrived && !j.assigned && compatible(j, r) && !excluded[j.Account] {
				candidates = append(candidates, i)
			}
		}
		sort.Slice(candidates, func(a, b int) bool {
			x, y := e.jobs[candidates[a]], e.jobs[candidates[b]]
			if x.ArrivalMS != y.ArrivalMS {
				return x.ArrivalMS < y.ArrivalMS
			}
			return x.ID < y.ID
		})
		if len(candidates) == 0 {
			return
		}
		if len(candidates) > 20 {
			candidates = candidates[:20]
		}
		chosen := candidates[0]
		head := &e.jobs[chosen]
		if r.Platform == "macos" && !e.resident(head, r) && (e.now-head.ArrivalMS)/1000 <= 30 {
			for _, i := range candidates {
				if e.resident(&e.jobs[i], r) {
					chosen = i
					break
				}
			}
		}
		if !e.fits(&e.jobs[chosen]) {
			excluded[e.jobs[chosen].Account] = true
			continue
		}
		e.assign(chosen, slot)
		return
	}
}

var epoch = time.Date(2026, 1, 1, 0, 0, 0, 0, time.UTC)

func simTime(ms int64) time.Time { return epoch.Add(time.Duration(ms) * time.Millisecond) }

func (e *engine) pickShadow(idle []int) error {
	if len(idle) == 0 {
		return nil
	}
	snapshot := assignment.Snapshot{Version: assignment.Version, Complete: true, CapturedAt: simTime(e.now), Accounts: e.scenario.Accounts}
	byJob := map[int64]int{}
	byPod := map[string]int{}
	var runners []assignment.Runner
	for i := range e.jobs {
		j := &e.jobs[i]
		if j.arrived && !j.assigned {
			snapshot.Demand = append(snapshot.Demand, assignment.Demand{JobID: j.ID, AccountID: j.Account, CacheVolume: cacheVolume(j.Repository), Pool: j.Pool, Platform: j.Platform, Resources: j.Resources, EnqueuedAt: simTime(j.ArrivalMS)})
			byJob[j.ID] = i
		}
		if j.assigned && !j.released {
			id := j.ID
			snapshot.Claims = append(snapshot.Claims, assignment.Claim{Pod: j.pod, JobID: &id, AccountID: j.Account, Platform: j.Platform, Resources: j.Resources, ClaimedAt: simTime(j.result.AssignedMS)})
		}
	}
	for _, i := range idle {
		r := &e.slots[i]
		byPod[r.pod()] = i
		runners = append(runners, assignment.Runner{Pod: r.pod(), UID: r.pod(), Node: r.Node, Pool: r.Pool, Platform: r.Platform, Resources: r.Resources, ResidentVolumes: e.residentVolumes(r.Node)})
	}
	plan, err := assignment.Propose(snapshot, runners, simTime(e.now))
	if err != nil {
		return err
	}
	for _, a := range plan.Assignments {
		e.assign(byJob[a.JobID], byPod[a.Pod])
	}
	if len(plan.Assignments) == assignment.MaxAssignments {
		e.requestDispatch()
	}
	return nil
}

// Mirror VolumeHeads.volume_name_for_repository/1 without exposing names to the policy.
func cacheVolume(repository string) string {
	if repository == "" {
		return assignment.AccountCacheVolume
	}
	return fmt.Sprintf("repo-%x", sha256.Sum256([]byte(strings.ToLower(repository))))[:21]
}

func (e *engine) residentVolumes(node string) map[int64]map[string]bool {
	volumes := map[int64]map[string]bool{}
	add := func(account int64, volume string) {
		if volumes[account] == nil {
			volumes[account] = map[string]bool{}
		}
		volumes[account][volume] = true
	}
	for account, resident := range e.accountMasters[node] {
		if resident {
			add(account, assignment.AccountCacheVolume)
		}
	}
	for master, resident := range e.repositoryMasters[node] {
		if resident {
			add(master.Account, cacheVolume(master.Repository))
		}
	}
	return volumes
}

func (e *engine) assign(job, slot int) {
	j, r := &e.jobs[job], &e.slots[slot]
	if j.assigned || !r.idle || !compatible(j, r) || !e.fits(j) {
		panic("invalid simulated admission")
	}
	j.assigned = true
	j.pod = r.pod()
	j.result.AssignedMS = e.now
	j.result.Node = r.Node
	j.result.Slot = r.Name
	j.result.CacheHit = e.resident(j, r)
	r.idle = false
	k := accountKey{j.Account, j.Platform}
	u := e.used[k]
	u.VCPUs += j.Resources.VCPUs
	u.MemoryGB += j.Resources.MemoryGB
	e.used[k] = u
	cost := j.RuntimeMS
	if j.Platform == "macos" && !j.result.CacheHit {
		cost += j.ColdPenaltyMS
	}
	e.add(e.now+cost, finish, job, slot)
}

// Attribute every millisecond of queue wait to the first failed prerequisite:
// quota, compatible ready capacity, then decision wait. Quota precedence means
// these categories are an accounting convention, not independent root causes.
func (e *engine) accountWaiting(dt int64) {
	if dt == 0 {
		return
	}
	for i := range e.jobs {
		j := &e.jobs[i]
		if !j.arrived || j.assigned {
			continue
		}
		if !e.fits(j) {
			j.result.QuotaBlockedMS += dt
			continue
		}
		hasRunner := false
		for k := range e.slots {
			if e.slots[k].idle && compatible(j, &e.slots[k]) {
				hasRunner = true
				break
			}
		}
		if hasRunner {
			j.result.ReadyWaitingMS += dt
		} else {
			j.result.CapacityBlockedMS += dt
		}
	}
}

func measure(jobs []JobResult) Metrics {
	m := Metrics{Jobs: len(jobs)}
	if len(jobs) == 0 {
		return m
	}
	var waits []float64
	for _, j := range jobs {
		w := float64(j.AssignedMS-j.ArrivalMS) / 1000
		waits = append(waits, w)
		m.QueueMeanSeconds += w
		m.CompletionMeanSeconds += float64(j.FinishedMS-j.ArrivalMS) / 1000
		m.MakespanSeconds = max(m.MakespanSeconds, float64(j.FinishedMS)/1000)
		m.QuotaBlockedMeanSeconds += float64(j.QuotaBlockedMS) / 1000
		m.CapacityBlockedMeanSeconds += float64(j.CapacityBlockedMS) / 1000
		m.ReadyWaitingMeanSeconds += float64(j.ReadyWaitingMS) / 1000
		if j.Platform == "macos" {
			m.CacheEligibleJobs++
			if j.CacheHit {
				m.CacheHits++
			}
		}
	}
	n := float64(len(jobs))
	m.QueueMeanSeconds /= n
	m.CompletionMeanSeconds /= n
	m.QuotaBlockedMeanSeconds /= n
	m.CapacityBlockedMeanSeconds /= n
	m.ReadyWaitingMeanSeconds /= n
	sort.Float64s(waits)
	m.QueueP95Seconds = waits[int(math.Ceil(.95*n))-1]
	m.QueueMaxSeconds = waits[len(waits)-1]
	return m
}
