// Package shadow proposes assignments without owning or changing any resources.
package shadow

import (
	"fmt"
	"sort"
	"time"
)

const (
	Version        = 1
	MaxDemand      = 1000
	MaxClaims      = 10000
	MaxAssignments = 100
	MaxSnapshotAge = 15 * time.Second
	AgingThreshold = 2 * time.Minute
)

type Resources struct {
	VCPUs    int64 `json:"vcpus"`
	MemoryGB int64 `json:"memory_gb"`
}

type Demand struct {
	JobID      int64     `json:"job_id"`
	AccountID  int64     `json:"account_id"`
	Pool       string    `json:"pool"`
	Platform   string    `json:"platform"`
	Resources  Resources `json:"resources"`
	EnqueuedAt time.Time `json:"enqueued_at"`
}

type Account struct {
	AccountID int64     `json:"account_id"`
	Platform  string    `json:"platform"`
	Limit     Resources `json:"limit"`
}

type Claim struct {
	Pod           string    `json:"pod"`
	JobID         *int64    `json:"job_id"`
	ExecutedJobID *int64    `json:"executed_job_id"`
	AccountID     int64     `json:"account_id"`
	Platform      string    `json:"platform"`
	Resources     Resources `json:"resources"`
	ClaimedAt     time.Time `json:"claimed_at"`
}

type Snapshot struct {
	Version    int       `json:"version"`
	CapturedAt time.Time `json:"captured_at"`
	Complete   bool      `json:"complete"`
	Demand     []Demand  `json:"demand"`
	Accounts   []Account `json:"accounts"`
	Claims     []Claim   `json:"claims"`
}

// Runner is an existing warm VM. Resources are the advertised job shape,
// not host capacity or the RuntimeClass overhead already paid at placement.
type Runner struct {
	Pod              string         `json:"pod"`
	UID              string         `json:"uid"`
	Node             string         `json:"node"`
	Pool             string         `json:"pool"`
	Platform         string         `json:"platform"`
	Resources        Resources      `json:"resources"`
	ResidentAccounts map[int64]bool `json:"resident_accounts"`
}

type Assignment struct {
	JobID         int64  `json:"job_id"`
	AccountID     int64  `json:"account_id"`
	Pod           string `json:"pod"`
	UID           string `json:"uid"`
	Node          string `json:"node"`
	Pool          string `json:"pool"`
	Platform      string `json:"platform"`
	CacheResident bool   `json:"cache_resident"`
	QueueSeconds  int64  `json:"queue_seconds"`
}

type Plan struct {
	Assignments []Assignment   `json:"assignments"`
	Deferred    map[string]int `json:"deferred"`
}

type accountKey struct {
	id       int64
	platform string
}

func (s Snapshot) Validate(now time.Time) error {
	if s.Version != Version || !s.Complete {
		return fmt.Errorf("unsupported or incomplete demand snapshot")
	}
	if s.CapturedAt.IsZero() || now.Sub(s.CapturedAt) > MaxSnapshotAge || s.CapturedAt.After(now.Add(5*time.Second)) {
		return fmt.Errorf("stale demand snapshot or clock skew")
	}
	if len(s.Demand) > MaxDemand || len(s.Claims) > MaxClaims || len(s.Accounts) > 2*(MaxDemand+MaxClaims) {
		return fmt.Errorf("demand snapshot exceeds bounds")
	}
	jobs := map[int64]bool{}
	for _, d := range s.Demand {
		if d.JobID <= 0 || d.AccountID <= 0 || jobs[d.JobID] || d.EnqueuedAt.IsZero() || d.EnqueuedAt.After(now.Add(5*time.Second)) {
			return fmt.Errorf("invalid or duplicate demand")
		}
		jobs[d.JobID] = true
	}
	accounts := map[accountKey]bool{}
	for _, a := range s.Accounts {
		key := accountKey{a.AccountID, a.Platform}
		if a.AccountID <= 0 || !validPlatform(a.Platform) || !positive(a.Limit) || accounts[key] {
			return fmt.Errorf("invalid or duplicate account budget")
		}
		accounts[key] = true
	}
	pods := map[string]bool{}
	for _, c := range s.Claims {
		if c.Pod == "" || c.AccountID <= 0 || !validPlatform(c.Platform) || !positive(c.Resources) || pods[c.Pod] || c.ClaimedAt.IsZero() {
			return fmt.Errorf("invalid or duplicate active claim")
		}
		pods[c.Pod] = true
	}
	return nil
}

// Propose orders feasible demand by the account's current dominant share of
// its platform limit. Each virtual assignment charges the shared account
// budget across pools. After two minutes, age wins over share. Within an
// account/platform, the oldest feasible demand wins. Cache residency only breaks ties
// between compatible runners; it never delays demand for a warmer host.
// This is a policy experiment, not a simulation of the live dispatch loop.
func Propose(snapshot Snapshot, runners []Runner, now time.Time) (Plan, error) {
	plan := Plan{Assignments: []Assignment{}, Deferred: map[string]int{}}
	if err := snapshot.Validate(now); err != nil {
		return plan, err
	}
	if len(runners) > MaxDemand {
		return plan, fmt.Errorf("warm runner snapshot exceeds bounds")
	}
	limits, used := map[accountKey]Resources{}, map[accountKey]Resources{}
	claimedPods, claimedJobs := map[string]bool{}, map[int64]bool{}
	for _, a := range snapshot.Accounts {
		limits[accountKey{a.AccountID, a.Platform}] = a.Limit
	}
	for _, c := range snapshot.Claims {
		key := accountKey{c.AccountID, c.Platform}
		u := used[key]
		u.VCPUs += c.Resources.VCPUs
		u.MemoryGB += c.Resources.MemoryGB
		used[key] = u
		claimedPods[c.Pod] = true
		if c.JobID != nil {
			claimedJobs[*c.JobID] = true
		}
		if c.ExecutedJobID != nil {
			claimedJobs[*c.ExecutedJobID] = true
		}
	}
	available := append([]Runner(nil), runners...)
	sort.Slice(available, func(i, j int) bool { return available[i].Pod < available[j].Pod })
	seenPods := map[string]bool{}
	for _, r := range available {
		if r.Pod == "" || r.UID == "" || r.Node == "" || seenPods[r.Pod] || !positive(r.Resources) || !validPlatform(r.Platform) {
			return plan, fmt.Errorf("invalid or duplicate warm runner")
		}
		seenPods[r.Pod] = true
	}
	options := indexRunners(available)
	pending := append([]Demand(nil), snapshot.Demand...)
	for len(pending) > 0 {
		best := -1
		var bestRunner Runner
		for i, d := range pending {
			key := accountKey{d.AccountID, d.Platform}
			if claimedJobs[d.JobID] || !positive(d.Resources) || !validPlatform(d.Platform) || !fits(used[key], d.Resources, limits[key]) {
				continue
			}
			candidateRunner, ok := options.find(d, claimedPods)
			if !ok {
				continue
			}
			if best < 0 || before(d, pending[best], used, limits, now) {
				best, bestRunner = i, candidateRunner
			}
		}
		if best < 0 || len(plan.Assignments) == MaxAssignments {
			break
		}
		d, r := pending[best], bestRunner
		plan.Assignments = append(plan.Assignments, Assignment{
			JobID: d.JobID, AccountID: d.AccountID, Pod: r.Pod, UID: r.UID,
			Node: r.Node, Pool: d.Pool, Platform: d.Platform,
			CacheResident: r.ResidentAccounts[d.AccountID], QueueSeconds: max(0, int64(now.Sub(d.EnqueuedAt).Seconds())),
		})
		key := accountKey{d.AccountID, d.Platform}
		u := used[key]
		u.VCPUs += d.Resources.VCPUs
		u.MemoryGB += d.Resources.MemoryGB
		used[key] = u
		claimedPods[r.Pod] = true
		pending = append(pending[:best], pending[best+1:]...)
	}
	for _, d := range pending {
		key := accountKey{d.AccountID, d.Platform}
		_, hasRunner := options.find(d, claimedPods)
		reason := "no_warm_runner"
		switch {
		case claimedJobs[d.JobID]:
			reason = "already_claimed"
		case !positive(d.Resources) || !validPlatform(d.Platform):
			reason = "unknown_shape"
		case !positive(limits[key]):
			reason = "missing_limit"
		case !fits(used[key], d.Resources, limits[key]):
			reason = "account_limit"
		case hasRunner:
			reason = "proposal_cap"
		}
		plan.Deferred[reason]++
	}
	return plan, nil
}

// Each bucket is sorted by Pod name. Consumed prefixes are discarded lazily,
// so each runner is skipped once per bucket instead of rescanning the fleet
// for every demand on every selection round.
type runnerKey struct {
	pool, platform string
	resources      Resources
	account        int64
}
type runnerIndex map[runnerKey][]Runner

func indexRunners(runners []Runner) runnerIndex {
	index := runnerIndex{}
	for _, r := range runners {
		key := runnerKey{pool: r.Pool, platform: r.Platform, resources: r.Resources}
		index[key] = append(index[key], r)
		for account, resident := range r.ResidentAccounts {
			if resident {
				key.account = account
				index[key] = append(index[key], r)
			}
		}
	}
	return index
}

func (index runnerIndex) find(d Demand, claimed map[string]bool) (Runner, bool) {
	key := runnerKey{pool: d.Pool, platform: d.Platform, resources: d.Resources, account: d.AccountID}
	if r, ok := index.first(key, claimed); ok {
		return r, true
	}
	key.account = 0
	return index.first(key, claimed)
}

func (index runnerIndex) first(key runnerKey, claimed map[string]bool) (Runner, bool) {
	runners := index[key]
	for len(runners) > 0 && claimed[runners[0].Pod] {
		runners = runners[1:]
	}
	index[key] = runners
	if len(runners) == 0 {
		return Runner{}, false
	}
	return runners[0], true
}

func before(a, b Demand, used, limits map[accountKey]Resources, now time.Time) bool {
	oldA, oldB := now.Sub(a.EnqueuedAt) >= AgingThreshold, now.Sub(b.EnqueuedAt) >= AgingThreshold
	if oldA != oldB {
		return oldA
	}
	if !oldA {
		ka, kb := accountKey{a.AccountID, a.Platform}, accountKey{b.AccountID, b.Platform}
		sa, sb := share(used[ka], limits[ka]), share(used[kb], limits[kb])
		if sa != sb {
			return sa < sb
		}
	}
	if !a.EnqueuedAt.Equal(b.EnqueuedAt) {
		return a.EnqueuedAt.Before(b.EnqueuedAt)
	}
	return a.JobID < b.JobID
}

func share(used, limit Resources) float64 {
	return max(float64(used.VCPUs)/float64(limit.VCPUs), float64(used.MemoryGB)/float64(limit.MemoryGB))
}
func positive(r Resources) bool   { return r.VCPUs > 0 && r.MemoryGB > 0 }
func validPlatform(p string) bool { return p == "linux" || p == "macos" }
func fits(used, demand, limit Resources) bool {
	return positive(limit) && demand.VCPUs <= limit.VCPUs-used.VCPUs && demand.MemoryGB <= limit.MemoryGB-used.MemoryGB
}
