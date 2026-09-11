package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"sort"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/validation"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	regionalPublicHostAnnotation = "kura.tuist.dev/regional-public-host"
	regionalPeerHostAnnotation   = "kura.tuist.dev/regional-peer-host"
	legacyPublicHostsAnnotation  = "kura.tuist.dev/legacy-public-hosts"
	legacyPeerHostsAnnotation    = "kura.tuist.dev/legacy-peer-hosts"
)

// RegionalRouting identifies an existing host-network ingress, independently
// of the nodes on which any account's cache pods happen to be placed.
type RegionalRouting struct {
	Region           string `json:"region"`
	Domain           string `json:"domain"`
	IngressClass     string `json:"ingressClass"`
	IngressNamespace string `json:"ingressNamespace"`
	IngressDaemonSet string `json:"ingressDaemonSet"`
}

func ParseRegionalRouting(value string) ([]RegionalRouting, error) {
	var regions []RegionalRouting
	if value == "" {
		return regions, nil
	}
	if err := json.Unmarshal([]byte(value), &regions); err != nil {
		return nil, err
	}
	seenRegions, seenDomains := map[string]bool{}, map[string]bool{}
	for _, region := range regions {
		if len(validation.IsDNS1123Label(region.Region)) != 0 || len(dnsNameValidationErrors(region.Domain)) != 0 || len(region.Domain) > 184 || !strings.Contains(region.Domain, ".") ||
			len(validation.IsDNS1123Label(region.IngressNamespace)) != 0 || len(validation.IsDNS1123Subdomain(region.IngressDaemonSet)) != 0 ||
			len(validation.IsDNS1123Subdomain(region.IngressClass)) != 0 || seenRegions[region.Region] || seenDomains[region.Domain] {
			return nil, fmt.Errorf("invalid or duplicate regional routing configuration: %q", region.Region)
		}
		for domain := range seenDomains {
			if strings.HasSuffix(region.Domain, "."+domain) || strings.HasSuffix(domain, "."+region.Domain) {
				return nil, fmt.Errorf("overlapping regional DNS domains: %q and %q", domain, region.Domain)
			}
		}
		seenRegions[region.Region], seenDomains[region.Domain] = true, true
	}
	return regions, nil
}

func regionalDNSName(region string) string { return "kura-regional-" + region + "-dns" }

// RegionalDNS owns one DNSEndpoint per configured region, never per account.
// Direct reads allow observing ingress pods outside the instance cache's
// namespace. API failures preserve the last published state; a successful
// observation with no ready ingress withdraws that plane's addresses.
type RegionalDNS struct {
	client.Client
	APIReader client.Reader
	Namespace string
	Regions   []RegionalRouting
}

func (r *RegionalDNS) NeedLeaderElection() bool { return true }

func (r *RegionalDNS) Start(ctx context.Context) error {
	for {
		for _, region := range r.Regions {
			readCtx, cancel := context.WithTimeout(ctx, 20*time.Second)
			err := r.Ensure(readCtx, region)
			cancel()
			if err != nil {
				log.FromContext(ctx).Error(err, "reconcile regional Kura DNS", "region", region.Region)
			}
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(30 * time.Second):
		}
	}
}

func (r *RegionalDNS) Ensure(ctx context.Context, region RegionalRouting) error {
	public, err := r.readyDaemonSetAddresses(ctx, region.IngressNamespace, region.IngressDaemonSet)
	if err != nil {
		return err
	}
	peer, err := r.readyDaemonSetAddresses(ctx, r.Namespace, peerDemuxName(region.Region))
	if err != nil {
		return err
	}
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	endpoint.SetName(regionalDNSName(region.Region))
	endpoint.SetNamespace(r.Namespace)
	_, err = controllerutil.CreateOrUpdate(ctx, r.Client, endpoint, func() error {
		endpoint.SetLabels(map[string]string{"app.kubernetes.io/managed-by": "kura-controller", "tuist.dev/region": region.Region})
		records := append(addressRecords("*."+region.Domain, public), addressRecords("*.peer."+region.Domain, peer)...)
		// The peer wildcard makes peer.<domain> an existing DNS node, which
		// suppresses *.domain synthesis for the account literally named peer.
		// Give that shared namespace node the public ingress addresses too.
		records = append(records, addressRecords("peer."+region.Domain, public)...)
		return unstructured.SetNestedSlice(endpoint.Object, records, "spec", "endpoints")
	})
	return err
}

func (r *RegionalDNS) readyDaemonSetAddresses(ctx context.Context, namespace, name string) ([]string, error) {
	ds := &appsv1.DaemonSet{}
	if err := r.APIReader.Get(ctx, types.NamespacedName{Namespace: namespace, Name: name}, ds); err != nil {
		return nil, fmt.Errorf("read ingress DaemonSet %s/%s: %w", namespace, name, err)
	}
	if !ds.Spec.Template.Spec.HostNetwork || ds.Spec.Selector == nil {
		return nil, fmt.Errorf("%s/%s must be a host-network DaemonSet with a selector", namespace, name)
	}
	selector, err := metav1.LabelSelectorAsSelector(ds.Spec.Selector)
	if err != nil {
		return nil, err
	}
	var pods corev1.PodList
	if err := r.APIReader.List(ctx, &pods, client.InNamespace(namespace), client.MatchingLabelsSelector{Selector: selector}); err != nil {
		return nil, err
	}
	addresses := []string{}
	for _, pod := range pods.Items {
		owner := metav1.GetControllerOf(&pod)
		if owner == nil || owner.UID != ds.UID || !pod.Spec.HostNetwork || !pod.DeletionTimestamp.IsZero() || !podReady(&pod) || pod.Spec.NodeName == "" {
			continue
		}
		var node corev1.Node
		if err := r.APIReader.Get(ctx, types.NamespacedName{Name: pod.Spec.NodeName}, &node); err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return nil, err
		}
		if !nodeReady(&node) || !node.DeletionTimestamp.IsZero() || node.Spec.Unschedulable || node.Annotations[EvacuateNodeAnnotation] != "" {
			continue
		}
		// On these bare-metal pools InternalIP is public. Prefer an explicit
		// ExternalIP when the provider publishes one; never publish private IPs.
		families := map[bool]bool{}
		for _, kind := range []corev1.NodeAddressType{corev1.NodeExternalIP, corev1.NodeInternalIP} {
			found := map[bool]bool{}
			for _, address := range node.Status.Addresses {
				ip := net.ParseIP(address.Address)
				if address.Type == kind && publicIngressIP(ip) && !families[ip.To4() != nil] {
					addresses = append(addresses, ip.String())
					found[ip.To4() != nil] = true
				}
			}
			for family := range found {
				families[family] = true
			}
		}
	}
	return uniqueHosts(addresses), nil
}

func publicIngressIP(ip net.IP) bool {
	if ip == nil || !ip.IsGlobalUnicast() || ip.IsPrivate() {
		return false
	}
	// net.IP.IsPrivate only includes RFC 1918 and ULA, not shared CGNAT space.
	v4 := ip.To4()
	return v4 == nil || !(v4[0] == 100 && v4[1] >= 64 && v4[1] <= 127)
}

func addressRecords(host string, addresses []string) []interface{} {
	records := []interface{}{}
	for _, recordType := range []string{"A", "AAAA"} {
		targets := []interface{}{}
		for _, address := range addresses {
			ip := net.ParseIP(address)
			if ip != nil && (ip.To4() != nil) == (recordType == "A") {
				targets = append(targets, address)
			}
		}
		if len(targets) > 0 {
			records = append(records, map[string]interface{}{"dnsName": host, "recordType": recordType, "recordTTL": int64(60), "targets": targets})
		}
	}
	return records
}

func (r *KuraInstanceReconciler) regionalRouting(instance *kurav1alpha1.KuraInstance) *RegionalRouting {
	if instance.Spec.Private || !instance.Spec.PublicHostNetwork {
		return nil
	}
	for i := range r.RegionalRouting {
		region := &r.RegionalRouting[i]
		if region.Region == instance.Spec.Region && region.IngressClass == ingressClassName(instance) {
			return region
		}
	}
	return nil
}

// Capture legacy names before rewriting ingress or DNS. Persisting them on
// the instance keeps compatibility across controller restarts and server
// manifest updates. New instances with regional names acquire no legacy names.
func (r *KuraInstanceReconciler) prepareRegionalRouting(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	region := r.regionalRouting(instance)
	if region == nil {
		return nil
	}
	if len(validation.IsDNS1123Label(instance.Spec.AccountHandle)) != 0 {
		return fmt.Errorf("invalid regional account DNS label")
	}
	for _, key := range []string{legacyPublicHostsAnnotation, legacyPeerHostsAnnotation} {
		if _, err := parseAnnotationHosts(instance, key); err != nil {
			return err
		}
	}
	before := instance.DeepCopy()
	if instance.Annotations == nil {
		instance.Annotations = map[string]string{}
	}
	publicHost := instance.Spec.AccountHandle + "." + region.Domain
	peerHost := instance.Spec.AccountHandle + ".peer." + region.Domain
	instance.Annotations[regionalPublicHostAnnotation] = publicHost
	if instance.Spec.MeshPeerHostNetwork && instance.Spec.MeshPublicPeerHost != "" {
		instance.Annotations[regionalPeerHostAnnotation] = peerHost
	}
	for _, plane := range []struct{ suffix, current, canonical, annotation string }{
		{"public", instance.Spec.PublicHost, publicHost, legacyPublicHostsAnnotation},
		{"peer", instance.Spec.MeshPublicPeerHost, peerHost, legacyPeerHostsAnnotation},
	} {
		hosts := annotationHosts(instance, plane.annotation)
		if plane.current != "" && plane.current != plane.canonical {
			hosts = append(hosts, plane.current)
		}
		// Publication rollback can introduce a legacy spec host even for an
		// account created with a regional URL. Always preserve the current
		// spec, but never rediscover explicitly retired aliases from resources.
		if _, initialized := before.Annotations[plane.annotation]; initialized {
			encoded, _ := json.Marshal(uniqueHosts(hosts))
			instance.Annotations[plane.annotation] = string(encoded)
			continue
		}
		endpoint := &unstructured.Unstructured{}
		endpoint.SetGroupVersionKind(dnsEndpointGVK)
		if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name + "-" + plane.suffix + "-dns"}, endpoint); err != nil {
			if !apierrors.IsNotFound(err) {
				return err
			}
		} else {
			records, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
			for _, record := range records {
				if record, ok := record.(map[string]interface{}); ok {
					if host, ok := record["dnsName"].(string); ok && host != plane.canonical {
						hosts = append(hosts, host)
					}
				}
			}
		}
		if plane.suffix == "public" {
			var ingress networkingv1.Ingress
			if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: instance.Name}, &ingress); err == nil {
				for _, rule := range ingress.Spec.Rules {
					if rule.Host != plane.canonical {
						hosts = append(hosts, rule.Host)
					}
				}
			} else if !apierrors.IsNotFound(err) {
				return err
			}
		}
		encoded, _ := json.Marshal(uniqueHosts(hosts))
		instance.Annotations[plane.annotation] = string(encoded)
	}
	if !stringMapEqual(before.Annotations, instance.Annotations) {
		if err := r.Patch(ctx, instance, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	return nil
}

func dnsNameValidationErrors(host string) []string {
	errors := validation.IsDNS1123Subdomain(host)
	for _, label := range strings.Split(host, ".") {
		if len(label) > 63 {
			return append(errors, "DNS labels must be at most 63 characters")
		}
	}
	return errors
}

func parseAnnotationHosts(instance *kurav1alpha1.KuraInstance, key string) ([]string, error) {
	value, present := instance.Annotations[key]
	if !present {
		return nil, nil
	}
	var hosts []string
	if err := json.Unmarshal([]byte(value), &hosts); err != nil || hosts == nil {
		return nil, fmt.Errorf("%s/%s annotation %s must be a JSON array of DNS names; refusing to retire aliases", instance.Namespace, instance.Name, key)
	}
	for _, host := range hosts {
		if len(dnsNameValidationErrors(host)) != 0 {
			return nil, fmt.Errorf("%s/%s annotation %s contains an invalid DNS name", instance.Namespace, instance.Name, key)
		}
	}
	return uniqueHosts(hosts), nil
}

// Mutating reconciliation paths validate annotations before consuming them.
func annotationHosts(instance *kurav1alpha1.KuraInstance, key string) []string {
	hosts, _ := parseAnnotationHosts(instance, key)
	return hosts
}

func uniqueHosts(hosts []string) []string {
	seen := map[string]bool{}
	result := []string{}
	for _, host := range hosts {
		if host != "" && !seen[host] {
			seen[host] = true
			result = append(result, host)
		}
	}
	sort.Strings(result)
	return result
}

// Only public route/certificate mutations wait for coverage. Backend Services,
// storage, pod templates, evacuation and status must continue reconciling.
func (r *KuraInstanceReconciler) regionalPublicTLSMissing(ctx context.Context, instance *kurav1alpha1.KuraInstance) bool {
	region := r.regionalRouting(instance)
	return region != nil && instance.Spec.PublicHost == instance.Spec.AccountHandle+"."+region.Domain &&
		!r.sharedPublicTLSCoversHost(ctx, instance.Namespace, instance.Spec.PublicHost)
}

func (r *KuraInstanceReconciler) publicHosts(ctx context.Context, instance *kurav1alpha1.KuraInstance) []string {
	if instance.Spec.Private {
		return uniqueHosts([]string{clientHost(instance)})
	}
	hosts := append([]string{instance.Spec.PublicHost}, annotationHosts(instance, legacyPublicHostsAnnotation)...)
	if host := instance.Annotations[regionalPublicHostAnnotation]; host != "" && r.sharedPublicTLSCoversHost(ctx, instance.Namespace, host) {
		hosts = append(hosts, host)
	}
	return uniqueHosts(hosts)
}

func publicPeerHosts(instance *kurav1alpha1.KuraInstance) []string {
	if instance.Spec.MeshPublicPeerHost == "" {
		return nil
	}
	return uniqueHosts(append([]string{instance.Spec.MeshPublicPeerHost, instance.Annotations[regionalPeerHostAnnotation]}, annotationHosts(instance, legacyPeerHostsAnnotation)...))
}

// Continue any in-flight LoadBalancer retirement against the original host and
// original per-instance DNS target. Regional targets take over only after that
// state machine has observed cutover, drained caches and deleted the fallback.
func (r *KuraInstanceReconciler) pendingLegacyPeerInstance(ctx context.Context, instance *kurav1alpha1.KuraInstance) (*kurav1alpha1.KuraInstance, error) {
	service := &corev1.Service{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: legacyAccountPublicPeerServiceName(instance)}, service); err != nil {
		return nil, client.IgnoreNotFound(err)
	}
	if !legacyAccountPublicPeerService(instance, service) {
		return nil, nil
	}
	if _, err := parseAnnotationHosts(instance, legacyPeerHostsAnnotation); err != nil {
		return nil, err
	}
	for _, host := range publicPeerHosts(instance) {
		if legacyPeerServiceMatchesHost(service, host) {
			legacy := instance.DeepCopy()
			legacy.Spec.MeshPublicPeerHost = host
			return legacy, nil
		}
	}
	return nil, nil
}

func (r *KuraInstanceReconciler) reconcileRegionalLegacyDNS(ctx context.Context, instance *kurav1alpha1.KuraInstance, region *RegionalRouting, peer bool) error {
	suffix, annotation, wildcard := "public", legacyPublicHostsAnnotation, "*."+region.Domain
	if peer {
		suffix, annotation, wildcard = "peer", legacyPeerHostsAnnotation, "*.peer."+region.Domain
	}
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	endpoint.SetNamespace(instance.Namespace)
	endpoint.SetName(instance.Name + "-" + suffix + "-dns")
	hosts, err := parseAnnotationHosts(instance, annotation)
	if err != nil {
		return err
	}
	if instance.Spec.Private || (!peer && instance.Spec.PublicHost == "") || (peer && instance.Spec.MeshPublicPeerHost == "") {
		hosts = nil
	}
	if len(hosts) == 0 {
		if err := r.Delete(ctx, endpoint); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
		return nil
	}
	regional := &unstructured.Unstructured{}
	regional.SetGroupVersionKind(dnsEndpointGVK)
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: regionalDNSName(region.Region)}, regional); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	source, _, _ := unstructured.NestedSlice(regional.Object, "spec", "endpoints")
	records := []interface{}{}
	for _, item := range source {
		record, ok := item.(map[string]interface{})
		if !ok || record["dnsName"] != wildcard {
			continue
		}
		for _, host := range hosts {
			records = append(records, map[string]interface{}{"dnsName": host, "recordType": record["recordType"], "recordTTL": int64(60), "targets": record["targets"]})
		}
	}
	// A missing/misconfigured regional ingress must not erase a working
	// compatibility address during preparation. Wildcards can be withdrawn
	// independently; retain this fallback until a healthy replacement exists.
	if len(records) == 0 {
		return nil
	}
	_, err = controllerutil.CreateOrUpdate(ctx, r.Client, endpoint, func() error {
		endpoint.SetLabels(labels(instance))
		if err := controllerutil.SetControllerReference(instance, endpoint, r.Scheme); err != nil {
			return err
		}
		return unstructured.SetNestedSlice(endpoint.Object, records, "spec", "endpoints")
	})
	return err
}
