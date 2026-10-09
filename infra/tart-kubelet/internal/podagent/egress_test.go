package podagent

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/egress"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

type recordingPF struct {
	mu     sync.Mutex
	rules  string
	tables map[string][]string
	log    string
}

func (p *recordingPF) record(line string) {
	if p.log == "" {
		return
	}
	f, err := os.OpenFile(p.log, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	_, _ = f.WriteString(line + "\n")
}

func (p *recordingPF) TableAddresses(_ context.Context, _ string, table string) ([]string, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]string(nil), p.tables[table]...), nil
}

func (p *recordingPF) KillStates(_ context.Context, address string) error {
	p.record("pf kill " + address)
	return nil
}

func (p *recordingPF) table(name string) []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]string(nil), p.tables[name]...)
}

func (p *recordingPF) LoadAnchor(_ context.Context, _ string, rules string) error {
	p.rules = rules
	return nil
}

func (p *recordingPF) ReplaceTable(_ context.Context, _ string, table string, addresses []string) error {
	p.record("pf replace " + table + " " + strings.Join(addresses, ","))
	p.mu.Lock()
	defer p.mu.Unlock()
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

// A sync that took its Pod snapshot before a VM was released must not land
// after the release and route the address again.
func TestSyncEgressSnapshotCannotLandAfterARelease(t *testing.T) {
	since := time.Now().Add(-time.Minute).Truncate(time.Second)
	r, pf := newEgressTestReconciler(t,
		egressPod("armed", "mini-1", "dedicated-1", armedCondition("192.168.64.20", since)),
		egressPod("fresh", "mini-1", "dedicated-1"),
	)
	dir := t.TempDir()
	marker := filepath.Join(dir, "slept")
	script := "#!/bin/sh\nif [ \"$1\" = ip ]; then\n  if [ ! -e " + marker + " ]; then touch " + marker + "; sleep 1; fi\n  echo 192.168.64.7\nfi\nexit 0\n"
	if err := os.WriteFile(r.Tart.Binary, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	armed := &Entry{VMName: "vm-armed"}
	r.Store.Put("tuist-runners", "armed", armed)
	r.Store.Put("tuist-runners", "fresh", &Entry{VMName: "vm-fresh"})

	done := make(chan error, 1)
	go func() { done <- r.syncEgress(context.Background()) }()
	for {
		if _, err := os.Stat(marker); err == nil {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	r.releaseEgress(context.Background(), armed)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"egress_all", "egress_dedicated-1"} {
		for _, address := range pf.table(table) {
			if address == "192.168.64.20" {
				t.Fatalf("%s routes a released address again: %v", table, pf.table(table))
			}
		}
	}
}

// Teardown stops the VM before it loses its route and backstop, and only
// deletes it once its address and states are gone.
func TestDeleteByKeyStopsBeforeReleasingAndReleasesBeforeDeleting(t *testing.T) {
	since := time.Now().Add(-time.Minute).Truncate(time.Second)
	r, pf := newEgressTestReconciler(t, egressPod("armed", "mini-1", "dedicated-1", armedCondition("192.168.64.20", since)))
	dir := t.TempDir()
	logPath := filepath.Join(dir, "calls.log")
	pf.log = logPath
	script := "#!/bin/sh\ncase \"$1\" in stop|delete) echo \"tart $1\" >> " + logPath + " ;; esac\nexit 0\n"
	if err := os.WriteFile(r.Tart.Binary, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	r.Tart.UserDataDir = dir
	r.Store.Put("tuist-runners", "armed", &Entry{VMName: "vm-armed"})
	if err := r.syncEgress(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(logPath, nil, 0o644); err != nil {
		t.Fatal(err)
	}

	if err := r.deleteByKey(context.Background(), "tuist-runners", "armed"); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(logPath)
	if err != nil {
		t.Fatal(err)
	}
	log := string(data)
	stop := strings.Index(log, "tart stop")
	release := strings.Index(log, "pf replace egress_dedicated-1 \n")
	kill := strings.Index(log, "pf kill 192.168.64.20")
	del := strings.Index(log, "tart delete")
	if stop < 0 || release < 0 || kill < 0 || del < 0 || !(stop < release && release < kill && kill < del) {
		t.Fatalf("teardown order is wrong:\n%s", log)
	}
}
