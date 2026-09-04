package controllers

import (
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
)

// TestRuleRefsAreCloudflareValid guards against a regression where
// a ref would be rejected by Cloudflare's `^[a-zA-Z0-9_]{1,32}$`
// constraint. Prior implementations concatenated the hyphenated CR
// name and overflowed the length; this test bakes the requirement
// into CI using the exact sample-CR names we ship.
func TestRuleRefsAreCloudflareValid(t *testing.T) {
	sampleNames := []string{
		"public-pages-anti-bombardment", // config/samples/public-pages-rate-limit.yaml
		"marketing-and-docs",            // config/samples/marketing-cache-rule.yaml
		"open-graph-images",             // config/samples/og-images-cache-rule.yaml
		"auth-form-managed-challenge",   // config/samples/auth-managed-challenge.yaml
	}
	uid := types.UID("11111111-2222-3333-4444-555555555555")

	for _, name := range sampleNames {
		om := metav1.ObjectMeta{Name: name, UID: uid}

		rl := &cfv1alpha1.CloudflareRateLimit{ObjectMeta: om}
		if err := sanityRef(ruleRef(rl)); err != nil {
			t.Errorf("rate limit ref for %q: %v", name, err)
		}

		cr := &cfv1alpha1.CloudflareCacheRule{ObjectMeta: om}
		if err := sanityRef(cacheRuleRef(cr)); err != nil {
			t.Errorf("cache rule ref for %q: %v", name, err)
		}

		waf := &cfv1alpha1.CloudflareWAFCustomRule{ObjectMeta: om}
		if err := sanityRef(wafRuleRef(waf)); err != nil {
			t.Errorf("WAF ref for %q: %v", name, err)
		}
	}
}

// TestRefDeterministic proves the same (name, uid) always yields the
// same ref — the reconciler relies on this to find its rule across
// pod restarts without a state backend.
func TestRefDeterministic(t *testing.T) {
	a := makeRef(rateLimitRefPrefix, "public-pages", "abc-uid")
	b := makeRef(rateLimitRefPrefix, "public-pages", "abc-uid")
	if a != b {
		t.Fatalf("makeRef not deterministic: %q vs %q", a, b)
	}
}

// TestRefChangesOnUIDChange guards the "delete + recreate under same
// name" case: the new CR has a fresh UID and must produce a fresh ref
// so the reconciler creates a new rule rather than adopting the old
// one that might have been left behind.
func TestRefChangesOnUIDChange(t *testing.T) {
	a := makeRef(rateLimitRefPrefix, "public-pages", "uid-one")
	b := makeRef(rateLimitRefPrefix, "public-pages", "uid-two")
	if a == b {
		t.Fatal("makeRef must vary with UID")
	}
}
