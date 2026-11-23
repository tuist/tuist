package controllers

import (
	"context"
	"fmt"
	"net"
	"sort"
	"strconv"
	"strings"

	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// A gateway entrance publishes a private instance on another site's gateway.
// That gateway is a host-network ingress-nginx on the other site's storage
// node, so it reaches the instance's primary Service over the cluster network
// (the platform chart's kura-gateway-ingress policy admits remote-node on the
// cache ports), and the other site's runners reach it on their own segment.
// An entrance shares nothing with the instance's own PrivateHost but the
// primary Service: its Ingresses, its DNS record and its readiness are its own,
// so a dark site loses only its entrances and never the instance's own host.
//
// Entrances are served only with the shared wildcard certificate. Minting one
// per entrance would spend the ACME per-registered-domain allowance every
// private instance already draws on; until the wildcard covers the host the
// entrance reports CertificatePending and the server hands out nothing.
const (
	gatewayEntranceOfLabel   = "tuist.dev/gateway-entrance-of"
	gatewayEntranceSiteLabel = "tuist.dev/gateway-entrance-site"
)

func gatewayEntranceName(instance *kurav1alpha1.KuraInstance, site string) string {
	return instance.Name + "-via-" + site
}

func gatewayEntranceGRPCName(instance *kurav1alpha1.KuraInstance, site string) string {
	return gatewayEntranceName(instance, site) + "-grpc"
}

func gatewayEntranceDNSName(instance *kurav1alpha1.KuraInstance, site string) string {
	return gatewayEntranceName(instance, site) + "-dns"
}

// validGatewayEntrances are the entrances the controller publishes: those of a
// configured private gateway instance with every field usable. A malformed one
// is skipped rather than failing the reconcile, and its status says why.
func validGatewayEntrances(instance *kurav1alpha1.KuraInstance) map[string]kurav1alpha1.GatewayEntrance {
	valid := map[string]kurav1alpha1.GatewayEntrance{}
	if clientHost(instance) == "" {
		return valid
	}
	seen := map[string]int{}
	for _, entrance := range instance.Spec.GatewayEntrances {
		seen[entrance.Site]++
	}
	for _, entrance := range instance.Spec.GatewayEntrances {
		if gatewayEntranceInvalid(instance, entrance) == "" && seen[entrance.Site] == 1 {
			valid[entrance.Site] = entrance
		}
	}
	return valid
}

func gatewayEntranceInvalid(instance *kurav1alpha1.KuraInstance, entrance kurav1alpha1.GatewayEntrance) string {
	switch {
	case entrance.Site == "" || entrance.Host == "" || entrance.IngressClassName == "":
		return "Entrance requires a site, host and ingress class"
	case entrance.Host == instance.Spec.PrivateHost || slicesContain(instance.Spec.ClientHostAliases, entrance.Host):
		return "Entrance host must differ from the instance's own hosts"
	case entrance.IngressClassName == instance.Spec.IngressClassName:
		return "Entrance must use another site's ingress class"
	case len(entrance.NodeSelector) == 0:
		return "Entrance requires a gateway node selector"
	case len(entrance.ClientCIDRs) == 0:
		return "Entrance requires client CIDRs"
	}
	for _, cidr := range entrance.ClientCIDRs {
		if _, _, err := net.ParseCIDR(cidr); err != nil {
			return fmt.Sprintf("Invalid client CIDR %q", cidr)
		}
	}
	return ""
}

func slicesContain(values []string, value string) bool {
	for _, candidate := range values {
		if candidate == value {
			return true
		}
	}
	return false
}

func gatewayEntranceLabels(instance *kurav1alpha1.KuraInstance, site string) map[string]string {
	result := labels(instance)
	result[gatewayEntranceOfLabel] = instance.Name
	result[gatewayEntranceSiteLabel] = site
	return result
}

// gatewayEntranceAnnotations add the entrance's source allowlist and limits to
// the instance's streaming annotations. ingress-nginx applies limit-rate only
// with proxy buffering on, which the instance's own Ingress turns off to stream
// artifacts. The entrance turns it on in memory only (no temporary files on the
// storage node's disk): nginx passes a response through synchronously once its
// buffers fill, so the limit holds without spooling. Both limits are per
// gateway replica: limit-rate is per response (per stream on HTTP/2) and
// limit-connections per client address, so neither is an aggregate cap.
func gatewayEntranceAnnotations(entrance kurav1alpha1.GatewayEntrance, annotations map[string]string) map[string]string {
	annotations["external-dns.alpha.kubernetes.io/ingress-hostname-source"] = "annotation-only"
	annotations["nginx.ingress.kubernetes.io/whitelist-source-range"] = strings.Join(entrance.ClientCIDRs, ",")
	if entrance.RateLimitKBps > 0 {
		annotations["nginx.ingress.kubernetes.io/proxy-buffering"] = "on"
		annotations["nginx.ingress.kubernetes.io/proxy-max-temp-file-size"] = "0"
		annotations["nginx.ingress.kubernetes.io/limit-rate"] = strconv.Itoa(int(entrance.RateLimitKBps))
	}
	if entrance.ConnectionLimit > 0 {
		annotations["nginx.ingress.kubernetes.io/limit-connections"] = strconv.Itoa(int(entrance.ConnectionLimit))
	}
	return annotations
}

// reconcileGatewayEntrances renders every valid entrance's HTTP and gRPC
// Ingresses and DNS record, and removes the objects of entrances that are gone
// or no longer valid. It runs after the instance's own gRPC Ingress so the gRPC
// port it routes to follows the same pod evidence.
func (r *KuraInstanceReconciler) reconcileGatewayEntrances(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod, observed map[string]runtimeStatus, primaryPod string) error {
	entrances := validGatewayEntrances(instance)
	if err := r.pruneGatewayEntrances(ctx, instance, entrances); err != nil {
		return err
	}
	sites := make([]string, 0, len(entrances))
	for site := range entrances {
		sites = append(sites, site)
	}
	sort.Strings(sites)
	for _, site := range sites {
		entrance := entrances[site]
		if err := r.reconcileGatewayEntranceIngress(ctx, instance, entrance); err != nil {
			return err
		}
		if err := r.reconcileGatewayEntranceGRPCIngress(ctx, instance, entrance, pods, observed, primaryPod); err != nil {
			return err
		}
		if err := r.reconcileGatewayEntranceDNS(ctx, instance, entrance); err != nil {
			return err
		}
	}
	return nil
}

func (r *KuraInstanceReconciler) reconcileGatewayEntranceIngress(ctx context.Context, instance *kurav1alpha1.KuraInstance, entrance kurav1alpha1.GatewayEntrance) error {
	ingress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: gatewayEntranceName(instance, entrance.Site), Namespace: instance.Namespace}}
	covered := r.sharedTLSCoversHost(ctx, instance, entrance.Host)
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, ingress, func() error {
		if err := controllerutil.SetControllerReference(instance, ingress, r.Scheme); err != nil {
			return err
		}
		ingress.Labels = gatewayEntranceLabels(instance, entrance.Site)
		ingress.Annotations = gatewayEntranceAnnotations(entrance, publicIngressAnnotations())
		ingress.Spec.IngressClassName = ptr(entrance.IngressClassName)
		ingress.Spec.TLS = nil
		if covered {
			ingress.Spec.TLS = []networkingv1.IngressTLS{{Hosts: []string{entrance.Host}, SecretName: r.PublicTLSSecretName}}
		}
		ingress.Spec.Rules = []networkingv1.IngressRule{{
			Host: entrance.Host,
			IngressRuleValue: networkingv1.IngressRuleValue{HTTP: &networkingv1.HTTPIngressRuleValue{
				Paths: []networkingv1.HTTPIngressPath{{
					Path:     "/",
					PathType: ptr(networkingv1.PathTypePrefix),
					Backend:  ingressBackend(instance.Name, "http"),
				}},
			}},
		}}
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) reconcileGatewayEntranceGRPCIngress(ctx context.Context, instance *kurav1alpha1.KuraInstance, entrance kurav1alpha1.GatewayEntrance, pods []corev1.Pod, observed map[string]runtimeStatus, primaryPod string) error {
	ingress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: gatewayEntranceGRPCName(instance, entrance.Site), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, ingress, func() error {
		if err := controllerutil.SetControllerReference(instance, ingress, r.Scheme); err != nil {
			return err
		}
		ingress.Labels = gatewayEntranceLabels(instance, entrance.Site)
		ingress.Annotations = gatewayEntranceAnnotations(entrance, grpcIngressAnnotations())
		ingress.Spec.IngressClassName = ptr(entrance.IngressClassName)
		ingress.Spec.TLS = nil
		// The same port choice as the instance's own gRPC Ingress, for the
		// same reason: see grpcIngressServicePort.
		servicePort := grpcIngressServicePort(pods, observed, primaryPod)
		if current := grpcIngressBackendPort(ingress); current != "" && !anyPodReady(pods) {
			servicePort = current
		}
		paths := make([]networkingv1.HTTPIngressPath, 0, len(grpcPublicPathPrefixes))
		for _, prefix := range grpcPublicPathPrefixes {
			paths = append(paths, networkingv1.HTTPIngressPath{
				Path:     prefix,
				PathType: ptr(networkingv1.PathTypeImplementationSpecific),
				Backend:  ingressBackend(instance.Name, servicePort),
			})
		}
		ingress.Spec.Rules = []networkingv1.IngressRule{{
			Host:             entrance.Host,
			IngressRuleValue: networkingv1.IngressRuleValue{HTTP: &networkingv1.HTTPIngressRuleValue{Paths: paths}},
		}}
		return nil
	})
	return err
}

// gatewayEntranceTarget picks the address the entrance's DNS names: the one it
// already names while that gateway stays Ready, else the first Ready gateway
// node of the site by name. Pod List order never decides it.
func (r *KuraInstanceReconciler) gatewayEntranceTarget(ctx context.Context, instance *kurav1alpha1.KuraInstance, entrance kurav1alpha1.GatewayEntrance) (string, error) {
	nodes, err := r.readyGatewayNodesFor(ctx, entrance.IngressClassName, entrance.NodeSelector)
	if err != nil || len(nodes) == 0 {
		return "", err
	}
	for _, current := range r.gatewayEntranceDNSTargets(ctx, instance, entrance) {
		for _, address := range nodes {
			if address == current {
				return address, nil
			}
		}
	}
	names := make([]string, 0, len(nodes))
	for name := range nodes {
		names = append(names, name)
	}
	sort.Strings(names)
	return nodes[names[0]], nil
}

func (r *KuraInstanceReconciler) gatewayEntranceDNSTargets(ctx context.Context, instance *kurav1alpha1.KuraInstance, entrance kurav1alpha1.GatewayEntrance) []string {
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := r.Get(ctx, types.NamespacedName{Namespace: instance.Namespace, Name: gatewayEntranceDNSName(instance, entrance.Site)}, endpoint); err != nil {
		return nil
	}
	records, _, _ := unstructured.NestedSlice(endpoint.Object, "spec", "endpoints")
	for _, entry := range records {
		record, ok := entry.(map[string]interface{})
		if !ok || record["dnsName"] != entrance.Host {
			continue
		}
		targets, _, _ := unstructured.NestedStringSlice(record, "targets")
		return targets
	}
	return nil
}

// reconcileGatewayEntranceDNS publishes the entrance host at the site's
// gateway. With no Ready gateway the existing record keeps its target, as the
// instance's own record does: unpublishing a host clients may still hold gets
// cached as NXDOMAIN for the zone's negative TTL. The entrance then reports
// GatewayUnavailable, so the server stops handing it out.
func (r *KuraInstanceReconciler) reconcileGatewayEntranceDNS(ctx context.Context, instance *kurav1alpha1.KuraInstance, entrance kurav1alpha1.GatewayEntrance) error {
	target, err := r.gatewayEntranceTarget(ctx, instance, entrance)
	if err != nil || target == "" {
		return err
	}
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	endpoint.SetNamespace(instance.Namespace)
	endpoint.SetName(gatewayEntranceDNSName(instance, entrance.Site))
	_, err = controllerutil.CreateOrUpdate(ctx, r.Client, endpoint, func() error {
		endpoint.SetLabels(gatewayEntranceLabels(instance, entrance.Site))
		records := []interface{}{map[string]interface{}{
			"dnsName": entrance.Host, "recordType": "A", "recordTTL": int64(60), "targets": []interface{}{target},
		}}
		if err := unstructured.SetNestedSlice(endpoint.Object, records, "spec", "endpoints"); err != nil {
			return err
		}
		return controllerutil.SetControllerReference(instance, endpoint, r.Scheme)
	})
	return err
}

// pruneGatewayEntrances deletes the Ingresses and DNS records of entrances the
// instance no longer publishes. Objects are found by label rather than by the
// current spec, so an entrance removed from the spec is still found.
func (r *KuraInstanceReconciler) pruneGatewayEntrances(ctx context.Context, instance *kurav1alpha1.KuraInstance, keep map[string]kurav1alpha1.GatewayEntrance) error {
	selector := client.MatchingLabels{gatewayEntranceOfLabel: instance.Name}
	ingresses := &networkingv1.IngressList{}
	if err := r.List(ctx, ingresses, client.InNamespace(instance.Namespace), selector); err != nil {
		return err
	}
	for i := range ingresses.Items {
		ingress := &ingresses.Items[i]
		if _, ok := keep[ingress.Labels[gatewayEntranceSiteLabel]]; ok {
			continue
		}
		if err := r.Delete(ctx, ingress); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}
	endpoints := &unstructured.UnstructuredList{}
	endpoints.SetGroupVersionKind(dnsEndpointGVK.GroupVersion().WithKind(dnsEndpointGVK.Kind + "List"))
	if err := r.List(ctx, endpoints, client.InNamespace(instance.Namespace), selector); err != nil {
		return err
	}
	for i := range endpoints.Items {
		endpoint := &endpoints.Items[i]
		if _, ok := keep[endpoint.GetLabels()[gatewayEntranceSiteLabel]]; ok {
			continue
		}
		if err := r.Delete(ctx, endpoint); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}
	return nil
}

// gatewayEntranceStatuses observes each spec entrance the way
// privateGatewayStatus observes the instance's own host: the URL is published
// only while the serving primary, the wildcard certificate, a Ready gateway at
// the site and DNS resolving to exactly that gateway all hold.
func (r *KuraInstanceReconciler) gatewayEntranceStatuses(ctx context.Context, instance *kurav1alpha1.KuraInstance, primary string, pods []corev1.Pod, samples map[string]runtimeStatus, now metav1.Time) []kurav1alpha1.GatewayEntranceStatus {
	if len(instance.Spec.GatewayEntrances) == 0 {
		return nil
	}
	valid := validGatewayEntrances(instance)
	primaryReason, primaryMessage := primaryUnavailable(primary, pods, samples)
	statuses := make([]kurav1alpha1.GatewayEntranceStatus, 0, len(instance.Spec.GatewayEntrances))
	for _, entrance := range instance.Spec.GatewayEntrances {
		status := kurav1alpha1.GatewayEntranceStatus{Site: entrance.Site, LastCheckedAt: &now, ObservedGeneration: instance.Generation}
		status.Reason, status.Message = r.gatewayEntranceUnavailable(ctx, instance, entrance, valid, primaryReason, primaryMessage)
		if status.Reason == "" {
			status.URL = "https://" + entrance.Host
			status.Reason = "Ready"
			status.Message = "Entrance gateway, certificate, DNS and serving primary are ready"
		}
		statuses = append(statuses, status)
	}
	return statuses
}

func (r *KuraInstanceReconciler) gatewayEntranceUnavailable(ctx context.Context, instance *kurav1alpha1.KuraInstance, entrance kurav1alpha1.GatewayEntrance, valid map[string]kurav1alpha1.GatewayEntrance, primaryReason, primaryMessage string) (string, string) {
	if clientHost(instance) == "" {
		return "InvalidConfiguration", "Entrances require the instance's own private gateway"
	}
	if message := gatewayEntranceInvalid(instance, entrance); message != "" {
		return "InvalidConfiguration", message
	}
	if _, ok := valid[entrance.Site]; !ok {
		return "InvalidConfiguration", "Another entrance names the same site"
	}
	if primaryReason != "" {
		return primaryReason, primaryMessage
	}
	if !r.sharedTLSCoversHost(ctx, instance, entrance.Host) {
		return "CertificatePending", "The shared wildcard certificate does not cover the entrance host"
	}
	target, err := r.gatewayEntranceTarget(ctx, instance, entrance)
	if err != nil {
		return "ObservationFailed", err.Error()
	}
	if target == "" {
		return "GatewayUnavailable", "No Ready gateway with a private IPv4 address at the entrance's site"
	}
	addresses := r.privateDNSAddresses(ctx, entrance.Host, target)
	if len(addresses) == 0 {
		return "DNSPending", fmt.Sprintf("Waiting for %s to resolve to %s", entrance.Host, target)
	}
	for _, address := range addresses {
		if address != target {
			return "DNSPending", fmt.Sprintf("Expected only %s; observed %v", target, addresses)
		}
	}
	return "", ""
}
