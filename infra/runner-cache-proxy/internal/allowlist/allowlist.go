// Package allowlist decides whether a TLS SNI belongs to the GitHub
// Actions cache plane the proxy is allowed to MITM. Anything not on the
// list is spliced through untouched, so the interception surface is
// bounded to GitHub's cache hostnames and unrelated (cert-pinned,
// private) traffic is never decrypted.
package allowlist

import "strings"

// DefaultHosts is the GitHub-Actions cache-coordination SNI allowlist.
//
// Only the Actions results hostnames (which serve the Twirp CacheService)
// are MITM'd. The Azure blob hostname (*.blob.core.windows.net) is
// deliberately NOT here: the gateway mints signed blob URLs pointing at
// its own hostname, so the only time a runner ever talks to Azure blob is
// the fail-open path (coordination forwarded to genuine GitHub), where we
// must pass that blob traffic straight through untouched.
var DefaultHosts = []string{
	"results-receiver.actions.githubusercontent.com",
	"*.actions.githubusercontent.com",
}

// Matcher tests SNIs against an exact set plus suffix wildcards.
type Matcher struct {
	exact    map[string]struct{}
	suffixes []string // each begins with "." (from "*.example.com")
}

// New builds a Matcher from host patterns. A pattern beginning with "*."
// is a suffix wildcard; everything else is an exact host. Matching is
// case-insensitive and tolerant of a trailing dot.
func New(hosts []string) *Matcher {
	m := &Matcher{exact: map[string]struct{}{}}
	for _, h := range hosts {
		h = normalize(h)
		if h == "" {
			continue
		}
		if strings.HasPrefix(h, "*.") {
			m.suffixes = append(m.suffixes, h[1:]) // keep the leading "."
			continue
		}
		m.exact[h] = struct{}{}
	}
	return m
}

// Match reports whether sni is on the allowlist.
func (m *Matcher) Match(sni string) bool {
	h := normalize(sni)
	if h == "" {
		return false
	}
	if _, ok := m.exact[h]; ok {
		return true
	}
	for _, suf := range m.suffixes {
		// "*.example.com" must match "a.example.com" but not "example.com".
		if len(h) > len(suf) && strings.HasSuffix(h, suf) {
			return true
		}
	}
	return false
}

func normalize(h string) string {
	h = strings.TrimSpace(strings.ToLower(h))
	h = strings.TrimSuffix(h, ".")
	return h
}
