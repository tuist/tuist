// Real API server coverage for what one macOS host may do with its identity:
// the chart's tart-kubelet ClusterRole, Role and admission policy, rendered
// with helm, together with the grants the node access controller writes. The
// fake-client tests above cannot see RBAC escalation checks or the policy's
// CEL, and a wrong expression there would only show at deploy time.
//
// Needs the envtest binaries (KUBEBUILDER_ASSETS, installed by the provider
// workflow with setup-envtest) and helm on PATH. Without them it skips, so
// `go test ./...` still passes on a fresh checkout.

package macos

import (
	"bytes"
	"context"
	"errors"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	utilyaml "k8s.io/apimachinery/pkg/util/yaml"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"k8s.io/utils/ptr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/envtest"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

const (
	scopeNamespace    = "tuist"
	scopeRunners      = "tuist-runners"
	scopeSandboxes    = "tuist-sandboxes"
	scopeClusterRole  = "tuist-tuist-tart-kubelet"
	scopeOperatorRole = "tuist-tuist-capi-scaleway-applesilicon"
	scopeCacheSA      = "tuist-tuist-runner-cache-volumes"
	scopeFleet        = "tuist-tuist-runners-fleet"
	hostA             = "mac-a"
	hostB             = "mac-b"
)

// renderNodeScope renders the chart's tart-kubelet RBAC and policy and the
// operator's ClusterRole as the production values do.
func renderNodeScope(t *testing.T) []*unstructured.Unstructured {
	t.Helper()
	helm, err := exec.LookPath("helm")
	if err != nil {
		t.Skip("helm not on PATH")
	}
	chart := filepath.Join("..", "..", "..", "helm", "tuist")
	cmd := exec.Command(helm, "template", "tuist", chart, "-n", scopeNamespace,
		"-f", filepath.Join(chart, "values-managed-common.yaml"),
		"-f", filepath.Join(chart, "values-managed-production.yaml"),
		"-f", filepath.Join(chart, "values-ci.yaml"),
		"--show-only", "templates/tart-kubelet-rbac.yaml",
		"--show-only", "templates/capi-scaleway-applesilicon.yaml")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		t.Fatalf("helm template: %v\n%s", err, stderr.String())
	}
	var objs []*unstructured.Unstructured
	dec := utilyaml.NewYAMLOrJSONDecoder(bytes.NewReader(out), 4096)
	for {
		u := &unstructured.Unstructured{}
		if err := dec.Decode(&u.Object); errors.Is(err, io.EOF) {
			break
		} else if err != nil {
			t.Fatalf("decode render: %v", err)
		}
		switch {
		case u.Object == nil:
		case strings.HasPrefix(u.GetName(), scopeClusterRole),
			u.GetKind() == "ClusterRole" && u.GetName() == scopeOperatorRole:
			objs = append(objs, u)
		}
	}
	return objs
}

func TestHostIdentityIsScopedToItsOwnNodeOnARealAPIServer(t *testing.T) {
	if os.Getenv("KUBEBUILDER_ASSETS") == "" {
		t.Skip("envtest binaries not present (set KUBEBUILDER_ASSETS to run)")
	}
	rendered := renderNodeScope(t)
	ctx := context.Background()

	env := &envtest.Environment{}
	cfg, err := env.Start()
	if err != nil {
		t.Fatalf("envtest start: %v", err)
	}
	t.Cleanup(func() { _ = env.Stop() })
	admin, err := client.New(cfg, client.Options{Scheme: clientgoscheme.Scheme})
	if err != nil {
		t.Fatal(err)
	}
	mustCreate := func(objs ...client.Object) {
		t.Helper()
		for _, o := range objs {
			if err := admin.Create(ctx, o); err != nil {
				t.Fatalf("create %T %s: %v", o, o.GetName(), err)
			}
		}
	}

	for _, ns := range []string{scopeNamespace, scopeRunners, scopeSandboxes} {
		mustCreate(&corev1.Namespace{ObjectMeta: metav1.ObjectMeta{Name: ns}})
	}
	kinds := map[string]bool{}
	for _, u := range rendered {
		kinds[u.GetKind()] = true
		mustCreate(u)
	}
	for _, kind := range []string{"ClusterRole", "Role", "ValidatingAdmissionPolicy", "ValidatingAdmissionPolicyBinding"} {
		if !kinds[kind] {
			t.Fatalf("the render has no %s", kind)
		}
	}

	// The operator acts with the chart's ClusterRole, so a grant it may not
	// make (RBAC escalation) fails here as it would in the cluster.
	mustCreate(
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: scopeNamespace, Name: "operator"}},
		&rbacv1.ClusterRoleBinding{
			ObjectMeta: metav1.ObjectMeta{Name: "operator"},
			RoleRef:    rbacv1.RoleRef{APIGroup: rbacv1.GroupName, Kind: "ClusterRole", Name: scopeOperatorRole},
			Subjects:   []rbacv1.Subject{{Kind: "ServiceAccount", Namespace: scopeNamespace, Name: "operator"}},
		},
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: scopeRunners, Name: scopeCacheSA}},
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: scopeRunners, Name: "runner"}},
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: scopeSandboxes, Name: "tuist-macos-sandboxd"}},
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: scopeNamespace, Name: "server"}},
		// No controller-manager here to create it.
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: scopeSandboxes, Name: "default"}},
	)
	operatorCfg := rest.CopyConfig(cfg)
	operatorCfg.Impersonate = rest.ImpersonationConfig{UserName: "system:serviceaccount:" + scopeNamespace + ":operator"}
	operator, err := client.New(operatorCfg, client.Options{Scheme: clientgoscheme.Scheme})
	if err != nil {
		t.Fatal(err)
	}
	creds := &credentials.Manager{
		Client:                  operator,
		Namespace:               scopeNamespace,
		NodeIdentityClusterRole: scopeClusterRole,
		NodeIdentityRoles:       []types.NamespacedName{{Namespace: scopeRunners, Name: scopeClusterRole}},
		ClusterCA:               cfg.CAData,
	}
	access := &NodeAccessReconciler{Client: operator, Credentials: creds}
	host := func(node string) client.Client {
		t.Helper()
		identity, err := creds.EnsureTartKubeletIdentity(ctx, node, scopeFleet)
		if err != nil {
			t.Fatalf("identity for %s: %v", node, err)
		}
		hostCfg := rest.AnonymousClientConfig(cfg)
		hostCfg.BearerToken = string(identity.Token)
		c, err := client.New(hostCfg, client.Options{Scheme: clientgoscheme.Scheme})
		if err != nil {
			t.Fatal(err)
		}
		return c
	}
	a, b := host(hostA), host(hostB)

	// What tart-kubelet registers (nodeagent.configureNode).
	macNode := func(name string) *corev1.Node {
		return &corev1.Node{
			ObjectMeta: metav1.ObjectMeta{Name: name, Labels: map[string]string{
				"kubernetes.io/os": "darwin", "kubernetes.io/arch": "arm64", "kubernetes.io/hostname": name,
				"tuist.dev/runtime": "tart", "tuist.dev/fleet": scopeFleet, "tuist.dev/macos-sandbox-host": "v1",
			}},
			Spec: corev1.NodeSpec{Taints: []corev1.Taint{{Key: "tuist.dev/macos", Value: "true", Effect: corev1.TaintEffectNoSchedule}}},
		}
	}
	// The policy and the hosts' RBAC take effect a moment after they are
	// written; a host registering a Node of another name is the probe.
	waitFor := func(what string, check func() error) {
		t.Helper()
		deadline := time.Now().Add(30 * time.Second)
		for {
			err := check()
			if err == nil {
				return
			}
			if time.Now().After(deadline) {
				t.Fatalf("%s: %v", what, err)
			}
			time.Sleep(250 * time.Millisecond)
		}
	}
	denied := func(err error, message string) error {
		if err == nil {
			return errors.New("allowed")
		}
		if !strings.Contains(err.Error(), message) {
			return err
		}
		return nil
	}
	waitFor("the policy keeps a host to its own Node", func() error {
		return denied(a.Create(ctx, macNode("mac-z")), "only its own Node")
	})
	waitFor("host A registers its Node", func() error { return a.Create(ctx, macNode(hostA)) })
	waitFor("host B registers its Node", func() error { return b.Create(ctx, macNode(hostB)) })
	mustCreate(&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "general-1", Labels: map[string]string{
		"kubernetes.io/os": "linux", "node.cluster.x-k8s.io/pool": "general",
	}}})

	// B1: the ways to attract the server's Pod onto a Mac are refused.
	updateNode := func(c client.Client, name string, mutate func(*corev1.Node)) error {
		node := &corev1.Node{}
		if err := c.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
			return err
		}
		mutate(node)
		return c.Update(ctx, node)
	}
	for _, tc := range []struct {
		name, node, message string
		mutate              func(*corev1.Node)
	}{
		{"join the general pool", hostA, "only the darwin, hostname and tuist.dev/* labels", func(n *corev1.Node) {
			n.Labels["node.cluster.x-k8s.io/pool"] = "general"
		}},
		{"pass as Linux", hostA, "only the darwin, hostname and tuist.dev/* labels", func(n *corev1.Node) {
			n.Labels["kubernetes.io/os"] = "linux"
		}},
		{"drop the macOS taint", hostA, "keep the tuist.dev/macos taint", func(n *corev1.Node) { n.Spec.Taints = nil }},
		{"join another fleet", hostA, "only in the fleet the operator registered it in", func(n *corev1.Node) {
			n.Labels["tuist.dev/fleet"] = "tuist-tuist-xcresult-fleet"
		}},
		{"cordon a Linux node", "general-1", "only its own Node", func(n *corev1.Node) { n.Spec.Unschedulable = true }},
		{"taint another Mac", hostB, "only its own Node", func(n *corev1.Node) {
			n.Spec.Taints = append(n.Spec.Taints, corev1.Taint{Key: "tuist.dev/power-budget", Effect: corev1.TaintEffectNoSchedule})
		}},
		{"cordon itself", hostA, "may not cordon or uncordon", func(n *corev1.Node) { n.Spec.Unschedulable = true }},
	} {
		if err := denied(updateNode(a, tc.node, tc.mutate), tc.message); err != nil {
			t.Errorf("host A could %s: %v", tc.name, err)
		}
	}
	// What tart-kubelet does on a heartbeat still goes through.
	if err := updateNode(a, hostA, func(n *corev1.Node) {
		n.Labels["tuist.dev/golden-abc"] = "v1"
		n.Spec.Taints = append(n.Spec.Taints, corev1.Taint{Key: "tuist.dev/prewarming", Value: "true", Effect: corev1.TaintEffectNoSchedule})
	}); err != nil {
		t.Fatalf("a heartbeat's labels and prewarm taint: %v", err)
	}
	if err := updateNode(a, hostA, func(n *corev1.Node) {
		kept := n.Spec.Taints[:0]
		for _, taint := range n.Spec.Taints {
			if taint.Key != "tuist.dev/prewarming" {
				kept = append(kept, taint)
			}
		}
		n.Spec.Taints = kept
		n.Status.Conditions = []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}
	}); err != nil {
		t.Fatalf("lifting the prewarm taint: %v", err)
	}
	node := &corev1.Node{}
	if err := a.Get(ctx, types.NamespacedName{Name: hostA}, node); err != nil {
		t.Fatal(err)
	}
	node.Status.Conditions = []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue, Reason: "TartKubeletReady"}}
	if err := a.Status().Update(ctx, node); err != nil {
		t.Fatalf("status heartbeat: %v", err)
	}
	other := &corev1.Node{}
	if err := a.Get(ctx, types.NamespacedName{Name: hostB}, other); err != nil {
		t.Fatal(err)
	}
	other.Status.Conditions = []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionFalse}}
	if err := denied(a.Status().Update(ctx, other), "only its own Node"); err != nil {
		t.Errorf("host A wrote host B's status: %v", err)
	}

	// Pods: a runner and a sandbox control Pod on each Mac, and the server's
	// Pod bound to host A as if it had been attracted there anyway.
	secretRef := func(name string) []corev1.EnvVar {
		return []corev1.EnvVar{{Name: "S", ValueFrom: &corev1.EnvVarSource{SecretKeyRef: &corev1.SecretKeySelector{
			LocalObjectReference: corev1.LocalObjectReference{Name: name}, Key: "k",
		}}}}
	}
	pod := func(namespace, name, node, sa string, selector map[string]string, env []corev1.EnvVar) *corev1.Pod {
		return &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{Namespace: namespace, Name: name},
			Spec: corev1.PodSpec{
				NodeName: node, NodeSelector: selector, ServiceAccountName: sa,
				AutomountServiceAccountToken: ptr.To(false),
				Containers:                   []corev1.Container{{Name: "c", Image: "x", Env: env}},
			},
		}
	}
	darwin := map[string]string{"kubernetes.io/os": "darwin"}
	mustCreate(
		&corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: scopeRunners, Name: "runner-a"}},
		&corev1.Secret{ObjectMeta: metav1.ObjectMeta{Namespace: scopeNamespace, Name: "server-secrets"}},
		pod(scopeRunners, "runner-a", hostA, "runner", darwin, secretRef("runner-a")),
		pod(scopeSandboxes, "control-a", hostA, "tuist-macos-sandboxd", darwin, nil),
		pod(scopeSandboxes, "control-b", hostB, "tuist-macos-sandboxd", darwin, nil),
		pod(scopeNamespace, "server", hostA, "server", map[string]string{"node.cluster.x-k8s.io/pool": "general"}, secretRef("server-secrets")),
	)
	for _, n := range []string{hostA, hostB} {
		if _, err := access.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: n}}); err != nil {
			t.Fatalf("node access for %s: %v", n, err)
		}
	}
	waitFor("host A reads its runner's Secret", func() error {
		return a.Get(ctx, types.NamespacedName{Namespace: scopeRunners, Name: "runner-a"}, &corev1.Secret{})
	})
	if err := b.Get(ctx, types.NamespacedName{Namespace: scopeRunners, Name: "runner-a"}, &corev1.Secret{}); !apierrors.IsForbidden(err) {
		t.Errorf("host B read host A's runner Secret: %v", err)
	}
	if err := a.Get(ctx, types.NamespacedName{Namespace: scopeNamespace, Name: "server-secrets"}, &corev1.Secret{}); !apierrors.IsForbidden(err) {
		t.Errorf("host A read the server's Secrets through a Linux Pod bound to it: %v", err)
	}

	// B2: tokens for the shared sandbox account bind only to this host's Pods.
	mint := func(c client.Client, namespace, sa string, bound *corev1.Pod) error {
		req := &authenticationv1.TokenRequest{}
		if bound != nil {
			req.Spec.BoundObjectRef = &authenticationv1.BoundObjectReference{Kind: "Pod", APIVersion: "v1", Name: bound.Name, UID: bound.UID}
		}
		return c.SubResource("token").Create(ctx, &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Namespace: namespace, Name: sa}}, req)
	}
	controlA, controlB := &corev1.Pod{}, &corev1.Pod{}
	for p, name := range map[*corev1.Pod]string{controlA: "control-a", controlB: "control-b"} {
		if err := admin.Get(ctx, types.NamespacedName{Namespace: scopeSandboxes, Name: name}, p); err != nil {
			t.Fatal(err)
		}
	}
	waitFor("host A mints its control Pod's token", func() error {
		return mint(a, scopeSandboxes, "tuist-macos-sandboxd", controlA)
	})
	if err := denied(mint(a, scopeSandboxes, "tuist-macos-sandboxd", controlB), "bound to a Pod on its own Node"); err != nil {
		t.Errorf("host A minted a token as host B's control Pod: %v", err)
	}
	if err := denied(mint(a, scopeSandboxes, "tuist-macos-sandboxd", nil), "bound to a Pod on its own Node"); err != nil {
		t.Errorf("host A minted an unbound sandbox token: %v", err)
	}
	if err := mint(a, scopeRunners, scopeCacheSA, nil); err != nil {
		t.Errorf("the cache-volume agent's token: %v", err)
	}
	if err := mint(a, scopeNamespace, credentials.NodeIdentityServiceAccount(hostA), nil); err != nil {
		t.Errorf("host A rotating its own token: %v", err)
	}
	if err := mint(a, scopeNamespace, credentials.NodeIdentityServiceAccount(hostB), nil); err == nil {
		t.Error("host A minted host B's identity token")
	}

	// The macOS sandbox service's reservation (macosandbox.capacity) still
	// passes; a Pod naming a Secret does not.
	reservation := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: scopeSandboxes, Name: "reservation"},
		Spec: corev1.PodSpec{NodeName: hostA, RestartPolicy: corev1.RestartPolicyNever, AutomountServiceAccountToken: ptr.To(false),
			Containers: []corev1.Container{{Name: "sandbox", Image: "tuist-macos-sandbox-reservation"}}},
	}
	if err := a.Create(ctx, reservation); err != nil {
		t.Errorf("sandbox reservation: %v", err)
	}
	if err := denied(a.Create(ctx, pod(scopeSandboxes, "grab", hostA, "", darwin, secretRef("server-secrets"))), "may reference no Secret"); err != nil {
		t.Errorf("host A created a Pod naming a Secret: %v", err)
	}
}
