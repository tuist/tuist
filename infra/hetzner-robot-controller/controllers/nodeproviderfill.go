package controllers

import (
	"context"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
)

// hetznerBareMetalMachineGVK is the caph HBMM resource. We read
// it (not own it) to look up the cluster a host is bound to.
var hetznerBareMetalMachineGVK = schema.GroupVersionKind{
	Group:   "infrastructure.cluster.x-k8s.io",
	Version: "v1beta1",
	Kind:    "HetznerBareMetalMachine",
}

// NodeProviderIDFillReconciler patches `Node.spec.providerID` on
// workload-cluster Nodes whose backing `HetznerBareMetalMachine`
// has a providerID set.
//
// Why this exists: our `bare-metal.yaml` `joinConfiguration`
// intentionally does NOT pass `--cloud-provider=external` because
// there's no CCM that knows about Hetzner Robot bare-metal hosts —
// setting the flag would add `node.cloudprovider.kubernetes.io/uninitialized:NoSchedule`,
// which nothing would ever remove, blocking every Pod. The
// downside is that the kubelet never sets `Node.spec.providerID`
// itself, and CAPI's `noderef` controller can't match Machine to
// Node by providerID — so `Machine.Status.NodeRef.Name` stays
// empty forever and caph hot-loops at `actionProvisioned` with
// `machine.Status.NodeRef.Name is empty`.
//
// caph's HetznerBareMetalMachineReconciler is supposed to patch
// the Node's providerID itself but only does so when
// `--cloud-provider=external` is set (per its source). With that
// flag removed, nothing patches the Node, the deadlock persists.
//
// This reconciler closes the gap: once an HBM is `provisioned`
// and has a `consumerRef`, we look up the HBMM (to find the
// cluster name), load the workload kubeconfig from
// `org-tuist/<cluster>-kubeconfig`, find the Node, and patch
// `spec.providerID = hcloud://bm-<server-number>` if empty. CAPI
// then matches Node→Machine, sets `NodeRef`, drops the
// `node.cluster.x-k8s.io/uninitialized` taint, and caph stops
// looping.
//
// Naming: caph rewrites the Robot panel name (and OS hostname)
// to `bm-<HBMM-name>` during provisioning, and kubeadm-join
// registers the Node with the OS hostname — so the Node name in
// the workload cluster is `bm-` + HBMM name. We try that first
// and fall back to the bare HBMM name in case the prefix
// convention changes.
type NodeProviderIDFillReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// workloadClientFor builds a Kubernetes clientset against a
	// workload cluster from a kubeconfig stored in a mgmt-cluster
	// Secret. Pluggable so tests can stub it.
	workloadClientFor func(kubeconfig []byte) (kubernetes.Interface, error)
}

// retryAfterNodeNotReady is how long we wait before re-checking
// when the HBM is `provisioned` but its Node hasn't joined the
// workload cluster yet (kubeadm-join still mid-flight, or kubelet
// hasn't registered).
const retryAfterNodeNotReady = 20 * time.Second

func (r *NodeProviderIDFillReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("host", req.NamespacedName)

	hbm := &unstructured.Unstructured{}
	hbm.SetGroupVersionKind(hetznerBareMetalHostGVK)
	if err := r.Get(ctx, req.NamespacedName, hbm); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, fmt.Errorf("get host: %w", err)
	}

	// Only act on CRs we own (same posture as WWNFillReconciler).
	if hbm.GetLabels()[ManagedByLabel] != ManagedByValue {
		return ctrl.Result{}, nil
	}

	// Skip until caph reaches `provisioned`. Earlier states either
	// haven't installimaged the host yet (no Node exists), or
	// they're mid-flight and the Node, if it exists, isn't joined
	// yet. The HBM transitions to `provisioned` only after kubeadm
	// reports success — by that point the workload Node has
	// already registered.
	state, _, _ := unstructured.NestedString(hbm.Object, "spec", "status", "provisioningState")
	if state != "provisioned" {
		return ctrl.Result{}, nil
	}

	// `consumerRef` is set by caph when an HBMM claims this HBM.
	// Without it we can't know which cluster the Node lives in.
	consumerName, _, _ := unstructured.NestedString(hbm.Object, "spec", "consumerRef", "name")
	if consumerName == "" {
		return ctrl.Result{}, nil
	}

	// Server number comes from the label the InventorySyncer
	// stamps at create time. This is the integer Robot ID; caph
	// composes the providerID as `hcloud://bm-<n>` for bare-metal
	// hosts, distinct from `hcloud://<n>` for hcloud VMs.
	serverNumber := hbm.GetLabels()[ServerNumberLabel]
	if serverNumber == "" {
		logger.Info("host missing server-number label; cannot derive providerID", "name", req.Name)
		return ctrl.Result{}, nil
	}
	wantProviderID := fmt.Sprintf("hcloud://bm-%s", serverNumber)

	// HBMM holds `cluster.x-k8s.io/cluster-name` — that's how we
	// know which workload cluster's API server to talk to.
	hbmm := &unstructured.Unstructured{}
	hbmm.SetGroupVersionKind(hetznerBareMetalMachineGVK)
	if err := r.Get(ctx, types.NamespacedName{Namespace: hbm.GetNamespace(), Name: consumerName}, hbmm); err != nil {
		if apierrors.IsNotFound(err) {
			// HBMM disappeared between us reading the HBM and now.
			// Caph will clear consumerRef next reconcile; just retry.
			return ctrl.Result{RequeueAfter: retryAfterNodeNotReady}, nil
		}
		return ctrl.Result{}, fmt.Errorf("get HBMM: %w", err)
	}
	clusterName := hbmm.GetLabels()["cluster.x-k8s.io/cluster-name"]
	if clusterName == "" {
		logger.Info("HBMM missing cluster-name label; cannot find workload kubeconfig", "hbmm", consumerName)
		return ctrl.Result{}, nil
	}

	// CAPI convention: workload kubeconfig lives in
	// `<cluster-name>-kubeconfig` Secret, key `value`, in the
	// same namespace as the Cluster CR.
	secret := &corev1.Secret{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: hbm.GetNamespace(), Name: clusterName + "-kubeconfig"}, secret); err != nil {
		if apierrors.IsNotFound(err) {
			// Cluster control plane may still be coming up. Retry.
			return ctrl.Result{RequeueAfter: retryAfterNodeNotReady}, nil
		}
		return ctrl.Result{}, fmt.Errorf("get workload kubeconfig secret: %w", err)
	}
	kubeconfigBytes := secret.Data["value"]
	if len(kubeconfigBytes) == 0 {
		logger.Info("workload kubeconfig secret has empty `value` key", "secret", clusterName+"-kubeconfig")
		return ctrl.Result{RequeueAfter: retryAfterNodeNotReady}, nil
	}

	cs, err := r.buildWorkloadClient(kubeconfigBytes)
	if err != nil {
		return ctrl.Result{}, fmt.Errorf("build workload client: %w", err)
	}

	// Node name = `bm-<HBMM-name>` per caph's rename convention.
	// Fall back to the bare HBMM name in case a future caph
	// release stops adding the prefix.
	candidates := []string{"bm-" + consumerName, consumerName}
	var node *corev1.Node
	for _, name := range candidates {
		n, err := cs.CoreV1().Nodes().Get(ctx, name, metav1.GetOptions{})
		if err == nil {
			node = n
			break
		}
		if !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("get workload Node %s: %w", name, err)
		}
	}
	if node == nil {
		// kubelet hasn't registered yet — common for the ~30s
		// between caph marking `provisioned` and the Node
		// actually being visible.
		logger.V(1).Info("workload Node not found yet; will retry", "cluster", clusterName, "candidates", candidates)
		return ctrl.Result{RequeueAfter: retryAfterNodeNotReady}, nil
	}

	// Idempotent: if providerID is already set, we're done. We
	// only patch the empty case — never overwrite an existing
	// value, even if it doesn't match what we'd derive.
	if node.Spec.ProviderID != "" {
		return ctrl.Result{}, nil
	}

	patch := []byte(fmt.Sprintf(`{"spec":{"providerID":%q}}`, wantProviderID))
	if _, err := cs.CoreV1().Nodes().Patch(ctx, node.Name, types.MergePatchType, patch, metav1.PatchOptions{}); err != nil {
		return ctrl.Result{}, fmt.Errorf("patch Node providerID: %w", err)
	}
	logger.Info("patched Node providerID",
		"cluster", clusterName, "node", node.Name, "providerID", wantProviderID)
	return ctrl.Result{}, nil
}

func (r *NodeProviderIDFillReconciler) buildWorkloadClient(kubeconfig []byte) (kubernetes.Interface, error) {
	if r.workloadClientFor != nil {
		return r.workloadClientFor(kubeconfig)
	}
	return defaultWorkloadClient(kubeconfig)
}

func defaultWorkloadClient(kubeconfig []byte) (kubernetes.Interface, error) {
	cfg, err := clientcmd.NewClientConfigFromBytes(kubeconfig)
	if err != nil {
		return nil, fmt.Errorf("parse kubeconfig: %w", err)
	}
	rc, err := cfg.ClientConfig()
	if err != nil {
		return nil, fmt.Errorf("rest config from kubeconfig: %w", err)
	}
	return kubernetes.NewForConfig(rc)
}

// Compile-time assertion this signature matches rest.Config consumers.
var _ = (*rest.Config)(nil)

// SetupWithManager wires the reconciler. Predicate-filtered to
// our own CRs so we don't get woken for hand-authored hosts (the
// `managed-by` label scopes "what's mine").
func (r *NodeProviderIDFillReconciler) SetupWithManager(mgr ctrl.Manager) error {
	obj := &unstructured.Unstructured{}
	obj.SetGroupVersionKind(hetznerBareMetalHostGVK)

	managedByFilter := predicate.NewPredicateFuncs(func(o client.Object) bool {
		return o.GetLabels()[ManagedByLabel] == ManagedByValue
	})

	return ctrl.NewControllerManagedBy(mgr).
		Named("nodeproviderfill").
		For(obj, builder.WithPredicates(managedByFilter)).
		Complete(r)
}
