package controllers

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// Record returns the provider's actual regional record, never Kubernetes intent.
// A missing record and a failed observation must remain distinguishable.
type StableDNSProvider interface {
	EnsureHealthCheck(context.Context, string) (string, error)
	Record(context.Context, string, string) (*StableDNSRecord, error)
}

type StableDNSRecord struct{ Target, AWSRegion, HealthCheckID string }
type StableHostProber interface {
	Probe(context.Context, string, string) error
}
type httpsStableHostProber struct{}

func (httpsStableHostProber) Probe(ctx context.Context, host, target string) error {
	transport := &http.Transport{
		Proxy:           nil,
		TLSClientConfig: &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12},
		DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, "tcp", net.JoinHostPort(target, "443"))
		},
	}
	defer transport.CloseIdleConnections()
	client := &http.Client{Transport: transport, Timeout: 2 * time.Second,
		CheckRedirect: func(_ *http.Request, _ []*http.Request) error { return http.ErrUseLastResponse }}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, "https://"+host+"/ready", nil)
	if err != nil {
		return err
	}
	response, err := client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("stable gateway returned %d", response.StatusCode)
	}
	return nil
}

func stableAdvertising(instance *kurav1alpha1.KuraInstance) bool {
	if instance.Spec.Private || !instance.Spec.PublicHostNetwork || instance.Spec.PublicHost == "" ||
		!instance.Spec.StableAdvertise || instance.Spec.StableHost == "" || instance.Spec.StableAWSRegion == "" || !instance.DeletionTimestamp.IsZero() {
		return false
	}
	state := instance.Status.StableEndpoint
	return state == nil || (state.Host == instance.Spec.StableHost && state.SetIdentifier == instance.Spec.Region && state.AWSRegion == instance.Spec.StableAWSRegion)
}

func stableClientHosts(instance *kurav1alpha1.KuraInstance) []string {
	hosts := []string{clientHost(instance)}
	if instance.Spec.Private {
		return hosts
	}
	host := instance.Spec.StableHost
	// Persisted identity wins during disable/rename so cached answers keep routing.
	if state := instance.Status.StableEndpoint; state != nil {
		host = state.Host
	}
	if host != "" && host != hosts[0] {
		hosts = append(hosts, host)
	}
	return hosts
}

func stableDNSEndpoint(instance *kurav1alpha1.KuraInstance) *unstructured.Unstructured {
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	endpoint.SetNamespace(instance.Namespace)
	endpoint.SetName(instance.Name + "-stable-dns")
	return endpoint
}

func (r *KuraInstanceReconciler) saveStableEndpoint(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	state := instance.Status.StableEndpoint
	err := r.Status().Update(ctx, instance)
	if err == nil {
		instance.Status.StableEndpoint = state
	}
	return err
}

func (r *KuraInstanceReconciler) reconcileStableEndpoint(ctx context.Context, instance *kurav1alpha1.KuraInstance, primary string, pods []corev1.Pod, samples map[string]runtimeStatus) (reconcileErr error) {
	if !stableAdvertising(instance) {
		return nil
	}
	if !validStableHost(instance.Spec.StableHost) {
		return fmt.Errorf("invalid stable hostname")
	}
	if r.StableDNS == nil {
		return fmt.Errorf("stable DNS configured without a Route53 provider")
	}
	parentCtx := ctx
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	state := instance.Status.StableEndpoint
	newIdentity := state == nil
	if state == nil {
		state = &kurav1alpha1.StableEndpointStatus{Host: instance.Spec.StableHost, SetIdentifier: instance.Spec.Region, AWSRegion: instance.Spec.StableAWSRegion}
		instance.Status.StableEndpoint = state
	}
	state.Ready = false
	state.ObservedGeneration = instance.Generation
	state.LastCheckedAt = time.Now().UTC().Format(time.RFC3339)
	state.WithdrawnAt = ""
	if newIdentity {
		// Persist identity before creating anything that can send traffic here.
		if err := r.saveStableEndpoint(ctx, instance); err != nil {
			return err
		}
	}
	// Readers must see a completed observation, not a transient false result on
	// every healthy pass. Persist failures too, even if the probe deadline expired.
	defer func() {
		statusCtx, statusCancel := context.WithTimeout(parentCtx, 5*time.Second)
		defer statusCancel()
		reconcileErr = errors.Join(reconcileErr, r.saveStableEndpoint(statusCtx, instance))
	}()
	target, err := r.instanceNodeIP(ctx, instance, primary)
	if err != nil {
		return err
	}
	ready := false
	for i := range pods {
		if pods[i].Name == primary {
			ready = podReady(&pods[i])
		}
	}
	sample, sampled := samples[primary]
	if !ready || !sampled || !runtimeStatusServing(sample) || net.ParseIP(target).To4() == nil {
		return nil
	}
	prober := r.StableProbe
	if prober == nil {
		prober = httpsStableHostProber{}
	}
	// Direct box connection with real SNI and certificate verification proves
	// nginx has loaded the host. No DNS dependency before initial advertising.
	if err := prober.Probe(ctx, state.Host, target); err != nil {
		return nil
	}
	if state.Target != target || state.HealthCheckID == "" {
		// Only check creation and its durable claim serialize with garbage
		// collection. Gateway probes and steady-state provider reads run concurrently.
		if err := func() error {
			r.stableDNSMu.Lock()
			defer r.stableDNSMu.Unlock()
			healthID, err := r.StableDNS.EnsureHealthCheck(ctx, target)
			if err != nil {
				return err
			}
			state.Target, state.HealthCheckID = target, healthID
			return r.saveStableEndpoint(ctx, instance)
		}(); err != nil {
			return err
		}
	}

	endpoint := stableDNSEndpoint(instance)
	_, err = controllerutil.CreateOrUpdate(ctx, r.Client, endpoint, func() error {
		endpoint.SetLabels(labels(instance))
		endpoint.Object["spec"] = map[string]interface{}{"endpoints": []interface{}{map[string]interface{}{
			"dnsName": state.Host, "recordType": "A", "recordTTL": int64(60),
			"setIdentifier": state.SetIdentifier, "targets": []interface{}{state.Target},
			"providerSpecific": []interface{}{
				map[string]interface{}{"name": "aws/region", "value": state.AWSRegion},
				map[string]interface{}{"name": "aws/health-check-id", "value": state.HealthCheckID},
			},
		}}}
		return controllerutil.SetControllerReference(instance, endpoint, r.Scheme)
	})
	if err != nil {
		return err
	}
	record, err := r.StableDNS.Record(ctx, state.Host, state.SetIdentifier)
	if err != nil {
		return err
	}
	state.Ready = record != nil && record.Target == target && record.AWSRegion == state.AWSRegion && record.HealthCheckID == state.HealthCheckID
	return nil
}

// Every removal path (retirement, flag rollback, rename and CR deletion) uses
// this barrier. A stalled external-dns or failed AWS read extends serving.
func (r *KuraInstanceReconciler) withdrawStableEndpoint(ctx context.Context, instance *kurav1alpha1.KuraInstance) (bool, error) {
	state := instance.Status.StableEndpoint
	if state == nil {
		return true, nil
	}
	// The target is persisted before a DNS source can be created. An identity
	// that never reached that point cannot have sent traffic to this gateway.
	if state.Target == "" {
		instance.Status.StableEndpoint = nil
		return true, r.saveStableEndpoint(ctx, instance)
	}
	if r.StableDNS == nil {
		return false, fmt.Errorf("cannot confirm stable DNS withdrawal without Route53")
	}
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	state.Ready = false
	state.LastCheckedAt = time.Now().UTC().Format(time.RFC3339)
	if err := r.saveStableEndpoint(ctx, instance); err != nil {
		return false, err
	}
	if err := r.Delete(ctx, stableDNSEndpoint(instance)); err != nil && !apierrors.IsNotFound(err) {
		return false, err
	}
	record, err := r.StableDNS.Record(ctx, state.Host, state.SetIdentifier)
	if err != nil {
		return false, err
	}
	if record != nil {
		state.WithdrawnAt = ""
		return false, r.saveStableEndpoint(ctx, instance)
	}
	now := time.Now().UTC()
	withdrawn, err := time.Parse(time.RFC3339, state.WithdrawnAt)
	if err != nil {
		state.WithdrawnAt = now.Format(time.RFC3339)
		return false, r.saveStableEndpoint(ctx, instance)
	}
	drain := r.StableDrain
	if drain <= 0 {
		drain = 3720 * time.Second
	}
	if now.Sub(withdrawn) < drain {
		return false, nil
	}
	instance.Status.StableEndpoint = nil
	return true, r.saveStableEndpoint(ctx, instance)
}

// Keep names inside the delegated zone and within one label. The server also
// rejects environment-suffixed handles; this check guards direct CR authors.
func validStableHost(host string) bool {
	label, ok := strings.CutSuffix(host, ".cache.tuist.dev")
	return ok && label != "" && !strings.Contains(label, ".") && len(label) <= 63
}
