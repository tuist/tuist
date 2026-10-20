package linux

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/yaml"
)

func TestKataSharedMemoryScript(t *testing.T) {
	for _, tc := range []struct {
		name, initial, fs, failure, want string
		wantError, wantMount             bool
	}{
		{name: "grow default ceiling", initial: "65536", fs: "tmpfs", want: "131072", wantMount: true},
		{name: "already sized", initial: "131072", fs: "tmpfs", want: "131072"},
		{name: "preserve larger ceiling", initial: "262144", fs: "tmpfs", want: "262144"},
		{name: "refuse other filesystem", initial: "65536", fs: "ext4", want: "65536", wantError: true},
		{name: "failed remount", initial: "65536", fs: "tmpfs", failure: "fail", want: "65536", wantError: true, wantMount: true},
		{name: "verify remount took effect", initial: "65536", fs: "tmpfs", failure: "noop", want: "65536", wantError: true, wantMount: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			// All privileged/host-dependent commands are replaced. Execute the
			// actual service script, but never mount anything on the test host.
			shim := `#!/bin/sh
case "${0##*/}" in
  findmnt) echo "$TEST_FS" ;;
  awk) echo 128 ;;
  df) echo Size; cat "$TEST_DIR/size" ;;
  mount)
    printf '%s\n' "$*" >> "$TEST_DIR/mounts"
    [ "$*" = '-o remount,size=128k /dev/shm' ] || exit 2
    [ "$TEST_FAILURE" != fail ] || exit 1
    [ "$TEST_FAILURE" = noop ] || echo 131072 > "$TEST_DIR/size"
    ;;
esac
`
			for _, name := range []string{"findmnt", "awk", "df", "mount"} {
				if err := os.WriteFile(filepath.Join(dir, name), []byte(shim), 0755); err != nil {
					t.Fatal(err)
				}
			}
			if err := os.WriteFile(filepath.Join(dir, "size"), []byte(tc.initial), 0600); err != nil {
				t.Fatal(err)
			}
			for attempt := 0; attempt < 2; attempt++ {
				cmd := exec.Command("/bin/sh", "-s")
				cmd.Stdin = strings.NewReader(kataSharedMemoryScript)
				cmd.Env = append(os.Environ(), "PATH="+dir+":/usr/bin:/bin", "TEST_DIR="+dir,
					"TEST_FS="+tc.fs, "TEST_FAILURE="+tc.failure)
				out, err := cmd.CombinedOutput()
				if (err != nil) != tc.wantError {
					t.Fatalf("attempt %d: err=%v output=%s", attempt, err, out)
				}
			}
			size, err := os.ReadFile(filepath.Join(dir, "size"))
			if err != nil || strings.TrimSpace(string(size)) != tc.want {
				t.Fatalf("size=%q err=%v, want %s", size, err, tc.want)
			}
			mounts, err := os.ReadFile(filepath.Join(dir, "mounts"))
			if tc.wantMount != (err == nil) {
				t.Fatalf("mounts=%q err=%v, wantMount=%v", mounts, err, tc.wantMount)
			}
			if !tc.wantError && strings.Count(string(mounts), "\n") > 1 {
				t.Fatal("second run must not remount a sufficient ceiling")
			}
		})
	}
}

func TestKataSharedMemoryDriftOnExistingHost(t *testing.T) {
	for _, revision := range []string{"", "old-configuration", "previous-boot"} {
		t.Run(revision, func(t *testing.T) {
			h := newKataHarness(t, true, map[string]string{KataRuntimeSelectorLabel: "true"})
			h.node.Annotations[kataSharedMemoryAnnotation] = revision
			if err := h.client.Update(context.Background(), h.node); err != nil {
				t.Fatal(err)
			}
			h.reconcile()
			cond := conditions.Get(h.machine, KataRuntimeReadyCondition)
			if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != KataSharedMemoryUnverifiedReason {
				t.Fatalf("unverified shared memory must be surfaced: %v", cond)
			}
			if h.liveNode().Annotations[kataSharedMemoryAnnotation] != revision {
				t.Fatal("a deferred repair must not stamp the node")
			}
			if !h.machine.Status.Ready {
				t.Fatal("shared-memory drift must not cause CAPI to replace a healthy node")
			}
		})
	}
}

func TestKataSharedMemoryRepairFailureNeverRecordsProof(t *testing.T) {
	h := newKataHarness(t, true, map[string]string{KataRuntimeSelectorLabel: "true"})
	h.node.Status.Addresses = []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "127.0.0.1"}}
	if err := h.client.Status().Update(context.Background(), h.node); err != nil {
		t.Fatal(err)
	}
	_, err := reconcileLinuxKataRuntimeDrift(context.Background(), h.client, h.r.CredentialsManager,
		h.machine, h.machine.Name, h.machine.Spec.FleetName, h.r.hostOptions(h.machine), h.liveNode())
	if err == nil {
		t.Fatal("expected repair to fail against an unreachable host")
	}
	node := h.liveNode()
	if node.Annotations[kataSharedMemoryAnnotation] != "" {
		t.Fatal("failed repair must not record proof")
	}
	if node.Labels[KataRuntimeSelectorLabel] != "true" {
		t.Fatal("failed repair must preserve the runtime label")
	}
	cond := conditions.Get(h.machine, KataRuntimeReadyCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != KataRuntimeRepairFailedReason {
		t.Fatalf("failed repair must remain visible: %v", cond)
	}
}

func TestKataSharedMemoryProofPreservesNodeMetadataAndExpiresAfterBoot(t *testing.T) {
	h := newKataHarness(t, true, map[string]string{KataRuntimeSelectorLabel: "true", "keep": "label"})
	h.node.Annotations["keep"] = "annotation"
	if err := h.client.Update(context.Background(), h.node); err != nil {
		t.Fatal(err)
	}
	if err := labelKataRuntimeNode(context.Background(), h.client, h.liveNode()); err != nil {
		t.Fatal(err)
	}
	node := h.liveNode()
	proof := node.Annotations[kataSharedMemoryAnnotation]
	if proof != kataSharedMemoryRevision(node) || node.Annotations["keep"] != "annotation" || node.Labels["keep"] != "label" {
		t.Fatalf("invalid proof or lost metadata: %v", node.ObjectMeta)
	}
	node.Status.NodeInfo.BootID = "new-boot"
	if proof == kataSharedMemoryRevision(node) {
		t.Fatal("a new boot must invalidate the previous verification")
	}
}

func TestKataSharedMemoryRepairDoesNotRestartRuntime(t *testing.T) {
	for _, user := range []string{"root", "ubuntu"} {
		script := renderKataSharedMemoryRepairScript(linuxCloudInitOptions{BootstrapUser: user})
		cmd := exec.Command("/bin/bash", "-n")
		cmd.Stdin = strings.NewReader(script)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("invalid repair script: %v: %s", err, out)
		}
		for _, banned := range []string{"apt-get", "restart containerd", "restart kubelet", "reboot", "umount"} {
			if strings.Contains(script, banned) {
				t.Fatalf("shared-memory-only repair contains %q", banned)
			}
		}
	}
}

func TestHetznerKataSharedMemoryMatchesProvider(t *testing.T) {
	data, err := os.ReadFile("../../../k8s/clusters/bare-metal.yaml")
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]string{
		"/usr/local/sbin/tuist-kata-shared-memory":             kataSharedMemoryScript,
		"/etc/systemd/system/tuist-kata-shared-memory.service": kataSharedMemoryUnit,
	}
	for _, document := range strings.Split(string(data), "\n---") {
		var template struct {
			Spec struct {
				Template struct {
					Spec struct {
						Files              []struct{ Path, Content string }
						PreKubeadmCommands []string
					}
				}
			}
		}
		if err := yaml.Unmarshal([]byte(document), &template); err != nil {
			t.Fatal(err)
		}
		for _, file := range template.Spec.Template.Spec.Files {
			if expected, ok := want[file.Path]; ok {
				if file.Content != expected {
					t.Fatalf("Hetzner %s differs from the provider", file.Path)
				}
				delete(want, file.Path)
			}
		}
		commands := strings.Join(template.Spec.Template.Spec.PreKubeadmCommands, "\n")
		if commands != "" {
			start := strings.Index(commands, "systemctl start tuist-kata-shared-memory.service")
			containerd := strings.Index(commands, "systemctl enable --now containerd")
			if start < 0 || start > containerd {
				t.Fatal("shared-memory service must run before containerd")
			}
		}
	}
	if len(want) != 0 {
		t.Fatalf("missing Hetzner files: %v", want)
	}
}
