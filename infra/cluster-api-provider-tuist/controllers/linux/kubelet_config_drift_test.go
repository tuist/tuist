package linux

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

func TestDesiredKubeletConfigHash(t *testing.T) {
	ca1 := []byte("cluster-ca-one")
	ca2 := []byte("cluster-ca-two")
	if desiredKubeletConfigHash(ca1, "v1.34", false, false) != desiredKubeletConfigHash(ca1, "v1.34", false, false) {
		t.Fatal("desiredKubeletConfigHash must be stable across calls")
	}
	if desiredKubeletConfigHash(ca1, "v1.34", false, false) == "" {
		t.Fatal("desiredKubeletConfigHash must not be empty")
	}
	// The CA bundle is part of the fingerprint, so a CA rotation changes the hash
	// and re-pushes a fresh ca.crt onto already-stamped nodes.
	if desiredKubeletConfigHash(ca1, "v1.34", false, false) == desiredKubeletConfigHash(ca2, "v1.34", false, false) {
		t.Fatal("desiredKubeletConfigHash must change when the CA bundle changes")
	}
	// The hashed config is the post-fix one (clientCAFile set, serverTLSBootstrap
	// unset), so existing (pre-fix) nodes drift and get re-pushed.
	cfg := kubeletConfigContent("", kubeletClientCAPath, "v1.34", false)
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
		"tee /etc/sysctl.d/99-tuist-hardening.conf > /dev/null <<'TUIST_EOF'",
		"kernel.io_uring_disabled = 1",
		"sysctl -p /etc/sysctl.d/99-tuist-hardening.conf",
		`[ "$(cat /proc/sys/kernel/io_uring_disabled)" -ge 1 ]`,
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
	node.Annotations = map[string]string{kubeletConfigHashAnnotation: desiredKubeletConfigHash(ca, "v1.34", false, false)}

	// The node is stamped with the current CA's hash, so the drift check reads the
	// identity, matches, and returns before discovering DNS or dialing SSH (the
	// nil apiReader is safe precisely because the converged path stops at the
	// compare).
	requeue, err := reconcileLinuxKubeletConfigDrift(context.Background(), c, nil, cm, KubeletIdentityMode{}, nil, "m", "fleet", "ubuntu", false, node)
	if err != nil || requeue {
		t.Fatalf("expected no-op (requeue=false, err=nil) when the node is already stamped, got requeue=%v err=%v", requeue, err)
	}
}

// A node whose kubelet could not get a certificate waits an hour before the
// next attempt, which restarts its kubelet twice, instead of every resync.
func TestCertificateMigrationBacksOffAfterAFailure(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	for name, tc := range map[string]struct {
		failedAt time.Duration
		held     bool
	}{
		"failed ten minutes ago": {10 * time.Minute, true},
		"failed two hours ago":   {2 * time.Hour, false},
	} {
		t.Run(name, func(t *testing.T) {
			node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "m", Annotations: map[string]string{
				kubeletIdentityFailedAnnotation: time.Now().Add(-tc.failedAt).UTC().Format(time.RFC3339)}}}
			c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(node).Build()
			cm := &credentials.Manager{Client: c, Namespace: "tuist", ClusterCA: []byte("ca\n")}
			// Past the hold, the re-push defers on the missing kube-dns Service.
			requeue, err := reconcileLinuxKubeletConfigDrift(context.Background(), c, c, cm, KubeletIdentityMode{Certificates: true}, nil, "m", "fleet", "ubuntu", false, node)
			if err != nil {
				t.Fatal(err)
			}
			if held := !requeue; held != tc.held {
				t.Errorf("held = %v, want %v", held, tc.held)
			}
		})
	}
}

// The re-push restarts the kubelet on every Ready node, and a v1.34 kubelet
// panics on the v1.36 feature gate. So the desired config must follow the
// kubelet each node runs: a v1.34 Kata node stays converged on its v1.34
// config, and a v1.36 one converges on the pod-level config, not the reverse.
func TestReconcileLinuxKubeletConfigDrift_FollowsTheNodesKubelet(t *testing.T) {
	const ns = "tuist-fleet"
	ca := []byte("-----BEGIN CERTIFICATE-----\nMIIBstampCAbytes\n-----END CERTIFICATE-----\n")
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := rbacv1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	tokenSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: "tart-kubelet-m-token"},
		Type:       corev1.SecretTypeServiceAccountToken,
		Data:       map[string][]byte{"token": []byte("tok"), "ca.crt": ca},
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(tokenSecret).Build()
	cm := &credentials.Manager{Client: c, Namespace: ns, NodeIdentityClusterRole: linuxNodeIdentityClusterRole}

	for _, tc := range []struct {
		kubelet, stampedFor string
		converged           bool
	}{
		{kubelet: "v1.34.11", stampedFor: "v1.34", converged: true},
		{kubelet: "v1.34.11", stampedFor: "v1.36"},
		{kubelet: "v1.36.6", stampedFor: "v1.36", converged: true},
		{kubelet: "v1.36.6", stampedFor: "v1.34"},
	} {
		node := &corev1.Node{}
		node.Status.NodeInfo.KubeletVersion = tc.kubelet
		node.Annotations = map[string]string{kubeletConfigHashAnnotation: desiredKubeletConfigHash(ca, tc.stampedFor, true, false)}
		// A drifted node goes on to discover clusterDNS, finds no kube-dns
		// Service in the fake client, and defers with requeue=true.
		requeue, err := reconcileLinuxKubeletConfigDrift(context.Background(), c, c, cm, KubeletIdentityMode{}, nil, "m", "fleet", "ubuntu", true, node)
		if err != nil {
			t.Fatal(err)
		}
		if requeue == tc.converged {
			t.Fatalf("kubelet %s stamped with the %s config: requeue=%v, want converged=%v", tc.kubelet, tc.stampedFor, requeue, tc.converged)
		}
	}
}

// A re-push restarts the kubelet, which leaks the cores of every Pod with
// exclusive CPUs on the node (kubernetes/kubernetes#140989). A drifted node
// holding such a Pod, idle or running a job, keeps its config until the Pod is
// gone; Pods without a Pod-level CPU budget never hold it. A held node returns
// requeue=false; one that proceeds looks up kube-dns, finds none in the fake
// client, and defers with requeue=true.
func TestReconcileLinuxKubeletConfigDrift_HoldsForExclusiveCPUPods(t *testing.T) {
	const ns = "tuist-fleet"
	ca := []byte("-----BEGIN CERTIFICATE-----\nMIIBstampCAbytes\n-----END CERTIFICATE-----\n")
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := rbacv1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	twoCPUs := corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("2"), corev1.ResourceMemory: resource.MustParse("8Gi")}
	exclusive := func(name, nodeName string, phase corev1.PodPhase) *corev1.Pod {
		pod := runnerPod(name, nodeName, phase)
		pod.Spec.Resources = &corev1.ResourceRequirements{Requests: twoCPUs, Limits: twoCPUs}
		return pod
	}
	shared := runnerPod("shared", runnerBox, corev1.PodRunning)
	shared.Spec.Containers = []corev1.Container{{Name: "runner", Resources: corev1.ResourceRequirements{Requests: twoCPUs, Limits: twoCPUs}}}

	for _, tc := range []struct {
		name string
		pod  *corev1.Pod
		held bool
	}{
		{name: "an exclusive-CPU Pod running a job", pod: exclusive("job", runnerBox, corev1.PodRunning), held: true},
		{name: "an idle exclusive-CPU Pod on standby", pod: exclusive("standby", runnerBox, corev1.PodPending), held: true},
		{name: "a runner Pod on shared CPUs", pod: shared},
		{name: "an exclusive-CPU Pod on another node", pod: exclusive("elsewhere", "another-box", corev1.PodRunning)},
		{name: "a finished exclusive-CPU Pod", pod: exclusive("done", runnerBox, corev1.PodSucceeded)},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tokenSecret := &corev1.Secret{
				ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: "tart-kubelet-m-token"},
				Type:       corev1.SecretTypeServiceAccountToken,
				Data:       map[string][]byte{"token": []byte("tok"), "ca.crt": ca},
			}
			c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(tokenSecret, tc.pod).Build()
			cm := &credentials.Manager{Client: c, Namespace: ns, NodeIdentityClusterRole: linuxNodeIdentityClusterRole}
			node := runnerBoxNode(corev1.ConditionTrue)
			node.Status.NodeInfo.KubeletVersion = "v1.36.6"
			node.Annotations = map[string]string{kubeletConfigHashAnnotation: "stale"}

			requeue, err := reconcileLinuxKubeletConfigDrift(context.Background(), c, c, cm, KubeletIdentityMode{}, nil, "m", "fleet", "ubuntu", true, node)
			if err != nil {
				t.Fatal(err)
			}
			if requeue == tc.held {
				t.Fatalf("requeue=%v, want the re-push held=%v", requeue, tc.held)
			}
		})
	}
}

func TestNodeInternalIP(t *testing.T) {
	node := &corev1.Node{}
	node.Status.Addresses = []corev1.NodeAddress{
		{Type: corev1.NodeHostName, Address: "tuist-tuist-ovh-fleet-abc"},
		{Type: corev1.NodeInternalIP, Address: "195.154.208.48"},
	}
	if got := nodeInternalIP(node); got != "195.154.208.48" {
		t.Fatalf("expected the node InternalIP, got %q", got)
	}
	if got := nodeInternalIP(&corev1.Node{}); got != "" {
		t.Fatalf("expected empty string when no InternalIP, got %q", got)
	}
}

func TestDesiredKubeletConfigHashCoversTheSSHStartLimitDropIns(t *testing.T) {
	ca := []byte("cluster-ca")
	h := sha256.New()
	h.Write([]byte(kubeletConfigContent("", kubeletClientCAPath, "v1.34", false)))
	h.Write(ca)
	if desiredKubeletConfigHash(ca, "v1.34", false, false) == hex.EncodeToString(h.Sum(nil)) {
		t.Fatal("expected the sshd drop-ins in the hash, so nodes stamped before them drift and receive them")
	}
}

func TestRenderKubeletConfigRepushScript_InstallsSSHStartLimitDropIns(t *testing.T) {
	s := renderKubeletConfigRepushScript(linuxCloudInitOptions{
		ClusterDNS:    "10.96.0.10",
		BootstrapUser: "ubuntu",
	})
	for _, want := range []string{
		sshStartLimitDropIns("sudo ", writeFileFunc("sudo ")),
		"sudo systemctl daemon-reload",
	} {
		if !strings.Contains(s, want) {
			t.Fatalf("expected re-push script to contain %q, got:\n%s", want, s)
		}
	}
	if strings.Index(s, sshSocketDropInPath) > strings.Index(s, "systemctl daemon-reload") {
		t.Fatalf("expected the drop-ins written before the daemon-reload that loads them, got:\n%s", s)
	}
	// The re-push runs over the very SSH session these units serve.
	for _, banned := range []string{"restart ssh", "stop ssh", "reload ssh", "daemon-reexec"} {
		if strings.Contains(s, banned) {
			t.Fatalf("re-push must not run %q under its own SSH session, got:\n%s", banned, s)
		}
	}
	syntax := exec.Command("bash", "-n")
	syntax.Stdin = strings.NewReader(s)
	if output, err := syntax.CombinedOutput(); err != nil {
		t.Fatalf("invalid script: %s: %v", output, err)
	}
}

// A node joined on a ServiceAccount moves onto a certificate identity in
// place: the unit edit must leave exactly the unit a certificate join renders,
// or the kubelet keeps running without its bootstrap kubeconfig.
func TestKubeletUnitMigratesToTheCertificateJoinsUnit(t *testing.T) {
	taints := taintArgFor([]corev1.Taint{{Key: "tuist.dev/kura", Value: "true", Effect: corev1.TaintEffectNoSchedule}})
	labels := kataNodeLabelsArg(true, true)
	unit := filepath.Join(t.TempDir(), "kubelet.service")
	if err := os.WriteFile(unit, []byte(kubeletUnitContent("node-a", taints, "ovh", labels, false)), 0o644); err != nil {
		t.Fatal(err)
	}
	for range 2 { // the second run must change nothing
		if out, err := exec.Command("bash", "-ec", kubeletUnitBootstrapFlag("", unit)).CombinedOutput(); err != nil {
			t.Fatalf("%v: %s", err, out)
		}
	}
	got, _ := os.ReadFile(unit)
	if want := kubeletUnitContent("node-a", taints, "ovh", labels, true); string(got) != want {
		t.Errorf("migrated unit:\n%s\nwant:\n%s", got, want)
	}

	opts := linuxCloudInitOptions{NodeName: "node-a", NodeCertificates: true, BootstrapKubeconfigYAML: "kind: Config\n",
		ClusterCAPEM: []byte("ca"), K8sMinor: "v1.36", BootstrapUser: "ubuntu", KataRuntime: true}
	for name, script := range map[string]string{"re-push": renderKubeletConfigRepushScript(opts), "join": renderLinuxBootstrapScript(opts)} {
		if out, err := exec.Command("bash", "-n", "-c", script).CombinedOutput(); err != nil {
			t.Errorf("%s script does not parse: %v: %s", name, err, out)
		}
		for _, want := range []string{"rotateCertificates: true", kubeletBootstrapKubeconfigPath, "kubelet-client-current.pem"} {
			if !strings.Contains(script, want) {
				t.Errorf("%s script lacks %q", name, want)
			}
		}
		if strings.Contains(script, "tee /var/lib/kubelet/kubeconfig") {
			t.Errorf("%s script writes a ServiceAccount kubeconfig", name)
		}
	}
	if desiredKubeletConfigHash([]byte("ca"), "v1.36", true, true) == desiredKubeletConfigHash([]byte("ca"), "v1.36", true, false) {
		t.Error("turning certificates on would not re-push joined nodes")
	}
}

// runRepushInRoot runs the certificate re-push in a temporary root with a fake
// systemctl and sysctl. kubeletIssues says whether the fake kubelet gets a
// client certificate when restarted with a bootstrap kubeconfig.
func runRepushInRoot(t *testing.T, unit string, kubeletIssues bool) (root string, err error) {
	t.Helper()
	return runRepush(t, repushRun{unit: unit, kubeletIssues: kubeletIssues})
}

type repushRun struct {
	unit          string
	kubeletIssues bool
	// interrupted leaves the files as a run killed during the certificate
	// wait does: the backups, the migrated config and unit, no kubeconfig.
	interrupted bool
	// hangUp closes the script's output at once, as a dropped SSH session does.
	hangUp bool
}

func runRepush(t *testing.T, run repushRun) (root string, err error) {
	t.Helper()
	unit, kubeletIssues := run.unit, run.kubeletIssues
	root = t.TempDir()
	bin := filepath.Join(root, "bin")
	kubelet := filepath.Join(root, "var/lib/kubelet")
	for _, d := range []string{bin, kubelet, filepath.Join(root, "etc/systemd/system"), filepath.Join(root, "run/lock")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write := func(p, content string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(root, p), []byte(content), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	write("var/lib/kubelet/config.yaml", "old config\n")
	write("var/lib/kubelet/kubeconfig", "users: [{user: {token: sa}}]\n")
	write("etc/systemd/system/kubelet.service", unit)
	if run.interrupted {
		for _, p := range []string{"var/lib/kubelet/config.yaml", "etc/systemd/system/kubelet.service"} {
			if err := os.Rename(filepath.Join(root, p), filepath.Join(root, p+".serviceaccount")); err != nil {
				t.Fatal(err)
			}
		}
		if err := os.Rename(filepath.Join(root, "var/lib/kubelet/kubeconfig"), filepath.Join(root, "var/lib/kubelet/kubeconfig.serviceaccount")); err != nil {
			t.Fatal(err)
		}
		write("var/lib/kubelet/config.yaml", "rotateCertificates: true\n")
		write("etc/systemd/system/kubelet.service", kubeletUnitContent("node-a", "", "ovh", "", true))
		write("var/lib/kubelet/bootstrap-kubeconfig", "bootstrap\n")
	}
	issue := ""
	if kubeletIssues {
		// A kubelet with --bootstrap-kubeconfig and no valid kubeconfig
		// gets a certificate and writes a kubeconfig naming it.
		issue = fmt.Sprintf(`if [ "$1 $2" = "restart kubelet" ] && grep -q -- --bootstrap-kubeconfig= %[1]s/etc/systemd/system/kubelet.service && ! grep -qs client-certificate %[1]s/var/lib/kubelet/kubeconfig; then
  mkdir -p %[1]s/var/lib/kubelet/pki && echo cert > %[1]s/var/lib/kubelet/pki/kubelet-client-current.pem
  echo "client-certificate: pki/kubelet-client-current.pem" > %[1]s/var/lib/kubelet/kubeconfig
fi
`, root)
	}
	write("bin/systemctl", "#!/bin/bash\n"+issue)
	write("bin/sysctl", "#!/bin/bash\n")

	script := renderKubeletConfigRepushScript(linuxCloudInitOptions{NodeName: "node-a", NodeCertificates: true,
		BootstrapKubeconfigYAML: "bootstrap\n", ClusterCAPEM: []byte("ca\n"), K8sMinor: "v1.36", BootstrapUser: "root"})
	for _, d := range []string{"/var/lib/", "/etc/", "/run/"} {
		script = strings.ReplaceAll(script, " "+d, " "+root+d)
		script = strings.ReplaceAll(script, "'"+d, "'"+root+d)
	}
	script = strings.ReplaceAll(script, "seq 1 60", "seq 1 1")
	script = strings.ReplaceAll(script, "/proc/sys/kernel/io_uring_disabled", root+"/no-such-file")
	cmd := exec.Command("bash", "-c", script)
	cmd.Env = append(os.Environ(), "PATH="+bin+":"+os.Getenv("PATH"))
	if !run.hangUp {
		out, err := cmd.CombinedOutput()
		t.Logf("%s", out)
		return root, err
	}
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	cmd.Stdout, cmd.Stderr = w, w
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	w.Close()
	r.Close()
	return root, cmd.Wait()
}

// A node whose kubelet gets no certificate must come back exactly as it ran on
// its ServiceAccount: with rotateCertificates or --bootstrap-kubeconfig left
// behind, the kubelet bootstraps over the restored kubeconfig and goes
// NotReady once the bootstrap token is deleted.
func TestCertificateMigrationRestoresTheServiceAccountKubelet(t *testing.T) {
	unit := kubeletUnitContent("node-a", "", "ovh", "", false)
	for name, tc := range map[string]struct{ unit string }{
		"no certificate":   {unit},
		"unit edit failed": {"[Service]\nExecStart=/usr/bin/kubelet --kubeconfig=/var/lib/kubelet/kubeconfig\n"},
	} {
		t.Run(name, func(t *testing.T) {
			root, err := runRepushInRoot(t, tc.unit, false)
			if err == nil {
				t.Fatal("the re-push succeeded")
			}
			// Only a missing certificate holds the node off its next attempt.
			var exitErr *exec.ExitError
			if noCertificate := errors.As(err, &exitErr) && exitErr.ExitCode() == kubeletNoCertificateExit; noCertificate != (name == "no certificate") {
				t.Errorf("exit = %v, want status %d only without a certificate", err, kubeletNoCertificateExit)
			}
			for p, want := range map[string]string{
				"var/lib/kubelet/config.yaml":        "old config\n",
				"var/lib/kubelet/kubeconfig":         "users: [{user: {token: sa}}]\n",
				"etc/systemd/system/kubelet.service": tc.unit,
			} {
				if got, _ := os.ReadFile(filepath.Join(root, p)); string(got) != want {
					t.Errorf("%s = %q, want %q", p, got, want)
				}
			}
			for _, p := range []string{"var/lib/kubelet/bootstrap-kubeconfig", "var/lib/kubelet/kubeconfig.serviceaccount",
				"var/lib/kubelet/config.yaml.serviceaccount", "etc/systemd/system/kubelet.service.serviceaccount"} {
				if _, err := os.Stat(filepath.Join(root, p)); err == nil {
					t.Errorf("%s left behind", p)
				}
			}
		})
	}
	t.Run("certificate", func(t *testing.T) {
		root, err := runRepushInRoot(t, unit, true)
		if err != nil {
			t.Fatalf("the re-push failed: %v", err)
		}
		if got, _ := os.ReadFile(filepath.Join(root, "etc/systemd/system/kubelet.service")); string(got) != kubeletUnitContent("node-a", "", "ovh", "", true) {
			t.Errorf("unit:\n%s", got)
		}
		if got, _ := os.ReadFile(filepath.Join(root, "var/lib/kubelet/config.yaml")); !strings.Contains(string(got), "rotateCertificates: true") {
			t.Errorf("config.yaml does not rotate certificates:\n%s", got)
		}
		for _, p := range []string{"var/lib/kubelet/bootstrap-kubeconfig", "var/lib/kubelet/kubeconfig.serviceaccount",
			"var/lib/kubelet/config.yaml.serviceaccount", "etc/systemd/system/kubelet.service.serviceaccount"} {
			if _, err := os.Stat(filepath.Join(root, p)); err == nil {
				t.Errorf("%s left behind", p)
			}
		}
	})
}

// A dropped SSH session must not leave the kubelet half migrated: under
// set -x the next trace write would kill bash with SIGPIPE before its EXIT
// trap runs. A run killed anyway is restored by the next one.
func TestCertificateMigrationSurvivesADroppedSession(t *testing.T) {
	unit := kubeletUnitContent("node-a", "", "ovh", "", false)
	saFiles := map[string]string{
		"var/lib/kubelet/config.yaml":        "old config\n",
		"var/lib/kubelet/kubeconfig":         "users: [{user: {token: sa}}]\n",
		"etc/systemd/system/kubelet.service": unit,
	}
	backups := []string{"var/lib/kubelet/bootstrap-kubeconfig", "var/lib/kubelet/kubeconfig.serviceaccount",
		"var/lib/kubelet/config.yaml.serviceaccount", "etc/systemd/system/kubelet.service.serviceaccount"}
	for name, tc := range map[string]struct {
		run      repushRun
		migrated bool
	}{
		"hung up, certificate issued":        {repushRun{unit: unit, kubeletIssues: true, hangUp: true}, true},
		"hung up, no certificate":            {repushRun{unit: unit, hangUp: true}, false},
		"after a killed run, no certificate": {repushRun{unit: unit, interrupted: true}, false},
		"after a killed run, certificate":    {repushRun{unit: unit, interrupted: true, kubeletIssues: true}, true},
	} {
		t.Run(name, func(t *testing.T) {
			root, err := runRepush(t, tc.run)
			if (err == nil) != tc.migrated {
				t.Fatalf("re-push error = %v, want migrated = %v", err, tc.migrated)
			}
			if tc.migrated {
				if got, _ := os.ReadFile(filepath.Join(root, "var/lib/kubelet/kubeconfig")); !strings.Contains(string(got), "client-certificate") {
					t.Errorf("kubeconfig = %q, want the certificate", got)
				}
			} else {
				for p, want := range saFiles {
					if got, _ := os.ReadFile(filepath.Join(root, p)); string(got) != want {
						t.Errorf("%s = %q, want %q", p, got, want)
					}
				}
			}
			for _, p := range backups {
				if _, err := os.Stat(filepath.Join(root, p)); err == nil {
					t.Errorf("%s left behind", p)
				}
			}
		})
	}
}

// A box re-adopted under another name must not keep the certificate it held
// as its old node: NodeRestriction refuses the new Node, and the join's
// certificate wait passes at once on the old one.
func TestCertificateJoinDropsAnotherNodesCertificate(t *testing.T) {
	heredoc := func(path, content string) string { return "cat > " + path + " <<'E'\n" + content + "E" }
	for name, tc := range map[string]struct {
		marker     string
		kubeconfig string
		keep       bool
	}{
		"another node's certificate": {"node-old\n", "client-certificate: pki/kubelet-client-current.pem\n", false},
		"its own certificate":        {"node-a\n", "client-certificate: pki/kubelet-client-current.pem\n", true},
		"a ServiceAccount token":     {"node-a\n", "token: sa\n", false},
	} {
		t.Run(name, func(t *testing.T) {
			root := t.TempDir()
			for _, d := range []string{"var/lib/kubelet/pki", "var/lib/tuist"} {
				if err := os.MkdirAll(filepath.Join(root, d), 0o755); err != nil {
					t.Fatal(err)
				}
			}
			os.WriteFile(filepath.Join(root, "var/lib/tuist/joined-node"), []byte(tc.marker), 0o644)
			os.WriteFile(filepath.Join(root, "var/lib/kubelet/kubeconfig"), []byte(tc.kubeconfig), 0o600)
			os.WriteFile(filepath.Join(root, "var/lib/kubelet/pki/kubelet-client-current.pem"), []byte("cert"), 0o600)
			os.WriteFile(filepath.Join(root, "var/lib/kubelet/pki/kubelet.crt"), []byte("serving"), 0o600)
			script := kubeletCredentialWrite("", linuxCloudInitOptions{NodeName: "node-a", NodeCertificates: true, BootstrapKubeconfigYAML: "b\n"}, heredoc)
			script = strings.ReplaceAll(script, "/var/lib/", root+"/var/lib/")
			if out, err := exec.Command("bash", "-ec", script).CombinedOutput(); err != nil {
				t.Fatalf("%v: %s", err, out)
			}
			_, err := os.Stat(filepath.Join(root, "var/lib/kubelet/kubeconfig"))
			if kept := err == nil; kept != tc.keep {
				t.Errorf("kubeconfig kept = %v, want %v", kept, tc.keep)
			}
			// The serving certificate names the node; only another node's goes.
			_, err = os.Stat(filepath.Join(root, "var/lib/kubelet/pki/kubelet.crt"))
			if kept, want := err == nil, tc.marker == "node-a\n"; kept != want {
				t.Errorf("serving certificate kept = %v, want %v", kept, want)
			}
			if _, err := os.Stat(filepath.Join(root, "var/lib/kubelet/bootstrap-kubeconfig")); err != nil {
				t.Errorf("no bootstrap kubeconfig: %v", err)
			}
		})
	}
}
