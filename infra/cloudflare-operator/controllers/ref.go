package controllers

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
)

// makeRef builds a Cloudflare-safe rule ref that fits its
// `^[a-zA-Z0-9_]{1,32}$` regex. The CR name can contain characters
// Cloudflare rejects (hyphens are common in Kubernetes names), and
// the raw `prefix + name + uid` string can overflow 32 bytes for
// long names — so we hash the CR identity into a fixed-width hex
// suffix. That gives us a deterministic ref that changes only when
// the CR is recreated (uid differs) and never collides in practice.
//
// Layout: <kindPrefix><hash>. kindPrefix is 5–6 bytes, hash is 20
// hex chars → 25–26 bytes total.
func makeRef(kindPrefix, name, uid string) string {
	sum := sha256.Sum256([]byte(name + "|" + uid))
	return kindPrefix + hex.EncodeToString(sum[:10])
}

// String constants callers pass as kindPrefix. Keep short — refs are
// capped at 32 chars total by Cloudflare and the hash suffix eats 20.
const (
	rateLimitRefPrefix = "cfrl_"
	cacheRuleRefPrefix = "cfcr_"
	wafRuleRefPrefix   = "cfwaf_"
)

// sanityRef panics if the produced ref would violate Cloudflare's
// regex. Called in tests to keep the constant refactor honest.
func sanityRef(ref string) error {
	if len(ref) == 0 || len(ref) > 32 {
		return fmt.Errorf("ref %q length %d violates 1..32", ref, len(ref))
	}
	for i := 0; i < len(ref); i++ {
		c := ref[i]
		valid := (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
		if !valid {
			return fmt.Errorf("ref %q contains disallowed character %q", ref, c)
		}
	}
	return nil
}
