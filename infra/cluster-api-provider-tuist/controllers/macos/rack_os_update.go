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
	"k8s.io/apimachinery/pkg/util/uuid"
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
// update finishes; removing it before the Installing phase cancels the update.
const OSUpdateAnnotation = "tuist.dev/os-update"

// OSReinstallAnnotation asks the controller to erase the machine's host and
// install the named macOS version from its full installer, e.g. "27.0": how a
// host moves to another release family, which the in-place update refuses. It
// is its own annotation because it wipes the host's images and cache volume.
// The controller clears it when the reinstall finishes; removing it before the
// Erasing phase cancels the reinstall.
const OSReinstallAnnotation = "tuist.dev/os-reinstall"

// OSUpdateCordonAnnotation marks a Node cordon an update placed. It is written
// in the same patch as the cordon, so the update can lift its cordon even after
// losing its own status, and a retry takes over a cordon an earlier failed
// update left. A cordon someone else placed never carries it.
const OSUpdateCordonAnnotation = "tuist.dev/os-update-cordon"

// osUpdateSkipRemediationValue is the value an update gives skip-remediation on
// the CAPI Machine. CAPI reads the annotation by presence alone, so the value
// only tells the update which one it set.
const osUpdateSkipRemediationValue = "tuist.dev/os-update"

const (
	OSUpdatePhasePreparing     = "Preparing"
	OSUpdatePhaseDraining      = "Draining"
	OSUpdatePhaseDownloading   = "Downloading"
	OSUpdatePhaseInstalling    = "Installing"
	OSUpdatePhaseErasing       = "Erasing"
	OSUpdatePhaseEnrolling     = "Enrolling"
	OSUpdatePhaseBootstrapping = "Bootstrapping"
	OSUpdatePhaseRestarting    = "Restarting"
	OSUpdatePhaseConverging    = "Converging"
	OSUpdatePhaseSucceeded     = "Succeeded"
	OSUpdatePhaseFailed        = "Failed"
)

const (
	osUpdatePollInterval      = 30 * time.Second
	osUpdateDownloadTimeout   = time.Hour
	osUpdateInstallTimeout    = time.Hour
	osUpdateEraseTimeout      = time.Hour
	osUpdateEnrollTimeout     = 30 * time.Minute
	osUpdateBootstrapTimeout  = time.Hour
	osUpdateRestartTimeout    = 30 * time.Minute
	osUpdateConvergeTimeout   = 30 * time.Minute
	osUpdateInstallersOffered = 5
)

var macOSVersionPattern = regexp.MustCompile(`^\d+(\.\d+){1,2}$`)

// osUpdateHost is the SSH side of an update.
type osUpdateHost interface {
	Fingerprint() string
	Version(ctx context.Context) (string, error)
	BootTime(ctx context.Context) (int64, error)
	Serial(ctx context.Context) (string, error)
	ListUpdates(ctx context.Context) ([]bootstrap.OSUpdate, error)
	ListFullInstallers(ctx context.Context) ([]bootstrap.OSInstaller, error)
	StartDownload(ctx context.Context, id, label string) error
	StartFetchInstaller(ctx context.Context, id, version string) error
	StartInstall(ctx context.Context, id, label, user, password string) error
	StartErase(ctx context.Context, id string, installer bootstrap.OSInstaller, user, password string) error
	Job(ctx context.Context, id, job string) (bootstrap.OSUpdateJob, error)
	TailscaleState(ctx context.Context) ([]byte, error)
	Restart(ctx context.Context) error
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

// osUpdateRunsFirst reports whether the update has to run before the rest of
// the reconcile. While the host installs, erases, enrolls or restarts nothing
// else may dial it; while it bootstraps again the update only watches, and the
// reconcile goes on to bootstrap it.
func osUpdateRunsFirst(machine *infrav1.RackAppleSiliconMachine) bool {
	if machine.Status.OSUpdate == nil {
		return false
	}
	switch machine.Status.OSUpdate.Phase {
	case OSUpdatePhaseInstalling, OSUpdatePhaseErasing, OSUpdatePhaseEnrolling, OSUpdatePhaseBootstrapping, OSUpdatePhaseRestarting:
		return true
	}
	return false
}

func osUpdatePending(machine *infrav1.RackAppleSiliconMachine) bool {
	if _, requested := machine.Annotations[OSUpdateAnnotation]; requested {
		return true
	}
	if _, requested := machine.Annotations[OSReinstallAnnotation]; requested {
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

func osUpdateAnnotationFor(reinstall bool) string {
	if reinstall {
		return OSReinstallAnnotation
	}
	return OSUpdateAnnotation
}

// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=machines,verbs=get;list;watch;patch
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch;patch
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch

// reconcileOSUpdate advances an in-place update or a reinstall by one step. A
// zero Result means there is nothing to wait for before the rest of the
// reconcile.
func (r *RackAppleSiliconMachineReconciler) reconcileOSUpdate(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	machine := oc.machine
	st := machine.Status.OSUpdate

	if st == nil || osUpdateFinished(st.Phase) {
		update, updateRequested := machine.Annotations[OSUpdateAnnotation]
		reinstall, reinstallRequested := machine.Annotations[OSReinstallAnnotation]
		switch {
		case updateRequested && reinstallRequested:
			delete(machine.Annotations, OSUpdateAnnotation)
			delete(machine.Annotations, OSReinstallAnnotation)
			now := metav1.Now()
			machine.Status.OSUpdate = &infrav1.OSUpdateStatus{
				Phase: OSUpdatePhaseFailed, Reason: "ConflictingRequests",
				Message:   "both " + OSUpdateAnnotation + " and " + OSReinstallAnnotation + " were set; set only one",
				StartedAt: &now, PhaseStartedAt: &now, CompletedAt: &now,
			}
			r.Recorder.Event(machine, corev1.EventTypeWarning, "OSUpdateFailed", "ConflictingRequests: "+machine.Status.OSUpdate.Message)
			return ctrl.Result{}, nil
		case reinstallRequested:
			return r.startOSUpdate(ctx, oc, strings.TrimSpace(reinstall), true)
		case updateRequested:
			return r.startOSUpdate(ctx, oc, strings.TrimSpace(update), false)
		}
		return ctrl.Result{}, nil
	}

	target, requested := machine.Annotations[osUpdateAnnotationFor(st.Reinstall)]
	if !requested && osUpdateCancellable(st.Phase) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "Cancelled",
			"the "+osUpdateAnnotationFor(st.Reinstall)+" annotation was removed before the host was changed", true)
	}

	switch st.Phase {
	case OSUpdatePhasePreparing:
		return r.startOSUpdate(ctx, oc, strings.TrimSpace(target), st.Reinstall)
	case OSUpdatePhaseDraining:
		return r.osUpdateDraining(ctx, oc)
	case OSUpdatePhaseDownloading:
		return r.osUpdateDownloading(ctx, oc)
	case OSUpdatePhaseInstalling:
		return r.osUpdateAwaitingInstall(ctx, oc)
	case OSUpdatePhaseErasing:
		return r.osUpdateErasing(ctx, oc)
	case OSUpdatePhaseEnrolling:
		return r.osUpdateEnrolling(ctx, oc)
	case OSUpdatePhaseBootstrapping:
		return r.osUpdateBootstrapping(ctx, oc)
	case OSUpdatePhaseRestarting:
		return r.osUpdateRestarting(ctx, oc)
	case OSUpdatePhaseConverging:
		return r.osUpdateConverging(ctx, oc)
	}
	return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "UnknownPhase",
		fmt.Sprintf("unknown phase %q", st.Phase), false)
}

func (r *RackAppleSiliconMachineReconciler) startOSUpdate(ctx context.Context, oc *osUpdateContext, target string, reinstall bool) (ctrl.Result, error) {
	machine := oc.machine
	if previous := machine.Status.OSUpdate; previous == nil || osUpdateFinished(previous.Phase) {
		now := metav1.Now()
		machine.Status.OSUpdate = &infrav1.OSUpdateStatus{
			ID:             string(uuid.NewUUID()),
			Reinstall:      reinstall,
			Phase:          OSUpdatePhasePreparing,
			StartedAt:      &now,
			PhaseStartedAt: &now,
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
	if reinstall && oc.host.Spec.Serial == "" {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "NoSerial",
			fmt.Sprintf("RackHost %s records no serial, which is how the reinstalled host is recognised before its new host key is trusted", oc.host.Name), false)
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

	if !reinstall {
		switch cmp := compareMacOSVersions(target, current); {
		case cmp == 0:
			recovering, err := r.nodeCordonedByOSUpdate(ctx, machine.Name)
			if err != nil {
				return osUpdateWait(st, "could not read Node %s: %v", machine.Name, err)
			}
			if recovering {
				r.setOSUpdatePhase(machine, OSUpdatePhaseConverging,
					fmt.Sprintf("already on macOS %s; finishing the recovery an earlier update left", current))
				return r.osUpdateConverging(ctx, oc)
			}
			return r.finishOSUpdate(ctx, oc, OSUpdatePhaseSucceeded, "",
				"already on macOS "+current, false)
		case macOSMajor(target) != macOSMajor(current):
			return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "ReleaseFamilyMove",
				fmt.Sprintf("macOS %s to %s changes release family, which is an erase and not an in-place update; set %s=%s instead", current, target, OSReinstallAnnotation, target), false)
		case cmp < 0:
			return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "Downgrade",
				fmt.Sprintf("the host runs macOS %s, which is newer than %s", current, target), false)
		}
	}

	user := oc.host.Spec.SSHUser
	tokenEnabled, err := host.SecureTokenEnabled(ctx, user)
	if err != nil {
		return osUpdateWait(st, "could not read %s's secure token status: %v", user, err)
	}
	if !tokenEnabled {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "NoSecureToken",
			fmt.Sprintf("%s has no secure token, so the installer cannot authorise as them; a newly enrolled host gets one at its first auto-login, so restart it once", user), false)
	}

	label, offered, err := resolveOSUpdateLabel(ctx, host, target, reinstall)
	if err != nil {
		return osUpdateWait(st, "could not list what Software Update offers: %v", err)
	}
	if label == "" {
		if len(offered) == 0 {
			offered = []string{"none"}
		}
		what := "offered to this host"
		if reinstall {
			what = "offered as a full installer to this host"
		}
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "NotOffered",
			fmt.Sprintf("macOS %s is not %s (offered: %s)", target, what, strings.Join(offered, ", ")), false)
	}

	if err := r.cordonNodeForOSUpdate(ctx, machine.Name, target); err != nil {
		return osUpdateWait(st, "could not cordon Node %s: %v", machine.Name, err)
	}
	st.Label = label
	r.setOSUpdatePhase(machine, OSUpdatePhaseDraining, "cordoned; waiting for running pods to finish")
	// The update's ID reaches the status before any job starts on the host.
	return ctrl.Result{Requeue: true}, nil
}

// resolveOSUpdateLabel finds what to download for target: the softwareupdate
// label of an in-place update, or the title of a full installer. It also
// returns the versions on offer, for the message when target is not among them.
func resolveOSUpdateLabel(ctx context.Context, host osUpdateHost, target string, reinstall bool) (string, []string, error) {
	var offered []string
	if reinstall {
		installers, err := host.ListFullInstallers(ctx)
		if err != nil {
			return "", nil, err
		}
		for _, installer := range installers {
			if compareMacOSVersions(installer.Version, target) == 0 {
				return installer.Title, nil, nil
			}
			if len(offered) < osUpdateInstallersOffered {
				offered = append(offered, installer.Version)
			}
		}
		return "", offered, nil
	}

	updates, err := host.ListUpdates(ctx)
	if err != nil {
		return "", nil, err
	}
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
	return label, offered, nil
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

	job, err := host.Job(ctx, st.ID, bootstrap.OSUpdateJobDownload)
	if err != nil {
		return osUpdateWait(st, "could not read the download: %v", err)
	}
	if job.State == bootstrap.OSUpdateJobAbsent {
		start := func() error { return host.StartDownload(ctx, st.ID, st.Label) }
		if st.Reinstall {
			start = func() error { return host.StartFetchInstaller(ctx, st.ID, st.Target) }
		}
		if err := start(); err != nil {
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

	job, err := host.Job(ctx, st.ID, bootstrap.OSUpdateJobDownload)
	if err != nil {
		return osUpdateWait(st, "could not read the download: %v", err)
	}
	switch {
	case job.State == bootstrap.OSUpdateJobRunning:
		return osUpdateWait(st, "downloading: %s", job.LogTail)
	case job.State == bootstrap.OSUpdateJobAbsent || job.State == bootstrap.OSUpdateJobLost:
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "DownloadLost",
			"the download stopped without recording an exit code", true)
	case job.ExitCode != 0:
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "DownloadFailed",
			fmt.Sprintf("softwareupdate --download exited %d: %s", job.ExitCode, job.LogTail), true)
	}

	if err := r.suspendRemediationForOSUpdate(ctx, oc.machine); err != nil {
		return osUpdateWait(st, "could not suspend health-check remediation: %v", err)
	}
	bootTime, err := host.BootTime(ctx)
	if err != nil {
		return osUpdateWait(st, "could not read the host's boot time: %v", err)
	}
	st.BootTimeBefore = bootTime
	// The installer resets files the host config owns, /etc/pf.conf among them,
	// so the drift loop pushes the whole config again however the update ends.
	oc.machine.Status.HostConfigHash = ""
	if st.Reinstall {
		r.setOSUpdatePhase(oc.machine, OSUpdatePhaseErasing,
			fmt.Sprintf("erasing the host to install macOS %s", st.Target))
	} else {
		r.setOSUpdatePhase(oc.machine, OSUpdatePhaseInstalling,
			fmt.Sprintf("installing %s; the host restarts when it finishes", st.Label))
	}
	// The install or erase starts only once this status is written, so a
	// restarted controller always knows the boot time to compare against.
	return ctrl.Result{Requeue: true}, nil
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
		r.setOSUpdatePhase(oc.machine, OSUpdatePhaseConverging,
			fmt.Sprintf("restarted on macOS %s; pushing the host config again", version))
		return ctrl.Result{Requeue: true}, nil
	}

	job, err := host.Job(ctx, st.ID, bootstrap.OSUpdateJobInstall)
	if err != nil {
		return osUpdateWait(st, "could not read the install: %v", err)
	}
	switch {
	case job.State == bootstrap.OSUpdateJobAbsent:
		if err := host.StartInstall(ctx, st.ID, st.Label, oc.host.Spec.SSHUser, oc.sudoPassword); err != nil {
			return osUpdateWait(st, "could not start the install: %v", err)
		}
		return osUpdateWait(st, "installing %s; the host restarts when it finishes", st.Label)
	case job.State == bootstrap.OSUpdateJobExited && job.ExitCode != 0:
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "InstallFailed",
			fmt.Sprintf("softwareupdate --install exited %d before restarting: %s", job.ExitCode, job.LogTail), true)
	case job.State == bootstrap.OSUpdateJobExited:
		return osUpdateWait(st, "installed; waiting for the host to restart")
	case job.State == bootstrap.OSUpdateJobLost:
		return osUpdateWait(st, "the install stopped without an exit code; waiting for the host to restart: %s", job.LogTail)
	}
	return osUpdateWait(st, "installing: %s", job.LogTail)
}

func (r *RackAppleSiliconMachineReconciler) osUpdateErasing(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	st := oc.machine.Status.OSUpdate
	if osUpdatePhaseOlderThan(st, osUpdateEraseTimeout) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "EraseTimedOut",
			fmt.Sprintf("the host did not come back freshly installed within %s; the Node stays cordoned", osUpdateEraseTimeout), false)
	}

	host, err := r.openOSUpdateHost(ctx, oc)
	if errors.Is(err, bootstrap.ErrHostKeyMismatch) {
		r.setOSUpdatePhase(oc.machine, OSUpdatePhaseEnrolling,
			fmt.Sprintf("the host answers with a new host key; checking it is %s before trusting the key", oc.host.Spec.Serial))
		return ctrl.Result{Requeue: true}, nil
	}
	if err != nil {
		return osUpdateWait(st, "erasing the host and installing macOS %s: %v", st.Target, err)
	}
	defer host.Close()

	bootTime, err := host.BootTime(ctx)
	if err != nil {
		return osUpdateWait(st, "could not read the host's boot time: %v", err)
	}
	if bootTime > st.BootTimeBefore {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "NotErased",
			"the host restarted with its old host key, so it was not erased; the Node stays cordoned", false)
	}

	job, err := host.Job(ctx, st.ID, bootstrap.OSUpdateJobErase)
	if err != nil {
		return osUpdateWait(st, "could not read the erase: %v", err)
	}
	switch {
	case job.State == bootstrap.OSUpdateJobAbsent:
		// The erase wipes the host's tailnet identity. Carried over, it lets the
		// host rejoin as the same device, which its egress Service, metrics and
		// VNC relay address by name.
		state, err := host.TailscaleState(ctx)
		if err != nil {
			return osUpdateWait(st, "could not read the host's tailnet state: %v", err)
		}
		if state != nil {
			if err := r.CredentialsManager.SetMachineTailscaleState(ctx, oc.machine.Name, state); err != nil {
				return osUpdateWait(st, "could not keep the host's tailnet state: %v", err)
			}
		}
		installer := bootstrap.OSInstaller{Title: st.Label, Version: st.Target}
		if err := host.StartErase(ctx, st.ID, installer, oc.host.Spec.SSHUser, oc.sudoPassword); err != nil {
			return osUpdateWait(st, "could not start the erase: %v", err)
		}
		return osUpdateWait(st, "erasing the host to install macOS %s", st.Target)
	case job.State == bootstrap.OSUpdateJobExited && job.ExitCode != 0:
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "EraseFailed",
			fmt.Sprintf("startosinstall exited %d before restarting: %s", job.ExitCode, job.LogTail), true)
	case job.State == bootstrap.OSUpdateJobExited, job.State == bootstrap.OSUpdateJobLost:
		return osUpdateWait(st, "the installer is restarting the host")
	}
	return osUpdateWait(st, "preparing the erase: %s", job.LogTail)
}

// osUpdateEnrolling waits for the erased host to come back through automated
// enrollment and trusts its new host key only once it reports the RackHost's
// serial and the target version.
func (r *RackAppleSiliconMachineReconciler) osUpdateEnrolling(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	machine := oc.machine
	st := machine.Status.OSUpdate
	if osUpdatePhaseOlderThan(st, osUpdateEnrollTimeout) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "EnrollTimedOut",
			fmt.Sprintf("the reinstalled host did not accept the fleet key within %s; the Node stays cordoned", osUpdateEnrollTimeout), false)
	}

	host, err := r.dialOSUpdateTargets(ctx, oc, "")
	if err != nil {
		return osUpdateWait(st, "waiting for the reinstalled host to enroll: %v", err)
	}
	defer host.Close()

	serial, err := host.Serial(ctx)
	if err != nil {
		return osUpdateWait(st, "could not read the host's serial: %v", err)
	}
	if serial != oc.host.Spec.Serial {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "HostIdentityMismatch",
			fmt.Sprintf("the host answering for %s reports serial %q, not %q, so its host key was not trusted; the Node stays cordoned", oc.host.Name, serial, oc.host.Spec.Serial), false)
	}
	version, err := host.Version(ctx)
	if err != nil {
		return osUpdateWait(st, "could not read the host's macOS version: %v", err)
	}
	if compareMacOSVersions(version, st.Target) != 0 {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "VersionMismatch",
			fmt.Sprintf("the host came back on macOS %s, not %s; the Node stays cordoned", version, st.Target), false)
	}
	if err := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, host.Fingerprint()); err != nil {
		return osUpdateWait(st, "could not pin the host's new key: %v", err)
	}

	conditions.MarkFalse(machine, BootstrappedCondition, "Reinstalled", clusterv1.ConditionSeverityInfo,
		"macOS %s was installed from scratch; bootstrapping again", st.Target)
	machine.Status.BootstrapAttempts = 0
	machine.Status.BootstrapRebootIssued = false
	r.setOSUpdatePhase(machine, OSUpdatePhaseBootstrapping,
		fmt.Sprintf("trusted the new host key of %s (%s); bootstrapping it again", oc.host.Name, serial))
	return ctrl.Result{Requeue: true}, nil
}

// osUpdateBootstrapping watches the reconcile bootstrap the reinstalled host.
// It returns a zero Result while it waits, so the reconcile goes on to do it.
func (r *RackAppleSiliconMachineReconciler) osUpdateBootstrapping(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	machine := oc.machine
	st := machine.Status.OSUpdate
	if osUpdatePhaseOlderThan(st, osUpdateBootstrapTimeout) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "BootstrapTimedOut",
			fmt.Sprintf("the reinstalled host did not bootstrap within %s; the Node stays cordoned", osUpdateBootstrapTimeout), false)
	}
	if !conditions.IsTrue(machine, BootstrappedCondition) {
		st.Message = "bootstrapping the reinstalled host"
		return ctrl.Result{}, nil
	}

	host, err := r.openOSUpdateHost(ctx, oc)
	if err != nil {
		return osUpdateWait(st, "could not reach the host: %v", err)
	}
	defer host.Close()

	user := oc.host.Spec.SSHUser
	tokenEnabled, err := host.SecureTokenEnabled(ctx, user)
	if err != nil {
		return osUpdateWait(st, "could not read %s's secure token status: %v", user, err)
	}
	if tokenEnabled {
		r.setOSUpdatePhase(machine, OSUpdatePhaseConverging, "bootstrapped; waiting for the host config push, a Ready Node and the console session")
		return ctrl.Result{Requeue: true}, nil
	}
	bootTime, err := host.BootTime(ctx)
	if err != nil {
		return osUpdateWait(st, "could not read the host's boot time: %v", err)
	}
	st.BootTimeBefore = bootTime
	r.setOSUpdatePhase(machine, OSUpdatePhaseRestarting,
		fmt.Sprintf("restarting once so %s logs in at the console and gets a secure token", user))
	// The restart is issued only once this status is written.
	return ctrl.Result{Requeue: true}, nil
}

// osUpdateRestarting restarts a freshly installed host once. Its SSH user gets a
// secure token at the first auto-login, which bootstrap has just configured, and
// the next in-place update needs one.
func (r *RackAppleSiliconMachineReconciler) osUpdateRestarting(ctx context.Context, oc *osUpdateContext) (ctrl.Result, error) {
	machine := oc.machine
	st := machine.Status.OSUpdate
	if osUpdatePhaseOlderThan(st, osUpdateRestartTimeout) {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "RestartTimedOut",
			fmt.Sprintf("the host did not come back from its restart within %s; the Node stays cordoned", osUpdateRestartTimeout), false)
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
	if bootTime <= st.BootTimeBefore {
		if err := host.Restart(ctx); err != nil {
			return osUpdateWait(st, "could not restart the host: %v", err)
		}
		return osUpdateWait(st, "restarting the host")
	}

	user := oc.host.Spec.SSHUser
	tokenEnabled, err := host.SecureTokenEnabled(ctx, user)
	if err != nil {
		return osUpdateWait(st, "could not read %s's secure token status: %v", user, err)
	}
	if !tokenEnabled {
		return r.finishOSUpdate(ctx, oc, OSUpdatePhaseFailed, "NoSecureToken",
			fmt.Sprintf("%s still has no secure token after a restart; the Node stays cordoned", user), false)
	}
	r.setOSUpdatePhase(machine, OSUpdatePhaseConverging, "restarted; waiting for the host config push, a Ready Node and the console session")
	return ctrl.Result{Requeue: true}, nil
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
			fmt.Sprintf("the host did not converge within %s; the Node stays cordoned", osUpdateConvergeTimeout), false)
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

	message := fmt.Sprintf("updated from macOS %s to %s", st.FromVersion, st.Target)
	switch {
	case st.Reinstall:
		message = fmt.Sprintf("erased the host and installed macOS %s over %s", st.Target, st.FromVersion)
	case compareMacOSVersions(st.FromVersion, st.Target) == 0:
		message = fmt.Sprintf("already on macOS %s; the host converged, so its Node is back in service", st.Target)
	}
	return r.finishOSUpdate(ctx, oc, OSUpdatePhaseSucceeded, "", message, true)
}

// finishOSUpdate ends the update. With uncordon set it lifts an update's
// cordon; remediation is always handed back. Both touch only what an update
// marked as its own.
func (r *RackAppleSiliconMachineReconciler) finishOSUpdate(ctx context.Context, oc *osUpdateContext, phase, reason, message string, uncordon bool) (ctrl.Result, error) {
	machine := oc.machine
	st := machine.Status.OSUpdate
	if uncordon {
		if err := r.uncordonNodeAfterOSUpdate(ctx, machine.Name); err != nil {
			return ctrl.Result{}, fmt.Errorf("uncordon Node %s: %w", machine.Name, err)
		}
	}
	if err := r.resumeRemediationAfterOSUpdate(ctx, machine); err != nil {
		return ctrl.Result{}, fmt.Errorf("resume health-check remediation: %w", err)
	}
	// A reinstall that failed before erasing leaves the host on the tailnet as
	// it was, so the state kept for it has no use. Otherwise the next bootstrap
	// consumes it.
	if st.Reinstall && uncordon && phase == OSUpdatePhaseFailed {
		if err := r.CredentialsManager.SetMachineTailscaleState(ctx, machine.Name, nil); err != nil {
			return ctrl.Result{}, fmt.Errorf("drop the kept tailnet state: %w", err)
		}
	}

	now := metav1.Now()
	st.Phase, st.Reason, st.Message = phase, reason, message
	st.PhaseStartedAt, st.CompletedAt = &now, &now
	annotation := osUpdateAnnotationFor(st.Reinstall)
	if requested, ok := machine.Annotations[annotation]; ok && strings.TrimSpace(requested) == st.Target {
		delete(machine.Annotations, annotation)
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

// openOSUpdateHost dials the host against its pinned key.
func (r *RackAppleSiliconMachineReconciler) openOSUpdateHost(ctx context.Context, oc *osUpdateContext) (osUpdateHost, error) {
	host, err := r.dialOSUpdateTargets(ctx, oc, oc.knownFingerprint)
	if err != nil {
		return nil, err
	}
	r.persistFingerprint(ctx, oc.machine, host.Fingerprint(), oc.knownFingerprint)
	return host, nil
}

// dialOSUpdateTargets dials the host's address, then its tailnet egress. An
// empty knownFingerprint accepts any host key and persists none.
func (r *RackAppleSiliconMachineReconciler) dialOSUpdateTargets(_ context.Context, oc *osUpdateContext, knownFingerprint string) (osUpdateHost, error) {
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
		host, err := dial(target, oc.host.Spec.SSHUser, oc.sshKey, knownFingerprint)
		if err != nil {
			errs = append(errs, err)
			continue
		}
		return host, nil
	}
	return nil, errors.Join(errs...)
}

// cordonNodeForOSUpdate cordons the Node and marks the cordon as an update's in
// the same patch. A Node that is already cordoned keeps whatever marking it has,
// so a cordon someone else placed is never lifted by the update.
func (r *RackAppleSiliconMachineReconciler) cordonNodeForOSUpdate(ctx context.Context, name, target string) error {
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		return err
	}
	if node.Spec.Unschedulable {
		return nil
	}
	base := node.DeepCopy()
	node.Spec.Unschedulable = true
	metav1.SetMetaDataAnnotation(&node.ObjectMeta, OSUpdateCordonAnnotation, target)
	return r.Patch(ctx, node, client.MergeFrom(base))
}

// uncordonNodeAfterOSUpdate lifts a cordon an update placed, and no other.
func (r *RackAppleSiliconMachineReconciler) uncordonNodeAfterOSUpdate(ctx context.Context, name string) error {
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	if _, marked := node.Annotations[OSUpdateCordonAnnotation]; !marked {
		return nil
	}
	base := node.DeepCopy()
	node.Spec.Unschedulable = false
	delete(node.Annotations, OSUpdateCordonAnnotation)
	return r.Patch(ctx, node, client.MergeFrom(base))
}

// nodeCordonedByOSUpdate reports whether an update's cordon is still on the Node.
func (r *RackAppleSiliconMachineReconciler) nodeCordonedByOSUpdate(ctx context.Context, name string) (bool, error) {
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return false, nil
		}
		return false, err
	}
	_, marked := node.Annotations[OSUpdateCordonAnnotation]
	return marked && node.Spec.Unschedulable, nil
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

// suspendRemediationForOSUpdate sets skip-remediation on the owning CAPI
// Machine, valued so the update can tell it set it. One already set, by anyone,
// is left as it is.
func (r *RackAppleSiliconMachineReconciler) suspendRemediationForOSUpdate(ctx context.Context, machine *infrav1.RackAppleSiliconMachine) error {
	owner, err := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if err != nil || owner == nil {
		return err
	}
	if _, set := owner.Annotations[clusterv1.MachineSkipRemediationAnnotation]; set {
		return nil
	}
	base := owner.DeepCopy()
	metav1.SetMetaDataAnnotation(&owner.ObjectMeta, clusterv1.MachineSkipRemediationAnnotation, osUpdateSkipRemediationValue)
	return r.Patch(ctx, owner, client.MergeFrom(base))
}

// resumeRemediationAfterOSUpdate removes skip-remediation only when an update set it.
func (r *RackAppleSiliconMachineReconciler) resumeRemediationAfterOSUpdate(ctx context.Context, machine *infrav1.RackAppleSiliconMachine) error {
	owner, err := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if err != nil || owner == nil {
		return err
	}
	if value, set := owner.Annotations[clusterv1.MachineSkipRemediationAnnotation]; !set || value != osUpdateSkipRemediationValue {
		return nil
	}
	base := owner.DeepCopy()
	delete(owner.Annotations, clusterv1.MachineSkipRemediationAnnotation)
	return r.Patch(ctx, owner, client.MergeFrom(base))
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
