// Package controllers contains the reconcilers for the Scaleway Apple
// Silicon CAPI provider's CRDs.
package controllers

import (
	"context"
	"fmt"
	"time"

	"github.com/go-logr/logr"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/api/v1alpha1"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-scaleway-applesilicon/internal/scaleway"
)

const (
	// MachineFinalizer prevents the CR from being garbage-collected
	// before we've released the underlying Scaleway server (Apple's
	// 24h floor means leaks cost money — this matters).
	MachineFinalizer = "scalewayapplesilicon.cluster.x-k8s.io/finalizer"

	// Conditions surfaced on the CR for operator visibility.
	ProvisionedCondition  clusterv1.ConditionType = "Provisioned"
	BootstrappedCondition clusterv1.ConditionType = "Bootstrapped"
)

// ScalewayAppleSiliconMachineReconciler reconciles ScalewayAppleSiliconMachine objects.
type ScalewayAppleSiliconMachineReconciler struct {
	client.Client
	Scheme             *runtime.Scheme
	ScalewayClient     *scaleway.Client
	CredentialsManager *credentials.Manager

	// Kubeconfig builds the per-host kubeconfig the bootstrap installs.
	// Required for tart-kubelet to authenticate to the cluster.
	Kubeconfig *kubeconfig.Builder

	// TartKubeletBinary is the darwin/arm64 binary baked into the
	// operator's own image. Read once at operator startup, uploaded to
	// each Mac mini over SSH at provision time and on every drift-
	// detected rolling update.
	TartKubeletBinary []byte

	// TartKubeletBinarySHA is the SHA-256 of TartKubeletBinary. Used
	// as the version stamp on each ScalewayAppleSiliconMachine: when
	// status.tartKubeletBinarySHA != this value, the reconciler
	// re-uploads + reloads launchd.
	TartKubeletBinarySHA string

	// TartKubelet host advertising — passed into bootstrap which bakes
	// them into the launchd plist on each Mac mini.
	TartKubeletHostCPU      int
	TartKubeletHostMemoryMB int
	TartKubeletMaxPods      int

	// TartKubeletMaxUpdateAttempts caps how many times the drift loop
	// retries a failing UpdateTartKubelet before transitioning the CR
	// to a terminal Failed state. Without a cap the operator
	// SSH-hammers a wedged host every 60s indefinitely with no
	// terminal-failure surface for ops. Defaulted to 5 attempts in
	// the manager binary; chart can override per env if needed.
	TartKubeletMaxUpdateAttempts int32
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayapplesiliconmachines/finalizers,verbs=update
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=machines,verbs=get;list;watch
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=clusters,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=secrets,verbs=get;list;watch;create;update
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch

func (r *ScalewayAppleSiliconMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("machine", req.NamespacedName)
	logger.Info("reconcile entry")

	machine := &infrav1.ScalewayAppleSiliconMachine{}
	if err := r.Get(ctx, req.NamespacedName, machine); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	patchHelper, err := patch.NewHelper(machine, r.Client)
	if err != nil {
		return ctrl.Result{}, err
	}
	defer func() {
		if perr := patchHelper.Patch(ctx, machine); perr != nil && err == nil {
			err = perr
		}
	}()

	// Handle deletion.
	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}

	// Make sure we have a finalizer so we always get a chance to
	// release the Scaleway server before the CR disappears.
	if !controllerutil.ContainsFinalizer(machine, MachineFinalizer) {
		controllerutil.AddFinalizer(machine, MachineFinalizer)
	}

	return r.reconcileNormal(ctx, machine)
}

func (r *ScalewayAppleSiliconMachineReconciler) reconcileNormal(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)

	// Stage 0: ensure the per-fleet SSH key is registered with Scaleway
	// BEFORE we order the Mac mini. Scaleway only injects project SSH
	// keys at first-boot — keys registered after CreateServer are not
	// auto-installed on the host, leaving us locked out of SSH and
	// unable to bootstrap kubelet. Doing this first means the Mac mini
	// comes up with our pubkey already in ~/.ssh/authorized_keys.
	fleet := machine.Spec.FleetName
	if fleet == "" {
		fleet = machine.Namespace + "-" + machine.Name
	}
	sshKey, err := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
	if err != nil {
		conditions.MarkFalse(machine, BootstrappedCondition, "SSHKeyUnavailable",
			clusterv1.ConditionSeverityError, "%v", err)
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	// Stage 1: ensure the Scaleway server exists.
	if machine.Status.ServerID == "" {
		machine.Status.Phase = "Provisioning"
		srv, err := r.ScalewayClient.CreateServer(
			ctx,
			machine.Name,
			machine.Spec.Zone,
			machine.Spec.Type,
			machine.Spec.OS,
		)
		if err != nil {
			conditions.MarkFalse(machine, ProvisionedCondition, "ScalewayCreateFailed",
				clusterv1.ConditionSeverityError, "%v", err)
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}

		machine.Status.ServerID = srv.ID
		machine.Status.Addresses = []clusterv1.MachineAddress{{
			Type:    clusterv1.MachineExternalIP,
			Address: srv.IP,
		}}
		providerID := fmt.Sprintf("scw-applesilicon://%s/%s", machine.Spec.Zone, srv.ID)
		machine.Spec.ProviderID = &providerID

		// Persist sudo password + SSH username in a per-machine
		// Secret. They used to live as annotations on the CR, which
		// exposed the sudo password to anyone with read on the CR
		// (kubectl describe, etcd backups, audit, exports). The
		// Secret stays in the operator's namespace alongside the SSH
		// key, gated by the chart's RBAC.
		if err := r.CredentialsManager.SetMachineCredentials(ctx, machine.Name, srv.SudoPassword, srv.SSHUsername); err != nil {
			conditions.MarkFalse(machine, ProvisionedCondition, "CredentialsPersistFailed",
				clusterv1.ConditionSeverityError, "%v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		conditions.MarkTrue(machine, ProvisionedCondition)
		logger.Info("provisioned Scaleway Mac mini", "id", srv.ID, "ip", srv.IP)
	}

	bootstrapCreds, err := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name)
	if err != nil {
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}
	// One-time migration off the legacy CR-annotation layout. Older
	// reconciles wrote sudo-password + ssh-username as annotations on
	// the CR. We now keep them in a per-machine Secret instead. If the
	// Secret doesn't exist but the legacy annotations are still on the
	// CR, copy them across and strip the annotations so the next
	// reconcile reads from the Secret.
	if bootstrapCreds == nil {
		legacyPwd := machine.Annotations["scaleway.tuist.dev/sudo-password"]
		legacyUser := machine.Annotations["scaleway.tuist.dev/ssh-username"]
		if legacyPwd != "" && legacyUser != "" {
			if err := r.CredentialsManager.SetMachineCredentials(ctx, machine.Name, legacyPwd, legacyUser); err != nil {
				logger.Error(err, "migrate legacy bootstrap annotations to secret; will retry")
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			delete(machine.Annotations, "scaleway.tuist.dev/sudo-password")
			delete(machine.Annotations, "scaleway.tuist.dev/ssh-username")
			bootstrapCreds = &credentials.MachineBootstrap{
				SudoPassword: legacyPwd,
				SSHUsername:  legacyUser,
			}
		}
	}
	if bootstrapCreds == nil {
		// Stage 1 didn't write the Secret yet (fresh CR mid-reconcile,
		// or operator pod that crashed between CreateServer + Secret
		// write). Requeue.
		return ctrl.Result{RequeueAfter: 10 * time.Second}, nil
	}

	// Stage 2: bootstrap (idempotent — re-running picks up where it
	// left off).
	if !conditions.IsTrue(machine, BootstrappedCondition) {
		machine.Status.Phase = "Bootstrapping"

		ip := machineIP(machine)
		if ip == "" {
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		identity, err := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name)
		if err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "NodeIdentityUnavailable",
				clusterv1.ConditionSeverityWarning, "%v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		kubeconfigYAML, err := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "KubeconfigUnavailable",
				clusterv1.ConditionSeverityWarning, "%v", err)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		fingerprint, err := bootstrap.Run(ctx, bootstrap.Config{
			IP:                   ip,
			SSHUser:              bootstrapCreds.SSHUsername,
			UserPassword:         bootstrapCreds.SudoPassword,
			SSHPrivateKey:        sshKey,
			NodeName:             machine.Name,
			Kubeconfig:           kubeconfigYAML,
			TartKubeletBinary:    r.TartKubeletBinary,
			HostCPU:              r.TartKubeletHostCPU,
			HostMemoryMB:         r.TartKubeletHostMemoryMB,
			MaxPods:              r.TartKubeletMaxPods,
			KnownHostFingerprint: bootstrapCreds.HostFingerprint,
		})
		// Persist whatever fingerprint Run captured even on the error
		// path, so a transient bootstrap failure doesn't lose the
		// TOFU pin we already verified successfully.
		if fingerprint != "" && fingerprint != bootstrapCreds.HostFingerprint {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, fingerprint); perr != nil {
				logger.Error(perr, "persist host fingerprint; will retry")
			} else {
				bootstrapCreds.HostFingerprint = fingerprint
			}
		}
		if err != nil {
			conditions.MarkFalse(machine, BootstrappedCondition, "BootstrapFailed",
				clusterv1.ConditionSeverityWarning, "%v", err)
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}

		conditions.MarkTrue(machine, BootstrappedCondition)
		// Bootstrap pushes a per-machine kubeconfig as part of Stage 2,
		// so flag the marker so the Stage 3 migration path doesn't fire
		// redundantly on the next reconcile.
		machine.Status.PerMachineKubeconfigInstalled = true
		logger.Info("bootstrap complete", "host", ip)
	}

	// Stage 3: rolling tart-kubelet update.
	//
	// Bootstrap installs the agent once. After that, the operator's
	// own image carries the source-of-truth binary; deploying a new
	// operator image rolls a new kubelet across the fleet. We compare
	// the operator's binary SHA-256 to the last-applied SHA on each
	// Machine and on mismatch re-upload + reload launchd.
	//
	// Running Tart VMs survive an agent restart (`nohup`-detached) and
	// the kubelet's startup state-recovery pass re-binds them, so the
	// rollout is zero-downtime for workloads.
	// Stage 3 fires on either of two conditions:
	//   - tart-kubelet binary drift: operator's baked-in SHA differs
	//     from what last landed on the host. Routine after operator
	//     image bumps.
	//   - PerMachineKubeconfigInstalled is false: the machine still
	//     has the legacy shared-fleet kubeconfig. Forcing a single
	//     kubeconfig push migrates it onto the per-machine token.
	//     The marker stays sticky once we set it.
	binaryDrift := r.TartKubeletBinarySHA != "" && machine.Status.TartKubeletBinarySHA != r.TartKubeletBinarySHA
	// Once a CR enters the terminal-failed state (FailureReason set
	// and FailureMessage describes the underlying error) we stop
	// firing the drift loop. CAPI core takes over: surfaces the
	// failure on the parent Machine and refuses to drive replacement
	// without operator action. Recovery: clear FailureReason +
	// reset TartKubeletUpdateAttempts to resume the loop.
	terminalFailure := machine.Status.FailureReason != nil
	if !terminalFailure && (binaryDrift || !machine.Status.PerMachineKubeconfigInstalled) {
		ip := machineIP(machine)
		if ip == "" {
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		identity, err := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name)
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("ensure node identity: %w", err), r.TartKubeletMaxUpdateAttempts, logger)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		kubeconfigYAML, err := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("render kubeconfig: %w", err), r.TartKubeletMaxUpdateAttempts, logger)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		fingerprint, err := bootstrap.UpdateTartKubelet(ctx, bootstrap.Config{
			IP:                   ip,
			SSHUser:              bootstrapCreds.SSHUsername,
			SSHPrivateKey:        sshKey,
			NodeName:             machine.Name,
			Kubeconfig:           kubeconfigYAML,
			TartKubeletBinary:    r.TartKubeletBinary,
			HostCPU:              r.TartKubeletHostCPU,
			HostMemoryMB:         r.TartKubeletHostMemoryMB,
			MaxPods:              r.TartKubeletMaxPods,
			KnownHostFingerprint: bootstrapCreds.HostFingerprint,
		})
		if fingerprint != "" && fingerprint != bootstrapCreds.HostFingerprint {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, fingerprint); perr != nil {
				logger.Error(perr, "persist host fingerprint on update; will retry")
			}
		}
		if err != nil {
			recordUpdateFailure(machine, fmt.Errorf("tart-kubelet update: %w", err), r.TartKubeletMaxUpdateAttempts, logger)
			if machine.Status.FailureReason != nil {
				return ctrl.Result{}, nil
			}
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}
		machine.Status.TartKubeletBinarySHA = r.TartKubeletBinarySHA
		machine.Status.PerMachineKubeconfigInstalled = true
		machine.Status.TartKubeletUpdateAttempts = 0
		logger.Info("rolled new tart-kubelet", "host", ip, "sha", r.TartKubeletBinarySHA)
	}

	// Mac mini is now running tart-kubelet and registering itself as a
	// real Node. From CAPI's perspective the Machine is Ready as soon
	// as bootstrap returns; whether the Node has reported Ready yet is
	// a separate concern observable via `kubectl get nodes`.
	machine.Status.Ready = true
	machine.Status.Phase = "Ready"
	return ctrl.Result{RequeueAfter: 5 * time.Minute}, nil
}


func (r *ScalewayAppleSiliconMachineReconciler) reconcileDelete(
	ctx context.Context,
	machine *infrav1.ScalewayAppleSiliconMachine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	machine.Status.Phase = "Deleting"

	if machine.Status.ServerID != "" {
		if err := r.ScalewayClient.DeleteServer(ctx, machine.Status.ServerID, machine.Spec.Zone); err != nil {
			logger.Error(err, "Scaleway delete failed; will retry")
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}
		machine.Status.ServerID = ""
	}

	controllerutil.RemoveFinalizer(machine, MachineFinalizer)
	return ctrl.Result{}, nil
}

// === helpers ================================================================

// recordUpdateFailure increments the drift-loop retry counter and,
// once it crosses maxAttempts, flips the CR into a terminal Failed
// state. The counter is reset on successful UpdateTartKubelet. We
// don't try to be clever about which step in the loop failed; from
// the CR's perspective, any failure that prevents the kubeconfig
// landing on the host counts the same. Recovery is operator-driven:
// `kubectl patch` to clear status.failureReason + zero
// status.tartKubeletUpdateAttempts and the loop resumes.
func recordUpdateFailure(machine *infrav1.ScalewayAppleSiliconMachine, err error, maxAttempts int32, logger logr.Logger) {
	machine.Status.TartKubeletUpdateAttempts++
	logger.Error(err, "tart-kubelet update step failed",
		"attempt", machine.Status.TartKubeletUpdateAttempts,
		"max", maxAttempts)
	if maxAttempts > 0 && machine.Status.TartKubeletUpdateAttempts >= maxAttempts {
		reason := "TartKubeletUpdateExceededRetries"
		msg := fmt.Sprintf("tart-kubelet update failed %d times: %v",
			machine.Status.TartKubeletUpdateAttempts, err)
		machine.Status.FailureReason = &reason
		machine.Status.FailureMessage = &msg
		machine.Status.Phase = "Failed"
		logger.Error(err, "tart-kubelet update permanently failed; CR transitioned to Failed",
			"attempts", machine.Status.TartKubeletUpdateAttempts)
	}
}

func machineIP(m *infrav1.ScalewayAppleSiliconMachine) string {
	for _, a := range m.Status.Addresses {
		if a.Type == clusterv1.MachineExternalIP {
			return a.Address
		}
	}
	return ""
}

func (r *ScalewayAppleSiliconMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.ScalewayAppleSiliconMachine{}).
		Complete(r)
}

