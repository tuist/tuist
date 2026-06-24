package linux

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util"
	"sigs.k8s.io/cluster-api/util/annotations"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"

	"golang.org/x/crypto/ssh"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	// OVHDedicatedMachineFinalizer guards the CR until the node identity is
	// cleaned up. It does NOT guard a paid resource the way the Elastic Metal
	// finalizer does: an OVH dedicated server is a monthly contract, so CR
	// deletion intentionally leaves the physical box intact (release is "drop
	// the Node + identity"); terminating the contract is an operator action.
	OVHDedicatedMachineFinalizer = "ovhdedicated.cluster.x-k8s.io/finalizer"

	// ovhBootstrapUser is the login the OVH Ubuntu install lands on (with
	// sudo). Like Elastic Metal, the self-join is delivered over SSH and
	// escalates with sudo because the login user isn't root.
	ovhBootstrapUser = "ubuntu"

	// ovhInstanceType is the node.cluster.x-k8s.io/instance-type label value
	// the self-join stamps, so an OVH node is distinguishable from a Scaleway
	// one.
	ovhInstanceType = "ovh"

	// ovhSSHTimeout caps the per-attempt SSH dial + bootstrap run.
	ovhSSHTimeout = 5 * time.Minute
)

// OVHDedicatedMachineReconciler reconciles an OVHDedicatedMachine: it adopts a
// pre-ordered OVH dedicated server by reverse-DNS prefix, drives the OVH install
// API to lay down the OS and authorize the fleet SSH key, then SSH-delivers the
// same self-join cloud-init the Scaleway Linux kinds use so the host registers
// as an ordinary Linux Node and links by providerID. The operator only
// pre-orders the box and points its reverse DNS at the adopt prefix; the OS
// install is scripted, never manual. There is no Scaleway Private Network: a
// customer-facing box serves public cache traffic over its public IP, so the
// self-join runs with VLAN 0.
type OVHDedicatedMachineReconciler struct {
	client.Client
	// APIReader is the uncached reader for the cross-namespace kube-dns read
	// (clusterDNS discovery), same as the Scaleway Linux reconcilers.
	APIReader client.Reader
	Scheme    *runtime.Scheme
	OVHClient *ovh.Client
	Recorder  record.EventRecorder

	CredentialsManager *credentials.Manager
	Kubeconfig         *kubeconfig.Builder

	// KubernetesMinor is the pkgs.k8s.io channel the self-join installs kubelet
	// from (e.g. "v1.34"); keep in step with the control plane.
	KubernetesMinor string

	// DefaultDatacenter / DefaultOS fill a spec that left them empty.
	DefaultDatacenter string
	DefaultOS         string
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=ovhdedicatedmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=ovhdedicatedmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=ovhdedicatedmachines/finalizers,verbs=update

func (r *OVHDedicatedMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	machine := &infrav1.OVHDedicatedMachine{}
	if getErr := r.Get(ctx, req.NamespacedName, machine); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, getErr
	}

	patchHelper, helperErr := patch.NewHelper(machine, r.Client)
	if helperErr != nil {
		return ctrl.Result{}, helperErr
	}
	defer func() {
		if patchErr := patchHelper.Patch(ctx, machine); patchErr != nil && err == nil {
			err = patchErr
		}
	}()

	ownerMachine, ownerErr := util.GetOwnerMachine(ctx, r.Client, machine.ObjectMeta)
	if ownerErr != nil {
		return ctrl.Result{}, fmt.Errorf("get owner Machine: %w", ownerErr)
	}

	if !machine.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, machine)
	}

	if !controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer) {
		controllerutil.AddFinalizer(machine, OVHDedicatedMachineFinalizer)
	}

	var cluster *clusterv1.Cluster
	if ownerMachine != nil && ownerMachine.Spec.ClusterName != "" {
		cluster = &clusterv1.Cluster{}
		if err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: ownerMachine.Spec.ClusterName}, cluster); err != nil {
			if apierrors.IsNotFound(err) {
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			return ctrl.Result{}, err
		}
	}

	if cluster != nil && cluster.Spec.Paused {
		return ctrl.Result{}, nil
	}
	if annotations.HasPaused(machine) {
		return ctrl.Result{}, nil
	}
	if cluster != nil && !cluster.Status.InfrastructureReady {
		return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
	}

	return r.reconcileNormal(ctx, machine)
}

func (r *OVHDedicatedMachineReconciler) reconcileNormal(ctx context.Context, machine *infrav1.OVHDedicatedMachine) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	datacenter := firstNonEmpty(machine.Spec.Datacenter, r.DefaultDatacenter)

	// Provision: adopt a pre-ordered server, install the OS, then SSH-bootstrap.
	// ServiceName is recorded as soon as the server is claimed so a controller
	// restart re-finds it rather than double-claiming; providerID is set only
	// once the bootstrap completes so a transient failure retries.
	if machine.Spec.ProviderID == nil || *machine.Spec.ProviderID == "" {
		fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
		privateKey, keyErr := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
		if keyErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "SSHKeyUnavailable",
				clusterv1.ConditionSeverityError, "%v", keyErr)
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		// Adopt: claim a free pre-ordered box not already held by a sibling CR.
		if machine.Status.ServiceName == "" {
			claimed, claimErr := r.claimedServiceNames(ctx, machine)
			if claimErr != nil {
				return ctrl.Result{}, claimErr
			}
			server, adoptErr := r.OVHClient.FindAdoptableServer(ctx, ovh.AdoptParams{
				Datacenter:        datacenter,
				Offer:             machine.Spec.Offer,
				DisplayNamePrefix: machine.Spec.AdoptDisplayNamePrefix,
			}, claimed)
			if adoptErr != nil {
				return ctrl.Result{}, adoptErr
			}
			if server == nil {
				conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptableServer",
					clusterv1.ConditionSeverityInfo,
					"no free pre-ordered OVH server in %s under %q; awaiting capacity", datacenter, machine.Spec.AdoptDisplayNamePrefix)
				machine.Status.Phase = "Adopting"
				logger.Info("no adoptable OVH server yet", "datacenter", datacenter, "prefix", machine.Spec.AdoptDisplayNamePrefix)
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			}
			machine.Status.ServiceName = server.Name
			machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: server.IP}}
			machine.Status.Phase = "Adopting"
			r.event(machine, "Adopted", "Adopted OVH server %s in %s", server.Name, datacenter)
			logger.Info("adopted OVH server", "service", server.Name, "datacenter", datacenter)
		}

		// Scripted install: the operator only pre-orders the box and points its
		// reverse DNS at the adopt prefix. The controller drives the OVH install
		// API itself (register the fleet SSH key, resolve the OS template, start
		// the reinstall, poll to completion) before self-joining, so an OS
		// install is never manual operator work.
		server, getErr := r.OVHClient.GetServer(ctx, machine.Status.ServiceName)
		if getErr != nil {
			return ctrl.Result{}, getErr
		}
		// Drive our own install once per adoption rather than trusting the
		// delivered OS: a pre-ordered box can arrive already carrying an OS (a
		// prior install task reads as done) that has neither the install login nor
		// the fleet SSH key, so the self-join would target a box we can never
		// authenticate to and wedge in Bootstrapping forever. Reinstalling
		// unconditionally here authorizes the fleet key + lays the OS down
		// ourselves; Status.InstallStarted makes it a one-shot so the next
		// reconcile polls the install instead of reinstalling the box again.
		if !machine.Status.InstallStarted {
			signer, signErr := ssh.ParsePrivateKey(privateKey)
			if signErr != nil {
				return ctrl.Result{}, fmt.Errorf("parse fleet ssh key: %w", signErr)
			}
			if err := r.OVHClient.EnsureSSHKey(ctx, fleet, string(ssh.MarshalAuthorizedKey(signer.PublicKey()))); err != nil {
				conditions.MarkFalse(machine, shared.ProvisionedCondition, "SSHKeyRegistrationFailed",
					clusterv1.ConditionSeverityWarning, "%v", err)
				machine.Status.Phase = "Provisioning"
				return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
			}
			template, tmplErr := r.OVHClient.ResolveTemplate(ctx, machine.Status.ServiceName, firstNonEmpty(machine.Spec.OS, "ubuntu_24.04"))
			if tmplErr != nil {
				return ctrl.Result{}, tmplErr
			}
			if err := r.OVHClient.StartInstall(ctx, machine.Status.ServiceName, ovh.InstallParams{
				TemplateName: template,
				Hostname:     machine.Name,
				SSHKeyName:   fleet,
			}); err != nil {
				return ctrl.Result{}, fmt.Errorf("start OVH install: %w", err)
			}
			machine.Status.InstallStarted = true
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "Installing",
				clusterv1.ConditionSeverityInfo, "OVH OS install (%s) started for %s", template, machine.Status.ServiceName)
			machine.Status.Phase = "Installing"
			r.event(machine, "Installing", "Started OVH OS install (%s) on %s", template, machine.Status.ServiceName)
			return ctrl.Result{RequeueAfter: 90 * time.Second}, nil
		}

		switch state, stateErr := r.OVHClient.InstallState(ctx, machine.Status.ServiceName); {
		case stateErr != nil:
			return ctrl.Result{}, stateErr
		case state == ovh.InstallFailed:
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "InstallFailed",
				clusterv1.ConditionSeverityWarning, "OVH OS install failed for %s", machine.Status.ServiceName)
			machine.Status.Phase = "InstallFailed"
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		case state == ovh.InstallRunning, state == ovh.InstallPending:
			// Pending here means our StartInstall hasn't surfaced an install task
			// yet, not "never installed" — keep waiting.
			machine.Status.Phase = "Installing"
			logger.Info("OVH OS install in progress", "service", machine.Status.ServiceName)
			return ctrl.Result{RequeueAfter: 90 * time.Second}, nil
		}
		// InstallDone: the OS is up; fall through to the SSH self-join.
		if server.IP == "" {
			machine.Status.Phase = "Provisioning"
			logger.Info("public IP not assigned yet", "service", machine.Status.ServiceName)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.Addresses = []clusterv1.MachineAddress{{Type: clusterv1.MachineExternalIP, Address: server.IP}}

		identity, idErr := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name, linuxNodeIdentityClusterRole)
		if idErr != nil {
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 20 * time.Second}, fmt.Errorf("mint node identity: %w", idErr)
		}
		kubeconfigYAML, kcErr := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if kcErr != nil {
			return ctrl.Result{}, fmt.Errorf("render kubelet kubeconfig: %w", kcErr)
		}
		script := renderLinuxBootstrapScript(linuxCloudInitOptions{
			NodeName:       machine.Name,
			KubeconfigYAML: kubeconfigYAML,
			K8sMinor:       firstNonEmpty(r.KubernetesMinor, "v1.34"),
			Taints:         machine.Spec.NodeTaints,
			BootstrapUser:  ovhBootstrapUser,
			ClusterDNS:     discoverClusterDNS(ctx, r.APIReader),
			InstanceType:   ovhInstanceType,
		})

		machine.Status.Phase = "Bootstrapping"
		// TOFU host-key pinning: persist the fingerprint observed on the first
		// dial and verify it on every retry, so the bootstrap that ships the
		// kubelet identity can't be MITM'd after the first contact.
		known := ""
		if creds, fpErr := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name); fpErr != nil {
			return ctrl.Result{}, fmt.Errorf("read host fingerprint: %w", fpErr)
		} else if creds != nil {
			known = creds.HostFingerprint
		}
		hk := bootstrap.NewHostKeyState(known)
		bootErr := bootstrapOverSSH(ctx, ovhBootstrapUser, server.IP, privateKey, script, hk)
		if observed := hk.Observed(); observed != "" && observed != known {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, observed); perr != nil {
				logger.Error(perr, "persist host fingerprint; will retry")
			}
		}
		if bootErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "BootstrapFailed",
				clusterv1.ConditionSeverityWarning, "%v", bootErr)
			machine.Status.BootstrapAttempts++
			logger.Info("bootstrap over SSH failed, will retry", "host", server.IP, "err", bootErr.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.BootstrapAttempts = 0

		providerID := ovh.ProviderID(firstNonEmpty(server.Datacenter, datacenter), machine.Status.ServiceName)
		machine.Spec.ProviderID = &providerID
		conditions.MarkTrue(machine, shared.ProvisionedCondition)
		r.event(machine, "Bootstrapped", "Bootstrapped OVH server %s as %s@%s", machine.Status.ServiceName, ovhBootstrapUser, server.IP)
		return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
	}

	// Provisioned: link + finish once the self-joined Node appears.
	node := &corev1.Node{}
	if err := r.Get(ctx, types.NamespacedName{Name: machine.Name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			machine.Status.Phase = "Bootstrapping"
			return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
		}
		return ctrl.Result{}, err
	}

	if node.Spec.ProviderID == "" && machine.Spec.ProviderID != nil {
		helper, err := patch.NewHelper(node, r.Client)
		if err != nil {
			return ctrl.Result{}, err
		}
		node.Spec.ProviderID = *machine.Spec.ProviderID
		if err := helper.Patch(ctx, node); err != nil {
			return ctrl.Result{}, err
		}
	}

	if nodeReady(node) {
		machine.Status.Ready = true
		machine.Status.Phase = "Ready"
		conditions.MarkTrue(machine, NodeReadyCondition)
		return ctrl.Result{}, nil
	}
	machine.Status.Phase = "Bootstrapping"
	return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
}

// claimedServiceNames is the set of OVH service names already held by other
// OVHDedicatedMachines in the namespace, so adoption never double-claims a box.
// Claim state lives in the CR status rather than OVH-side because the cluster
// is the durable record and OVH dedicated servers carry no operator-writable
// claim marker the way Scaleway names do.
func (r *OVHDedicatedMachineReconciler) claimedServiceNames(ctx context.Context, self *infrav1.OVHDedicatedMachine) (map[string]bool, error) {
	list := &infrav1.OVHDedicatedMachineList{}
	if err := r.List(ctx, list, client.InNamespace(self.Namespace)); err != nil {
		return nil, fmt.Errorf("list OVHDedicatedMachines: %w", err)
	}
	claimed := make(map[string]bool, len(list.Items))
	for i := range list.Items {
		m := &list.Items[i]
		if m.UID == self.UID {
			continue
		}
		if m.Status.ServiceName != "" {
			claimed[m.Status.ServiceName] = true
		}
	}
	return claimed, nil
}

// reconcileDelete releases the Machine without terminating the OVH contract:
// it drops the per-machine kubelet identity and removes the finalizer, leaving
// the physical server running (its kubelet keeps the Node registered until the
// operator reinstalls or terminates the box out of band). This is the key
// difference from the on-demand Elastic Metal kind, whose delete tears down the
// paid server.
func (r *OVHDedicatedMachineReconciler) reconcileDelete(ctx context.Context, machine *infrav1.OVHDedicatedMachine) (ctrl.Result, error) {
	machine.Status.Phase = "Deleting"
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		r.event(machine, "DeleteIdentityFailed", "delete node identity: %v (will retry)", err)
		return ctrl.Result{}, err
	}
	// Drop the per-machine bootstrap Secret (the TOFU host fingerprint), so a
	// replacement Machine re-pins the box's key fresh instead of failing against
	// a stale pin keyed on the deleted Machine's name.
	if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, machine.Name); err != nil {
		r.event(machine, "DeleteBootstrapFailed", "delete machine bootstrap secret: %v (will retry)", err)
		return ctrl.Result{}, err
	}
	// Drop the Node the kubelet registered: the host is gone, so it can't
	// deregister itself, and the foreign providerID means no CCM reaps it.
	// A lingering NotReady Node keeps its DaemonSet slot and wedges helm
	// --wait gates (e.g. the observability rollout) across the cluster.
	node := &corev1.Node{}
	node.SetName(machine.Name)
	if err := r.Delete(ctx, node); err != nil && !apierrors.IsNotFound(err) {
		r.event(machine, "DeleteNodeFailed", "delete Node: %v (will retry)", err)
		return ctrl.Result{}, err
	}
	controllerutil.RemoveFinalizer(machine, OVHDedicatedMachineFinalizer)
	return ctrl.Result{}, nil
}

func (r *OVHDedicatedMachineReconciler) event(machine *infrav1.OVHDedicatedMachine, reason, format string, args ...any) {
	if r.Recorder != nil {
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, reason, format, args...)
	}
}

func (r *OVHDedicatedMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.OVHDedicatedMachine{}).
		Complete(r)
}

// bootstrapOverSSH SSHes into the freshly-installed host as the install user and
// pipes the rendered self-join script to bash. The script is idempotent, so a
// retried bootstrap after a partial run converges. Shared shape with the Elastic
// Metal kind's SSH bootstrap.
func bootstrapOverSSH(ctx context.Context, user, host string, privateKey []byte, script string, hk *bootstrap.HostKeyState) error {
	signer, err := ssh.ParsePrivateKey(privateKey)
	if err != nil {
		return fmt.Errorf("parse ssh private key: %w", err)
	}
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: hk.Callback(),
		Timeout:         30 * time.Second,
	}

	dialCtx, cancel := context.WithTimeout(ctx, ovhSSHTimeout)
	defer cancel()

	var d net.Dialer
	conn, err := d.DialContext(dialCtx, "tcp", net.JoinHostPort(host, "22"))
	if err != nil {
		return fmt.Errorf("dial %s:22: %w", host, err)
	}
	defer conn.Close()
	if deadline, ok := dialCtx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	sshConn, chans, reqs, err := ssh.NewClientConn(conn, net.JoinHostPort(host, "22"), cfg)
	if err != nil {
		return fmt.Errorf("ssh handshake %s: %w", host, err)
	}
	sshClient := ssh.NewClient(sshConn, chans, reqs)
	defer sshClient.Close()

	session, err := sshClient.NewSession()
	if err != nil {
		return fmt.Errorf("open ssh session: %w", err)
	}
	defer session.Close()

	session.Stdin = strings.NewReader(script)
	if out, runErr := session.CombinedOutput("bash -s"); runErr != nil {
		return fmt.Errorf("run bootstrap on %s: %w (output: %s)", host, runErr, truncate(out, 2000))
	}
	return nil
}
