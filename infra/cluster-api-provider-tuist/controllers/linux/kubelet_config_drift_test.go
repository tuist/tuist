package linux

import (
	"context"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
)

func TestDesiredKubeletConfigHash(t *testing.T) {
	if desiredKubeletConfigHash() != desiredKubeletConfigHash() {
		t.Fatal("desiredKubeletConfigHash must be stable across calls")
	}
	if desiredKubeletConfigHash() == "" {
		t.Fatal("desiredKubeletConfigHash must not be empty")
	}
	// The hashed config is the post-fix one — clientCAFile set, serverTLSBootstrap
	// unset — so existing (pre-fix) nodes drift and get re-pushed.
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
	node := &corev1.Node{}
	node.Annotations = map[string]string{kubeletConfigHashAnnotation: desiredKubeletConfigHash()}

	// A matching stamp short-circuits before any client / credentials / SSH use,
	// so nil dependencies are safe here — that's the point: the steady-state
	// reconcile does no work.
	requeue, err := reconcileLinuxKubeletConfigDrift(context.Background(), nil, nil, nil, "m", "fleet", "ubuntu", node)
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
