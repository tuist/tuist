// simulate-scheduling compares synthetic traces without accessing a cluster.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"sort"

	"github.com/tuist/tuist/infra/runners-controller/internal/simulation"
	"github.com/tuist/tuist/infra/runners-controller/internal/simulation/assignment"
)

func main() {
	seeds := flag.Int("seeds", 30, "Number of paired random poll phases; seeds start at 1")
	delay := flag.Int64("push-delay-ms", 250, "Assumed central decision/delivery delay")
	jsonPath := flag.String("json", "", "Optional full per-job JSON results")
	inputPath := flag.String("scenarios", "", "Optional JSON array of simulation.Scenario; defaults to synthetic scenarios")
	exportPath := flag.String("export-scenarios", "", "Optional path to save the exact input scenarios")
	flag.Parse()
	if *seeds < 1 {
		fmt.Fprintln(os.Stderr, "seeds must be positive")
		os.Exit(1)
	}
	var results []simulation.Result
	scenarios := simulation.Scenarios()
	if *inputPath != "" {
		data, err := os.ReadFile(*inputPath)
		if err == nil {
			err = json.Unmarshal(data, &scenarios)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	if *exportPath != "" {
		data, err := json.MarshalIndent(scenarios, "", "  ")
		if err == nil {
			err = os.WriteFile(*exportPath, data, 0644)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	for _, s := range scenarios {
		for _, p := range simulation.Policies {
			for seed := 1; seed <= *seeds; seed++ {
				cfg := simulation.DefaultConfig(int64(seed))
				cfg.PushDelayMS = *delay
				r, err := simulation.Run(s, p, cfg)
				if err != nil {
					fmt.Fprintln(os.Stderr, err)
					os.Exit(1)
				}
				results = append(results, r)
			}
		}
	}
	if *jsonPath != "" {
		data, err := json.MarshalIndent(results, "", "  ")
		if err == nil {
			err = os.WriteFile(*jsonPath, data, 0644)
		}
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
	fmt.Printf("Model-based scheduling comparison: %d paired seeds; central delay %dms; shadow policy v%d. Values are averages across seeds, including each seed's p95.\n\n", *seeds, *delay, assignment.Version)
	fmt.Println("| Scenario | Policy | Queue mean (s) | Queue p95 (s) | Mean completion (s) | Makespan (s) | Cache hit % |")
	fmt.Println("|---|---|---:|---:|---:|---:|---:|")
	for _, s := range scenarios {
		for _, p := range simulation.Policies {
			var q, p95, c, m float64
			var hits, eligible int
			for _, r := range results {
				if r.Scenario == s.Name && r.Policy == p {
					q += r.Metrics.QueueMeanSeconds
					p95 += r.Metrics.QueueP95Seconds
					c += r.Metrics.CompletionMeanSeconds
					m += r.Metrics.MakespanSeconds
					hits += r.Metrics.CacheHits
					eligible += r.Metrics.CacheEligibleJobs
				}
			}
			cache := "—"
			if eligible > 0 {
				cache = fmt.Sprintf("%.1f", 100*float64(hits)/float64(eligible))
			}
			n := float64(*seeds)
			fmt.Printf("| %s | %s | %.2f | %.2f | %.2f | %.2f | %s |\n", s.Name, p, q/n, p95/n, c/n, m/n, cache)
		}
	}
	fmt.Println("\nPer-account queue means in competing-account scenarios:")
	for _, s := range scenarios {
		if len(s.Accounts) < 2 {
			continue
		}
		ids := []int64{}
		for _, a := range s.Accounts {
			ids = append(ids, a.AccountID)
		}
		sort.Slice(ids, func(i, j int) bool { return ids[i] < ids[j] })
		for _, p := range simulation.Policies {
			for _, id := range ids {
				var q float64
				for _, r := range results {
					if r.Scenario == s.Name && r.Policy == p {
						q += r.ByAccount[id].QueueMeanSeconds
					}
				}
				fmt.Printf("%s %s account %d: %.2fs\n", s.Name, p, id, q/float64(*seeds))
			}
		}
	}
}
