package linux

import (
	"context"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

func TestDesiredKubeletConfigHash(t *testing.T) {
	ca1 := []byte("cluster-ca-one")
	ca2 := []byte("cluster-ca-two")
	if desiredKubeletConfigHash(ca1) != desiredKubeletConfigHash(ca1) {
		t.Fatal("desiredKubeletConfigHash must be stable across calls")
	}
	if desiredKubeletConfigHash(ca1) == "" {
		t.Fatal("desiredKubeletConfigHash must not be empty")
	}
	// The CA bundle is part of the fingerprint, so a CA rotation changes the hash
	// and re-pushes a fresh ca.crt onto already-stamped nodes.
	if desiredKubeletConfigHash(ca1) == desiredKubeletConfigHash(ca2) {
		t.Fatal("desiredKubeletConfigHash must change when the CA bundle changes")
	}
	// The hashed config is the post-fix one (clientCAFile set, serverTLSBootstrap
	// unset), so existing (pre-fix) nodes drift and get re-pushed.
	cfg := kubeletConfigContent("", kubeletClientCAPath)
	if !strings.Contains(cfg, "clientCAFile: "+kubeletClientCAPath) {
		t.Fatalf("expected clientCAFile in the hashed config, got:\n%s", cfg)
	}
	if strings.Contains(cfg, "serverTLSBootstrap") {
		t.Fatalf("expected serverTLSBootstrap absent in the hashed config, got:\n%s", cfg)
	}
}

func TestRenderKubeletConfigRepushScript(t *testing.T) {
	ca := "-----BEGIN CERTIFICATE-----\nMIIBrepushCAbytes\n-----END CERTIFICATE-----\n"
	s := renderKubeletConfigRepushScript(linuxCloudInitOptions{
		ClusterDNS:    "10.96.0.10",
		ClusterCAPEM:  []byte(ca),
		BootstrapUser: "ubuntu",
	})

	for _, want := range []string{
		"tee /var/lib/kubelet/ca.crt > /dev/null <<'TUIST_EOF'",
		"-----BEGIN CERTIFICATE-----",
		"tee /var/lib/kubelet/config.yaml > /dev/null <<'TUIST_EOF'",
		"clientCAFile: /var/lib/kubelet/ca.crt",
		"clusterDNS:\n  - 10.96.0.10",
		"systemctl restart kubelet",
	} {
		if !strings.Contains(s, want) {
			t.Fatalf("expected re-push script to contain %q, got:\n%s", want, s)
		}
	}

	// Zero-downtime subset: the re-push must NOT reinstall containerd/kubelet,
	// touch apt, or re-run the /data mounts — those would disrupt running pods.
	for _, banned := range []string{"apt-get", "containerd", "modprobe", "mount --bind", "swapoff", "install -y kubelet"} {
		if strings.Contains(s, banned) {
			t.Fatalf("re-push must not run %q (not zero-downtime), got:\n%s", banned, s)
		}
	}
	if strings.Contains(s, "serverTLSBootstrap") {
		t.Fatalf("re-push config must leave serverTLSBootstrap unset, got:\n%s", s)
	}
	// CA is written before the config.yaml that references it.
	if strings.Index(s, "/var/lib/kubelet/ca.crt") > strings.Index(s, "/var/lib/kubelet/config.yaml") {
		t.Fatalf("expected ca.crt written before config.yaml, got:\n%s", s)
	}
}

func TestRenderKubeletConfigRepushScript_NoCA(t *testing.T) {
	s := renderKubeletConfigRepushScript(linuxCloudInitOptions{
		ClusterDNS:    "10.96.0.10",
		BootstrapUser: "ubuntu",
	})
	if strings.Contains(s, "ca.crt") || strings.Contains(s, "clientCAFile") {
		t.Fatalf("expected no CA write / clientCAFile without a CA, got:\n%s", s)
	}
	if !strings.Contains(s, "systemctl restart kubelet") {
		t.Fatalf("expected the kubelet restart, got:\n%s", s)
	}
}

func TestReconcileLinuxKubeletConfigDrift_NoOpWhenStamped(t *testing.T) {
	const ns = "tuist-fleet"
	ca := []byte("-----BEGIN CERTIFICATE-----\nMIIBstampCAbytes\n-----END CERTIFICATE-----\n")

	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := rbacv1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	// A pre-populated node-identity token secret lets EnsureNodeIdentity return
	// the CA without a real token controller (the SA + binding are created by the
	// idempotent ensures against the fake client).
	tokenSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: "tart-kubelet-m-token"},
		Type:       corev1.SecretTypeServiceAccountToken,
		Data:       map[string][]byte{"token": []byte("tok"), "ca.crt": ca},
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(tokenSecret).Build()
	cm := &credentials.Manager{Client: c, Namespace: ns, NodeIdentityClusterRole: linuxNodeIdentityClusterRole}

	node := &corev1.Node{}
	node.Annotations = map[string]string{kubeletConfigHashAnnotation: desiredKubeletConfigHash(ca)}

	// The node is stamped with the current CA's hash, so the drift check reads the
	// identity, matches, and returns before discovering DNS or dialing SSH (the
	// nil apiReader is safe precisely because the converged path stops at the
	// compare).
	requeue, err := reconcileLinuxKubeletConfigDrift(context.Background(), c, nil, cm, "m", "fleet", "ubuntu", node)
	if err != nil || requeue {
		t.Fatalf("expected no-op (requeue=false, err=nil) when the node is already stamped, got requeue=%v err=%v", requeue, err)
	}
}

func TestNodeInternalIP(t *testing.T) {
	node := &corev1.Node{}
	node.Status.Addresses = []corev1.NodeAddress{
		{Type: corev1.NodeHostName, Address: "tuist-tuist-dedibox-fleet-abc"},
		{Type: corev1.NodeInternalIP, Address: "195.154.208.48"},
	}
	if got := nodeInternalIP(node); got != "195.154.208.48" {
		t.Fatalf("expected the node InternalIP, got %q", got)
	}
	if got := nodeInternalIP(&corev1.Node{}); got != "" {
		t.Fatalf("expected empty string when no InternalIP, got %q", got)
	}
}
