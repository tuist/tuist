package controllers

import (
	"context"
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func wildcardCertSubject(t *testing.T, objects ...runtime.Object) *PublicWildcardCertificate {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	builder := fake.NewClientBuilder().WithScheme(scheme)
	for _, o := range objects {
		builder = builder.WithRuntimeObjects(o)
	}
	return &PublicWildcardCertificate{
		Client:        builder.Build(),
		Namespace:     "kura",
		SecretName:    "kura-public-wildcard-tls",
		DNSNames:      []string{"*.kura.tuist.dev"},
		ClusterIssuer: "letsencrypt-cloudflare",
	}
}

func TestPublicWildcardCertificateCreatesUnownedSingleton(t *testing.T) {
	ctx := context.Background()
	c := wildcardCertSubject(t)

	if err := c.Ensure(ctx); err != nil {
		t.Fatal(err)
	}

	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := c.Get(ctx, types.NamespacedName{Name: "kura-public-wildcard-tls", Namespace: "kura"}, cert); err != nil {
		t.Fatalf("expected the shared wildcard Certificate to be created: %v", err)
	}
	if got, _, _ := unstructured.NestedStringSlice(cert.Object, "spec", "dnsNames"); len(got) != 1 || got[0] != "*.kura.tuist.dev" {
		t.Fatalf("expected the wildcard name, got %v", got)
	}
	if got, _, _ := unstructured.NestedString(cert.Object, "spec", "issuerRef", "name"); got != "letsencrypt-cloudflare" {
		t.Fatalf("expected the ClusterIssuer ref, got %q", got)
	}
	// An owner reference would garbage-collect the fleet's certificate when
	// that one account is destroyed.
	if refs := cert.GetOwnerReferences(); len(refs) != 0 {
		t.Fatalf("expected no owner references on the fleet-wide Certificate, got %v", refs)
	}
}

func TestPublicWildcardCertificateRepairsDrift(t *testing.T) {
	ctx := context.Background()
	existing := &unstructured.Unstructured{}
	existing.SetGroupVersionKind(certificateGVK())
	existing.SetName("kura-public-wildcard-tls")
	existing.SetNamespace("kura")
	_ = unstructured.SetNestedField(existing.Object, map[string]any{
		"secretName": "kura-public-wildcard-tls",
		"dnsNames":   []any{"wrong.kura.tuist.dev"},
	}, "spec")

	c := wildcardCertSubject(t, existing)
	if err := c.Ensure(ctx); err != nil {
		t.Fatal(err)
	}

	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := c.Get(ctx, types.NamespacedName{Name: "kura-public-wildcard-tls", Namespace: "kura"}, cert); err != nil {
		t.Fatal(err)
	}
	if got, _, _ := unstructured.NestedStringSlice(cert.Object, "spec", "dnsNames"); len(got) != 1 || got[0] != "*.kura.tuist.dev" {
		t.Fatalf("expected drifted dnsNames to be repaired, got %v", got)
	}
}

func TestPublicWildcardCertificateNoopsWithoutConfiguration(t *testing.T) {
	ctx := context.Background()
	for _, tc := range []struct {
		name   string
		mutate func(*PublicWildcardCertificate)
	}{
		{"no secret name", func(c *PublicWildcardCertificate) { c.SecretName = "" }},
		{"no issuer", func(c *PublicWildcardCertificate) { c.ClusterIssuer = "" }},
		{"no dns names", func(c *PublicWildcardCertificate) { c.DNSNames = nil }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c := wildcardCertSubject(t)
			tc.mutate(c)
			if err := c.Ensure(ctx); err != nil {
				t.Fatal(err)
			}
			list := &unstructured.UnstructuredList{}
			list.SetGroupVersionKind(certificateGVK())
			if err := c.List(ctx, list); err == nil && len(list.Items) != 0 {
				t.Fatalf("expected no Certificate to be written, got %d", len(list.Items))
			}
		})
	}
}

func TestPublicWildcardCertificateKeepsExistingWhenDeconfigured(t *testing.T) {
	ctx := context.Background()
	existing := &unstructured.Unstructured{}
	existing.SetGroupVersionKind(certificateGVK())
	existing.SetName("kura-public-wildcard-tls")
	existing.SetNamespace("kura")
	existing.SetAnnotations(map[string]string{"kept": "true"})

	c := wildcardCertSubject(t, existing)
	c.DNSNames = nil

	if err := c.Ensure(ctx); err != nil {
		t.Fatal(err)
	}

	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := c.Get(ctx, types.NamespacedName{Name: "kura-public-wildcard-tls", Namespace: "kura"}, cert); err != nil {
		t.Fatalf("a deconfigured controller must never delete the certificate the fleet terminates on: %v", err)
	}
}

var _ = metav1.ObjectMeta{}
