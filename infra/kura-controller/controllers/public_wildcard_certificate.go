package controllers

import (
	"context"
	"fmt"
	"time"

	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// PublicWildcardCertificate keeps the fleet's shared wildcard Certificate in
// the watched namespace. It is a cluster singleton rather than a chart
// resource: `--rollback-on-failure` defaults Helm 4's wait strategy to
// `watcher`, which waits on every resource in a release including custom ones,
// so a Certificate in the chart makes a first issuance slower than the release
// timeout fail the deploy and roll it back. Nothing here can block a deploy.
//
// It is also deliberately not owner-referenced to any KuraInstance. The
// certificate serves every tenant and outlives all of them, so an owner would
// garbage-collect the fleet's TLS when that one account is destroyed.
type PublicWildcardCertificate struct {
	client.Client
	Namespace     string
	SecretName    string
	DNSNames      []string
	ClusterIssuer string
	Interval      time.Duration
}

// Start satisfies manager.Runnable. It requires leader election (the default
// for a runnable added to the manager), so only one replica writes.
func (c *PublicWildcardCertificate) Start(ctx context.Context) error {
	logger := log.FromContext(ctx).WithValues("certificate", c.SecretName)
	interval := c.Interval
	if interval <= 0 {
		interval = 10 * time.Minute
	}

	for {
		if err := c.Ensure(ctx); err != nil {
			logger.Error(err, "ensure shared wildcard certificate")
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(interval):
		}
	}
}

// Ensure creates the Certificate when absent and repairs its spec when it
// drifts. It is never deleted, including when the controller is reconfigured
// without a wildcard: a deploy that momentarily renders no configuration would
// otherwise drop the certificate every tenant is terminating on, and an unused
// Certificate costs one renewal rather than an outage.
func (c *PublicWildcardCertificate) Ensure(ctx context.Context) error {
	if c.SecretName == "" || c.ClusterIssuer == "" || len(c.DNSNames) == 0 {
		return nil
	}

	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	cert.SetName(c.SecretName)
	cert.SetNamespace(c.Namespace)

	result, err := controllerutil.CreateOrUpdate(ctx, c.Client, cert, func() error {
		cert.SetLabels(map[string]string{
			"app.kubernetes.io/name":      "kura",
			"app.kubernetes.io/component": "kura",
		})
		spec := map[string]any{
			"secretName": c.SecretName,
			"dnsNames":   dnsNames(c.DNSNames...),
			"issuerRef": map[string]any{
				"name": c.ClusterIssuer,
				"kind": "ClusterIssuer",
			},
			"privateKey": map[string]any{
				"algorithm":      "ECDSA",
				"size":           int64(256),
				"rotationPolicy": "Always",
			},
		}
		return unstructured.SetNestedField(cert.Object, spec, "spec")
	})
	if err != nil {
		if apierrors.IsNotFound(err) {
			return fmt.Errorf("cert-manager Certificate CRD not installed: %w", err)
		}
		return err
	}
	if result != controllerutil.OperationResultNone {
		log.FromContext(ctx).Info("shared wildcard certificate reconciled", "result", result, "dnsNames", c.DNSNames)
	}
	return nil
}
