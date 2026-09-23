package simulation

import (
	"fmt"
	"github.com/tuist/tuist/infra/runners-controller/internal/simulation/assignment"
	"math/rand"
)

func budget(id int64, platform string, slots int64, shape assignment.Resources) assignment.Account {
	return assignment.Account{AccountID: id, Platform: platform, Limit: assignment.Resources{VCPUs: slots * shape.VCPUs, MemoryGB: slots * shape.MemoryGB}}
}
func slots(n int, pool, platform string, shape assignment.Resources) []Slot {
	var result []Slot
	for i := 0; i < n; i++ {
		result = append(result, Slot{Name: fmt.Sprintf("%s-slot-%02d", pool, i), Node: fmt.Sprintf("%s-host-%02d", pool, i), Pool: pool, Platform: platform, Resources: shape, RecycleMS: 2000})
	}
	return result
}
func jobs(n int, account, firstID, arrival, spacing, runtime int64, pool, platform string, shape assignment.Resources) []Job {
	var result []Job
	for i := 0; i < n; i++ {
		result = append(result, Job{ID: firstID + int64(i), Account: account, Pool: pool, Platform: platform, Repository: "repo", Resources: shape, ArrivalMS: arrival + int64(i)*spacing, RuntimeMS: runtime})
	}
	return result
}

// Scenarios are synthetic mechanism tests, not fitted production traces.
// Contrasting pairs change exactly one quota, release-lag or capacity input.
func Scenarios() []Scenario {
	linux := assignment.Resources{VCPUs: 2, MemoryGB: 8}
	mac := assignment.Resources{VCPUs: 4, MemoryGB: 14}
	var out []Scenario
	out = append(out, Scenario{Name: "sparse_linux", Description: "20 five-second jobs, ten seconds apart; eight ready slots and no quota contention.", Jobs: jobs(20, 1, 1, 0, 10000, 5000, "linux", "linux", linux), Slots: slots(8, "linux", "linux", linux), Accounts: []assignment.Account{budget(1, "linux", 8, linux)}})
	for _, limit := range []int64{2, 4} {
		out = append(out, Scenario{Name: fmt.Sprintf("quota_%d_slots", limit), Description: fmt.Sprintf("32 simultaneous 60-second jobs, 16 warm slots, one account limited to %d jobs.", limit), Jobs: jobs(32, 1, 1, 0, 0, 60000, "linux", "linux", linux), Slots: slots(16, "linux", "linux", linux), Accounts: []assignment.Account{budget(1, "linux", limit, linux)}})
	}
	for _, lag := range []int64{0, 30000} {
		jj := jobs(24, 1, 1, 0, 0, 30000, "linux", "linux", linux)
		for i := range jj {
			jj[i].ReleaseLagMS = lag
		}
		out = append(out, Scenario{Name: fmt.Sprintf("claim_release_lag_%ds", lag/1000), Description: fmt.Sprintf("24 simultaneous 30-second jobs, 16 warm slots, two-job quota; claims persist %ds after completion.", lag/1000), Jobs: jj, Slots: slots(16, "linux", "linux", linux), Accounts: []assignment.Account{budget(1, "linux", 2, linux)}})
	}
	for _, available := range []int64{0, 180000} {
		jj := append(jobs(48, 1, 1, 0, 0, 30000, "linux", "linux", linux), jobs(8, 2, 100, 5000, 0, 30000, "linux", "linux", linux)...)
		rr := slots(8, "linux", "linux", linux)
		for i := range rr {
			rr[i].AvailableMS = available
		}
		out = append(out, Scenario{Name: fmt.Sprintf("competing_accounts_ready_%ds", available/1000), Description: fmt.Sprintf("Account 1 bursts 48 jobs; account 2 adds eight after 5s. Eight slots become ready at %ds; each account can fill all eight.", available/1000), Jobs: jj, Slots: rr, Accounts: []assignment.Account{budget(1, "linux", 8, linux), budget(2, "linux", 8, linux)}})
	}
	for _, penalty := range []int64{0, 45000} {
		jj := jobs(8, 1, 1, 0, 90000, 20000, "mac", "macos", mac)
		for i := range jj {
			jj[i].ColdPenaltyMS = penalty
		}
		rr := slots(4, "mac", "macos", mac)
		rr[3].AccountMasters = []int64{1}
		out = append(out, Scenario{Name: fmt.Sprintf("sparse_mac_cold_%ds", penalty/1000), Description: fmt.Sprintf("Eight sparse 20-second macOS jobs; four hosts, one initial account master, %ds cold-materialization penalty. Completed jobs populate repository masters.", penalty/1000), Jobs: jj, Slots: rr, Accounts: []assignment.Account{budget(1, "macos", 4, mac)}})
	}
	{
		jj := append(jobs(16, 1, 1, 0, 0, 30000, "mac", "macos", mac), jobs(16, 2, 100, 0, 0, 30000, "mac", "macos", mac)...)
		for i := range jj {
			jj[i].ColdPenaltyMS = 45000
		}
		rr := slots(8, "mac", "macos", mac)
		for i := range rr {
			rr[i].AccountMasters = []int64{int64(i%2 + 1)}
		}
		out = append(out, Scenario{Name: "busy_mac_locality", Description: "Two accounts each burst 16 jobs; eight hosts split their initial account masters evenly; 45s cold cost.", Jobs: jj, Slots: rr, Accounts: []assignment.Account{budget(1, "macos", 8, mac), budget(2, "macos", 8, mac)}})
	}
	{
		jj := jobs(2, 1, 1, 0, 0, 30000, "mac", "macos", mac)
		jj[0].Repository = "a"
		jj[1].Repository = "b"
		for i := range jj {
			jj[i].ColdPenaltyMS = 60000
		}
		rr := slots(2, "mac", "macos", mac)
		rr[0].RepositoryMasters = []Master{{1, "b"}}
		rr[1].RepositoryMasters = []Master{{1, "a"}}
		out = append(out, Scenario{Name: "repository_only_cache", Description: "Two jobs from one account use different repositories; each host has the opposite repository's master and no account master. Counterexample for account-only shadow locality.", Jobs: jj, Slots: rr, Accounts: []assignment.Account{budget(1, "macos", 2, mac)}})
	}
	{
		big := assignment.Resources{VCPUs: 12, MemoryGB: 28}
		rr := slots(12, "small", "macos", mac)
		large := slots(2, "large", "macos", big)
		for i := range large {
			large[i].AvailableMS = 180000
		}
		rr = append(rr, large...)
		out = append(out, Scenario{Name: "incompatible_warm_capacity", Description: "Eight large jobs; twelve incompatible small warm slots. Two matching slots arrive at 180s under the same external provisioning schedule for every policy.", Jobs: jobs(8, 1, 1, 0, 0, 60000, "large", "macos", big), Slots: rr, Accounts: []assignment.Account{budget(1, "macos", 16, big)}})
	}
	for _, platform := range []string{"linux", "macos"} {
		shape := linux
		if platform == "macos" {
			shape = mac
		}
		rng := rand.New(rand.NewSource(20260922))
		var jj []Job
		var at int64
		for i := 0; i < 160; i++ {
			at += int64(rng.ExpFloat64() * 5000)
			account := int64(1)
			if rng.Float64() > .6 {
				account = 2 + int64(rng.Intn(3))
			}
			j := jobs(1, account, int64(i+1), at, 0, 5000+int64(rng.ExpFloat64()*40000), platform, platform, shape)[0]
			j.Repository = fmt.Sprintf("repo-%d", rng.Intn(2))
			j.ColdPenaltyMS = 20000
			jj = append(jj, j)
		}
		rr := slots(8, platform, platform, shape)
		var aa []assignment.Account
		for a := int64(1); a <= 4; a++ {
			aa = append(aa, budget(a, platform, 4, shape))
		}
		if platform == "macos" {
			for i := range rr {
				rr[i].AccountMasters = []int64{int64(i%4 + 1)}
			}
		}
		out = append(out, Scenario{Name: "mixed_arrivals_" + platform, Description: "Fixed-seed synthetic trace: 160 exponential arrivals (5s mean), four accounts with four-job quotas, 60% of demand from account 1, two repositories each, eight slots, runtimes 5s + exponential mean 40s, macOS cold penalty 20s.", Jobs: jj, Slots: rr, Accounts: aa})
	}
	return out
}
