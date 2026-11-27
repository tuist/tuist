package linux

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/core/v1beta1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	conditions "github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/capiconditions"
)

// The handler a box bootstrapped without the field has, as kataSetup wrote it,
// followed by the next table so the edit is shown to stop at the options table.
const kataHandlerWithoutSnapshotter = `[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata-qemu]
runtime_type = "io.containerd.kata-qemu.v2"
runtime_path = "/opt/kata/bin/containerd-shim-kata-v2"
privileged_without_host_devices = true
pod_annotations = ["io.katacontainers.*"]
[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata-qemu.options]
ConfigPath = "/opt/kata/share/defaults/kata-containers/configuration-qemu.toml"
snapshotter = "keep-me"
SystemdCgroup = true
`

func TestKataHandlerSnapshotterSedSetsTheHandlerOnly(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	runcSection := "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc]\nsnapshotter = ''\n\n"
	if err := os.WriteFile(path, []byte(runcSection+kataHandlerWithoutSnapshotter), 0600); err != nil {
		t.Fatal(err)
	}
	want := runcSection + strings.Replace(kataHandlerWithoutSnapshotter,
		"pod_annotations = [\"io.katacontainers.*\"]\n",
		"pod_annotations = [\"io.katacontainers.*\"]\nsnapshotter = \"devmapper\"\n", 1)
	// Twice: a retried conversion must not add a second line.
	for i := 0; i < 2; i++ {
		if out, err := exec.Command("sed", "-i", kataHandlerSnapshotterSed, path).CombinedOutput(); err != nil {
			t.Fatalf("sed: %v\n%s", err, out)
		}
		got, _ := os.ReadFile(path)
		if string(got) != want {
			t.Fatalf("pass %d: config =\n%s\nwant\n%s", i+1, got, want)
		}
	}
	// The bootstrap's own rendering already passes the probe's handler check.
	bootstrapped := kataSetup("sudo ", "sudo -E ", true, true, true)
	handler := bootstrapped[strings.Index(bootstrapped, "[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.kata-qemu]"):]
	cmd := exec.Command("sh", "-c", fmt.Sprintf(`sed -n "/^%s$/,/^%s$/p" | grep -qx 'snapshotter = "devmapper"'`, kataQemuHandlerTable, kataQemuOptionsTable))
	cmd.Stdin = strings.NewReader(handler)
	if err := cmd.Run(); err != nil {
		t.Fatalf("the probe's handler check does not match what bootstrap writes:\n%s", handler)
	}
}

func TestKataBlockRootfsScriptsParse(t *testing.T) {
	opts := linuxCloudInitOptions{BootstrapUser: ovhBootstrapUser, KataRuntime: true, KataBlockRootfs: true}
	for name, script := range map[string]string{
		"probe":   renderKataBlockRootfsProbeScript(opts),
		"convert": renderKataBlockRootfsConvertScript(opts),
	} {
		if out, err := exec.Command("bash", "-n", "-c", script).CombinedOutput(); err != nil {
			t.Fatalf("%s script does not parse: %v\n%s\n%s", name, err, out, script)
		}
	}
	convert := renderKataBlockRootfsConvertScript(opts)
	// The pool comes up before the handler names devmapper, and containerd is
	// only restarted after both.
	pool := strings.Index(convert, "systemctl start tuist-kata-devmapper.service")
	handler := strings.Index(convert, "TUIST_KATA_HANDLER_SED")
	restart := strings.Index(convert, "systemctl restart containerd")
	if pool < 0 || handler < pool || restart < handler {
		t.Fatalf("expected pool (%d) < handler edit (%d) < restart (%d) in:\n%s", pool, handler, restart, convert)
	}
}

type exitStatusError int

func (e exitStatusError) Error() string   { return fmt.Sprintf("exit status %d", int(e)) }
func (e exitStatusError) ExitStatus() int { return int(e) }

type blockRootfsBox struct {
	t       *testing.T
	client  client.Client
	machine *infrav1.OVHDedicatedMachine
	node    string
	scripts []string
	// converted is what the probe reports; the convert script sets it.
	converted bool
	failWith  error
}

func newBlockRootfsBox(t *testing.T, objects ...client.Object) *blockRootfsBox {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "box-a"}}
	return &blockRootfsBox{
		t:       t,
		client:  fake.NewClientBuilder().WithScheme(scheme).WithObjects(append(objects, node)...).Build(),
		machine: &infrav1.OVHDedicatedMachine{ObjectMeta: metav1.ObjectMeta{Name: "box-a", Namespace: "tuist"}},
		node:    "box-a",
	}
}

func (b *blockRootfsBox) reconcile(limit int) error {
	b.t.Helper()
	node := b.getNode()
	_, err := reconcileKataBlockRootfs(context.Background(), kataBlockRootfsConversion{
		Client: b.client, Reader: b.client, Object: b.machine, MaxConverting: limit,
		Run: func(_ context.Context, script string) error {
			if strings.Contains(script, "TUIST_KATA_BLOCK_ROOTFS_PROBE") {
				b.scripts = append(b.scripts, "probe")
				if b.converted {
					return nil
				}
				return fmt.Errorf("run script: %w", exitStatusError(kataBlockRootfsPendingExit))
			}
			b.scripts = append(b.scripts, "convert")
			if b.failWith != nil {
				return b.failWith
			}
			b.converted = true
			return nil
		},
	}, true, linuxCloudInitOptions{BootstrapUser: ovhBootstrapUser, KataRuntime: true, KataBlockRootfs: true}, node)
	return err
}

func (b *blockRootfsBox) getNode() *corev1.Node {
	b.t.Helper()
	node := &corev1.Node{}
	if err := b.client.Get(context.Background(), types.NamespacedName{Name: b.node}, node); err != nil {
		b.t.Fatal(err)
	}
	return node
}

func (b *blockRootfsBox) reason() string {
	c := conditions.Get(b.machine, KataBlockRootfsReadyCondition)
	if c == nil {
		return "<none>"
	}
	if c.Status == corev1.ConditionTrue {
		return "True"
	}
	return c.Reason
}

func TestKataBlockRootfsConvertsADrainedBoxAndPutsItBack(t *testing.T) {
	pod := runnerPod("runner-1", "box-a", corev1.PodRunning)
	b := newBlockRootfsBox(t, pod)

	if err := b.reconcile(1); err != nil {
		t.Fatal(err)
	}
	node := b.getNode()
	if !node.Spec.Unschedulable || node.Annotations[kataBlockRootfsConvertingAnnotation] != kataBlockRootfsCordonedByUs {
		t.Fatalf("expected the box cordoned with a slot, got unschedulable=%v annotations=%v", node.Spec.Unschedulable, node.Annotations)
	}
	if b.reason() != kataBlockRootfsWaitingForJobsReason {
		t.Fatalf("condition = %s, want %s", b.reason(), kataBlockRootfsWaitingForJobsReason)
	}

	// Another pass while the job runs neither probes again nor converts.
	if err := b.reconcile(1); err != nil {
		t.Fatal(err)
	}
	if got := strings.Join(b.scripts, ","); got != "probe" {
		t.Fatalf("scripts = %s, want only the first probe while the job runs", got)
	}

	if err := b.client.Delete(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if err := b.reconcile(1); err != nil {
		t.Fatal(err)
	}
	node = b.getNode()
	if node.Spec.Unschedulable || node.Annotations[kataBlockRootfsConvertingAnnotation] != "" || node.Annotations[kataBlockRootfsAnnotation] != kataBlockRootfsRevision {
		t.Fatalf("expected the box back in service and stamped, got unschedulable=%v annotations=%v", node.Spec.Unschedulable, node.Annotations)
	}
	if b.reason() != "True" || strings.Join(b.scripts, ",") != "probe,convert" {
		t.Fatalf("condition = %s, scripts = %v", b.reason(), b.scripts)
	}

	// A stamped box is left alone.
	if err := b.reconcile(1); err != nil {
		t.Fatal(err)
	}
	if len(b.scripts) != 2 {
		t.Fatalf("a converted box ran %v", b.scripts)
	}
}

func TestKataBlockRootfsStampsAnAlreadyConvertedBoxWithoutCordoning(t *testing.T) {
	b := newBlockRootfsBox(t, runnerPod("runner-1", "box-a", corev1.PodRunning))
	b.converted = true
	if err := b.reconcile(1); err != nil {
		t.Fatal(err)
	}
	node := b.getNode()
	if node.Spec.Unschedulable || node.Annotations[kataBlockRootfsAnnotation] != kataBlockRootfsRevision {
		t.Fatalf("expected a stamp and no cordon, got unschedulable=%v annotations=%v", node.Spec.Unschedulable, node.Annotations)
	}
}

func TestKataBlockRootfsWaitsForARolloutSlot(t *testing.T) {
	other := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "box-b", Annotations: map[string]string{kataBlockRootfsConvertingAnnotation: kataBlockRootfsCordonedByUs}}}
	b := newBlockRootfsBox(t, other)
	if err := b.reconcile(1); err != nil {
		t.Fatal(err)
	}
	if node := b.getNode(); node.Spec.Unschedulable || b.reason() != kataBlockRootfsWaitingForSlotReason {
		t.Fatalf("expected no cordon while the slot is taken, got unschedulable=%v condition=%s", node.Spec.Unschedulable, b.reason())
	}
	// With room for two it goes ahead.
	if err := b.reconcile(2); err != nil {
		t.Fatal(err)
	}
	if node := b.getNode(); node.Annotations[kataBlockRootfsAnnotation] != kataBlockRootfsRevision {
		t.Fatalf("expected the box converted with a second slot, got %v", node.Annotations)
	}
}

func TestKataBlockRootfsKeepsSomeoneElsesCordonAndAFailedBoxCordoned(t *testing.T) {
	b := newBlockRootfsBox(t)
	node := b.getNode()
	node.Spec.Unschedulable = true
	if err := b.client.Update(context.Background(), node); err != nil {
		t.Fatal(err)
	}
	b.failWith = fmt.Errorf("pool needs 60 GiB")
	if err := b.reconcile(1); err == nil {
		t.Fatal("expected the failed conversion to be reported")
	}
	if node := b.getNode(); !node.Spec.Unschedulable || node.Annotations[kataBlockRootfsConvertingAnnotation] != kataBlockRootfsWasCordoned || b.reason() != kataBlockRootfsFailedReason {
		t.Fatalf("expected a failed box to keep its slot and cordon, got unschedulable=%v annotations=%v condition=%s", node.Spec.Unschedulable, node.Annotations, b.reason())
	}
	b.failWith = nil
	if err := b.reconcile(1); err != nil {
		t.Fatal(err)
	}
	if node := b.getNode(); !node.Spec.Unschedulable || node.Annotations[kataBlockRootfsConvertingAnnotation] != "" {
		t.Fatalf("a box cordoned by someone else must stay cordoned, got unschedulable=%v annotations=%v", node.Spec.Unschedulable, node.Annotations)
	}
}

func TestWantsKataBlockRootfsFollowsTheTemplate(t *testing.T) {
	template := &infrav1.OVHDedicatedMachineTemplate{ObjectMeta: metav1.ObjectMeta{Name: "runners-linux", Namespace: "tuist"}}
	template.Spec.Template.Spec.KataBlockRootfs = true
	b := newBlockRootfsBox(t, template)
	r := &OVHDedicatedMachineReconciler{Client: b.client}
	machine := &infrav1.OVHDedicatedMachine{ObjectMeta: metav1.ObjectMeta{Name: "m", Namespace: "tuist",
		Annotations: map[string]string{clusterv1.TemplateClonedFromNameAnnotation: "runners-linux"}}}
	machine.Spec.KataRuntime = true
	if got, err := r.wantsKataBlockRootfs(context.Background(), machine); err != nil || !got {
		t.Fatalf("a Machine cloned before the template turned the field on must follow it, got %v %v", got, err)
	}
	machine.Spec.KataRuntime = false
	if got, _ := r.wantsKataBlockRootfs(context.Background(), machine); got {
		t.Fatal("a box without kata must never be converted")
	}
}
