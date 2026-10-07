package controllers

import (
	"context"
	"strings"

	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

// haproxyGRPCServicePort gives gRPC its own HAProxy backend. haproxytech keys
// a backend, and its single protocol, on the Service port, so HTTP keeps
// HTTP/1.1 (Kura's sendfile path) while gRPC uses h2c. Both ports target the
// co-hosted listener, which serves /ready for the health checks.
const (
	haproxyGRPCServicePort             = "grpc-h2"
	haproxyGRPCServicePortNumber int32 = 4001
)

func haproxyIngressClassName(instance *kurav1alpha1.KuraInstance) string {
	return strings.TrimSpace(instance.Spec.HAProxyIngressClassName)
}

func haproxyGatewayEnabled(instance *kurav1alpha1.KuraInstance) bool {
	return haproxyIngressClassName(instance) != "" && clientHost(instance) != ""
}

func haproxyServiceName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-haproxy"
}

func haproxyIngressName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-haproxy"
}

func haproxyGRPCIngressName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-grpc-haproxy"
}

// haproxyGRPCPathPrefixes are grpcPublicPathPrefixes unescaped: haproxytech
// matches ImplementationSpecific paths as plain begins-with strings, and the
// longest match wins over the public Ingress's "/".
func haproxyGRPCPathPrefixes() []string {
	prefixes := make([]string, 0, len(grpcPublicPathPrefixes))
	for _, prefix := range grpcPublicPathPrefixes {
		prefixes = append(prefixes, strings.ReplaceAll(prefix, `\.`, "."))
	}
	return prefixes
}

// reconcileHAProxyGateway renders the client plane for the region's HAProxy
// gateway. Its backend Service publishes the primary even while Kubernetes
// marks it NotReady, which the node lifecycle controller does to every pod on
// a box that lost its heartbeat to the control plane while the box keeps
// serving. HAProxy routes on its own /ready checks instead, which also take a
// starting or draining pod out within seconds; a terminating pod leaves the
// EndpointSlice regardless.
func (r *KuraInstanceReconciler) reconcileHAProxyGateway(ctx context.Context, instance *kurav1alpha1.KuraInstance, primaryPod string) error {
	if !haproxyGatewayEnabled(instance) {
		return r.deleteHAProxyGateway(ctx, instance)
	}

	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: haproxyServiceName(instance), Namespace: instance.Namespace}}
	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		service.Labels = labels(instance)
		service.Spec.Selector = primaryServiceSelector(instance, primaryPod)
		service.Spec.Type = corev1.ServiceTypeClusterIP
		service.Spec.PublishNotReadyAddresses = true
		service.Spec.Ports = []corev1.ServicePort{
			{Name: "http", Port: httpPort, TargetPort: intstr.FromString("http")},
			{Name: haproxyGRPCServicePort, Port: haproxyGRPCServicePortNumber, TargetPort: intstr.FromString("http")},
		}
		return nil
	}); err != nil {
		return err
	}

	public := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: haproxyIngressName(instance), Namespace: instance.Namespace}}
	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, public, func() error {
		if err := controllerutil.SetControllerReference(instance, public, r.Scheme); err != nil {
			return err
		}
		public.Labels = labels(instance)
		public.Annotations = haproxyIngressAnnotations(instance, false)
		public.Spec.IngressClassName = ptr(haproxyIngressClassName(instance))
		public.Spec.TLS = r.clientIngressTLS(ctx, instance)
		public.Spec.Rules = clientIngressRules(instance, []networkingv1.HTTPIngressPath{{
			Path:     "/",
			PathType: ptr(networkingv1.PathTypePrefix),
			Backend:  ingressBackend(haproxyServiceName(instance), "http"),
		}})
		return nil
	}); err != nil {
		return err
	}

	grpc := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: haproxyGRPCIngressName(instance), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, grpc, func() error {
		if err := controllerutil.SetControllerReference(instance, grpc, r.Scheme); err != nil {
			return err
		}
		grpc.Labels = labels(instance)
		grpc.Annotations = haproxyIngressAnnotations(instance, true)
		grpc.Spec.IngressClassName = ptr(haproxyIngressClassName(instance))
		grpc.Spec.TLS = nil
		prefixes := haproxyGRPCPathPrefixes()
		paths := make([]networkingv1.HTTPIngressPath, 0, len(prefixes))
		for _, prefix := range prefixes {
			paths = append(paths, networkingv1.HTTPIngressPath{
				Path:     prefix,
				PathType: ptr(networkingv1.PathTypeImplementationSpecific),
				Backend:  ingressBackend(haproxyServiceName(instance), haproxyGRPCServicePort),
			})
		}
		grpc.Spec.Rules = clientIngressRules(instance, paths)
		return nil
	})
	return err
}

// deleteHAProxyGateway reads from the cache first so the instances that never
// joined a gateway cost no API writes on each reconcile.
func (r *KuraInstanceReconciler) deleteHAProxyGateway(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	for _, object := range []client.Object{
		&networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: haproxyGRPCIngressName(instance), Namespace: instance.Namespace}},
		&networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: haproxyIngressName(instance), Namespace: instance.Namespace}},
		&corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: haproxyServiceName(instance), Namespace: instance.Namespace}},
	} {
		if err := r.Get(ctx, client.ObjectKeyFromObject(object), object); err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return err
		}
		if err := r.Delete(ctx, object); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}
	return nil
}

func haproxyIngressAnnotations(instance *kurav1alpha1.KuraInstance, grpc bool) map[string]string {
	annotations := map[string]string{
		// Customer DNS comes from the controller's DNSEndpoints, never from
		// these Ingresses.
		"external-dns.alpha.kubernetes.io/ingress-hostname-source": "annotation-only",
		"haproxy.org/check":          "true",
		"haproxy.org/check-http":     "/ready",
		"haproxy.org/check-interval": "1s",
		"haproxy.org/timeout-server": "3600s",
	}
	if grpc {
		annotations["haproxy.org/server-proto"] = "h2"
	}
	if instance.Spec.Private {
		annotations["haproxy.org/allow-list"] = strings.Join(instance.Spec.ClientCIDRs, ",")
	}
	return annotations
}
