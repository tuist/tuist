package assignment

import (
	"fmt"
	"reflect"
	"testing"
	"time"
)

var testNow = time.Date(2026, 9, 22, 12, 0, 0, 0, time.UTC)
var small = Resources{VCPUs: 2, MemoryGB: 8}

func demand(id, account int64, pool string, age time.Duration) Demand {
	return Demand{CacheVolume: AccountCacheVolume, JobID: id, AccountID: account, Pool: pool, Platform: "linux", Resources: small, EnqueuedAt: testNow.Add(-age)}
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
	a.Platform, b.Platform = "macos", "macos"
	for i := range s.Demand {
		s.Demand[i].Platform = "macos"
	}
	for i := range s.Accounts {
		s.Accounts[i].Platform = "macos"
	}
	a.ResidentVolumes = map[int64]map[string]bool{2: {AccountCacheVolume: true}}
	b.ResidentVolumes = map[int64]map[string]bool{1: {AccountCacheVolume: true}}
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

func TestRepositoryCacheAffinity(t *testing.T) {
	const volume = "repo-0123456789abcdef"
	const other = "repo-fedcba9876543210"
	for _, tc := range []struct {
		name     string
		account  int64
		volume   string
		resident bool
		platform string
		warm     bool
	}{
		{"repository master", 1, volume, true, "macos", true},
		{"account fallback", 1, AccountCacheVolume, true, "macos", true},
		{"different repository", 1, other, true, "macos", false},
		{"different account", 2, volume, true, "macos", false},
		{"false residency", 1, volume, false, "macos", false},
		{"Linux ignores cache masters", 1, volume, true, "linux", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			d := demand(1, 1, "pool", time.Minute)
			d.Platform, d.CacheVolume = tc.platform, volume
			s := fixture(d)
			s.Accounts[0].Platform = tc.platform
			a, b := runner("a-cold", "pool"), runner("b-master", "pool")
			a.Platform, b.Platform = tc.platform, tc.platform
			b.ResidentVolumes = map[int64]map[string]bool{tc.account: {tc.volume: tc.resident}}
			p := propose(t, s, b, a)
			want := a.Pod
			if tc.warm {
				want = b.Pod
			}
			if len(p.Assignments) != 1 || p.Assignments[0].Pod != want || p.Assignments[0].CacheResident != tc.warm {
				t.Fatalf("%+v", p)
			}
		})
	}
}

func TestCacheMasterUnionPreservesDeterminismAndConsumesRunners(t *testing.T) {
	const volume = "repo-0123456789abcdef"
	s := fixture(demand(1, 1, "pool", time.Minute), demand(2, 1, "pool", time.Second))
	s.Accounts[0].Platform = "macos"
	for i := range s.Demand {
		s.Demand[i].Platform, s.Demand[i].CacheVolume = "macos", volume
	}
	a, b := runner("a-account-master", "pool"), runner("b-repository-master", "pool")
	a.Platform, b.Platform = "macos", "macos"
	a.ResidentVolumes = map[int64]map[string]bool{1: {AccountCacheVolume: true, volume: true}}
	b.ResidentVolumes = map[int64]map[string]bool{1: {volume: true}}
	p := propose(t, s, b, a)
	if len(p.Assignments) != 2 || p.Assignments[0].Pod != a.Pod || p.Assignments[1].Pod != b.Pod || !p.Assignments[1].CacheResident {
		t.Fatalf("%+v", p)
	}
	delete(a.ResidentVolumes[1], volume)
	if other := propose(t, s, a, b); !reflect.DeepEqual(p, other) {
		t.Fatalf("account fallback changed ordering: %+v", other)
	}
}

func TestCacheVolumeRequiredInVersionTwo(t *testing.T) {
	for _, volume := range []string{"", "private/repository", "repo-ABCDEF0123456789", "repo-0123456789abcdef\n"} {
		s := fixture(demand(1, 1, "pool", time.Second))
		s.Demand[0].CacheVolume = volume
		if _, err := Propose(s, nil, testNow); err == nil {
			t.Fatalf("accepted invalid cache volume %q", volume)
		}
	}
	s := fixture()
	s.Version = 1
	if _, err := Propose(s, nil, testNow); err == nil {
		t.Fatal("accepted version 1")
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
		func(s *Snapshot) { s.Complete = false }, func(s *Snapshot) { s.Version = Version + 1 },
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
