// The runner's bundled node, installed over each externals/node*/bin/node. It
// runs the real node (node.real beside it) with one change: while this host's
// cache agent answers, a JavaScript action's GitHub results service points at
// the agent, which serves the Actions cache from this host and passes every
// other results request to GitHub. The runner sets ACTIONS_RESULTS_URL itself
// right before it starts node, so no job-level environment can do this.
package main

import (
	"fmt"
	"net/http"
	"os"
	"strings"
	"syscall"
	"time"
)

const (
	githubResultsURL = "https://results-receiver.actions.githubusercontent.com"
	healthPath       = "/actions-cache/healthz"
	probeTimeout     = 150 * time.Millisecond
)

func main() {
	self, err := os.Executable()
	if err != nil {
		fmt.Fprintf(os.Stderr, "node: %v\n", err)
		os.Exit(127)
	}
	real := self + ".real"
	err = syscall.Exec(real, os.Args, environment(os.Environ(), probe))
	fmt.Fprintf(os.Stderr, "node: %s: %v\n", real, err)
	os.Exit(127)
}

// environment points GitHub's results service at the cache agent when the
// runner set GitHub's own, the job has the agent's address, the job did not
// turn the cache off (TUIST_ACTIONS_CACHE=0 or false) and the agent answered.
// Anything else leaves the environment as the runner made it.
func environment(env []string, healthy func(string) bool) []string {
	index := map[string]int{}
	for i, entry := range env {
		if name, _, ok := strings.Cut(entry, "="); ok {
			index[name] = i
		}
	}
	value := func(name string) string {
		if i, ok := index[name]; ok {
			_, v, _ := strings.Cut(env[i], "=")
			return v
		}
		return ""
	}
	agent := strings.TrimSuffix(value("TUIST_CACHE_VOLUME_URL"), "/")
	switch {
	case strings.TrimSuffix(value("ACTIONS_RESULTS_URL"), "/") != githubResultsURL,
		!strings.HasPrefix(agent, "http://"),
		value("TUIST_ACTIONS_CACHE") == "0", strings.EqualFold(value("TUIST_ACTIONS_CACHE"), "false"),
		!healthy(agent + healthPath):
		return env
	}
	rewritten := append([]string(nil), env...)
	rewritten[index["ACTIONS_RESULTS_URL"]] = "ACTIONS_RESULTS_URL=" + agent + "/"
	return rewritten
}

func probe(url string) bool {
	client := http.Client{Timeout: probeTimeout, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	response, err := client.Get(url)
	if err != nil {
		return false
	}
	response.Body.Close()
	return response.StatusCode == http.StatusOK
}
