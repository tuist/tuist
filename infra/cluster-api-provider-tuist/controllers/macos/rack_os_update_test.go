package macos

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	osUpdateTestMachine = "ber1-0"
	osUpdateTestOwner   = "capi-ber1-0"
	osUpdateTestLabel   = "macOS Tahoe 26.7-25G229"
)

type fakeInstall struct{ label, user, password string }

type fakeErase struct{ app, user, password string }

type fakeOSUpdateHost struct {
	unreachable bool
	// enrolling refuses the fleet key, as a freshly installed host does until
	// automated enrollment has installed it.
	enrolling      bool
	hostKey        string
	serial         string
	installers     []bootstrap.OSInstaller
	fetches        []string
	erases         []fakeErase
	restarts       int
	tailscaleState []byte
	dials          int
	version        string
	bootTime       int64
	updates        []bootstrap.OSUpdate
	jobs           map[string]bootstrap.OSUpdateJob
	jobsID         string
	console        string
	noToken        bool
	downloads      []string
	installs       []fakeInstall
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
		serial: "C07FC05JQ6NY",
		installers: []bootstrap.OSInstaller{
			{Title: "macOS 27 Golden Gate", Version: "27.0", Build: "26A428"},
			{Title: "macOS Tahoe", Version: "26.7", Build: "25G229"},
		},
		jobs:    map[string]bootstrap.OSUpdateJob{},
		console: "tuist",
	}
}

func (f *fakeOSUpdateHost) Fingerprint() string                         { return f.hostKey }
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

func (f *fakeOSUpdateHost) StartDownload(_ context.Context, id, label string) error {
	f.downloads = append(f.downloads, label)
	f.start(id, bootstrap.OSUpdateJobDownload)
	return nil
}

func (f *fakeOSUpdateHost) StartInstall(_ context.Context, id, label, user, password string) error {
	f.installs = append(f.installs, fakeInstall{label, user, password})
	f.start(id, bootstrap.OSUpdateJobInstall)
	return nil
}

// start mirrors the host scripts: a job lives in its update's directory, and
// starting one removes every other update's.
func (f *fakeOSUpdateHost) start(id, job string) {
	if f.jobsID != id {
		f.jobs = map[string]bootstrap.OSUpdateJob{}
	}
	f.jobsID = id
	f.jobs[job] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobRunning}
}

func (f *fakeOSUpdateHost) Job(_ context.Context, id, job string) (bootstrap.OSUpdateJob, error) {
	if state, ok := f.jobs[job]; ok && f.jobsID == id {
		return state, nil
	}
	return bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobAbsent}, nil
}

func (f *fakeOSUpdateHost) Serial(context.Context) (string, error) { return f.serial, nil }
func (f *fakeOSUpdateHost) ListFullInstallers(context.Context) ([]bootstrap.OSInstaller, error) {
	return f.installers, nil
}
func (f *fakeOSUpdateHost) TailscaleState(context.Context) ([]byte, error) {
	return f.tailscaleState, nil
}
func (f *fakeOSUpdateHost) Restart(context.Context) error { f.restarts++; return nil }

func (f *fakeOSUpdateHost) StartFetchInstaller(_ context.Context, id, version string) error {
	f.fetches = append(f.fetches, version)
	f.start(id, bootstrap.OSUpdateJobDownload)
	return nil
}

func (f *fakeOSUpdateHost) StartErase(_ context.Context, id string, installer bootstrap.OSInstaller, user, password string) error {
	f.erases = append(f.erases, fakeErase{installer.App(), user, password})
	f.start(id, bootstrap.OSUpdateJobErase)
	return nil
}

// reinstalled is the erase finishing: the host restarts on a fresh install of
// version with a new host key, and none of the old host's jobs, tailnet state
// or secure token.
func (f *fakeOSUpdateHost) reinstalled(version, hostKey string) {
	f.version, f.hostKey = version, hostKey
	f.bootTime += 1000
	f.jobs, f.jobsID = map[string]bootstrap.OSUpdateJob{}, ""
	f.tailscaleState = nil
	f.noToken = true
}

// leftover places a job an earlier update left on the host.
func (f *fakeOSUpdateHost) leftover(job string, state bootstrap.OSUpdateJob) {
	f.jobsID = "an-earlier-update"
	f.jobs[job] = state
}

// exit ends a job the current update started.
func (f *fakeOSUpdateHost) exit(job string, code int, tail string) {
	f.jobs[job] = bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobExited, ExitCode: code, LogTail: tail}
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
		m.Spec.Host = "mini-01"
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
	rack := rackHost("mini-01", func(h *infrav1.RackHost) { h.Status.Machine = osUpdateTestMachine })
	r := newRackReconciler(t, append([]runtime.Object{rack, machine}, objs...)...)
	fake := newFakeOSUpdateHost()
	r.osUpdateDial = func(_, _ string, _ []byte, knownFingerprint string) (osUpdateHost, error) {
		fake.dials++
		switch {
		case fake.unreachable:
			return nil, errors.New("dial tcp 192.168.0.41:22: connect: connection refused")
		case knownFingerprint != "" && knownFingerprint != fake.hostKey:
			return nil, fmt.Errorf("ssh: handshake failed: %w: expected %s, got %s", bootstrap.ErrHostKeyMismatch, knownFingerprint, fake.hostKey)
		case fake.enrolling:
			return nil, errors.New("ssh: handshake failed: ssh: unable to authenticate")
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
	f.stepResult()
}

// stepResult reconciles once, reading the pinned host key the way every
// reconcile does.
func (f *osUpdateFixture) stepResult() ctrl.Result {
	f.t.Helper()
	creds, err := f.r.CredentialsManager.GetMachineBootstrap(context.Background(), osUpdateTestMachine)
	if err != nil {
		f.t.Fatal(err)
	}
	f.oc.knownFingerprint = ""
	if creds != nil {
		f.oc.knownFingerprint = creds.HostFingerprint
	}
	result, err := f.r.reconcileOSUpdate(context.Background(), f.oc)
	if err != nil {
		f.t.Fatalf("reconcileOSUpdate: %v", err)
	}
	return result
}

// stepLosingStatus runs a reconcile whose status write never lands, as when the
// controller restarts or the patch fails. What it did to the host, the Node and
// the Machine stays done.
func (f *osUpdateFixture) stepLosingStatus() {
	f.t.Helper()
	persisted := f.oc.machine.Status.DeepCopy()
	f.step()
	f.oc.machine.Status = *persisted
}

func (f *osUpdateFixture) stepUntil(phase string) {
	f.t.Helper()
	for range 4 {
		f.step()
		if f.status().Phase == phase {
			return
		}
	}
	f.wantPhase(phase)
}

func (f *osUpdateFixture) converged() {
	f.oc.machine.Status.HostConfigHash = f.r.desiredHostConfigHash(f.oc.machine, f.oc.host)
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

func (f *osUpdateFixture) cordonMarked() bool {
	f.t.Helper()
	node := &corev1.Node{}
	if err := f.r.Get(context.Background(), types.NamespacedName{Name: osUpdateTestMachine}, node); err != nil {
		f.t.Fatalf("get node: %v", err)
	}
	_, marked := node.Annotations[OSUpdateCordonAnnotation]
	return marked
}

// driveToInstalling runs a fresh update through an empty drain and the
// download until the install is running.
func (f *osUpdateFixture) driveToInstalling() {
	f.t.Helper()
	installs := len(f.host.installs)
	f.stepUntil(OSUpdatePhaseDownloading)
	f.host.exit(bootstrap.OSUpdateJobDownload, 0, "")
	f.stepUntil(OSUpdatePhaseInstalling)
	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)
	if len(f.host.installs) != installs+1 {
		f.t.Fatal("the install did not start")
	}
}

func TestOSUpdateRunsTheWholeWave(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode(),
		runnerPod("job-1", corev1.PodRunning), runnerPod("job-0", corev1.PodSucceeded))

	f.step()
	f.wantPhase(OSUpdatePhaseDraining)
	if st := f.status(); st.Label != osUpdateTestLabel || st.FromVersion != "26.6" || st.ID == "" {
		t.Fatalf("label %q from %q id %q", st.Label, st.FromVersion, st.ID)
	}
	if !f.cordoned() || !f.cordonMarked() {
		t.Fatal("the Node was not cordoned, as the update's, before anything else")
	}
	f.step()
	f.wantPhase(OSUpdatePhaseDraining)
	if !strings.Contains(f.status().Message, "tuist-runners/job-1") || strings.Contains(f.status().Message, "job-0") {
		t.Fatalf("drain message %q should name only the running pod", f.status().Message)
	}
	if len(f.host.downloads) != 0 {
		t.Fatal("downloaded the update while a job was still running")
	}

	if err := f.r.Delete(context.Background(), runnerPod("job-1", corev1.PodRunning)); err != nil {
		t.Fatal(err)
	}
	f.step()
	f.wantPhase(OSUpdatePhaseDownloading)
	if len(f.host.downloads) != 1 || f.host.downloads[0] != osUpdateTestLabel {
		t.Fatalf("downloads = %v", f.host.downloads)
	}
	if len(f.host.installs) != 0 || f.remediationSkipped() {
		t.Fatal("the install started before the download finished")
	}

	f.host.exit(bootstrap.OSUpdateJobDownload, 0, "")
	f.oc.machine.Status.HostConfigHash = "converged-before-the-update"
	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)
	if len(f.host.installs) != 0 {
		t.Fatal("the install started before its boot time was written to the status")
	}
	if !f.remediationSkipped() {
		t.Fatal("skip-remediation was not set for the install")
	}
	if f.status().BootTimeBefore != 100 {
		t.Fatalf("boot time before = %d", f.status().BootTimeBefore)
	}
	if f.oc.machine.Status.HostConfigHash != "" {
		t.Fatal("the host config hash was not cleared, so the drift loop will not re-push what the installer resets")
	}

	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)
	if want := []fakeInstall{{osUpdateTestLabel, "tuist", "hunter2"}}; len(f.host.installs) != 1 || f.host.installs[0] != want[0] {
		t.Fatalf("installs = %+v, want %+v", f.host.installs, want)
	}
	f.step()
	if len(f.host.installs) != 1 {
		t.Fatal("started the running install again")
	}

	f.host.unreachable = true
	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)

	f.host.unreachable = false
	f.host.bootTime, f.host.version = 200, "26.7"
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)

	f.step()
	f.wantPhase(OSUpdatePhaseConverging)
	if !f.cordoned() {
		t.Fatal("uncordoned before the host config was pushed again")
	}

	f.converged()
	f.host.console = "root"
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)

	f.host.console = "tuist"
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if f.cordoned() || f.cordonMarked() || f.remediationSkipped() || f.annotated() {
		t.Fatalf("after success: cordoned=%t marked=%t skipRemediation=%t annotated=%t", f.cordoned(), f.cordonMarked(), f.remediationSkipped(), f.annotated())
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
	f.wantPhase(OSUpdatePhaseDraining)
}

func TestOSUpdateFailedDownloadHandsTheNodeBack(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.stepUntil(OSUpdatePhaseDownloading)
	if !f.cordoned() {
		t.Fatal("downloading on a Node that can still take jobs")
	}
	f.host.exit(bootstrap.OSUpdateJobDownload, 1, "Error downloading updates.")
	f.step()
	f.wantFailed("DownloadFailed")
	if f.cordoned() || f.remediationSkipped() {
		t.Fatal("a failed download left the unchanged host out of service")
	}
}

func TestOSUpdateCancelledWhileDownloadingUncordons(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.stepUntil(OSUpdatePhaseDownloading)

	delete(f.oc.machine.Annotations, OSUpdateAnnotation)
	f.step()
	f.wantFailed("Cancelled")
	if f.cordoned() || len(f.host.installs) != 0 {
		t.Fatal("cancelling a download left the Node cordoned or installed anyway")
	}
}

func TestOSUpdateCancelledWhileDrainingUncordons(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode(), runnerPod("job-1", corev1.PodRunning))
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
	f.host.exit(bootstrap.OSUpdateJobInstall, 1, "Failed to authenticate")
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

func TestOSUpdateResumesAnInstallWhoseStatusWriteWasLost(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.stepUntil(OSUpdatePhaseDownloading)
	f.host.exit(bootstrap.OSUpdateJobDownload, 0, "")

	for i := 0; i < 3 && len(f.host.installs) == 0; i++ {
		f.stepLosingStatus()
	}
	f.step()
	f.step()
	f.wantPhase(OSUpdatePhaseInstalling)
	if len(f.host.installs) != 1 {
		t.Fatalf("installs = %d, want exactly one", len(f.host.installs))
	}

	f.host.bootTime, f.host.version = 200, "26.7"
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)
	f.converged()
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if f.cordoned() || f.remediationSkipped() {
		t.Fatalf("after a resumed install: cordoned=%t skipRemediation=%t", f.cordoned(), f.remediationSkipped())
	}
}

func TestOSUpdateLiftsItsCordonAfterALostStatusWrite(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.stepLosingStatus()
	if !f.cordoned() {
		t.Fatal("the first reconcile did not cordon")
	}

	f.stepUntil(OSUpdatePhaseDownloading)
	f.host.exit(bootstrap.OSUpdateJobDownload, 0, "")
	f.stepUntil(OSUpdatePhaseInstalling)
	f.step()
	f.host.bootTime, f.host.version = 200, "26.7"
	f.step()
	f.converged()
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if f.cordoned() {
		t.Fatal("the update left behind the cordon it placed before losing its status")
	}
}

func TestOSUpdateAdoptsItsDownloadAfterALostStatusWrite(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.step()
	f.wantPhase(OSUpdatePhaseDraining)
	f.stepLosingStatus()
	f.step()
	f.wantPhase(OSUpdatePhaseDownloading)
	if len(f.host.downloads) != 1 {
		t.Fatalf("downloads = %d, want the one already running", len(f.host.downloads))
	}
}

func TestOSUpdateRetryAfterAFailedConvergeFinishesTheRecovery(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	f.driveToInstalling()
	f.host.bootTime, f.host.version = 200, "26.7"
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)
	f.status().PhaseStartedAt = &metav1.Time{Time: time.Now().Add(-osUpdateConvergeTimeout - time.Minute)}
	f.step()
	f.wantFailed("ConvergeTimedOut")

	f.oc.machine.Annotations[OSUpdateAnnotation] = "26.7"
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)
	if !f.cordoned() {
		t.Fatal("uncordoned before the host converged")
	}
	f.converged()
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if f.cordoned() || f.annotated() {
		t.Fatalf("after the retry: cordoned=%t annotated=%t", f.cordoned(), f.annotated())
	}
}

func TestOSUpdateIgnoresJobsAnEarlierUpdateLeftOnTheHost(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("26.7"), ownerMachine(), updatingNode())
	// A PID recycled after a restart makes an earlier update's job look alive.
	f.host.leftover(bootstrap.OSUpdateJobDownload, bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobRunning})
	f.host.leftover(bootstrap.OSUpdateJobInstall, bootstrap.OSUpdateJob{State: bootstrap.OSUpdateJobRunning})

	f.stepUntil(OSUpdatePhaseDownloading)
	if len(f.host.downloads) != 1 {
		t.Fatal("took an earlier update's download for this one's")
	}
	f.host.exit(bootstrap.OSUpdateJobDownload, 0, "")
	f.stepUntil(OSUpdatePhaseInstalling)
	f.step()
	if len(f.host.installs) != 1 {
		t.Fatal("took an earlier update's install for this one's")
	}
}

func reinstallingMachine(target string, mutate ...func(*infrav1.RackAppleSiliconMachine)) *infrav1.RackAppleSiliconMachine {
	return updatingMachine(target, append([]func(*infrav1.RackAppleSiliconMachine){func(m *infrav1.RackAppleSiliconMachine) {
		m.Annotations = map[string]string{OSReinstallAnnotation: target}
	}}, mutate...)...)
}

// newReinstallFixture is a host on 26.7 pinned to its current key, on the
// tailnet, asked to reinstall onto 27.0.
func newReinstallFixture(t *testing.T, objs ...runtime.Object) *osUpdateFixture {
	t.Helper()
	f := newOSUpdateFixture(t, reinstallingMachine("27.0"), append([]runtime.Object{ownerMachine(), updatingNode()}, objs...)...)
	f.host.version, f.host.hostKey = "26.7", "SHA256:old"
	f.host.tailscaleState = []byte(`{"_machinekey":"ber1-0"}`)
	if err := f.r.CredentialsManager.SetMachineHostFingerprint(context.Background(), osUpdateTestMachine, "SHA256:old"); err != nil {
		t.Fatal(err)
	}
	return f
}

func (f *osUpdateFixture) machineCreds() (pinned string, tailscaleState []byte) {
	f.t.Helper()
	creds, err := f.r.CredentialsManager.GetMachineBootstrap(context.Background(), osUpdateTestMachine)
	if err != nil || creds == nil {
		f.t.Fatalf("machine bootstrap secret: %v", err)
	}
	return creds.HostFingerprint, creds.TailscaleState
}

// driveToErasing runs a reinstall through an empty drain and the installer download until the erase is running.
func (f *osUpdateFixture) driveToErasing() {
	f.t.Helper()
	f.stepUntil(OSUpdatePhaseDownloading)
	f.host.exit(bootstrap.OSUpdateJobDownload, 0, "")
	f.stepUntil(OSUpdatePhaseErasing)
	f.step()
	f.wantPhase(OSUpdatePhaseErasing)
	if len(f.host.erases) != 1 {
		f.t.Fatalf("erases = %d, want 1", len(f.host.erases))
	}
}

func TestOSUpdateReinstallRunsTheWholeWave(t *testing.T) {
	f := newReinstallFixture(t)

	f.step()
	f.wantPhase(OSUpdatePhaseDraining)
	if st := f.status(); !st.Reinstall || st.Label != "macOS 27 Golden Gate" || st.FromVersion != "26.7" {
		t.Fatalf("status = %+v", st)
	}
	if !f.cordoned() || !f.cordonMarked() {
		t.Fatal("the Node was not cordoned, as the update's, before anything else")
	}

	f.step()
	f.wantPhase(OSUpdatePhaseDownloading)
	if len(f.host.fetches) != 1 || f.host.fetches[0] != "27.0" || len(f.host.downloads) != 0 {
		t.Fatalf("fetches = %v, in-place downloads = %v", f.host.fetches, f.host.downloads)
	}

	f.host.exit(bootstrap.OSUpdateJobDownload, 0, "Install finished successfully")
	f.oc.machine.Status.HostConfigHash = "converged-before-the-reinstall"
	f.step()
	f.wantPhase(OSUpdatePhaseErasing)
	if len(f.host.erases) != 0 {
		t.Fatal("the erase started before its boot time was written to the status")
	}
	if !f.remediationSkipped() || f.status().BootTimeBefore != 100 || f.oc.machine.Status.HostConfigHash != "" {
		t.Fatalf("before the erase: skipRemediation=%t bootTimeBefore=%d hash=%q", f.remediationSkipped(), f.status().BootTimeBefore, f.oc.machine.Status.HostConfigHash)
	}

	f.step()
	want := fakeErase{"/Applications/Install macOS 27 Golden Gate.app", "tuist", "hunter2"}
	if len(f.host.erases) != 1 || f.host.erases[0] != want {
		t.Fatalf("erases = %+v, want %+v", f.host.erases, want)
	}
	if _, kept := f.machineCreds(); string(kept) != `{"_machinekey":"ber1-0"}` {
		t.Fatalf("tailnet state kept for the reinstall = %q", kept)
	}
	f.step()
	if len(f.host.erases) != 1 {
		t.Fatal("started the running erase again")
	}

	f.host.reinstalled("27.0", "SHA256:new")
	f.host.enrolling = true
	f.step()
	f.wantPhase(OSUpdatePhaseEnrolling)
	f.step()
	f.wantPhase(OSUpdatePhaseEnrolling)
	if pinned, _ := f.machineCreds(); pinned != "SHA256:old" {
		t.Fatalf("pinned %q before the host could be checked", pinned)
	}

	f.host.enrolling = false
	f.step()
	f.wantPhase(OSUpdatePhaseBootstrapping)
	if pinned, _ := f.machineCreds(); pinned != "SHA256:new" {
		t.Fatalf("pinned = %q, want the reinstalled host's key", pinned)
	}
	if conditions.IsTrue(f.oc.machine, BootstrappedCondition) {
		t.Fatal("the reinstalled host still reads as bootstrapped")
	}
	if result := f.stepResult(); !result.IsZero() {
		t.Fatalf("result = %+v, want zero so the reconcile goes on to bootstrap the host", result)
	}
	f.wantPhase(OSUpdatePhaseBootstrapping)

	conditions.MarkTrue(f.oc.machine, BootstrappedCondition)
	f.step()
	f.wantPhase(OSUpdatePhaseRestarting)
	if f.status().BootTimeBefore != 1100 {
		t.Fatalf("boot time before the restart = %d", f.status().BootTimeBefore)
	}
	f.step()
	if f.host.restarts != 1 {
		t.Fatalf("restarts = %d", f.host.restarts)
	}
	f.host.bootTime, f.host.noToken = 1200, false
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)
	if !f.cordoned() {
		t.Fatal("uncordoned before the host converged")
	}

	f.converged()
	f.step()
	f.wantPhase(OSUpdatePhaseSucceeded)
	if f.cordoned() || f.cordonMarked() || f.remediationSkipped() || f.annotated() || f.reinstallAnnotated() {
		t.Fatal("the reinstall did not hand the Node and the Machine back")
	}
	if msg := f.status().Message; msg != "erased the host and installed macOS 27.0 over 26.7" {
		t.Fatalf("message = %q", msg)
	}
}

func (f *osUpdateFixture) reinstallAnnotated() bool {
	_, ok := f.oc.machine.Annotations[OSReinstallAnnotation]
	return ok
}

func TestOSUpdateReinstallSkipsTheRestartWhenTheTokenIsThere(t *testing.T) {
	f := newReinstallFixture(t)
	f.driveToErasing()
	f.host.reinstalled("27.0", "SHA256:new")
	f.stepUntil(OSUpdatePhaseBootstrapping)
	conditions.MarkTrue(f.oc.machine, BootstrappedCondition)
	f.host.noToken = false
	f.step()
	f.wantPhase(OSUpdatePhaseConverging)
	if f.host.restarts != 0 {
		t.Fatal("restarted a host whose user already has a secure token")
	}
}

func TestOSUpdateReinstallNeverTrustsAHostWithAnotherSerial(t *testing.T) {
	f := newReinstallFixture(t)
	f.driveToErasing()
	f.host.reinstalled("27.0", "SHA256:impostor")
	f.host.serial = "C02XL0GZJGH5"
	f.stepUntil(OSUpdatePhaseEnrolling)
	f.step()
	f.wantFailed("HostIdentityMismatch")
	if pinned, _ := f.machineCreds(); pinned != "SHA256:old" {
		t.Fatalf("pinned %q from a host that is not the RackHost", pinned)
	}
	if !f.cordoned() {
		t.Fatal("a Node whose host could not be verified went back into service")
	}
}

func TestOSUpdateReinstallFailsOnAnotherVersion(t *testing.T) {
	f := newReinstallFixture(t)
	f.driveToErasing()
	f.host.reinstalled("26.7", "SHA256:new")
	f.stepUntil(OSUpdatePhaseEnrolling)
	f.step()
	f.wantFailed("VersionMismatch")
	if !f.cordoned() {
		t.Fatal("a host on an unexpected version went back into service")
	}
}

func TestOSUpdateReinstallThatRestartsUnerasedKeepsTheNodeCordoned(t *testing.T) {
	f := newReinstallFixture(t)
	f.driveToErasing()
	f.host.bootTime = 200
	f.step()
	f.wantFailed("NotErased")
	if !f.cordoned() || f.remediationSkipped() {
		t.Fatal("an unexplained restart must stay cordoned and go back to the health check")
	}
}

func TestOSUpdateFailedEraseHandsTheHostBack(t *testing.T) {
	f := newReinstallFixture(t)
	f.driveToErasing()
	f.host.exit(bootstrap.OSUpdateJobErase, 1, "Error: could not validate sizes")
	f.step()
	f.wantFailed("EraseFailed")
	if f.cordoned() || f.remediationSkipped() {
		t.Fatal("a host the erase never touched was not handed back")
	}
	if _, kept := f.machineCreds(); kept != nil {
		t.Fatal("kept the tailnet state of a host that is still on the tailnet")
	}
}

func TestOSUpdateReinstallRefusesAHostWithoutASerial(t *testing.T) {
	f := newReinstallFixture(t)
	f.oc.host.Spec.Serial = ""
	f.step()
	f.wantFailed("NoSerial")
	if f.host.dials != 0 || f.cordoned() {
		t.Fatal("started a reinstall whose new host key could not be verified")
	}
}

func TestOSUpdateReinstallRefusesAVersionWithoutAFullInstaller(t *testing.T) {
	f := newReinstallFixture(t)
	f.oc.machine.Annotations[OSReinstallAnnotation] = "27.1"
	f.step()
	f.wantFailed("NotOffered")
	if msg := f.status().Message; !strings.Contains(msg, "offered: 27.0, 26.7") {
		t.Fatalf("message %q should list the full installers on offer", msg)
	}
	if f.cordoned() {
		t.Fatal("cordoned for a reinstall that cannot happen")
	}
}

func TestOSUpdateInPlaceRefusalPointsAtTheReinstall(t *testing.T) {
	f := newOSUpdateFixture(t, updatingMachine("27.0"), ownerMachine(), updatingNode())
	f.host.version = "26.7"
	f.step()
	f.wantFailed("ReleaseFamilyMove")
	if msg := f.status().Message; !strings.Contains(msg, OSReinstallAnnotation+"=27.0") {
		t.Fatalf("message %q should name the reinstall annotation", msg)
	}
}

func TestOSUpdateRefusesBothRequestsAtOnce(t *testing.T) {
	f := newReinstallFixture(t)
	f.oc.machine.Annotations[OSUpdateAnnotation] = "26.8"
	f.step()
	f.wantFailed("ConflictingRequests")
	if f.annotated() || f.reinstallAnnotated() || f.host.dials != 0 {
		t.Fatal("acted on, or kept, conflicting requests")
	}
}

func TestErasingHostIsNotPushedByTheDriftLoop(t *testing.T) {
	machine := reinstallingMachine("27.0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.HostConfigHash = "stale"
		m.Status.OSUpdate = &infrav1.OSUpdateStatus{
			ID:             "u1",
			Reinstall:      true,
			Target:         "27.0",
			Label:          "macOS 27 Golden Gate",
			Phase:          OSUpdatePhaseErasing,
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
		t.Fatalf("result = %+v, want a poll of the erase", result)
	}
	if machine.Status.HostConfigHash != "stale" || machine.Status.TartKubeletUpdateAttempts != 0 {
		t.Fatal("the drift loop tried to push a host that is being erased")
	}
}

func TestInstallingHostIsNotPushedByTheDriftLoop(t *testing.T) {
	machine := updatingMachine("26.7", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.HostConfigHash = "stale"
		m.Status.OSUpdate = &infrav1.OSUpdateStatus{
			ID:             "u1",
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
