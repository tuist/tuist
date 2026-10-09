package podagent

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/egress"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

type recordingPF struct {
	rules  string
	tables map[string][]string
}

func (p *recordingPF) LoadAnchor(_ context.Context, _ string, rules string) error {
	p.rules = rules
	return nil
}

func (p *recordingPF) ReplaceTable(_ context.Context, _ string, table string, addresses []string) error {
	if p.tables == nil {
		p.tables = map[string][]string{}
	}
	p.tables[table] = append([]string(nil), addresses...)
	return nil
}

func (p *recordingPF) ShowRules(context.Context, string) (string, error) { return p.rules, nil }

func egressPod(name, node, gateway string, conditions ...corev1.PodCondition) *corev1.Pod {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: name},
		Spec:       corev1.PodSpec{NodeName: node, Containers: []corev1.Container{{Name: "runner", Image: "runner"}}},
		Status:     corev1.PodStatus{Conditions: conditions},
	}
	if gateway != "" {
		pod.Labels = map[string]string{egress.PodLabel: gateway}
	}
	return pod
}

func armedCondition(ip string, since time.Time) corev1.PodCondition {
	return corev1.PodCondition{
		Type:               corev1.PodConditionType(egress.ReadyCondition),
		Status:             corev1.ConditionTrue,
		Message:            egressArmedMessagePrefix + ip,
		LastTransitionTime: metav1.NewTime(since),
	}
}

func newEgressTestReconciler(t *testing.T, objects ...runtime.Object) (*Reconciler, *recordingPF) {
	t.Helper()
	dir := t.TempDir()
	bin := filepath.Join(dir, "faketart")
	if err := os.WriteFile(bin, []byte("#!/bin/sh\n[ \"$1\" = ip ] && echo 192.168.64.7\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	statusDir := filepath.Join(dir, "status")
	if err := os.MkdirAll(statusDir, 0o755); err != nil {
		t.Fatal(err)
	}
	now := time.Now()
	if err := egress.WriteStatus(statusDir, egress.Status{
		Gateway: "dedicated-1", Index: 0, Interface: egress.InterfaceName(0),
		ProbeOK: true, UpdatedUnix: now.Unix(), LastHandshakeUnix: now.Unix(),
	}); err != nil {
		t.Fatal(err)
	}
	pf := &recordingPF{}
	return &Reconciler{
		CachedClient: newPodTestClient(t, objects...),
		Tart:         &tart.Client{Binary: bin},
		Store:        NewStore(),
		NodeName:     "mini-1",
		Egress: &egress.Manager{
			StatusDir: statusDir,
			StateDir:  dir,
			TailnetIP: "100.100.1.2",
			Exclude:   egress.DefaultExcludeCIDRs,
			PF:        pf,
		},
	}, pf
}

func TestSyncEgressRoutesOnlyLiveLabelledVMsOnThisNode(t *testing.T) {
	since := time.Now().Add(-time.Hour).Truncate(time.Second)
	r, pf := newEgressTestReconciler(t,
		egressPod("fresh", "mini-1", "dedicated-1"),
		egressPod("armed", "mini-1", "dedicated-1", armedCondition("192.168.64.20", since)),
		egressPod("releasing", "mini-1", "dedicated-1", armedCondition("192.168.64.30", since)),
		egressPod("elsewhere", "mini-2", "dedicated-1"),
		egressPod("shared", "mini-1", ""),
	)
	for _, name := range []string{"fresh", "armed", "elsewhere", "shared"} {
		r.Store.Put("tuist-runners", name, &Entry{VMName: "vm-" + name})
	}
	r.Store.Put("tuist-runners", "releasing", &Entry{VMName: "vm-releasing", EgressReleased: true})

	if err := r.syncEgress(context.Background()); err != nil {
		t.Fatal(err)
	}
	if want := []string{"192.168.64.20", "192.168.64.7"}; !reflect.DeepEqual(pf.tables["egress_dedicated-1"], want) {
		t.Fatalf("gateway table = %v, want %v", pf.tables["egress_dedicated-1"], want)
	}
	if want := []string{"192.168.64.20", "192.168.64.7"}; !reflect.DeepEqual(pf.tables["egress_all"], want) {
		t.Fatalf("all table = %v, want %v", pf.tables["egress_all"], want)
	}
	arm, ok := r.Egress.Armed("tuist-runners/armed")
	if !ok || arm.IP != "192.168.64.20" || !arm.Since.Equal(since) {
		t.Fatalf("armed pod = %+v %v", arm, ok)
	}
}

func TestReleaseEgressDropsVMBeforeTeardown(t *testing.T) {
	since := time.Now().Add(-time.Minute).Truncate(time.Second)
	r, pf := newEgressTestReconciler(t, egressPod("armed", "mini-1", "dedicated-1", armedCondition("192.168.64.20", since)))
	entry := &Entry{VMName: "vm-armed"}
	r.Store.Put("tuist-runners", "armed", entry)
	if err := r.syncEgress(context.Background()); err != nil {
		t.Fatal(err)
	}

	r.releaseEgress(context.Background(), entry)
	if len(pf.tables["egress_dedicated-1"]) != 0 || len(pf.tables["egress_all"]) != 0 {
		t.Fatalf("tables after release = %v", pf.tables)
	}
}

func TestEgressReadyCondition(t *testing.T) {
	since := time.Now().Add(-time.Hour).Truncate(time.Second)
	r, _ := newEgressTestReconciler(t)

	if _, ok := r.egressReadyCondition(egressPod("shared", "mini-1", "")); ok {
		t.Fatal("unlabelled pod got an egress condition")
	}

	existing := armedCondition("192.168.64.20", since)
	got, ok := r.egressReadyCondition(egressPod("armed", "mini-1", "dedicated-1", existing))
	if !ok || !reflect.DeepEqual(got, existing) {
		t.Fatalf("armed condition not kept: %+v", got)
	}

	got, ok = r.egressReadyCondition(egressPod("unarmed", "mini-1", "dedicated-1"))
	if !ok || got.Status != corev1.ConditionFalse || got.Reason != "GatewayNotReady" {
		t.Fatalf("unarmed condition = %+v", got)
	}

	r.Store.Put("tuist-runners", "fresh", &Entry{VMName: "vm-fresh"})
	pod := egressPod("fresh", "mini-1", "dedicated-1")
	r.CachedClient = newPodTestClient(t, pod)
	if err := r.syncEgress(context.Background()); err != nil {
		t.Fatal(err)
	}
	got, ok = r.egressReadyCondition(pod)
	if !ok || got.Status != corev1.ConditionTrue || got.Message != "armed 192.168.64.7" {
		t.Fatalf("fresh condition = %+v", got)
	}

	r.Egress = nil
	got, _ = r.egressReadyCondition(egressPod("disabled", "mini-1", "dedicated-1"))
	if got.Status != corev1.ConditionFalse || got.Reason != "EgressDisabled" {
		t.Fatalf("disabled condition = %+v", got)
	}
}
