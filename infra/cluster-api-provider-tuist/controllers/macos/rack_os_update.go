package macos

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// OSUpdateAnnotation asks the controller to update the machine's host to the
// named macOS version in place, e.g. "26.7". The controller clears it when the
// update finishes; removing it before the install starts cancels the update.
const OSUpdateAnnotation = "tuist.dev/os-update"

const (
	OSUpdatePhasePreparing   = "Preparing"
	OSUpdatePhaseDraining    = "Draining"
	OSUpdatePhaseDownloading = "Downloading"
	OSUpdatePhaseInstalling  = "Installing"
	OSUpdatePhaseConverging  = "Converging"
	OSUpdatePhaseSucceeded   = "Succeeded"
	OSUpdatePhaseFailed      = "Failed"
)

const (
	osUpdatePollInterval    = 30 * time.Second
	osUpdateDownloadTimeout = time.Hour
	osUpdateInstallTimeout  = time.Hour
	osUpdateConvergeTimeout = 30 * time.Minute
)

var macOSVersionPattern = regexp.MustCompile(`^\d+(\.\d+){1,2}$`)

// osUpdateHost is the SSH side of an in-place update.
type osUpdateHost interface {
	Fingerprint() string
	Version(ctx context.Context) (string, error)
	BootTime(ctx context.Context) (int64, error)
	ListUpdates(ctx context.Context) ([]bootstrap.OSUpdate, error)
	StartDownload(ctx context.Context, label string) error
	StartInstall(ctx context.Context, label, user, password string) error
	Job(ctx context.Context, job string) (bootstrap.OSUpdateJob, error)
	ConsoleUser(ctx context.Context) (string, error)
	SecureTokenEnabled(ctx context.Context, user string) (bool, error)
	Close() error
}

type osUpdateDialFunc func(ip, user string, privateKey []byte, knownFingerprint string) (osUpdateHost, error)

func dialOSUpdateHost(ip, user string, privateKey []byte, knownFingerprint string) (osUpdateHost, error) {
	session, err := bootstrap.OpenOSUpdateSession(ip, user, privateKey, knownFingerprint)
	if err != nil {
		return nil, err
	}
	return session, nil
}

type osUpdateContext struct {
	machine          *infrav1.RackAppleSiliconMachine
	host             *infrav1.RackHost
	sshKey           []byte
	sudoPassword     string
	knownFingerprint string
}

// osUpdateInstalling reports whether the host is mid-install, when nothing else may dial it.
func osUpdateInstalling(machine *infrav1.RackAppleSiliconMachine) bool {
	return machine.Status.OSUpdate != nil && machine.Status.OSUpdate.Phase == OSUpdatePhaseInstalling
}

func osUpdatePending(machine *infrav1.RackAppleSiliconMachine) bool {
	if _, requested := machine.Annotations[OSUpdateAnnotation]; requested {
		return true
	}
	return machine.Status.OSUpdate != nil && !osUpdateFinished(machine.Status.OSUpdate.Phase)
}

func osUpdateFinished(phase string) bool {
	return phase == OSUpdatePhaseSucceeded || phase == OSUpdatePhaseFailed
}

func osUpdateCancellable(phase string) bool {
	return phase == OSUpdatePhasePreparing || phase == OSUpdatePhaseDownloading || phase == OSUpdatePhaseDraining
}

// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=machines,verbs=get;list;watch;patch
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch;patch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch

// reconcileOSUpdate advances an in-place macOS update by one step. A zero
// Result means there is nothing left to wait for.
func (r *RackAppleSiliconMachineReconciler) reconcileOSUpdate(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	target, requested := oc.machine.Annotations[OSUpdateAnnotation]
	target = strings.TrimSpace(target)
	st := oc.machine.Status.OSUpdate

	if st == nil || osUpdateFinished(st.Phase) {
		if !requested {
			return ctrl.Result{}, nil
		}
		return r.startOSUpdate(ctx, oc, target)
	}

	if !requested && osUpdateCancellable(st.Phase) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "Cancelled",
			"the "+OSUpdateAnnotation+" annotation was removed before the install started", true)
	}

	switch st.Phase {
	case OSUpdatePhasePreparing:
		return r.startOSUpdate(ctx, oc, target)
	case OSUpdatePhaseDownloading:
		return r.osUpdateDownloading(ctx, oc)
	case OSUpdatePhaseDraining:
		return r.osUpdateDraining(ctx, oc)
	case OSUpdatePhaseInstalling:
		return r.osUpdateAwaitingInstall(ctx, oc)
	case OSUpdatePhaseConverging:
		return r.osUpdateConverging(ctx, oc)
	}
	return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "UnknownPhase",
		fmt.Sprintf("unknown phase %q", st.Phase), false)
}

func (r *RackAppleSiliconMachineReconciler) startOSUpdate(ctx context.Context, oc *osUpdateContext, target string) (ctrl.Result, error) {
	machine := oc.machine
	if previous := machine.Status.OSUpdate; previous == nil || osUpdateFinished(previous.Phase) {
		now := metav1.Now()
		machine.Status.OSUpdate = &infrav1.OSUpdateStatus{
			Phase:          OSUpdatePhasePreparing,
			StartedAt:      &now,
			PhaseStartedAt: &now,
			// A failed update can leave its cordon behind; a retry takes it over.
			Cordoned: previous != nil && previous.Cordoned,
		}
	}
	st := machine.Status.OSUpdate
	st.Target = target

	if !macOSVersionPattern.MatchString(target) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "InvalidTarget",
			fmt.Sprintf("%q is not a macOS version such as 26.7", target), false)
	}
	if !conditions.IsTrue(machine, BootstrappedCondition) || machine.Status.FailureReason != nil {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "HostNotReady",
			"the host must be bootstrapped with its host config converged before it can be updated", false)
	}

	host, err := r.openOSUpdateHost(ctx, oc)
	if err != nil {
		return osUpdateWait(st, "could not reach the host: %v", err)
	}
	defer host.Close()

	current, err := host.Version(ctx)
	if err != nil {
		return osUpdateWait(st, "could not read the host's macOS version: %v", err)
	}
	st.FromVersion = current

	switch cmp := compareMacOSVersions(target, current); {
	case cmp == 0:
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseSucceeded, "",
			"already on macOS "+current, false)
	case macOSMajor(target) != macOSMajor(current):
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "ReleaseFamilyMove",
			fmt.Sprintf("macOS %s to %s changes release family, which is an erase and not an in-place update", current, target), false)
	case cmp < 0:
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "Downgrade",
			fmt.Sprintf("the host runs macOS %s, which is newer than %s", current, target), false)
	}

	user := oc.host.Spec.SSHUser
	tokenEnabled, err := host.SecureTokenEnabled(ctx, user)
	if err != nil {
		return osUpdateWait(st, "could not read %s's secure token status: %v", user, err)
	}
	if !tokenEnabled {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "NoSecureToken",
			fmt.Sprintf("%s has no secure token, so softwareupdate cannot authorise an install as them; a newly enrolled host gets one at its first auto-login, so restart it once", user), false)
	}

	updates, err := host.ListUpdates(ctx)
	if err != nil {
		return osUpdateWait(st, "could not list available updates: %v", err)
	}
	var offered []string
	label := ""
	for _, u := range updates {
		if !u.IsMacOS() {
			continue
		}
		offered = append(offered, u.Version)
		if compareMacOSVersions(u.Version, target) == 0 {
			label = u.Label
		}
	}
	if label == "" {
		if len(offered) == 0 {
			offered = []string{"none"}
		}
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "NotOffered",
			fmt.Sprintf("macOS %s is not offered to this host (offered: %s)", target, strings.Join(offered, ", ")), false)
	}

	cordoned, err := r.setNodeUnschedulable(ctx, machine.Name, true)
	if err != nil {
		return osUpdateWait(st, "could not cordon Node %s: %v", machine.Name, err)
	}
	st.Label = label
	st.Cordoned = st.Cordoned || cordoned
	r.setOSUpdatePhase(machine, OSUpdatePhaseDraining, "cordoned; waiting for running pods to finish")
	return r.osUpdateDraining(ctx, oc)
}

func (r *RackAppleSiliconMachineReconciler) osUpdateDraining(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	st := oc.machine.Status.OSUpdate
	active, err := r.activePodsOn(ctx, oc.machine.Name)
	if err != nil {
		return osUpdateWait(st, "could not list pods on Node %s: %v", oc.machine.Name, err)
	}
	if len(active) > 0 {
		shown := active
		if len(shown) > 5 {
			shown = shown[:5]
		}
		return osUpdateWait(st, "waiting for %d pod(s) to finish: %s", len(active), strings.Join(shown, ", "))
	}

	host, err := r.openOSUpdateHost(ctx, oc)
	if err != nil {
		return osUpdateWait(st, "could not reach the host: %v", err)
	}
	defer host.Close()

	job, err := host.Job(ctx, bootstrap.OSUpdateJobDownload)
	if err != nil {
		return osUpdateWait(st, "could not read the download: %v", err)
	}
	if job.State != bootstrap.OSUpdateJobRunning {
		if err := host.StartDownload(ctx, st.Label); err != nil {
			return osUpdateWait(st, "could not start the download: %v", err)
		}
	}
	r.setOSUpdatePhase(oc.machine, OSUpdatePhaseDownloading, fmt.Sprintf("downloading %s", st.Label))
	return ctrl.Result{RequeueAfter: osUpdatePollInterval}, nil
}

func (r *RackAppleSiliconMachineReconciler) osUpdateDownloading(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	st := oc.machine.Status.OSUpdate
	if osUpdatePhaseOlderThan(st, osUpdateDownloadTimeout) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "DownloadTimedOut",
			fmt.Sprintf("the download did not finish within %s", osUpdateDownloadTimeout), true)
	}

	host, err := r.openOSUpdateHost(ctx, oc)
	if err != nil {
		return osUpdateWait(st, "could not reach the host: %v", err)
	}
	defer host.Close()

	job, err := host.Job(ctx, bootstrap.OSUpdateJobDownload)
	if err != nil {
		return osUpdateWait(st, "could not read the download: %v", err)
	}
	switch {
	case job.State == bootstrap.OSUpdateJobRunning:
		return osUpdateWait(st, "downloading: %s", job.LogTail)
	case job.State == bootstrap.OSUpdateJobAbsent:
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "DownloadLost",
			"the download stopped without recording an exit code", true)
	case job.ExitCode != 0:
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "DownloadFailed",
			fmt.Sprintf("softwareupdate --download exited %d: %s", job.ExitCode, job.LogTail), true)
	}

	if !st.RemediationSuspended {
		suspended, err := r.setSkipRemediation(ctx, oc.machine, true)
		if err != nil {
			return osUpdateWait(st, "could not suspend health-check remediation: %v", err)
		}
		st.RemediationSuspended = suspended
	}

	job, err = host.Job(ctx, bootstrap.OSUpdateJobInstall)
	if err != nil {
		return osUpdateWait(st, "could not read the install: %v", err)
	}
	if job.State != bootstrap.OSUpdateJobRunning {
		bootTime, err := host.BootTime(ctx)
		if err != nil {
			return osUpdateWait(st, "could not read the host's boot time: %v", err)
		}
		if err := host.StartInstall(ctx, st.Label, oc.host.Spec.SSHUser, oc.sudoPassword); err != nil {
			return osUpdateWait(st, "could not start the install: %v", err)
		}
		st.BootTimeBefore = bootTime
	}
	r.setOSUpdatePhase(oc.machine, OSUpdatePhaseInstalling,
		fmt.Sprintf("installing %s; the host restarts when it finishes", st.Label))
	return ctrl.Result{RequeueAfter: osUpdatePollInterval}, nil
}

func (r *RackAppleSiliconMachineReconciler) osUpdateAwaitingInstall(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	st := oc.machine.Status.OSUpdate
	if osUpdatePhaseOlderThan(st, osUpdateInstallTimeout) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "InstallTimedOut",
			fmt.Sprintf("the host did not come back on macOS %s within %s; the Node stays cordoned", st.Target, osUpdateInstallTimeout), false)
	}

	host, err := r.openOSUpdateHost(ctx, oc)
	if err != nil {
		return osUpdateWait(st, "waiting for the host to come back: %v", err)
	}
	defer host.Close()

	bootTime, err := host.BootTime(ctx)
	if err != nil {
		return osUpdateWait(st, "could not read the host's boot time: %v", err)
	}
	if bootTime > st.BootTimeBefore {
		version, err := host.Version(ctx)
		if err != nil {
			return osUpdateWait(st, "could not read the host's macOS version: %v", err)
		}
		if compareMacOSVersions(version, st.Target) != 0 {
			return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "VersionMismatch",
				fmt.Sprintf("the host restarted on macOS %s, not %s; the Node stays cordoned", version, st.Target), false)
		}
		// The installer resets files the host config owns, /etc/pf.conf among them.
		oc.machine.Status.HostConfigHash = ""
		r.setOSUpdatePhase(oc.machine, OSUpdatePhaseConverging,
			fmt.Sprintf("restarted on macOS %s; pushing the host config again", version))
		return ctrl.Result{Requeue: true}, nil
	}

	job, err := host.Job(ctx, bootstrap.OSUpdateJobInstall)
	if err != nil {
		return osUpdateWait(st, "could not read the install: %v", err)
	}
	if job.State == bootstrap.OSUpdateJobExited && job.ExitCode != 0 {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "InstallFailed",
			fmt.Sprintf("softwareupdate --install exited %d before restarting: %s", job.ExitCode, job.LogTail), true)
	}
	return osUpdateWait(st, "installing: %s", job.LogTail)
}

func (r *RackAppleSiliconMachineReconciler) osUpdateConverging(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	machine := oc.machine
	st := machine.Status.OSUpdate
	if machine.Status.FailureReason != nil {
		message := ""
		if machine.Status.FailureMessage != nil {
			message = *machine.Status.FailureMessage
		}
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "ConvergeFailed",
			"pushing the host config after the update failed: "+message, false)
	}
	if osUpdatePhaseOlderThan(st, osUpdateConvergeTimeout) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "ConvergeTimedOut",
			fmt.Sprintf("the host did not converge within %s of restarting; the Node stays cordoned", osUpdateConvergeTimeout), false)
	}
	if machine.Status.HostConfigHash != r.desiredHostConfigHash(machine, oc.host) {
		return osUpdateWait(st, "waiting for the host config push")
	}
	ready, err := r.nodeReady(ctx, machine.Name)
	if err != nil {
		return osUpdateWait(st, "could not read Node %s: %v", machine.Name, err)
	}
	if !ready {
		return osUpdateWait(st, "waiting for Node %s to report Ready", machine.Name)
	}

	host, err := r.openOSUpdateHost(ctx, oc)
	if err != nil {
		return osUpdateWait(st, "could not reach the host: %v", err)
	}
	defer host.Close()
	console, err := host.ConsoleUser(ctx)
	if err != nil {
		return osUpdateWait(st, "could not read the console session: %v", err)
	}
	if console != oc.host.Spec.SSHUser {
		return osUpdateWait(st, "waiting for %s to log in at the console; it belongs to %q", oc.host.Spec.SSHUser, console)
	}

	return r.finishOSUpdate(ctx, oc, OSUpdatePhaseSucceeded, "",
		fmt.Sprintf("updated from macOS %s to %s", st.FromVersion, st.Target), true)
}

// finishOSUpdate ends the update. The Node is uncordoned only when uncordon is
// set and the update cordoned it; remediation is always handed back.
func (r *RackAppleSiliconMachineReconciler) finishOSUpdate(ctx context.Context, oc *osUpdateContext, phase, reason, message string, uncordon bool) (ctrl.Result, error) {
	machine := oc.machine
	st := machine.Status.OSUpdate
	if uncordon && st.Cordoned {
		if _, err := r.setNodeUnschedulable(ctx, machine.Name, false); err != nil && !apierrors.IsNotFound(err) {
			return ctrl.Result{}, fmt.Errorf("uncordon Node %s: %w", machine.Name, err)
		}
		st.Cordoned = false
	}
	if st.RemediationSuspended {
		if _, err := r.setSkipRemediation(ctx, machine, false); err != nil {
			return ctrl.Result{}, fmt.Errorf("resume health-check remediation: %w", err)
		}
		st.RemediationSuspended = false
	}

	now := metav1.Now()
	st.Phase, st.Reason, st.Message = phase, reason, message
	st.PhaseStartedAt, st.CompletedAt = &now, &now
	if requested, ok := machine.Annotations[OSUpdateAnnotation]; ok && strings.TrimSpace(requested) == st.Target {
		delete(machine.Annotations, OSUpdateAnnotation)
	}

	eventType := corev1.EventTypeNormal
	if phase == OSUpdatePhaseFailed {
		eventType = corev1.EventTypeWarning
		message = reason + ": " + message
	}
	r.Recorder.Event(machine, eventType, "OSUpdate"+phase, message)
	return ctrl.Result{}, nil
}

func (r *RackAppleSiliconMachineReconciler) setOSUpdatePhase(machine *infrav1.RackAppleSiliconMachine, phase, message string) {
	now := metav1.Now()
	st := machine.Status.OSUpdate
	st.Phase, st.Message, st.PhaseStartedAt = phase, message, &now
	r.Recorder.Event(machine, corev1.EventTypeNormal, "OSUpdate"+phase, message)
}

func osUpdateWait(st *infrav1.OSUpdateStatus, format string, args ...any) (ctrl.Result, error) {
	st.Message = fmt.Sprintf(format, args...)
	return ctrl.Result{RequeueAfter: osUpdatePollInterval}, nil
}

func osUpdatePhaseOlderThan(st *infrav1.OSUpdateStatus, d time.Duration) bool {
	return st.PhaseStartedAt != nil && time.Since(st.PhaseStartedAt.Time) > d
}

func (r *RackAppleSiliconMachineReconciler) openOSUpdateHost(ctx context.Context, oc *osUpdateContext) (osUpdateHost, error) {
	dial := r.osUpdateDial
	if dial == nil {
		dial = dialOSUpdateHost
	}
	targets := []string{r.dialTarget(oc.host)}
	if egress := r.egressHost(oc.machine.Name); egress != "" && egress != targets[0] {
		targets = append(targets, egress)
	}
	var errs []error
	for _, target := range targets {
		host, err := dial(target, oc.host.Spec.SSHUser, oc.sshKey, oc.knownFingerprint)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		r.persistFingerprint(ctx, oc.machine, host.Fingerprint(), oc.knownFingerprint)
		return host, nil
	}
	return nil, errors.Join(errs...)
}

func (r *RackAppleSiliconMachineReconciler) setNodeUnschedulable(ctx context.Context, name string, unschedulable bool) (bool, error) {
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		return false, err
	}
	if node.Spec.Unschedulable == unschedulable {
		return false, nil
	}
	base := node.DeepCopy()
	node.Spec.Unschedulable = unschedulable
	return true, r.Patch(ctx, node, client.MergeFrom(base))
}

func (r *RackAppleSiliconMachineReconciler) nodeReady(ctx context.Context, name string) (bool, error) {
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return false, nil
		}
		return false, err
	}
	for _, cond := range node.Status.Conditions {
		if cond.Type == corev1.NodeReady {
			return cond.Status == corev1.ConditionTrue, nil
		}
	}
	return false, nil
}

// activePodsOn lists the pods still running work on the Node.
func (r *RackAppleSiliconMachineReconciler) activePodsOn(ctx context.Context, nodeName string) ([]string, error) {
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods); err != nil {
		return nil, err
	}
	var active []string
	for i := range pods.Items {
		pod := &pods.Items[i]
		if pod.Spec.NodeName != nodeName || pod.Status.Phase == corev1.PodSucceeded || pod.Status.Phase == corev1.PodFailed {
			continue
		}
		if _, mirror := pod.Annotations[corev1.MirrorPodAnnotationKey]; mirror {
			continue
		}
		if owner := metav1.GetControllerOf(pod); owner != nil && owner.Kind == "DaemonSet" {
			continue
		}
		active = append(active, pod.Namespace+"/"+pod.Name)
	}
	sort.Strings(active)
	return active, nil
}

// setSkipRemediation adds or removes skip-remediation on the owning CAPI
// Machine and reports whether it changed anything.
func (r *RackAppleSiliconMachineReconciler) setSkipRemediation(ctx context.Context, machine *infrav1.RackAppleSiliconMachine, skip bool) (bool, error) {
	owner, err := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if err != nil || owner == nil {
		return false, err
	}
	if _, has := owner.Annotations[clusterv1.MachineSkipRemediationAnnotation]; has == skip {
		return false, nil
	}
	base := owner.DeepCopy()
	if skip {
		if owner.Annotations == nil {
			owner.Annotations = map[string]string{}
		}
		owner.Annotations[clusterv1.MachineSkipRemediationAnnotation] = ""
	} else {
		delete(owner.Annotations, clusterv1.MachineSkipRemediationAnnotation)
	}
	return true, r.Patch(ctx, owner, client.MergeFrom(base))
}

func compareMacOSVersions(a, b string) int {
	as, bs := strings.Split(a, "."), strings.Split(b, ".")
	for i := 0; i < max(len(as), len(bs)); i++ {
		x, y := macOSVersionPart(as, i), macOSVersionPart(bs, i)
		if x != y {
			if x < y {
				return -1
			}
			return 1
		}
	}
	return 0
}

func macOSVersionPart(parts []string, i int) int {
	if i >= len(parts) {
		return 0
	}
	n, _ := strconv.Atoi(parts[i])
	return n
}

func macOSMajor(version string) string {
	major, _, _ := strings.Cut(version, ".")
	return major
}
