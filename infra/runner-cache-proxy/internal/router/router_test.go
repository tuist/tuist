package router

import (
	"testing"
	"time"
)

func TestRoute(t *testing.T) {
	cases := []struct {
		name          string
		path          string
		breakerAllows bool
		want          Target
	}{
		{"cache service to gateway", CacheServicePrefix + "GetCacheEntryDownloadURL", true, Gateway},
		{"cache service create", CacheServicePrefix + "CreateCacheEntry", true, Gateway},
		{"artifact service to github", "/twirp/github.actions.results.api.v1.ArtifactService/CreateArtifact", true, GitHub},
		{"oidc to github", "/actions/oidc/token", true, GitHub},
		{"telemetry to github", "/telemetry", true, GitHub},
		{"unknown path to github", "/something/else", true, GitHub},
		{"cache service fails open when breaker open", CacheServicePrefix + "CreateCacheEntry", false, GitHub},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := Route(tc.path, tc.breakerAllows); got != tc.want {
				t.Errorf("Route(%q, %v) = %v, want %v", tc.path, tc.breakerAllows, got, tc.want)
			}
		})
	}
}

func TestDecisionCacheStickiness(t *testing.T) {
	now := time.Unix(0, 0)
	c := NewDecisionCache(time.Minute)
	c.now = func() time.Time { return now }

	calls := 0
	compute := func() Target { calls++; return Gateway }

	if c.Resolve("ip|sni", compute) != Gateway || calls != 1 {
		t.Fatal("first resolve should compute")
	}
	// Even if the underlying decision would change, the cached one sticks.
	if c.Resolve("ip|sni", func() Target { return GitHub }) != Gateway || calls != 1 {
		t.Fatal("second resolve should return the cached decision")
	}
	// A different key is independent.
	if c.Resolve("other|sni", func() Target { return GitHub }) != GitHub {
		t.Fatal("distinct key should compute independently")
	}
	// After TTL it recomputes.
	now = now.Add(2 * time.Minute)
	if c.Resolve("ip|sni", func() Target { return GitHub }) != GitHub {
		t.Fatal("expired entry should recompute")
	}
}
