package controllers

import (
	"context"
	"crypto/sha256"
	"fmt"
	"sort"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	// The official nginx image ships the stream module + ngx_stream_ssl_preread_module,
	// which the demux needs to route by SNI without terminating TLS.
	defaultPeerDemuxImage         = "nginx:1.27.3-alpine"
	peerDemuxConfigHashAnnotation = "tuist.dev/peer-demux-config-hash"
	peerDemuxPort                 = 7443
)

// PeerDemuxReconciler maintains, per bare-metal (host-network) region, a
// host-network L4 SNI-passthrough demux on :7443 fronting the off-cluster
// self-hosted peer plane. Bare-metal regions have no cloud LoadBalancer, so a
// self-hosted node dials the region's failover IP and this demux — running on
// every box of the region's pool, wherever the failover IP currently lands —
// forwards the connection by SNI (ssl_preread, no TLS termination, so the
// end-to-end mTLS is preserved) to the addressed account's ClusterIP peer
// Service.
//
// It is keyed by region (req.Name == region, req.Namespace == the instances'
// namespace), not by a CR: the SNI->backend routes are derived from the
// region's KuraInstances. The DaemonSet + ConfigMap are not owner-referenced
// (there is no per-region owner object); the reconciler deletes them when the
// region has no host-network peering instances left.
type PeerDemuxReconciler struct {
	client.Client
	Scheme *runtime.Scheme
	Image  string
}

// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kurainstances,verbs=get;list;watch
// +kubebuilder:rbac:groups=apps,resources=daemonsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=configmaps,verbs=get;list;watch;create;update;patch;delete

func (r *PeerDemuxReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("region", req.Name)
	region := req.Name
	namespace := req.Namespace

	instances := &kurav1alpha1.KuraInstanceList{}
	if err := r.List(ctx, instances, client.InNamespace(namespace)); err != nil {
		return ctrl.Result{}, err
	}

	routes, nodeSelector, tolerations := peerDemuxDesiredState(region, namespace, instances.Items)

	name := peerDemuxName(region)
	configMap := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace}}
	daemonSet := &appsv1.DaemonSet{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace}}

	if len(routes) == 0 {
		// No host-network peering instances in this region: tear the demux down.
		if err := r.Delete(ctx, daemonSet); err != nil && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, err
		}
		if err := r.Delete(ctx, configMap); err != nil && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, err
		}
		return ctrl.Result{}, nil
	}

	nginxConf := peerDemuxNginxConf(routes)
	configHash := fmt.Sprintf("%x", sha256.Sum256([]byte(nginxConf)))

	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, configMap, func() error {
		configMap.Labels = peerDemuxLabels(region)
		configMap.Data = map[string]string{"nginx.conf": nginxConf}
		return nil
	}); err != nil {
		return ctrl.Result{}, err
	}

	if _, err := controllerutil.CreateOrUpdate(ctx, r.Client, daemonSet, func() error {
		daemonSet.Labels = peerDemuxLabels(region)
		daemonSet.Spec.Selector = &metav1.LabelSelector{MatchLabels: peerDemuxSelectorLabels(region)}
		daemonSet.Spec.Template = peerDemuxPodTemplate(region, name, configHash, nodeSelector, tolerations, r.image())
		return nil
	}); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("reconciled Kura peer demux", "routes", len(routes))
	// Re-reconcile periodically so manual drift (e.g. a deleted DaemonSet) heals
	// even without a KuraInstance change to trigger it.
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}

type peerDemuxRoute struct {
	host    string
	backend string
}

// peerDemuxDesiredState collects the SNI->backend routes for a region from its
// host-network peering KuraInstances, plus the pool nodeSelector + tolerations
// they share (all instances of a region land on the same bare-metal pool).
func peerDemuxDesiredState(region, namespace string, instances []kurav1alpha1.KuraInstance) ([]peerDemuxRoute, map[string]string, []corev1.Toleration) {
	var routes []peerDemuxRoute
	var nodeSelector map[string]string
	var tolerations []corev1.Toleration

	for i := range instances {
		instance := &instances[i]
		if instance.Spec.Region != region || !instance.Spec.MeshPeerHostNetwork || instance.Spec.MeshPublicPeerHost == "" {
			continue
		}
		routes = append(routes, peerDemuxRoute{
			host: instance.Spec.MeshPublicPeerHost,
			backend: fmt.Sprintf("%s.%s.svc.cluster.local:%d",
				instancePublicPeerServiceName(instance), namespace, peerPort),
		})
		if nodeSelector == nil {
			nodeSelector = instance.Spec.NodeSelector
			tolerations = instance.Spec.Tolerations
		}
	}

	sort.Slice(routes, func(i, j int) bool { return routes[i].host < routes[j].host })
	return routes, nodeSelector, tolerations
}

// peerDemuxNginxConf renders a stream-only nginx config that routes each peer
// SNI host to its account's ClusterIP peer Service. Unknown SNI maps to an empty
// upstream, which nginx closes — only enrolled hosts are routable.
func peerDemuxNginxConf(routes []peerDemuxRoute) string {
	var b strings.Builder
	b.WriteString("worker_processes auto;\n")
	b.WriteString("error_log /dev/stderr warn;\n")
	b.WriteString("pid /tmp/nginx.pid;\n")
	b.WriteString("events {\n  worker_connections 4096;\n}\n")
	b.WriteString("stream {\n")
	b.WriteString("  map $ssl_preread_server_name $kura_peer_backend {\n")
	b.WriteString("    default \"\";\n")
	for _, route := range routes {
		fmt.Fprintf(&b, "    %s %s;\n", route.host, route.backend)
	}
	b.WriteString("  }\n")
	b.WriteString("  server {\n")
	fmt.Fprintf(&b, "    listen %d;\n", peerDemuxPort)
	b.WriteString("    ssl_preread on;\n")
	b.WriteString("    proxy_pass $kura_peer_backend;\n")
	b.WriteString("    proxy_connect_timeout 5s;\n")
	b.WriteString("    proxy_timeout 10m;\n")
	b.WriteString("  }\n")
	b.WriteString("}\n")
	return b.String()
}

func peerDemuxPodTemplate(region, name, configHash string, nodeSelector map[string]string, tolerations []corev1.Toleration, image string) corev1.PodTemplateSpec {
	return corev1.PodTemplateSpec{
		ObjectMeta: metav1.ObjectMeta{
			Labels:      peerDemuxSelectorLabels(region),
			Annotations: map[string]string{peerDemuxConfigHashAnnotation: configHash},
		},
		Spec: corev1.PodSpec{
			HostNetwork:  true,
			DNSPolicy:    corev1.DNSClusterFirstWithHostNet,
			NodeSelector: nodeSelector,
			Tolerations:  tolerations,
			Containers: []corev1.Container{{
				Name:            "demux",
				Image:           image,
				ImagePullPolicy: corev1.PullIfNotPresent,
				Ports: []corev1.ContainerPort{
					{Name: "peer", ContainerPort: peerDemuxPort, Protocol: corev1.ProtocolTCP},
				},
				VolumeMounts: []corev1.VolumeMount{
					{Name: "config", MountPath: "/etc/nginx/nginx.conf", SubPath: "nginx.conf", ReadOnly: true},
				},
				ReadinessProbe: &corev1.Probe{
					ProbeHandler: corev1.ProbeHandler{
						TCPSocket: &corev1.TCPSocketAction{Port: intstr.FromInt(peerDemuxPort)},
					},
					InitialDelaySeconds: 5,
					PeriodSeconds:       10,
				},
				Resources: corev1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceCPU:    resource.MustParse("50m"),
						corev1.ResourceMemory: resource.MustParse("64Mi"),
					},
					Limits: corev1.ResourceList{
						corev1.ResourceMemory: resource.MustParse("256Mi"),
					},
				},
			}},
			Volumes: []corev1.Volume{{
				Name: "config",
				VolumeSource: corev1.VolumeSource{
					ConfigMap: &corev1.ConfigMapVolumeSource{
						LocalObjectReference: corev1.LocalObjectReference{Name: name},
					},
				},
			}},
		},
	}
}

func peerDemuxName(region string) string {
	return "kura-peer-demux-" + region
}

func peerDemuxLabels(region string) map[string]string {
	labels := peerDemuxSelectorLabels(region)
	labels["app.kubernetes.io/managed-by"] = "kura-controller"
	labels["tuist.dev/region"] = region
	return labels
}

func peerDemuxSelectorLabels(region string) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":      "kura-peer-demux",
		"app.kubernetes.io/component": "peer-demux",
		"app.kubernetes.io/instance":  region,
	}
}

func (r *PeerDemuxReconciler) image() string {
	if strings.TrimSpace(r.Image) != "" {
		return strings.TrimSpace(r.Image)
	}
	return defaultPeerDemuxImage
}

func (r *PeerDemuxReconciler) SetupWithManager(mgr ctrl.Manager) error {
	mapInstance := func(_ context.Context, obj client.Object) []reconcile.Request {
		instance, ok := obj.(*kurav1alpha1.KuraInstance)
		if !ok || instance.Spec.Region == "" {
			return nil
		}
		return []reconcile.Request{{
			NamespacedName: types.NamespacedName{Name: instance.Spec.Region, Namespace: instance.Namespace},
		}}
	}
	return ctrl.NewControllerManagedBy(mgr).
		Named("peer-demux").
		Watches(&kurav1alpha1.KuraInstance{}, handler.EnqueueRequestsFromMapFunc(mapInstance)).
		Complete(r)
}
