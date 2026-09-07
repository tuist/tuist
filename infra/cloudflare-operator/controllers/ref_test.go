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
// into CI using the exact sample-CR name we ship.
func TestRuleRefsAreCloudflareValid(t *testing.T) {
	sampleNames := []string{
		"public-pages-anti-bombardment", // config/samples/public-pages-rate-limit.yaml
	}
	uid := types.UID("11111111-2222-3333-4444-555555555555")

	for _, name := range sampleNames {
		om := metav1.ObjectMeta{Name: name, UID: uid}
		rl := &cfv1alpha1.CloudflareRateLimit{ObjectMeta: om}
		if err := sanityRef(ruleRef(rl)); err != nil {
			t.Errorf("rate limit ref for %q: %v", name, err)
		}
	}
}

func TestRefDeterministic(t *testing.T) {
	a := makeRef(rateLimitRefPrefix, "public-pages", "abc-uid")
	b := makeRef(rateLimitRefPrefix, "public-pages", "abc-uid")
	if a != b {
		t.Fatalf("makeRef not deterministic: %q vs %q", a, b)
	}
}

func TestRefChangesOnUIDChange(t *testing.T) {
	a := makeRef(rateLimitRefPrefix, "public-pages", "uid-one")
	b := makeRef(rateLimitRefPrefix, "public-pages", "uid-two")
	if a == b {
		t.Fatal("makeRef must vary with UID")
	}
}
