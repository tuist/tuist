package macos

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	osUpdateTestMachine = "ber1-0"
	osUpdateTestOwner   = "capi-ber1-0"
	osUpdateTestLabel   = "macOS Tahoe 26.7-25G229"
)

type fakeInstall struct{ label, user, password string }

type fakeOSUpdateHost struct {
	unreachable bool
	dials       int
	version     string
	bootTime    int64
	updates     []bootstrap.OSUpdate
	jobs        map[string]bootstrap.OSUpdateJob
	console     string
	noToken     bool
	downloads   []string
	installs    []fakeInstall
}

func newFakeOSUpdateHost() *fakeOSUpdateHost {
	return &fakeOSUpdateHost{
		version:  "26.6",
		bootTime: 100,
		updates: []bootstrap.OSUpdate{
			{Label: "Safari27.0TahoeAuto-27.0", Title: "Safari", Version: "27.0"},
			{Label: osUpdateTestLabel, Title: "macOS Tahoe 26.7", Version: "26.7"},
			{Label: "macOS 27-26A428", Title: "macOS 27", Version: "27"},
		},
		jobs:    map[string]bootstrap.OSUpdateJob{},
		console: "tuist",
	}
}

func (f *fakeOSUpdateHost) Fingerprint() string                         { return "" }
func (f *fakeOSUpdateHost) Version(context.Context) (string, error)     { return f.version, nil }
func (f *fakeOSUpdateHost) BootTime(context.Context) (int64, error)     { return f.bootTime, nil }
func (f *fakeOSUpdateHost) ConsoleUser(context.Context) (string, error) { return f.console, nil }
func (f *fakeOSUpdateHost) SecureTokenEnabled(context.Context, string) (bool, error) {
	return !f.noToken, nil
}
func (f *fakeOSUpdateHost) Close() error { return nil }
func (f *fakeOSUpdateHost) ListUpdates(context.Context) ([]bootstrap.OSUpdate, error) {
	return f.updates, nil
}

func (f *fakeOSUpdateHost) StartDownload(_ context.Context, label string) error {
	f.downloads = append(f.downloads, label)
	f.jobs[bootstrap.OSUpdateJobDownload] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobRunning}
	return nil
}

func (f *fakeOSUpdateHost) StartInstall(_ context.Context, label, user, password string) error {
	f.installs = append(f.installs, fakeInstall{label, user, password})
	f.jobs[bootstrap.OSUpdateJobInstall] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobRunning}
	return nil
}

func (f *fakeOSUpdateHost) Job(_ context.Context, job string) (bootstrap.OSUpdateJob, error) {
	if state, ok := f.jobs[job]; ok {
		return state, nil
	}
	return bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobAbsent}, nil
}

func updatingMachine(target string, mutate ...func(*infrav1.RackAppleSiliconMachine)) *infrav1.RackAppleSiliconMachine {
	return rackMachine(osUpdateTestMachine, append([]func(*infrav1.RackAppleSiliconMachine){func(m *infrav1.RackAppleSiliconMachine) {
		m.Annotations = map[string]string{OSUpdateAnnotation: target}
		m.OwnerReferences = []metav1.OwnerReference{{
			APIVersion: clusterv1.GroupVersion.String(),
			Kind:       "Machine",
			Name:       osUpdateTestOwner,
			UID:        "owner-uid",
		}}
		m.Status.RackHost = "mini-01"
		conditions.MarkTrue(m, BootstrappedCondition)
	}}, mutate...)...)
}

func ownerMachine(mutate ...func(*clusterv1.Machine)) *clusterv1.Machine {
	m := &clusterv1.Machine{ObjectMeta: metav1.ObjectMeta{Name: osUpdateTestOwner, Namespace: testNamespace}}
	for _, mut := range mutate {
		mut(m)
	}
	return m
}

func updatingNode(mutate ...func(*corev1.Node)) *corev1.Node {
	n := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: osUpdateTestMachine},
		Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{
			{Type: corev1.NodeReady, Status: corev1.ConditionTrue},
		}},
	}
	for _, mut := range mutate {
		mut(n)
	}
	return n
}

func runnerPod(name string, phase corev1.PodPhase) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners"},
		Spec:       corev1.PodSpec{NodeName: osUpdateTestMachine},
		Status:     corev1.PodStatus{Phase: phase},
	}
}

type osUpdateFixture struct {
	t    *testing.T
	r    *RackAppleSiliconMachineReconciler
	host *fakeOSUpdateHost
	oc   *osUpdateContext
}

func newOSUpdateFixture(t *testing.T, machine *infrav1.RackAppleSiliconMachine, objs ...runtime.Object) *osUpdateFixture {
	t.Helper()
	rack := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.ClaimedBy = osUpdateTestMachine })
	r := newRackReconciler(t, append([]runtime.Object{rack, machine}, objs...)...)
	fake := newFakeOSUpdateHost()
	r.osUpdateDial = func(string, string, []byte, string) (osUpdateHost, error) {
		fake.dials++
		if fake.unreachable {
			return nil, errors.New("dial tcp 192.168.0.41:22: connect: connection refused")
		}
		return fake, nil
	}
	return &osUpdateFixture{
		t:    t,
		r:    r,
		host: fake,
		oc:   &osUpdateContext{machine: machine, host: rack, sshKey: []byte("key"), sudoPassword: "hunter2"},
	}
}

func (f *osUpdateFixture) step() {
	f.t.Helper()
	if _, err := f.r.reconcileOSUpdate(context.Background(), f.oc); err != nil {
		f.t.Fatalf("reconcileOSUpdate: %v", err)
	}
}

func (f *osUpdateFixture) status() *infrav1.OSUpdateStatus {
	f.t.Helper()
	if f.oc.machine.Status.OSUpdate == nil {
		f.t.Fatal("no osUpdate status")
	}
	return f.oc.machine.Status.OSUpdate
}

func (f *osUpdateFixture) wantPhase(phase string) {
	f.t.Helper()
	if st := f.status(); st.Phase != phase {
		f.t.Fatalf("phase = %s (%s: %s), want %s", st.Phase, st.Reason, st.Message, phase)
	}
}

func (f *osUpdateFixture) wantFailed(reason string) {
	f.t.Helper()
	f.wantPhase(OSUpdatePhaseFailed)
	if st := f.status(); st.Reason != reason {
		f.t.Fatalf("reason = %s (%s), want %s", st.Reason, st.Message, reason)
	}
}

func (f *osUpdateFixture) cordoned() bool {
	f.t.Helper()
	node := &corev1.Node{}
	if err := f.r.Get(context.Background(), types.NamespacedName{Name: osUpdateTestMachine}, node); err != nil {
		f.t.Fatalf("get node: %v", err)
	}
	return node.Spec.Unschedulable
}

func (f *osUpdateFixture) remediationSkipped() bool {
	f.t.Helper()
	owner := &clusterv1.Machine{}
	if err := f.r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: osUpdateTestOwner}, owner); err != nil {
		f.t.Fatalf("get owner machine: %v", err)
	}
	_, skipped := owner.Annotations[clusterv1.MachineSkipRemediationAnnotation]
	return skipped
}

func (f *osUpdateFixture) annotated() bool {
	_, ok := f.oc.machine.Annotations[OSUpdateAnnotation]
	return ok
}

// driveToInstalling runs a fresh update through the download and an empty drain.
func (f *osUpdateFixture) driveToInstalling() {
	f.t.Helper()
	f.step()
	f.host.jobs[bootstrap.OSUpdateJobDownload] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobExited}
	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)
}

func TestOSUpdateRunsTheWholeWave(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode(),
		runnerPod("job-1", corev1.PodRunning), runnerPod("job-0", corev1.PodSucceeded))

	f.step()
	f.wantPhase(OSUpdatePhaseDownloading)
	if st := f.status(); st.Label != osUpdateTestLabel || st.FromVersion != "26.6" {
		t.Fatalf("label %q from %q", st.Label, st.FromVersion)
	}
	if f.cordoned() {
		t.Fatal("cordoned while the download can run with the host still serving")
	}

	f.host.jobs[bootstrap.OSUpdateJobDownload] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobExited}
	f.step()
	f.wantPhase(OSUpdatePhaseDraining)
	if !f.cordoned() {
		t.Fatal("the Node was not cordoned once the download finished")
	}
	if !strings.Contains(f.status().Message, "tuist-runners/job-1") || strings.Contains(f.status().Message, "job-0") {
		t.Fatalf("drain message %q should name only the running pod", f.status().Message)
	}
	if len(f.host.installs) != 0 || f.remediationSkipped() {
		t.Fatal("the install started while a job was still running")
	}

	if err := f.r.Delete(context.Background(), runnerPod("job-1", corev1.PodRunning)); err != nil {
		t.Fatal(err)
	}
	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)
	if want := []fakeInstall{{osUpdateTestLabel, "tuist", "hunter2"}}; len(f.host.installs) != 1 || f.host.installs[0] != want[0] {
		t.Fatalf("installs = %+v, want %+v", f.host.installs, want)
	}
	if !f.remediationSkipped() {
		t.Fatal("skip-remediation was not set for the install")
	}
	if f.status().BootTimeBefore != 100 {
		t.Fatalf("boot time before = %d", f.status().BootTimeBefore)
	}

	f.host.unreachable = true
	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)

	f.host.unreachable = false
	f.host.bootTime, f.host.version = 200, "26.7"
	f.oc.machine.Status.HostConfigHash = "converged-before-the-update"
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)
	if f.oc.machine.Status.HostConfigHash != "" {
		t.Fatal("the host config hash was not cleared, so the drift loop will not re-push what the installer reset")
	}

	f.step()
	f.wantPhase(OSUpdatePhaseConverging)
	if !f.cordoned() {
		t.Fatal("uncordoned before the host config was pushed again")
	}

	f.oc.machine.Status.HostConfigHash = f.r.desiredHostConfigHash(f.oc.machine, f.oc.host)
	f.host.console = "root"
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)

	f.host.console = "tuist"
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if f.cordoned() || f.remediationSkipped() || f.annotated() {
		t.Fatalf("after success: cordoned=%t skipRemediation=%t annotated=%t", f.cordoned(), f.remediationSkipped(), f.annotated())
	}
	if msg := f.status().Message; msg != "updated from macOS 26.6 to 26.7" {
		t.Fatalf("message = %q", msg)
	}
}

func TestOSUpdateRefusesAReleaseFamilyMove(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("27.0"), ownerMachine(), updatingNode())
	f.host.version = "26.7"
	f.step()
	f.wantFailed("ReleaseFamilyMove")
	if len(f.host.downloads) != 0 || f.cordoned() || f.annotated() {
		t.Fatal("a release-family move touched the host or kept its request")
	}
}

func TestOSUpdateOnTheTargetVersionIsANoOp(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.host.version = "26.7"
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if len(f.host.downloads) != 0 || f.cordoned() || f.annotated() {
		t.Fatal("a host already on the target was disturbed")
	}
}

func TestOSUpdateRefusesADowngrade(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.6"), ownerMachine(), updatingNode())
	f.host.version = "26.7"
	f.step()
	f.wantFailed("Downgrade")
}

func TestOSUpdateNeverInstallsAnAppWithAMatchingVersion(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.8"), ownerMachine(), updatingNode())
	f.host.updates = append(f.host.updates, bootstrap.OSUpdate{Label: "Safari26.8", Title: "Safari", Version: "26.8"})
	f.step()
	f.wantFailed("NotOffered")
	if msg := f.status().Message; !strings.Contains(msg, "offered: 26.7, 27") {
		t.Fatalf("message %q should list only the macOS versions offered", msg)
	}
	if len(f.host.downloads) != 0 {
		t.Fatal("downloaded an update that is not macOS")
	}
}

func TestOSUpdateRefusesAnAccountWithoutASecureToken(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.host.noToken = true
	f.step()
	f.wantFailed("NoSecureToken")
	if len(f.host.downloads) != 0 || f.cordoned() {
		t.Fatal("drained or downloaded for an install the host cannot authorise")
	}
}

func TestOSUpdateRejectsATargetThatIsNotAVersion(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("latest"), ownerMachine(), updatingNode())
	f.step()
	f.wantFailed("InvalidTarget")
	if f.host.dials != 0 {
		t.Fatal("dialled the host for a request that could never succeed")
	}
}

func TestOSUpdateRefusesAHostThatIsNotBootstrapped(t *testing.T) {
	machine := updatingMachine("26.7", func(m *infrav1.RackAppleSiliconMachine) {
		conditions.MarkFalse(m, BootstrappedCondition, "BootstrapFailed", clusterv1.ConditionSeverityWarning, "")
	})
	f := newOSUpdateFixture(t, machine, ownerMachine(), updatingNode())
	f.step()
	f.wantFailed("HostNotReady")
	if f.host.dials != 0 {
		t.Fatal("dialled a host that is not bootstrapped")
	}
}

func TestOSUpdateWaitsOutAnUnreachableHostBeforeStarting(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.host.unreachable = true
	f.step()
	f.wantPhase(OSUpdatePhasePreparing)
	if !f.annotated() {
		t.Fatal("dropped the request over a transient dial failure")
	}
	f.host.unreachable = false
	f.step()
	f.wantPhase(OSUpdatePhaseDownloading)
}

func TestOSUpdateFailedDownloadLeavesTheHostServing(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.step()
	f.host.jobs[bootstrap.OSUpdateJobDownload] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobExited, ExitCode: 1, LogTail: "Error downloading updates."}
	f.step()
	f.wantFailed("DownloadFailed")
	if f.cordoned() {
		t.Fatal("a failed download cordoned the Node")
	}
}

func TestOSUpdateCancelledWhileDrainingUncordons(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode(), runnerPod("job-1", corev1.PodRunning))
	f.step()
	f.host.jobs[bootstrap.OSUpdateJobDownload] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobExited}
	f.step()
	f.wantPhase(OSUpdatePhaseDraining)

	delete(f.oc.machine.Annotations, OSUpdateAnnotation)
	f.step()
	f.wantFailed("Cancelled")
	if f.cordoned() || len(f.host.installs) != 0 {
		t.Fatal("cancelling left the Node cordoned or installed anyway")
	}
}

func TestOSUpdateCannotBeCancelledOnceInstalling(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.driveToInstalling()
	delete(f.oc.machine.Annotations, OSUpdateAnnotation)
	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)
}

func TestOSUpdateInstallFailureBeforeRestartReturnsTheHost(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.driveToInstalling()
	f.host.jobs[bootstrap.OSUpdateJobInstall] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobExited, ExitCode: 1, LogTail: "Failed to authenticate"}
	f.step()
	f.wantFailed("InstallFailed")
	if f.cordoned() || f.remediationSkipped() {
		t.Fatal("a host left unchanged by a failed install was not handed back")
	}
}

func TestOSUpdateOnTheWrongVersionKeepsTheNodeCordoned(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.driveToInstalling()
	f.host.bootTime, f.host.version = 200, "26.6.1"
	f.step()
	f.wantFailed("VersionMismatch")
	if !f.cordoned() {
		t.Fatal("a host on an unexpected version went back into service")
	}
	if f.remediationSkipped() {
		t.Fatal("remediation stayed suspended after the update gave up")
	}
}

func TestOSUpdateRetryUncordonsWhatAFailedAttemptLeftCordoned(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.driveToInstalling()
	f.host.bootTime, f.host.version = 200, "26.6.1"
	f.step()
	f.wantFailed("VersionMismatch")

	f.oc.machine.Annotations[OSUpdateAnnotation] = "26.7"
	f.driveToInstalling()
	f.host.bootTime, f.host.version = 300, "26.7"
	f.step()
	f.oc.machine.Status.HostConfigHash = f.r.desiredHostConfigHash(f.oc.machine, f.oc.host)
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if f.cordoned() {
		t.Fatal("a successful retry left the cordon from the failed attempt in place")
	}
}

func TestOSUpdateTimesOutAHostThatNeverReturns(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.driveToInstalling()
	f.host.unreachable = true
	f.status().PhaseStartedAt = &metav1.Time{Time: time.Now().Add(-osUpdateInstallTimeout - time.Minute)}
	f.step()
	f.wantFailed("InstallTimedOut")
	if !f.cordoned() || f.remediationSkipped() {
		t.Fatal("a vanished host must stay cordoned and go back to the health check")
	}
}

func TestOSUpdateOnlyUndoesWhatItDid(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"),
		ownerMachine(func(m *clusterv1.Machine) {
			m.Annotations = map[string]string{clusterv1.MachineSkipRemediationAnnotation: ""}
		}),
		updatingNode(func(n *corev1.Node) { n.Spec.Unschedulable = true }))
	f.driveToInstalling()
	f.host.bootTime, f.host.version = 200, "26.7"
	f.step()
	f.oc.machine.Status.HostConfigHash = f.r.desiredHostConfigHash(f.oc.machine, f.oc.host)
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if !f.cordoned() || !f.remediationSkipped() {
		t.Fatal("the update undid a cordon or skip-remediation an operator set")
	}
}

func TestInstallingHostIsNotPushedByTheDriftLoop(t *testing.T) {
	machine := updatingMachine("26.7", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.HostConfigHash = "stale"
		m.Status.OSUpdate = &infrav1.OSUpdateStatus{
			Target:         "26.7",
			Label:          osUpdateTestLabel,
			Phase:          OSUpdatePhaseInstalling,
			PhaseStartedAt: &metav1.Time{Time: time.Now()},
			BootTimeBefore: 100,
		}
	})
	f := newOSUpdateFixture(t, machine, ownerMachine(), updatingNode(), fleetSecret())
	f.host.unreachable = true

	result, err := f.r.reconcileNormal(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileNormal: %v", err)
	}
	if result.RequeueAfter != osUpdatePollInterval {
		t.Fatalf("result = %+v, want a poll of the install", result)
	}
	if machine.Status.HostConfigHash != "stale" || machine.Status.TartKubeletUpdateAttempts != 0 {
		t.Fatal("the drift loop tried to push a host that is mid-install")
	}
}

func TestCompareMacOSVersions(t *testing.T) {
	for _, tc := range []struct {
		a, b string
		want int
	}{
		{"26.7", "26.7", 0},
		{"26.7", "26.7.0", 0},
		{"27", "27.0", 0},
		{"26.10", "26.9", 1},
		{"26.6", "26.7", -1},
		{"26.7.1", "26.7", 1},
	} {
		if got := compareMacOSVersions(tc.a, tc.b); got != tc.want {
			t.Errorf("compareMacOSVersions(%q, %q) = %d, want %d", tc.a, tc.b, got, tc.want)
		}
	}
}
