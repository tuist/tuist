package shadow

import (
	"fmt"
	"reflect"
	"testing"
	"time"
)

var testNow = time.Date(2026, 9, 22, 12, 0, 0, 0, time.UTC)
var small = Resources{VCPUs: 2, MemoryGB: 8}

func demand(id, account int64, pool string, age time.Duration) Demand {
	return Demand{JobID: id, AccountID: account, Pool: pool, Platform: "linux", Resources: small, EnqueuedAt: testNow.Add(-age)}
}
func runner(pod, pool string) Runner {
	return Runner{Pod: pod, UID: pod + "-uid", Node: pod + "-node", Pool: pool, Platform: "linux", Resources: small}
}
func fixture(ds ...Demand) Snapshot {
	return Snapshot{Version: Version, Complete: true, CapturedAt: testNow, Demand: ds,
		Accounts: []Account{{AccountID: 1, Platform: "linux", Limit: Resources{8, 32}}, {AccountID: 2, Platform: "linux", Limit: Resources{8, 32}}}}
}
func propose(t *testing.T, s Snapshot, rs ...Runner) Plan {
	t.Helper()
	p, err := Propose(s, rs, testNow)
	if err != nil {
		t.Fatal(err)
	}
	return p
}

func TestAccountBudgetSharedAcrossPools(t *testing.T) {
	s := fixture(demand(1, 1, "a", time.Minute), demand(2, 1, "b", time.Second))
	s.Accounts[0].Limit = small
	p := propose(t, s, runner("a", "a"), runner("b", "b"))
	if len(p.Assignments) != 1 || p.Assignments[0].JobID != 1 || p.Deferred["account_limit"] != 1 {
		t.Fatalf("%+v", p)
	}
}

func TestFairnessAndAging(t *testing.T) {
	for _, tc := range []struct {
		name string
		age  time.Duration
		want int64
	}{
		{"underused account first", time.Minute, 2}, {"old demand overrides share", 3 * time.Minute, 1},
	} {
		t.Run(tc.name, func(t *testing.T) {
			s := fixture(demand(1, 1, "a", tc.age), demand(2, 2, "a", time.Second))
			s.Claims = []Claim{{Pod: "busy", AccountID: 1, Platform: "linux", Resources: small, ClaimedAt: testNow.Add(-time.Minute)}}
			p := propose(t, s, runner("a", "a"))
			if len(p.Assignments) != 1 || p.Assignments[0].JobID != tc.want {
				t.Fatalf("%+v", p)
			}
		})
	}
}

func TestVirtualAssignmentsChangeFairShare(t *testing.T) {
	s := fixture(demand(1, 1, "a", time.Minute), demand(2, 1, "a", time.Minute), demand(3, 2, "a", time.Second))
	p := propose(t, s, runner("a", "a"), runner("b", "a"))
	if len(p.Assignments) != 2 || p.Assignments[0].JobID != 1 || p.Assignments[1].JobID != 3 {
		t.Fatalf("%+v", p)
	}
}

func TestIndependentPlatformBudgets(t *testing.T) {
	d := demand(2, 1, "mac", time.Second)
	d.Platform = "macos"
	s := fixture(demand(1, 1, "a", time.Minute), d)
	s.Accounts[0].Limit = small
	s.Accounts = append(s.Accounts, Account{AccountID: 1, Platform: "macos", Limit: small})
	r := runner("mac", "mac")
	r.Platform = "macos"
	p := propose(t, s, runner("a", "a"), r)
	if len(p.Assignments) != 2 {
		t.Fatalf("%+v", p)
	}
}

func TestAdmissionRejectsEitherResourceLimit(t *testing.T) {
	for _, limit := range []Resources{{1, 32}, {8, 4}} {
		s := fixture(demand(1, 1, "a", time.Second))
		s.Accounts[0].Limit = limit
		p := propose(t, s, runner("a", "a"))
		if len(p.Assignments) != 0 || p.Deferred["account_limit"] != 1 {
			t.Fatalf("%+v", p)
		}
	}
}

func TestClaimsOverrideStaleQueueAndWarmPodObservations(t *testing.T) {
	s := fixture(demand(1, 1, "a", time.Minute), demand(2, 1, "a", time.Minute), demand(3, 2, "a", time.Second))
	j1, j2 := int64(1), int64(2)
	s.Claims = []Claim{{Pod: "a", JobID: &j1, ExecutedJobID: &j2, AccountID: 1, Platform: "linux", Resources: small, ClaimedAt: testNow}}
	p := propose(t, s, runner("a", "a"))
	if len(p.Assignments) != 0 || p.Deferred["already_claimed"] != 2 || p.Deferred["no_warm_runner"] != 1 {
		t.Fatalf("%+v", p)
	}
}

func TestLocalityChoosesRunnerWithoutReorderingDemand(t *testing.T) {
	s := fixture(demand(1, 1, "a", time.Minute), demand(2, 2, "a", time.Second))
	a, b := runner("a", "a"), runner("b", "a")
	a.ResidentAccounts = map[int64]bool{2: true}
	b.ResidentAccounts = map[int64]bool{1: true}
	p := propose(t, s, a, b)
	if len(p.Assignments) != 2 || p.Assignments[0].JobID != 1 || p.Assignments[0].Pod != "b" || !p.Assignments[0].CacheResident {
		t.Fatalf("%+v", p)
	}
	p = propose(t, s, a)
	if p.Assignments[0].JobID != 1 || p.Assignments[0].CacheResident {
		t.Fatalf("cache preference reordered demand: %+v", p)
	}
}

func TestExactShapePoolAndPlatform(t *testing.T) {
	s := fixture(demand(1, 1, "xcode-a", time.Minute))
	for _, modify := range []func(*Runner){
		func(r *Runner) { r.Pool = "xcode-b" }, func(r *Runner) { r.Platform = "macos" }, func(r *Runner) { r.Resources.VCPUs = 8 },
	} {
		r := runner("a", "xcode-a")
		modify(&r)
		if p := propose(t, s, r); len(p.Assignments) != 0 {
			t.Fatalf("%+v", p)
		}
	}
}

func TestOldUnplaceableDemandDoesNotBlockOtherPools(t *testing.T) {
	s := fixture(demand(1, 1, "large", time.Hour), demand(2, 2, "a", time.Second))
	p := propose(t, s, runner("a", "a"))
	if len(p.Assignments) != 1 || p.Assignments[0].JobID != 2 || p.Deferred["no_warm_runner"] != 1 {
		t.Fatalf("%+v", p)
	}
}

func TestInvalidSnapshotsAndDuplicateRunners(t *testing.T) {
	for _, change := range []func(*Snapshot){
		func(s *Snapshot) { s.Complete = false }, func(s *Snapshot) { s.Version = 2 },
		func(s *Snapshot) { s.CapturedAt = testNow.Add(-time.Minute) }, func(s *Snapshot) { s.CapturedAt = testNow.Add(time.Minute) },
		func(s *Snapshot) { s.Demand = append(s.Demand, s.Demand[0]) }, func(s *Snapshot) { s.Accounts = append(s.Accounts, s.Accounts[0]) },
		func(s *Snapshot) { s.Claims = []Claim{{Pod: "broken", AccountID: 1}} },
	} {
		s := fixture(demand(1, 1, "a", time.Second))
		change(&s)
		if _, err := Propose(s, []Runner{runner("a", "a")}, testNow); err == nil {
			t.Fatal("accepted invalid snapshot")
		}
	}
	s := fixture(demand(1, 1, "a", time.Second))
	r := runner("a", "a")
	if _, err := Propose(s, []Runner{r, r}, testNow); err == nil {
		t.Fatal("accepted duplicate runner")
	}
}

func TestUnknownShapesAndMissingLimitsAreExplicit(t *testing.T) {
	s := fixture(demand(1, 1, "a", time.Second), demand(2, 3, "a", time.Second))
	s.Demand[0].Resources = Resources{}
	p := propose(t, s, runner("a", "a"))
	if p.Deferred["unknown_shape"] != 1 || p.Deferred["missing_limit"] != 1 {
		t.Fatalf("%+v", p)
	}
}

func TestDeterministicAndDoesNotMutateInputs(t *testing.T) {
	s := fixture(demand(2, 2, "a", time.Second), demand(1, 1, "a", time.Second))
	rs := []Runner{runner("b", "a"), runner("a", "a")}
	original := append([]Demand(nil), s.Demand...)
	p := propose(t, s, rs...)
	if !reflect.DeepEqual(original, s.Demand) || rs[0].Pod != "b" {
		t.Fatal("mutated inputs")
	}
	s.Demand[0], s.Demand[1] = s.Demand[1], s.Demand[0]
	rs[0], rs[1] = rs[1], rs[0]
	if q := propose(t, s, rs...); !reflect.DeepEqual(p, q) {
		t.Fatalf("unstable plans: %+v %+v", p, q)
	}
}

func TestProposalCap(t *testing.T) {
	s := fixture()
	s.Accounts[0].Limit = Resources{1000, 4000}
	rs := []Runner{}
	for i := 1; i <= MaxAssignments+1; i++ {
		s.Demand = append(s.Demand, demand(int64(i), 1, "a", time.Second))
		rs = append(rs, runner(fmt.Sprint(i), "a"))
	}
	p := propose(t, s, rs...)
	if len(p.Assignments) != MaxAssignments || p.Deferred["proposal_cap"] != 1 {
		t.Fatalf("%+v", p)
	}
}

func BenchmarkProposeBoundedSnapshot(b *testing.B) {
	s := fixture()
	s.Accounts[0].Limit = Resources{10000, 40000}
	rs := []Runner{}
	for i := 1; i <= MaxDemand; i++ {
		s.Demand = append(s.Demand, demand(int64(i), 1, "a", time.Second))
		rs = append(rs, runner(fmt.Sprint(i), "a"))
	}
	for b.Loop() {
		if _, err := Propose(s, rs, testNow); err != nil {
			b.Fatal(err)
		}
	}
}
