package controllers

import (
	"context"
	"fmt"
	"net"
	"sort"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	k8slabels "k8s.io/apimachinery/pkg/labels"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const gatewayClassLabel = "tuist.dev/kura-ingress-class"

// Private instances explicitly opt into a gateway. A leftover PublicHost must
// never turn a legacy private instance into a public endpoint.
func clientHost(instance *kurav1alpha1.KuraInstance) string {
	if !instance.Spec.Private {
		return instance.Spec.PublicHost
	}
	if !instance.Spec.PublicHostNetwork || instance.Spec.IngressClassName == "" || len(instance.Spec.ClientCIDRs) == 0 {
		return ""
	}
	for _, cidr := range instance.Spec.ClientCIDRs {
		if _, _, err := net.ParseCIDR(cidr); err != nil {
			return ""
		}
	}
	return instance.Spec.PrivateHost
}

func clientIngressAnnotations(instance *kurav1alpha1.KuraInstance, annotations map[string]string) map[string]string {
	if instance.Spec.Private {
		annotations["nginx.ingress.kubernetes.io/whitelist-source-range"] = strings.Join(instance.Spec.ClientCIDRs, ",")
	}
	return annotations
}

// Gateway discovery belongs to an ingress class, so accounts share one bounded
// snapshot. DNS answers are per hostname and cached for one record TTL; negative
// answers retry sooner. Nodes and certificates still come from the informer.
const gatewaySnapshotTTL = 30 * time.Second
const clientDNSTTL = 60 * time.Second

type gatewaySnapshot struct {
	pods    []corev1.Pod
	expires time.Time
}
type clientDNSObservation struct {
	target    string
	addresses []string
	expires   time.Time
}
type privateEndpointObservation struct {
	URL     string
	Reason  string
	Message string
}

func (r *KuraInstanceReconciler) gatewayPods(ctx context.Context, class string) ([]corev1.Pod, error) {
	r.gatewayCacheMu.Lock()
	defer r.gatewayCacheMu.Unlock()
	if snapshot, ok := r.gatewayCache[class]; ok && time.Now().Before(snapshot.expires) {
		return snapshot.pods, nil
	}
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	pods := &corev1.PodList{}
	if err := reader.List(ctx, pods, client.InNamespace("platform"), client.MatchingLabels{gatewayClassLabel: class}); err != nil {
		return nil, err
	}
	if r.gatewayCache == nil {
		r.gatewayCache = map[string]gatewaySnapshot{}
	}
	r.gatewayCache[class] = gatewaySnapshot{pods: pods.Items, expires: time.Now().Add(gatewaySnapshotTTL)}
	return pods.Items, nil
}

func (r *KuraInstanceReconciler) readyGatewayNodes(ctx context.Context, instance *kurav1alpha1.KuraInstance) (map[string]string, error) {
	pods, err := r.gatewayPods(ctx, instance.Spec.IngressClassName)
	if err != nil {
		return nil, err
	}
	nodes := map[string]string{}
	for i := range pods {
		pod := &pods[i]
		if !podReady(pod) || !pod.Spec.HostNetwork || pod.Spec.NodeName == "" {
			continue
		}
		node := &corev1.Node{}
		if err := r.Get(ctx, types.NamespacedName{Name: pod.Spec.NodeName}, node); err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return nil, err
		}
		ip := net.ParseIP(node.Labels["tuist.dev/pn-ipv4"])
		if nodeReady(node) && ip.To4() != nil && ip.IsPrivate() && k8slabels.SelectorFromSet(instance.Spec.NodeSelector).Matches(k8slabels.Set(node.Labels)) {
			nodes[node.Name] = ip.String()
		}
	}
	return nodes, nil
}

// Keep an already-published healthy gateway through a primary handover. For
// initial placement prefer the selected primary's node, then choose a stable
// fallback by node name. Pod List order never determines client DNS.
func (r *KuraInstanceReconciler) privateGatewayTarget(ctx context.Context, instance *kurav1alpha1.KuraInstance) (string, error) {
	if clientHost(instance) == "" {
		return "", nil
	}
	nodes, err := r.readyGatewayNodes(ctx, instance)
	if err != nil || len(nodes) == 0 {
		return "", err
	}
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-public-dns"}, endpoint); err != nil {
		if !apierrors.IsNotFound(err) {
			return "", err
		}
	} else {
		records, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
		for _, entry := range records {
			record, ok := entry.(map[string]interface{})
			if !ok || record["dnsName"] != instance.Spec.PrivateHost {
				continue
			}
			targets, _, _ := unstructured.NestedStringSlice(record, "targets")
			for _, target := range targets {
				for _, address := range nodes {
					if address == target {
						return address, nil
					}
				}
			}
		}
	}
	service := &corev1.Service{}
	if err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, service); err != nil {
		if !apierrors.IsNotFound(err) {
			return "", err
		}
	} else if primary := service.Spec.Selector[podNameLabel]; primary != "" {
		pod := &corev1.Pod{}
		if err := r.Get(ctx, types.NamespacedName{Name: primary, Namespace: instance.Namespace}, pod); err != nil {
			if !apierrors.IsNotFound(err) {
				return "", err
			}
		} else if address := nodes[pod.Spec.NodeName]; address != "" {
			return address, nil
		}
	}
	names := make([]string, 0, len(nodes))
	for name := range nodes {
		names = append(names, name)
	}
	sort.Strings(names)
	return nodes[names[0]], nil
}

func (r *KuraInstanceReconciler) privateDNSAddresses(ctx context.Context, host, target string) []string {
	r.gatewayCacheMu.Lock()
	cached, found := r.clientDNSCache[host]
	r.gatewayCacheMu.Unlock()
	if found && cached.target == target && time.Now().Before(cached.expires) {
		return cached.addresses
	}
	resolver := r.PeerDNSResolver
	if resolver == nil {
		resolver = netPeerDNSResolver{}
	}
	lookupCtx, cancel := context.WithTimeout(ctx, 2*time.Second)
	defer cancel()
	addresses, err := resolver.LookupHost(lookupCtx, host)
	ttl := clientDNSTTL
	if err != nil || len(addresses) == 0 {
		addresses = nil
		ttl = 5 * time.Second
	}
	for _, address := range addresses {
		if address != target {
			ttl = 5 * time.Second
			break
		}
	}
	r.gatewayCacheMu.Lock()
	defer r.gatewayCacheMu.Unlock()
	if r.clientDNSCache == nil {
		r.clientDNSCache = map[string]clientDNSObservation{}
	}
	for name, observation := range r.clientDNSCache {
		if time.Now().After(observation.expires) {
			delete(r.clientDNSCache, name)
		}
	}
	r.clientDNSCache[host] = clientDNSObservation{target: target, addresses: addresses, expires: time.Now().Add(ttl)}
	return addresses
}

func (r *KuraInstanceReconciler) privateGatewayStatus(ctx context.Context, instance *kurav1alpha1.KuraInstance, primary string, pods []corev1.Pod, samples map[string]runtimeStatus) (privateEndpointObservation, error) {
	pending := func(reason, message string) (privateEndpointObservation, error) {
		return privateEndpointObservation{Reason: reason, Message: message}, nil
	}
	host := clientHost(instance)
	if !instance.Spec.Private || instance.Spec.PrivateHost == "" {
		return pending("Disabled", "No private gateway configured")
	}
	if host == "" {
		return pending("InvalidConfiguration", "Private gateway requires a host-network ingress class and valid nonempty clientCIDRs")
	}
	status, fresh := samples[primary]
	if !fresh {
		return pending("PrimaryStatusUnavailable", "No fresh runtime sample for the selected primary")
	}
	// Availability differs from promotion suitability. A serving primary remains
	// available with one ring member while its sibling rolls or refills.
	ready := false
	for i := range pods {
		if pods[i].Name == primary {
			ready = podReady(&pods[i])
			break
		}
	}
	if !ready || !runtimeStatusServing(status) {
		return pending("PrimaryUnavailable", "Selected primary is not Ready and serving with its writer lock")
	}
	// A host the shared wildcard spans has no certificate of its own to read,
	// because none is minted for it. Coverage is established there against the
	// issued leaf itself, which is the same guarantee this branch reaches by
	// requiring Ready plus the host in dnsNames.
	if !r.sharedPublicTLSCovers(ctx, instance) {
		cert := &unstructured.Unstructured{}
		cert.SetGroupVersionKind(certificateGVK())
		if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: publicTLSSecretName(instance)}, cert); err != nil {
			if apierrors.IsNotFound(err) {
				return pending("CertificatePending", "Gateway certificate has not been created")
			}
			return privateEndpointObservation{}, err
		}
		conditions, _, _ := unstructured.NestedSlice(cert.Object, "status", "conditions")
		ready = false
		for _, entry := range conditions {
			condition, ok := entry.(map[string]interface{})
			if !ok || condition["type"] != "Ready" || condition["status"] != "True" {
				continue
			}
			// cert-manager permits an absent observedGeneration. An explicit stale
			// generation is never accepted; the certificate must name the current host.
			generation, observed := condition["observedGeneration"]
			if !observed || generation == cert.GetGeneration() {
				ready = true
			}
		}
		hosts, _, _ := unstructured.NestedStringSlice(cert.Object, "spec", "dnsNames")
		hostCovered := false
		for _, name := range hosts {
			if name == host {
				hostCovered = true
			}
		}
		if !ready || !hostCovered {
			return pending("CertificatePending", "Certificate is not Ready for the current hostname and generation")
		}
	}
	target, err := r.privateGatewayTarget(ctx, instance)
	if err != nil {
		return privateEndpointObservation{}, err
	}
	if target == "" {
		return pending("GatewayUnavailable", "No Ready gateway with a private IPv4 address in the instance node pool")
	}
	addresses := r.privateDNSAddresses(ctx, host, target)
	if len(addresses) == 0 {
		return pending("DNSPending", fmt.Sprintf("Waiting for %s to resolve to %s", host, target))
	}
	for _, address := range addresses {
		if address != target {
			return pending("DNSPending", fmt.Sprintf("Expected only %s; observed %v", target, addresses))
		}
	}
	return privateEndpointObservation{URL: "https://" + host, Reason: "Ready", Message: "Private gateway, certificate, DNS and serving primary are ready"}, nil
}

// This observation is independent of workload convergence. Run it after client
// routing and before storage maintenance can return early; patch only its fields
// so workload status retains its own meaning and timestamp.
func (r *KuraInstanceReconciler) observePrivateEndpoint(ctx context.Context, instance *kurav1alpha1.KuraInstance, primary string, pods []corev1.Pod, samples map[string]runtimeStatus) error {
	if instance.Spec.PrivateHost == "" && instance.Status.PrivateURL == "" {
		return nil
	}
	observation, err := r.privateGatewayStatus(ctx, instance, primary, pods, samples)
	if err != nil {
		observation = privateEndpointObservation{Reason: "ObservationFailed", Message: err.Error()}
	}
	before := instance.DeepCopy()
	now := metav1.Now()
	instance.Status.PrivateURL = observation.URL
	instance.Status.EndpointReason = observation.Reason
	instance.Status.EndpointMessage = observation.Message
	instance.Status.EndpointObservedGeneration = instance.Generation
	instance.Status.EndpointLastCheckedAt = &now
	if patchErr := r.Status().Patch(ctx, instance, client.MergeFrom(before)); patchErr != nil {
		return patchErr
	}
	return err
}
