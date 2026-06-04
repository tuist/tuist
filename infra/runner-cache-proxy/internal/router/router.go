// Package router decides, per decrypted HTTP request on a MITM'd cache
// connection, whether to send it to the local cache-gateway (with a token
// swap) or to forward it untouched to genuine GitHub. The rule is
// allowlist-based and fails open: only the Twirp CacheService path is
// ever diverted, and only when the breaker permits; everything else goes
// to GitHub with the runner's original token.
package router

import "strings"

// Target is where a request is routed.
type Target int

const (
	// Gateway routes to the local cache-gateway with a swapped token.
	Gateway Target = iota
	// GitHub forwards to genuine GitHub with the original token.
	GitHub
)

func (t Target) String() string {
	if t == Gateway {
		return "gateway"
	}
	return "genuine_github"
}

// CacheServicePrefix is the only path the proxy diverts.
const CacheServicePrefix = "/twirp/github.actions.results.api.v1.CacheService/"

// Route returns the target for a request. breakerAllows reflects backend
// health: when false, even CacheService calls fail open to GitHub.
func Route(path string, breakerAllows bool) Target {
	if breakerAllows && strings.HasPrefix(path, CacheServicePrefix) {
		return Gateway
	}
	// ArtifactService, OIDC, telemetry, unknown paths, or a tripped
	// breaker: forward to genuine GitHub untouched.
	return GitHub
}
