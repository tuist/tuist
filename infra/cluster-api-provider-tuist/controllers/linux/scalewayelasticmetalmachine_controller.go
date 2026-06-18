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

	baremetal "github.com/scaleway/scaleway-sdk-go/api/baremetal/v1"
	"github.com/scaleway/scaleway-sdk-go/scw"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/kubeconfig"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/scaleway"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const (
	// ElasticMetalMachineFinalizer guards the Elastic Metal server: it stays
	// on the CR until the underlying bare-metal server is deleted, so a CR
	// removed before its server is torn down doesn't strand a paid box.
	ElasticMetalMachineFinalizer = "scalewayelasticmetal.cluster.x-k8s.io/finalizer"

	// elasticMetalBootstrapUser is the OS login the bare-metal Ubuntu install
	// lands on (with sudo). Unlike a regular Instance — which consumes
	// cloud-init user-data as root — Elastic Metal has no user-data channel,
	// so the controller SSHes in as this user after install and runs the
	// rendered self-join script with sudo.
	elasticMetalBootstrapUser = "ubuntu"

	// elasticMetalSSHTimeout caps the per-attempt SSH dial + bootstrap run.
	// A reachable, just-installed box completes the script well within this;
	// a host that has finished install but isn't answering SSH yet errors out
	// and the reconcile retries on the normal cadence.
	elasticMetalSSHTimeout = 5 * time.Minute

	// pnIPv4Label is the node label dispatch reads as the Private-Network
	// address of the runner-cache node. kubelet can't self-set tuist.dev/*
	// labels under NodeRestriction, so the controller patches it.
	pnIPv4Label = "tuist.dev/pn-ipv4"

	// linuxNodeIdentityClusterRole binds the Linux kura node's kubelet identity
	// to the built-in system:node ClusterRole — the complete, canonical kubelet
	// permission set — instead of the chart's scoped tart-kubelet role (which
	// only covers what the macOS shim exercises). A real Linux kubelet needs the
	// full set (leases, services, PVCs, CSI, ...), and discovering those one
	// forbidden error at a time is its own kind of outage.
	linuxNodeIdentityClusterRole = "system:node"
)

// NodeReadyCondition is set True once the self-joined Node reports Ready. The
// Provisioned/Bootstrapped conditions are declared on the Apple Silicon
// reconciler in this package; this kind reuses Provisioned and adds NodeReady.
const NodeReadyCondition clusterv1.ConditionType = "NodeReady"

// ScalewayElasticMetalMachineReconciler reconciles a ScalewayElasticMetalMachine:
// it orders a Scaleway Elastic Metal (bare-metal) server, waits out the
// ~30-60 min OS install, attaches the runner-cache Private Network as a tagged
// VLAN, then SSH-delivers the same self-join cloud-init the Instance kind uses
// so the host registers as an ordinary Linux Node. It links the resulting Node
// by providerID and stamps the dynamic pn-ipv4 label. The provider runs in the
// same cluster the nodes join, so r.Client reaches both the CRs and the Nodes.
//
// Three things differ from the Instance reconciler: the OS-install wait state
// (a bare-metal server isn't reachable until install completes), the `ubuntu`
// bootstrap user (not root), and bringing the PN up as a VLAN interface on the
// primary NIC before kubelet starts (Elastic Metal delivers the PN as a tagged
// VLAN, not an auto-DHCP'd second interface).
type ScalewayElasticMetalMachineReconciler struct {
	client.Client
	// APIReader is the uncached reader for cross-namespace reads the scoped
	// cache can't serve (kube-system/kube-dns, for clusterDNS discovery).
	APIReader      client.Reader
	Scheme         *runtime.Scheme
	ScalewayClient *scaleway.BaremetalClient
	// VPC find-or-creates the per-env runner-cache Private Network by name (the
	// Elastic Metal + Apple Silicon fleets share it), so the spec carries a name
	// + CIDR instead of a hand-pasted UUID.
	VPC      *scaleway.VPCClient
	Recorder record.EventRecorder

	// CredentialsManager mints the kubelet node identity (token + CA) and the
	// per-fleet SSH key the bootstrap authenticates with; Kubeconfig renders
	// the identity into a kubelet kubeconfig — the same machinery the Instance
	// reconciler uses. The node self-registers with that kubeconfig.
	CredentialsManager *credentials.Manager
	Kubeconfig         *kubeconfig.Builder

	// KubernetesMinor is the pkgs.k8s.io channel the cloud-init installs
	// kubelet from (e.g. "v1.34"); keep in step with the control plane.
	KubernetesMinor string

	// DefaultOfferType / DefaultZone / DefaultOS fill in a Machine spec that
	// left them empty (the kubebuilder defaults cover the common path; these
	// guard standalone CRs and older templates).
	DefaultOfferType string
	DefaultZone      string
	DefaultOS        string
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayelasticmetalmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayelasticmetalmachines/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=scalewayelasticmetalmachines/finalizers,verbs=update

func (r *ScalewayElasticMetalMachineReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	machine := &infrav1.ScalewayElasticMetalMachine{}
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

	if !controllerutil.ContainsFinalizer(machine, ElasticMetalMachineFinalizer) {
		controllerutil.AddFinalizer(machine, ElasticMetalMachineFinalizer)
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

	return r.reconcileNormal(ctx, machine, ownerMachine)
}

func (r *ScalewayElasticMetalMachineReconciler) reconcileNormal(
	ctx context.Context,
	machine *infrav1.ScalewayElasticMetalMachine,
	_ *clusterv1.Machine,
) (ctrl.Result, error) {
	logger := log.FromContext(ctx)
	zone, err := scw.ParseZone(firstNonEmpty(machine.Spec.Zone, r.DefaultZone))
	if err != nil {
		return r.fail(machine, "InvalidZone", fmt.Sprintf("zone %q: %v", machine.Spec.Zone, err))
	}

	// Provision: find-or-create the server named after this Machine, wait out
	// the OS install, attach the PN as a VLAN, then SSH-bootstrap. ServerID is
	// recorded as soon as the server exists so a controller restart re-finds it
	// via FindServerByName instead of ordering (and paying for) a duplicate;
	// providerID is set only once the bootstrap completes, so a transient
	// failure retries instead of stranding a half-configured node.
	if machine.Spec.ProviderID == nil || *machine.Spec.ProviderID == "" {
		fleet := firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name)
		sshKey, _, keyErr := r.fleetSSHKey(ctx, fleet)
		if keyErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "SSHKeyUnavailable",
				clusterv1.ConditionSeverityError, "%v", keyErr)
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		// Claim a pre-ordered server rather than ordering one inline: bare-metal
		// capacity goes out of stock, so the operator pre-orders boxes named with
		// AdoptNamePrefix (authorized with the fleet key) and the controller claims
		// a free, OS-installed one. Claim state lives cluster-side (the CR status),
		// so a restart re-finds the box via GetServer instead of double-claiming,
		// and a deploy/rollout never blocks on procurement.
		var server *baremetal.Server
		if machine.Status.ServerID == "" {
			claimed, claimErr := r.claimedServerIDs(ctx, machine)
			if claimErr != nil {
				return ctrl.Result{}, claimErr
			}
			adopted, adoptErr := r.ScalewayClient.FindAdoptableServer(ctx, zone, machine.Spec.AdoptNamePrefix, claimed)
			if adoptErr != nil {
				return ctrl.Result{}, adoptErr
			}
			if adopted == nil {
				conditions.MarkFalse(machine, shared.ProvisionedCondition, "NoAdoptableServer",
					clusterv1.ConditionSeverityInfo,
					"no free pre-ordered Elastic Metal server under %q in %s; awaiting capacity", machine.Spec.AdoptNamePrefix, zone)
				machine.Status.Phase = "Adopting"
				logger.Info("no adoptable Elastic Metal server yet", "prefix", machine.Spec.AdoptNamePrefix, "zone", zone)
				return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
			}
			machine.Status.ServerID = adopted.ID
			machine.Status.Phase = "Adopting"
			r.event(machine, "Adopted", "Adopted Elastic Metal server %s in %s", adopted.ID, zone)
			logger.Info("adopted Elastic Metal server", "id", adopted.ID, "zone", zone)
			server = adopted
		} else {
			got, getErr := r.ScalewayClient.GetServer(ctx, zone, machine.Status.ServerID)
			if getErr != nil {
				return ctrl.Result{}, getErr
			}
			server = got
		}

		// OS-install wait. A bare-metal server is delivered + OS-installed
		// asynchronously before it is reachable, so poll install status and
		// don't SSH until it completes; the public IP is unreachable until
		// then.
		if scaleway.ServerInstallFailed(server) {
			return r.fail(machine, "InstallFailed",
				fmt.Sprintf("Elastic Metal server %s install failed (status %s)", server.ID, installStatus(server)))
		}
		if !scaleway.ServerInstalled(server) {
			machine.Status.Phase = installPhase(server)
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "Installing",
				clusterv1.ConditionSeverityInfo, "Server %s installing (status %s)", server.ID, installStatus(server))
			logger.Info("waiting for Elastic Metal OS install", "id", server.ID, "status", installStatus(server))
			return ctrl.Result{RequeueAfter: 60 * time.Second}, nil
		}

		// PN-as-VLAN bring-up: resolve (find-or-create) the runner-cache Private
		// Network by name, attach the server, and resolve its VLAN. Scaleway can
		// lag stamping the VLAN, so requeue on error (rather than bootstrapping a
		// host without its cache interface).
		pnID, pnResolveErr := r.resolvePrivateNetwork(ctx, machine, zone)
		if pnResolveErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "PrivateNetworkPending",
				clusterv1.ConditionSeverityInfo, "%v", pnResolveErr)
			machine.Status.Phase = "Provisioning"
			logger.Info("resolving Private Network", "id", server.ID, "err", pnResolveErr.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		vlan, pnErr := r.ScalewayClient.EnsurePrivateNetwork(ctx, zone, server.ID, pnID)
		if pnErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "PrivateNetworkPending",
				clusterv1.ConditionSeverityInfo, "%v", pnErr)
			machine.Status.Phase = "Provisioning"
			logger.Info("waiting for Private Network VLAN", "id", server.ID, "err", pnErr.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.PrivateNetworkVLAN = vlan

		host := scaleway.PublicIPv4(server)
		if host == "" {
			machine.Status.Phase = "Provisioning"
			logger.Info("public IPv4 not assigned yet", "id", server.ID)
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}

		identity, idErr := r.CredentialsManager.EnsureNodeIdentity(ctx, machine.Name, linuxNodeIdentityClusterRole)
		if idErr != nil {
			machine.Status.Phase = "Pending"
			return ctrl.Result{RequeueAfter: 20 * time.Second}, fmt.Errorf("mint node identity: %w", idErr)
		}
		kubeconfigYAML, kcErr := r.Kubeconfig.Render(ctx, machine.Name, identity.Token, identity.CA)
		if kcErr != nil {
			return ctrl.Result{}, fmt.Errorf("render kubelet kubeconfig: %w", kcErr)
		}
		bootstrapScript := renderLinuxBootstrapScript(linuxCloudInitOptions{
			NodeName:           machine.Name,
			KubeconfigYAML:     kubeconfigYAML,
			K8sMinor:           firstNonEmpty(r.KubernetesMinor, "v1.34"),
			Taints:             machine.Spec.NodeTaints,
			BootstrapUser:      elasticMetalBootstrapUser,
			PrivateNetworkVLAN: vlan,
			ClusterDNS:         discoverClusterDNS(ctx, r.APIReader),
		})

		machine.Status.Phase = "Bootstrapping"
		// Pinned host fingerprint (empty on first reconcile); persist what the
		// dial observes even on script failure so a retry verifies the same key.
		known := ""
		if creds, fpErr := r.CredentialsManager.GetMachineBootstrap(ctx, machine.Name); fpErr != nil {
			return ctrl.Result{}, fmt.Errorf("read host fingerprint: %w", fpErr)
		} else if creds != nil {
			known = creds.HostFingerprint
		}
		hk := bootstrap.NewHostKeyState(known)
		bootErr := r.sshBootstrap(ctx, host, sshKey, bootstrapScript, hk)
		if observed := hk.Observed(); observed != "" && observed != known {
			if perr := r.CredentialsManager.SetMachineHostFingerprint(ctx, machine.Name, observed); perr != nil {
				logger.Error(perr, "persist host fingerprint; will retry")
			}
		}
		if bootErr != nil {
			conditions.MarkFalse(machine, shared.ProvisionedCondition, "BootstrapFailed",
				clusterv1.ConditionSeverityWarning, "%v", bootErr)
			machine.Status.BootstrapAttempts++
			logger.Info("bootstrap over SSH failed, will retry", "host", host, "err", bootErr.Error())
			return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
		}
		machine.Status.BootstrapAttempts = 0

		providerID := scaleway.BaremetalProviderID(zone, server.ID)
		machine.Spec.ProviderID = &providerID
		conditions.MarkTrue(machine, shared.ProvisionedCondition)
		machine.Status.Phase = "Bootstrapping"
		r.event(machine, "Bootstrapped", "Bootstrapped Elastic Metal server %s as %s@%s", server.ID, elasticMetalBootstrapUser, host)
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

	if err := r.reconcileNode(ctx, machine, node); err != nil {
		return ctrl.Result{}, err
	}

	// The PN IPAM address can lag the node going Ready, so keep reconciling
	// until the pn-ipv4 label is stamped — otherwise a node that becomes Ready
	// before its address resolves would never get labelled (dispatch needs it
	// to route runner cache traffic over the Private Network).
	pnLabelPending := machine.Spec.PrivateNetworkName != "" && node.Labels[pnIPv4Label] == ""

	if nodeReady(node) {
		machine.Status.Ready = true
		machine.Status.Phase = "Ready"
		conditions.MarkTrue(machine, NodeReadyCondition)
		if pnLabelPending {
			return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
		}
		return ctrl.Result{}, nil
	}
	machine.Status.Phase = "Bootstrapping"
	return ctrl.Result{RequeueAfter: 20 * time.Second}, nil
}

// reconcileNode stamps the foreign providerID (so CAPI links Machine↔Node)
// and the dynamic pn-ipv4 label onto the Node, both idempotently.
func (r *ScalewayElasticMetalMachineReconciler) reconcileNode(ctx context.Context, machine *infrav1.ScalewayElasticMetalMachine, node *corev1.Node) error {
	helper, err := patch.NewHelper(node, r.Client)
	if err != nil {
		return err
	}
	changed := false

	if node.Spec.ProviderID == "" && machine.Spec.ProviderID != nil {
		node.Spec.ProviderID = *machine.Spec.ProviderID
		changed = true
	}

	if machine.Spec.PrivateNetworkName != "" && node.Labels[pnIPv4Label] == "" {
		logger := log.FromContext(ctx)
		ip, ipErr := r.privateNetworkIP(ctx, machine)
		switch {
		case ipErr != nil:
			logger.Info("pn-ipv4 unresolved, will retry", "node", node.Name, "err", ipErr.Error())
		case ip == "":
			logger.Info("pn-ipv4 IPAM address not assigned yet, will retry", "node", node.Name)
		default:
			if node.Labels == nil {
				node.Labels = map[string]string{}
			}
			node.Labels[pnIPv4Label] = ip
			changed = true
			logger.Info("stamped pn-ipv4 label", "node", node.Name, "ip", ip)
		}
	}

	if !changed {
		return nil
	}
	return helper.Patch(ctx, node)
}

func (r *ScalewayElasticMetalMachineReconciler) privateNetworkIP(ctx context.Context, machine *infrav1.ScalewayElasticMetalMachine) (string, error) {
	zone, err := scw.ParseZone(firstNonEmpty(machine.Spec.Zone, r.DefaultZone))
	if err != nil {
		return "", err
	}
	pnID, err := r.resolvePrivateNetwork(ctx, machine, zone)
	if err != nil {
		return "", err
	}
	server, err := r.ScalewayClient.GetServer(ctx, zone, machine.Status.ServerID)
	if err != nil {
		return "", err
	}
	return r.ScalewayClient.PrivateNetworkIP(ctx, server, pnID)
}

// resolvePrivateNetwork find-or-creates the runner-cache Private Network named
// in the spec and returns its ID; an empty name (PN not configured) yields "".
func (r *ScalewayElasticMetalMachineReconciler) resolvePrivateNetwork(ctx context.Context, machine *infrav1.ScalewayElasticMetalMachine, zone scw.Zone) (string, error) {
	if machine.Spec.PrivateNetworkName == "" {
		return "", nil
	}
	return r.VPC.EnsurePrivateNetworkByName(ctx, scaleway.RegionFromZone(zone), machine.Spec.PrivateNetworkName, machine.Spec.PrivateNetworkCIDR)
}

// claimedServerIDs is the set of Elastic Metal server IDs already held by other
// ScalewayElasticMetalMachines in the namespace, so adoption never double-claims
// a pre-ordered box. Claim state lives in the CR status (not Scaleway-side),
// matching the OVH kind.
func (r *ScalewayElasticMetalMachineReconciler) claimedServerIDs(ctx context.Context, self *infrav1.ScalewayElasticMetalMachine) (map[string]bool, error) {
	list := &infrav1.ScalewayElasticMetalMachineList{}
	if err := r.List(ctx, list, client.InNamespace(self.Namespace)); err != nil {
		return nil, fmt.Errorf("list ScalewayElasticMetalMachines: %w", err)
	}
	claimed := make(map[string]bool, len(list.Items))
	for i := range list.Items {
		m := &list.Items[i]
		if m.UID == self.UID {
			continue
		}
		if m.Status.ServerID != "" {
			claimed[m.Status.ServerID] = true
		}
	}
	return claimed, nil
}

func (r *ScalewayElasticMetalMachineReconciler) reconcileDelete(ctx context.Context, machine *infrav1.ScalewayElasticMetalMachine) (ctrl.Result, error) {
	if machine.Status.ServerID != "" {
		zone, err := scw.ParseZone(firstNonEmpty(machine.Spec.Zone, r.DefaultZone))
		if err == nil {
			// Release to pool, don't terminate: the box is pre-ordered capacity
			// the operator owns, so reinstall it (wipe) back to a clean, claimable
			// state — the Elastic Metal analog of the macOS ReleaseToPool. The
			// fleet SSH key is re-authored so the box bootstraps on its next claim.
			_, sshKeyID, keyErr := r.fleetSSHKey(ctx, firstNonEmpty(machine.Spec.FleetName, machine.Namespace+"-"+machine.Name))
			if keyErr != nil {
				return ctrl.Result{}, fmt.Errorf("read fleet ssh key for release: %w", keyErr)
			}
			if relErr := r.ScalewayClient.ReinstallServer(ctx, zone, machine.Status.ServerID,
				firstNonEmpty(machine.Spec.OS, r.DefaultOS), nonEmpty(sshKeyID)); relErr != nil {
				r.event(machine, "ReleaseFailed", "release (reinstall) Elastic Metal server %s: %v (will retry)", machine.Status.ServerID, relErr)
				return ctrl.Result{}, relErr
			}
		}
	}

	// Drop the per-machine kubelet identity (ServiceAccount + token Secret +
	// ClusterRoleBinding) once the server is gone, so a deleted machine
	// doesn't leave behind a long-lived token bound to system:node.
	if err := r.CredentialsManager.DeleteNodeIdentity(ctx, machine.Name); err != nil {
		r.event(machine, "DeleteIdentityFailed", "delete node identity: %v (will retry)", err)
		return ctrl.Result{}, err
	}

	// Wipe the per-machine bootstrap Secret (the TOFU host fingerprint), so a
	// future machine reusing this name doesn't fail bootstrap against a stale
	// pin from the released server.
	if err := r.CredentialsManager.DeleteMachineBootstrap(ctx, machine.Name); err != nil {
		r.event(machine, "DeleteBootstrapFailed", "delete machine bootstrap secret: %v (will retry)", err)
		return ctrl.Result{}, err
	}

	controllerutil.RemoveFinalizer(machine, ElasticMetalMachineFinalizer)
	return ctrl.Result{}, nil
}

// fleetSSHKey returns the private SSH key bytes and the Scaleway-side key ID
// for the fleet. The private key authenticates the bootstrap SSH; the Scaleway
// ID is authorized on the server at install time so the `ubuntu` user accepts
// our key. EnsureFleetSSHKey owns generation + Scaleway registration; the ID is
// recorded as an annotation on the Secret it manages, which we read back here.
func (r *ScalewayElasticMetalMachineReconciler) fleetSSHKey(ctx context.Context, fleet string) ([]byte, string, error) {
	key, err := r.CredentialsManager.EnsureFleetSSHKey(ctx, fleet)
	if err != nil {
		return nil, "", err
	}
	id, idErr := r.CredentialsManager.FleetSSHKeyID(ctx, fleet)
	if idErr != nil {
		return nil, "", idErr
	}
	return key, id, nil
}

// bootstrap SSHes into the freshly-installed bare-metal host as the install
// user and runs the rendered self-join script. Elastic Metal has no cloud-init
// user-data channel (unlike Instances), so the same self-join logic is rendered
// as a standalone bash script and piped to the host's shell instead; the script
// escalates with sudo because the login user isn't root.
func (r *ScalewayElasticMetalMachineReconciler) sshBootstrap(ctx context.Context, host string, privateKey []byte, script string, hk *bootstrap.HostKeyState) error {
	signer, err := ssh.ParsePrivateKey(privateKey)
	if err != nil {
		return fmt.Errorf("parse ssh private key: %w", err)
	}
	// TOFU host-key verification (shared with the Apple Silicon reconciler):
	// hk pins the host fingerprint on first contact and rejects a changed key
	// thereafter, so the self-join script — which carries the kubelet node
	// identity — isn't delivered over a blindly-trusted channel on retries.
	cfg := &ssh.ClientConfig{
		User:            elasticMetalBootstrapUser,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: hk.Callback(),
		Timeout:         30 * time.Second,
	}

	dialCtx, cancel := context.WithTimeout(ctx, elasticMetalSSHTimeout)
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

	// Pipe the self-join script to a fresh bash over stdin. The script is
	// idempotent (find-or-write files, enable units), so a retried bootstrap
	// after a partial run converges rather than failing.
	session.Stdin = strings.NewReader(script)
	if out, runErr := session.CombinedOutput("bash -s"); runErr != nil {
		return fmt.Errorf("run bootstrap on %s: %w (output: %s)", host, runErr, truncate(out, 2000))
	}
	return nil
}

func (r *ScalewayElasticMetalMachineReconciler) fail(machine *infrav1.ScalewayElasticMetalMachine, reason, message string) (ctrl.Result, error) {
	machine.Status.Phase = "Failed"
	machine.Status.FailureReason = &reason
	machine.Status.FailureMessage = &message
	conditions.MarkFalse(machine, shared.ProvisionedCondition, reason, clusterv1.ConditionSeverityError, "%s", message)
	r.event(machine, reason, "%s", message)
	return ctrl.Result{}, nil
}

func (r *ScalewayElasticMetalMachineReconciler) event(machine *infrav1.ScalewayElasticMetalMachine, reason, format string, args ...any) {
	if r.Recorder != nil {
		r.Recorder.Eventf(machine, corev1.EventTypeNormal, reason, format, args...)
	}
}

func (r *ScalewayElasticMetalMachineReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.ScalewayElasticMetalMachine{}).
		Complete(r)
}

// installPhase maps a not-yet-installed server's state to the CR's lifecycle
// phase: "Ordered" while it is still being delivered, "Installing" once the OS
// install is running.
func installPhase(server *baremetal.Server) string {
	if server.Install != nil {
		switch server.Install.Status {
		case baremetal.ServerInstallStatusInstalling, baremetal.ServerInstallStatusCompleted:
			return "Installing"
		}
	}
	if server.Status == baremetal.ServerStatusReady {
		return "Installing"
	}
	return "Ordered"
}

// installStatus is a human-readable "<server-status>/<install-status>" for
// events and conditions while the bare-metal box provisions.
func installStatus(server *baremetal.Server) string {
	install := "none"
	if server.Install != nil {
		install = string(server.Install.Status)
	}
	return fmt.Sprintf("%s/%s", server.Status, install)
}

// nonEmpty drops an empty id so CreateServer gets a nil SSHKeyIDs rather than a
// [""] the API would reject.
func nonEmpty(id string) []string {
	if id == "" {
		return nil
	}
	return []string{id}
}

// truncate caps oversized SSH output so a failed bootstrap's error stays a
// readable event rather than dumping the whole apt log.
func truncate(b []byte, max int) string {
	if len(b) <= max {
		return string(b)
	}
	return string(b[:max]) + "…(truncated)"
}

func nodeReady(node *corev1.Node) bool {
	for _, c := range node.Status.Conditions {
		if c.Type == corev1.NodeReady && c.Status == corev1.ConditionTrue {
			return true
		}
	}
	return false
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
