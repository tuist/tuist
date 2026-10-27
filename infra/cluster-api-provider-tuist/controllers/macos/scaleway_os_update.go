package macos

import (
	"context"
	"crypto/sha256"
	"fmt"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	coordinationv1 "k8s.io/api/coordination/v1"
	corev1 "k8s.io/api/core/v1"
	policyv1 "k8s.io/api/policy/v1"
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
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const osUpdatePhaseAccepting = "Accepting"

// Rented hosts have no RackHost/MDM erase lifecycle. Their in-place updates
// use the same SSH jobs and status vocabulary, but never erase or replace a
// Scaleway server. The fleet Lease deliberately has no expiry: losing the
// operator or timing out must not authorize taking a second host offline.
// Eviction RBAC is namespace-scoped in the chart, not a ClusterRole marker.
func (r *ScalewayAppleSiliconMachineReconciler) reconcileScalewayOSUpdate(ctx context.Context, m *infrav1.ScalewayAppleSiliconMachine, key []byte, creds *credentials.MachineBootstrap) (bool, ctrl.Result, error) {
	st := m.Status.OSUpdate
	target, requested := m.Annotations[OSUpdateAnnotation]
	if (st == nil || st.Phase == OSUpdatePhaseSucceeded) && !requested {
		return false, ctrl.Result{}, nil
	}
	wait := func(format string, args ...any) (bool, ctrl.Result, error) {
		result, err := osUpdateWait(m.Status.OSUpdate, format, args...)
		return true, result, err
	}
	fail := func(reason, message string) (bool, ctrl.Result, error) {
		setScalewayOSUpdatePhase(m, OSUpdatePhaseFailed, message)
		m.Status.OSUpdate.Reason = reason
		now := metav1.Now()
		m.Status.OSUpdate.CompletedAt = &now
		delete(m.Annotations, OSUpdateAnnotation)
		r.Recorder.Event(m, corev1.EventTypeWarning, "OSUpdateFailed", reason+": "+message)
		// Retain the fleet lock, cordon and remediation protection. An
		// recovery requires inspecting host jobs first; another host must not pass it.
		return true, ctrl.Result{}, nil
	}
	if st != nil && st.Phase == OSUpdatePhaseFailed {
		return true, ctrl.Result{}, fmt.Errorf("OS maintenance failed (%s): investigate host jobs before clearing its status or fleet lock", st.Reason)
	}
	if st == nil || st.Phase == OSUpdatePhaseSucceeded {
		now := metav1.Now()
		m.Status.OSUpdate = &infrav1.OSUpdateStatus{ID: string(uuid.NewUUID()), Target: strings.TrimSpace(target), Phase: OSUpdatePhasePreparing, StartedAt: &now, PhaseStartedAt: &now}
		st = m.Status.OSUpdate
		if !macOSVersionPattern.MatchString(st.Target) {
			return fail("InvalidTarget", "expected an explicit macOS point release")
		}
		if !conditions.IsTrue(m, BootstrappedCondition) || m.Status.FailureReason != nil || m.Status.HostConfigHash != r.desiredHostConfigHash(m) {
			return fail("HostNotReady", "bootstrap and host configuration must be healthy before maintenance")
		}
		return wait("waiting for the fleet maintenance lock")
	}
	locked, err := r.scalewayOSUpdateLock(ctx, m, false)
	if err != nil {
		return true, ctrl.Result{}, err
	}
	if !locked {
		return wait("another host holds the fleet maintenance lock")
	}
	if !requested && osUpdateCancellable(st.Phase) {
		// Keep a cancelled operation visible and isolated; retry explicitly
		// rather than silently re-enabling work while a download may run.
		return fail("Cancelled", "request removed; host and fleet remain held for an explicit retry")
	}
	if osUpdatePhaseOlderThan(st, 2*time.Hour) {
		return fail("TimedOut", "maintenance phase exceeded two hours; host and fleet remain held")
	}

	nodes := &RackAppleSiliconMachineReconciler{Client: r.Client}
	if st.Phase == OSUpdatePhaseConverging && m.Status.HostConfigHash != r.desiredHostConfigHash(m) {
		if m.Status.FailureReason != nil {
			return fail("ConvergeFailed", "host configuration could not be restored")
		}
		return false, ctrl.Result{}, nil // ordinary drift push restores everything the installer reset
	}
	if st.Phase == osUpdatePhaseAccepting {
		ready, err := r.scalewayProcessorReady(ctx, m.Name)
		if err != nil {
			return true, ctrl.Result{}, err
		}
		if !ready {
			return wait("waiting for the replacement processor to pass dependency and queue readiness")
		}
		if err := r.scalewayOSRemediation(ctx, m, false); err != nil {
			return true, ctrl.Result{}, err
		}
		if _, err := r.pauseScalewayProcessor(ctx, m, false); err != nil {
			return true, ctrl.Result{}, err
		}
		if _, err := r.scalewayOSUpdateLock(ctx, m, true); err != nil {
			return true, ctrl.Result{}, err
		}
		setScalewayOSUpdatePhase(m, OSUpdatePhaseSucceeded, "host updated and replacement processor Ready")
		now := metav1.Now()
		st.CompletedAt = &now
		delete(m.Annotations, OSUpdateAnnotation)
		r.Recorder.Event(m, corev1.EventTypeNormal, "OSUpdateSucceeded", st.Message)
		return true, ctrl.Result{}, nil
	}
	if st.Phase == OSUpdatePhaseDraining {
		empty, err := r.drainScalewayProcessor(ctx, m.Namespace, m.Name)
		if err != nil {
			return wait("draining: %v", err)
		}
		if !empty {
			return wait("waiting for processor eviction and VM drain acknowledgement")
		}
		setScalewayOSUpdatePhase(m, OSUpdatePhaseDownloading, "host drained; downloading approved macOS target")
		return true, ctrl.Result{Requeue: true}, nil
	}

	if creds.HostFingerprint == "" {
		return fail("UnpinnedHost", "maintenance requires the host key recorded by bootstrap")
	}
	dial := r.osUpdateDial
	if dial == nil {
		dial = dialOSUpdateHost
	}
	host, err := dial(machineIP(m), creds.SSHUsername, key, creds.HostFingerprint)
	if err != nil && r.egressHost(m.Name) != "" {
		host, err = dial(r.egressHost(m.Name), creds.SSHUsername, key, creds.HostFingerprint)
	}
	if err != nil {
		return wait("waiting for host SSH: %v", err)
	}
	defer host.Close()

	switch st.Phase {
	case OSUpdatePhasePreparing:
		version, err := host.Version(ctx)
		if err != nil {
			return wait("reading macOS version: %v", err)
		}
		st.FromVersion = version
		if macOSMajor(version) != macOSMajor(st.Target) || compareMacOSVersions(st.Target, version) < 0 {
			return fail("UnsupportedTarget", "only same-family upgrades are supported; no erase or downgrade")
		}
		console, err := host.ConsoleUser(ctx)
		if err != nil || console != creds.SSHUsername {
			return wait("waiting for volume owner console session")
		}
		token, err := host.SecureTokenEnabled(ctx, creds.SSHUsername)
		if err != nil || !token {
			return fail("NoSecureToken", "volume owner must have a secure token")
		}
		if compareMacOSVersions(version, st.Target) == 0 {
			// Also handles a retry after a successful reboot whose previous
			// operation failed during convergence. Never install twice.
			m.Status.HostConfigHash = ""
			setScalewayOSUpdatePhase(m, OSUpdatePhaseConverging, "already on target; validating host configuration")
			return true, ctrl.Result{Requeue: true}, nil
		}
		label, offered, err := resolveOSUpdateLabel(ctx, host, st.Target, false)
		if err != nil {
			return wait("listing offered updates: %v", err)
		}
		if label == "" {
			return fail("NotOffered", fmt.Sprintf("target not offered: %v", offered))
		}
		if err := r.checkScalewayMaintenanceCapacity(ctx, m); err != nil {
			return wait("waiting for maintenance capacity: %v", err)
		}
		if paused, err := r.pauseScalewayProcessor(ctx, m, true); err != nil || !paused {
			return wait("waiting for a settled, paused processor deployment: %v", err)
		}
		if err := nodes.cordonNodeForOSUpdate(ctx, m.Name, st.Target); err != nil {
			return true, ctrl.Result{}, err
		}
		if err := r.scalewayOSRemediation(ctx, m, true); err != nil {
			return true, ctrl.Result{}, err
		}
		st.Label = label
		setScalewayOSUpdatePhase(m, OSUpdatePhaseDraining, "cordoned; draining processor through the eviction API")
	case OSUpdatePhaseDownloading:
		job, err := host.Job(ctx, st.ID, bootstrap.OSUpdateJobDownload)
		if err != nil {
			return wait("reading download: %v", err)
		}
		switch job.State {
		case bootstrap.OSUpdateJobAbsent:
			if err := host.StartDownload(ctx, st.ID, st.Label); err != nil {
				return wait("starting download: %v", err)
			}
		case bootstrap.OSUpdateJobRunning:
			return wait("downloading: %s", job.LogTail)
		case bootstrap.OSUpdateJobLost:
			return fail("DownloadLost", "download disappeared; host remains isolated")
		case bootstrap.OSUpdateJobExited:
			if job.ExitCode != 0 {
				return fail("DownloadFailed", job.LogTail)
			}
			// Recheck after the long download: a directly bound Pod could
			// have bypassed the scheduler's cordon.
			empty, err := r.drainScalewayProcessor(ctx, m.Namespace, m.Name)
			if err != nil || !empty {
				return wait("waiting for a fully drained host before installation")
			}
			boot, err := host.BootTime(ctx)
			if err != nil {
				return wait("reading boot time: %v", err)
			}
			st.BootTimeBefore = boot
			m.Status.HostConfigHash = ""
			setScalewayOSUpdatePhase(m, OSUpdatePhaseInstalling, "installing approved target; waiting for reboot")
		}
	case OSUpdatePhaseInstalling:
		boot, err := host.BootTime(ctx)
		if err != nil {
			return wait("waiting for reboot: %v", err)
		}
		if boot > st.BootTimeBefore {
			version, err := host.Version(ctx)
			if err != nil {
				return wait("reading post-reboot version: %v", err)
			}
			if compareMacOSVersions(version, st.Target) != 0 {
				return fail("VersionMismatch", "host rebooted without reaching the approved target")
			}
			setScalewayOSUpdatePhase(m, OSUpdatePhaseConverging, "rebooted on target; restoring host configuration")
			return true, ctrl.Result{Requeue: true}, nil
		}
		job, err := host.Job(ctx, st.ID, bootstrap.OSUpdateJobInstall)
		if err != nil {
			return wait("reading installer: %v", err)
		}
		if job.State == bootstrap.OSUpdateJobAbsent {
			node := &corev1.Node{}
			if err := r.Get(ctx, types.NamespacedName{Name: m.Name}, node); err != nil {
				return wait("checking install isolation: %v", err)
			}
			if !node.Spec.Unschedulable {
				return fail("IsolationLost", "Node was uncordoned before installation; refusing to restart it")
			}
			if empty, err := r.drainScalewayProcessor(ctx, m.Namespace, m.Name); err != nil || !empty {
				return wait("waiting for a fully drained host before starting the installer")
			}
			if err := host.StartInstall(ctx, st.ID, st.Label, creds.SSHUsername, creds.SudoPassword); err != nil {
				return wait("starting installer: %v", err)
			}
		} else if job.State == bootstrap.OSUpdateJobExited && job.ExitCode != 0 {
			return fail("InstallFailed", job.LogTail)
		}
	case OSUpdatePhaseConverging:
		ready, err := nodes.nodeReady(ctx, m.Name)
		if err != nil || !ready {
			return wait("waiting for Node readiness")
		}
		version, err := host.Version(ctx)
		if err != nil || compareMacOSVersions(version, st.Target) != 0 {
			return wait("waiting for target OS verification")
		}
		console, err := host.ConsoleUser(ctx)
		if err != nil || console != creds.SSHUsername {
			return wait("waiting for the volume owner console")
		}
		if err := nodes.uncordonNodeAfterOSUpdate(ctx, m.Name); err != nil {
			return true, ctrl.Result{}, err
		}
		setScalewayOSUpdatePhase(m, osUpdatePhaseAccepting, "host converged; waiting for replacement processor readiness")
	default:
		return fail("UnknownPhase", st.Phase)
	}
	return true, ctrl.Result{RequeueAfter: osUpdatePollInterval}, nil
}

func setScalewayOSUpdatePhase(m *infrav1.ScalewayAppleSiliconMachine, phase, message string) {
	now := metav1.Now()
	m.Status.OSUpdate.Phase, m.Status.OSUpdate.Message, m.Status.OSUpdate.PhaseStartedAt = phase, message, &now
}

func maintenanceLeaseName(fleet string) string {
	return fmt.Sprintf("macos-maintenance-%x", sha256.Sum256([]byte(fleet)))[:50]
}

func (r *ScalewayAppleSiliconMachineReconciler) scalewayOSUpdateLock(ctx context.Context, m *infrav1.ScalewayAppleSiliconMachine, release bool) (bool, error) {
	name := maintenanceLeaseName(m.Spec.FleetName)
	lease := &coordinationv1.Lease{}
	err := r.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: name}, lease)
	holder := string(m.UID)
	if apierrors.IsNotFound(err) {
		if release {
			return true, nil
		}
		lease = &coordinationv1.Lease{ObjectMeta: metav1.ObjectMeta{Namespace: m.Namespace, Name: name}, Spec: coordinationv1.LeaseSpec{HolderIdentity: &holder}}
		if err := r.Create(ctx, lease); apierrors.IsAlreadyExists(err) {
			return false, nil
		} else {
			if err == nil && m.Status.OSUpdate != nil {
				now := metav1.Now()
				m.Status.OSUpdate.PhaseStartedAt = &now
			}
			return err == nil, err
		}
	}
	if err != nil {
		return false, err
	}
	if lease.Spec.HolderIdentity == nil || *lease.Spec.HolderIdentity != holder {
		return false, nil
	}
	if release {
		// Resource-version and UID preconditions prevent deleting a lock
		// that changed hands between this read and the delete.
		return true, r.Delete(ctx, lease, client.Preconditions{UID: &lease.UID, ResourceVersion: &lease.ResourceVersion})
	}
	return true, nil
}

func (r *ScalewayAppleSiliconMachineReconciler) scalewayOSRemediation(ctx context.Context, m *infrav1.ScalewayAppleSiliconMachine, hold bool) error {
	owner, err := util.GetOwnerMachine(ctx, r.Client, m.ObjectMeta)
	if err != nil || owner == nil {
		return err
	}
	value, present := owner.Annotations[clusterv1.MachineSkipRemediationAnnotation]
	if (hold && present) || (!hold && value != osUpdateSkipRemediationValue) {
		return nil
	}
	before := owner.DeepCopy()
	if hold {
		metav1.SetMetaDataAnnotation(&owner.ObjectMeta, clusterv1.MachineSkipRemediationAnnotation, osUpdateSkipRemediationValue)
	} else {
		delete(owner.Annotations, clusterv1.MachineSkipRemediationAnnotation)
	}
	return r.Patch(ctx, owner, client.MergeFrom(before))
}

func (r *ScalewayAppleSiliconMachineReconciler) checkScalewayMaintenanceCapacity(ctx context.Context, m *infrav1.ScalewayAppleSiliconMachine) error {
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods); err != nil {
		return err
	}
	own, peer := false, false
	for i := range pods.Items {
		p := &pods.Items[i]
		if p.Labels["app.kubernetes.io/component"] != "xcresult-processor" || p.Namespace != m.Namespace {
			continue
		}
		if p.Spec.NodeName == m.Name {
			own = true
			if p.Annotations["tuist.dev/graceful-drain"] != "xcresult-v1" {
				return fmt.Errorf("processor has not adopted the graceful drain protocol")
			}
		} else if p.Spec.NodeSelector["tuist.dev/fleet"] == m.Spec.FleetName && podReadyForOSUpdate(p) {
			peer = true
		}
	}
	if !own {
		return fmt.Errorf("automated Scaleway maintenance currently requires an xcresult processor")
	}
	if !peer {
		return fmt.Errorf("a Ready processor on another host is required")
	}
	return nil
}

func podReadyForOSUpdate(p *corev1.Pod) bool {
	if !p.DeletionTimestamp.IsZero() || p.Status.Phase != corev1.PodRunning {
		return false
	}
	for _, c := range p.Status.Conditions {
		if c.Type == corev1.PodReady {
			return c.Status == corev1.ConditionTrue
		}
	}
	return false
}

func (r *ScalewayAppleSiliconMachineReconciler) scalewayProcessorReady(ctx context.Context, node string) (bool, error) {
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods); err != nil {
		return false, err
	}
	for i := range pods.Items {
		p := &pods.Items[i]
		if p.Spec.NodeName == node && p.Labels["app.kubernetes.io/component"] == "xcresult-processor" && podReadyForOSUpdate(p) {
			return true, nil
		}
	}
	return false, nil
}

func (r *ScalewayAppleSiliconMachineReconciler) drainScalewayProcessor(ctx context.Context, namespace, node string) (bool, error) {
	pods := &corev1.PodList{}
	if err := r.List(ctx, pods); err != nil {
		return false, err
	}
	empty := true
	for i := range pods.Items {
		p := &pods.Items[i]
		if p.Spec.NodeName != node {
			continue
		}
		if _, mirror := p.Annotations[corev1.MirrorPodAnnotationKey]; mirror {
			continue
		}
		if owner := metav1.GetControllerOf(p); owner != nil && owner.Kind == "DaemonSet" {
			continue
		}
		// Even a terminal Pod still holding the VM finalizer must disappear
		// before reboot. A terminating Pod is not an empty host.
		empty = false
		if p.Namespace != namespace || p.Labels["app.kubernetes.io/component"] != "xcresult-processor" {
			return false, fmt.Errorf("unmanaged Pod %s/%s blocks maintenance", p.Namespace, p.Name)
		}
		if !p.DeletionTimestamp.IsZero() {
			continue
		}
		if p.Annotations["tuist.dev/graceful-drain"] != "xcresult-v1" {
			return false, fmt.Errorf("Pod %s/%s has no safe drain protocol", p.Namespace, p.Name)
		}
		uid := p.UID
		grace := int64(600)
		eviction := &policyv1.Eviction{ObjectMeta: metav1.ObjectMeta{Namespace: p.Namespace, Name: p.Name}, DeleteOptions: &metav1.DeleteOptions{GracePeriodSeconds: &grace, Preconditions: &metav1.Preconditions{UID: &uid}}}
		if err := r.SubResource("eviction").Create(ctx, p, eviction); err != nil && !apierrors.IsNotFound(err) {
			return false, err
		}
	}
	return empty, nil
}

// Pause only the configured processor Deployment, using the same narrowly
// scoped get/patch permission as fleet-spread. Helm can publish a new template
// while maintenance runs, but Kubernetes cannot roll away the serving peer.
func (r *ScalewayAppleSiliconMachineReconciler) pauseScalewayProcessor(ctx context.Context, m *infrav1.ScalewayAppleSiliconMachine, pause bool) (bool, error) {
	const marker = "tuist.dev/os-update-pause"
	if r.ProcessorDeploymentName == "" {
		return false, fmt.Errorf("processor Deployment is not configured")
	}
	reader := r.APIReader
	if reader == nil {
		reader = r.Client
	}
	dep := &appsv1.Deployment{}
	if err := reader.Get(ctx, types.NamespacedName{Namespace: m.Namespace, Name: r.ProcessorDeploymentName}, dep); err != nil {
		return false, err
	}
	if dep.Spec.Template.Spec.NodeSelector["tuist.dev/fleet"] != m.Spec.FleetName {
		return false, fmt.Errorf("Deployment does not select this fleet")
	}
	owned := dep.Annotations[marker] == string(m.UID)
	if pause && dep.Spec.Paused {
		return owned && deploymentRolloutSettled(*dep), nil
	}
	if !pause && !owned {
		return true, nil
	}
	if pause && !deploymentRolloutSettled(*dep) {
		return false, nil
	}
	before := dep.DeepCopy()
	dep.Spec.Paused = pause
	if pause {
		metav1.SetMetaDataAnnotation(&dep.ObjectMeta, marker, string(m.UID))
	} else {
		delete(dep.Annotations, marker)
	}
	err := r.Patch(ctx, dep, client.MergeFromWithOptions(before, client.MergeFromWithOptimisticLock{}))
	return !pause, err // a pause must be observed by the Deployment controller first
}
