package simulation

import (
	"reflect"
	"sort"
	"testing"

	"github.com/tuist/tuist/infra/runners-controller/internal/simulation/assignment"
)

func TestConservationAndAdmission(t *testing.T) {
	for _, s := range Scenarios() {
		for _, p := range Policies {
			t.Run(s.Name+"/"+string(p), func(t *testing.T) {
				r, err := Run(s, p, DefaultConfig(7))
				if err != nil {
					t.Fatal(err)
				}
				if len(r.Jobs) != len(s.Jobs) {
					t.Fatal("lost jobs")
				}
				original := map[int64]Job{}
				for _, j := range s.Jobs {
					original[j.ID] = j
				}
				limits := map[accountKey]assignment.Resources{}
				for _, a := range s.Accounts {
					limits[accountKey{a.AccountID, a.Platform}] = a.Limit
				}
				type change struct {
					at        int64
					key       accountKey
					resources assignment.Resources
					sign      int64
				}
				var changes []change
				bySlot := map[string][]JobResult{}
				seen := map[int64]bool{}
				for _, j := range r.Jobs {
					input := original[j.JobID]
					if seen[j.JobID] || j.AssignedMS < j.ArrivalMS || j.FinishedMS < j.AssignedMS+input.RuntimeMS {
						t.Fatalf("invalid lifecycle: %+v", j)
					}
					seen[j.JobID] = true
					if j.AssignedMS-j.ArrivalMS != j.QuotaBlockedMS+j.CapacityBlockedMS+j.ReadyWaitingMS {
						t.Fatal("wait attribution does not conserve time")
					}
					changes = append(changes, change{j.AssignedMS, accountKey{j.Account, j.Platform}, input.Resources, 1}, change{j.FinishedMS + input.ReleaseLagMS, accountKey{j.Account, j.Platform}, input.Resources, -1})
					bySlot[j.Slot] = append(bySlot[j.Slot], j)
				}
				sort.Slice(changes, func(i, j int) bool {
					if changes[i].at == changes[j].at {
						return changes[i].sign < changes[j].sign
					}
					return changes[i].at < changes[j].at
				})
				used := map[accountKey]assignment.Resources{}
				for _, c := range changes {
					u := used[c.key]
					u.VCPUs += c.sign * c.resources.VCPUs
					u.MemoryGB += c.sign * c.resources.MemoryGB
					used[c.key] = u
					l := limits[c.key]
					if u.VCPUs < 0 || u.MemoryGB < 0 || u.VCPUs > l.VCPUs || u.MemoryGB > l.MemoryGB {
						t.Fatal("account quota violated")
					}
				}
				for _, slot := range s.Slots {
					jj := bySlot[slot.Name]
					sort.Slice(jj, func(i, j int) bool { return jj[i].AssignedMS < jj[j].AssignedMS })
					available := slot.AvailableMS
					for _, j := range jj {
						if j.AssignedMS < available || j.Pool != slot.Pool || j.Platform != slot.Platform || original[j.JobID].Resources != slot.Resources {
							t.Fatal("slot capacity or compatibility violated")
						}
						available = j.FinishedMS + slot.RecycleMS
					}
				}
			})
		}
	}
}

func TestDeterministicWithoutMutatingScenario(t *testing.T) {
	s := Scenarios()[0]
	before := Scenarios()[0]
	for _, p := range Policies {
		a, err := Run(s, p, DefaultConfig(9))
		if err != nil {
			t.Fatal(err)
		}
		b, err := Run(s, p, DefaultConfig(9))
		if err != nil || !reflect.DeepEqual(a, b) {
			t.Fatal("nondeterministic result")
		}
	}
	if !reflect.DeepEqual(s, before) {
		t.Fatal("mutated input")
	}
}

func TestAnalyticalSingleSlotQueue(t *testing.T) {
	shape := assignment.Resources{VCPUs: 1, MemoryGB: 1}
	s := Scenario{Name: "analytical", Jobs: jobs(3, 1, 1, 0, 0, 10000, "p", "linux", shape), Slots: slots(1, "p", "linux", shape), Accounts: []assignment.Account{budget(1, "linux", 1, shape)}}
	s.Slots[0].RecycleMS = 0
	for _, p := range []Policy{PushCurrent, PushFair} {
		r, err := Run(s, p, DefaultConfig(1))
		if err != nil {
			t.Fatal(err)
		}
		for i, j := range r.Jobs {
			want := int64(i)*10250 + 250
			if j.AssignedMS != want || j.FinishedMS != want+10000 {
				t.Fatalf("got %+v, expected start %d", j, want)
			}
		}
	}
}

// Boundary cases mirror the production VolumeAffinities.select_candidate
// contract: top-20 window, repository fallback and head-age override.
func TestCurrentDispatchAffinityAndQuotaRetry(t *testing.T) {
	shape := assignment.Resources{VCPUs: 1, MemoryGB: 1}
	for _, tc := range []struct {
		name          string
		now           int64
		residentIndex int
		blockedHead   bool
		want          int64
	}{
		{"repository resident", 30000, 1, false, 2},
		{"head overdue", 31000, 1, false, 1},
		{"outside top twenty", 0, 20, false, 1},
		{"skip quota blocked account", 31000, 1, true, 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			e := &engine{now: tc.now, limits: map[accountKey]assignment.Resources{}, used: map[accountKey]assignment.Resources{}, accountMasters: map[string]map[int64]bool{"node": {}}, repositoryMasters: map[string]map[Master]bool{"node": {}}}
			e.slots = []slotState{{Slot: Slot{Name: "slot", Node: "node", Pool: "p", Platform: "macos", Resources: shape}, idle: true}}
			for i := 0; i < 21; i++ {
				j := jobs(1, int64(i+1), int64(i+1), 0, 0, 10000, "p", "macos", shape)[0]
				e.jobs = append(e.jobs, jobState{Job: j, arrived: true})
				e.limits[accountKey{j.Account, j.Platform}] = shape
			}
			e.repositoryMasters["node"][Master{int64(tc.residentIndex + 1), "repo"}] = true
			if tc.blockedHead {
				e.used[accountKey{1, "macos"}] = shape
			}
			e.pickCurrent(0)
			for _, j := range e.jobs {
				if j.assigned && j.ID != tc.want {
					t.Fatalf("picked %d, want %d", j.ID, tc.want)
				}
			}
			if !e.jobs[tc.want-1].assigned {
				t.Fatal("expected assignment missing")
			}
		})
	}
}

func TestRuntimeIsNotUsedToChooseNextJob(t *testing.T) {
	for _, p := range Policies {
		s := Scenarios()[0]
		s.Jobs = s.Jobs[:2]
		s.Jobs[1].ArrivalMS = 0
		s.Slots = s.Slots[:1]
		a, err := Run(s, p, DefaultConfig(1))
		if err != nil {
			t.Fatal(err)
		}
		s.Jobs[0].RuntimeMS = 90000
		s.Jobs[1].RuntimeMS = 1
		b, err := Run(s, p, DefaultConfig(1))
		if err != nil {
			t.Fatal(err)
		}
		if a.Jobs[0].AssignedMS != b.Jobs[0].AssignedMS || b.Jobs[1].AssignedMS <= b.Jobs[0].AssignedMS {
			t.Fatal("scheduler used future runtime")
		}
	}
}

func TestRejectInvalidPolicyAndStopUnfinishableScenario(t *testing.T) {
	s := Scenarios()[0]
	if _, err := Run(s, "unknown", DefaultConfig(1)); err == nil {
		t.Fatal("accepted unknown policy")
	}
	s.Slots = nil
	cfg := DefaultConfig(1)
	cfg.HorizonMS = 1000
	for _, p := range Policies {
		if _, err := Run(s, p, cfg); err == nil {
			t.Fatal("accepted unfinished simulation")
		}
	}
}

func TestCentralShadowRespectsRepositoryOnlyCacheMasters(t *testing.T) {
	for _, s := range Scenarios() {
		if s.Name != "repository_only_cache" {
			continue
		}
		for seed := int64(1); seed <= 30; seed++ {
			r, err := Run(s, PushFair, DefaultConfig(seed))
			if err != nil {
				t.Fatal(err)
			}
			for _, j := range r.Jobs {
				if !j.CacheHit || j.FinishedMS-j.ArrivalMS != 30250 {
					t.Fatalf("repository counterexample regressed: %+v", j)
				}
			}
		}
		return
	}
	t.Fatal("repository-only scenario missing")
}

func TestCacheVolumeMatchesServerContract(t *testing.T) {
	for _, repository := range []string{"private/repository", "PRIVATE/Repository"} {
		if got := cacheVolume(repository); got != "repo-3fa9f049da757381" {
			t.Fatalf("volume mismatch: %s", got)
		}
	}
	if cacheVolume("") != assignment.AccountCacheVolume {
		t.Fatal("missing account fallback")
	}
}
