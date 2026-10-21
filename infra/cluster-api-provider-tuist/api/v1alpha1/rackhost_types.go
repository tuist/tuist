package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackHostSpec describes one physical Mac mini we own, sitting in a rack we
// operate: the BER1 colo programme's hardware, as opposed to capacity ordered
// from a provider API.
//
// A host is its own node. The RackHost controller keeps one CAPI Machine and
// the RackAppleSiliconMachine it owns for each host, named `<fleet>-<host>`,
// with the host as their controller owner. A box upgrades in place, so there
// is no MachineDeployment and no pool of hosts to claim from.
type RackHostSpec struct {
	// Serial is the Mac's hardware serial (e.g. `C07FC05JQ6NY`). This is the
	// host's durable identity: it survives a hostname change, a DFU restore
	// and a re-cabling, it is what Apple Business Manager and the MDM know the
	// box by, and it is what the providerID is composed from. The address can
	// change; this cannot.
	// +optional
	Serial string `json:"serial,omitempty"`

	// Address is what the operator dials for SSH: an IP or a DNS name. For a
	// rack host this is normally the in-rack LAN address, reachable from the
	// cluster over a tailnet subnet route advertised by the rack's service
	// node.
	//
	// A subnet-routed address is deliberate rather than incidental. Bootstrap
	// stops and replaces tailscaled on the host to install the operator's
	// pinned build; over a session transported by the HOST's own tailnet
	// identity that would drop the tunnel it is riding (which is exactly why
	// the drift loop's tailnet fallback sets SkipTailscaleInstall). Routed via
	// a separate subnet router, the session survives, so a rack host can be
	// fully bootstrapped over one transport.
	// +optional
	Address string `json:"address,omitempty"`

	// SSHIngressAllowCIDRs are the source addresses a dial to Address arrives
	// from: the LAN address of every subnet router that advertises it, as a
	// /32. A router forwards with SNAT (the default on Linux, the only mode on
	// macOS), so the host sees the router, not the operator. They are added to
	// the host's SSH ingress guard on top of the fleet-wide
	// `--ssh-ingress-allow-cidrs`.
	//
	// Without them the router path works only while the host still holds its
	// own tailnet identity. The guard admits :22 from the tailnet, the fleet
	// list and the last session's source, and that last one is overwritten by
	// every push, including one over the tailnet fallback. A rented mini keeps
	// a public path through the fleet list; a rack mini has none, so one that
	// comes back without its tailnet device is reachable only from its
	// console. List every router when there is more than one, since a failover
	// changes the source address.
	// +optional
	// +kubebuilder:validation:items:Pattern=`^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$`
	SSHIngressAllowCIDRs []string `json:"sshIngressAllowCIDRs,omitempty"`

	// SSHUser is the account the operator logs in as. On rack hosts this is
	// the MDM-provisioned service account rather than a provider-issued one,
	// so it is per-host configurable instead of read back from an API.
	// +kubebuilder:default=tuist
	SSHUser string `json:"sshUser,omitempty"`

	// Location is where the box physically is. Nothing in the reconcile path
	// reads rack/shelf/positionU: they exist so that a human handed an
	// alerting node name can walk to it, but `site` IS load-bearing: it names
	// the rack site and composes the providerID, so the machine controller
	// does not bootstrap a host without one.
	// +optional
	Location RackHostLocation `json:"location,omitempty"`

	// Power names the outlet this host is plugged into. Cycling it is the
	// fleet's remote reboot: Apple silicon minis power on when mains is
	// applied, and every fleet host runs `pmset autorestart 1`, so an outlet
	// cycle is a full reboot with no console. It is the only repair a host
	// that fails bootstrap has short of being quarantined and paging a human.
	// +optional
	Power *PowerOutletRef `json:"power,omitempty"`

	// Machine sizes the node the host runs as. The controller copies it onto
	// the host's RackAppleSiliconMachine, and a change reaches the host
	// through the host-config drift loop.
	// +optional
	Machine RackHostMachine `json:"machine,omitempty"`

	// Parked keeps the host declared with no Machine: bench work, an RMA, a
	// box that is off. Parking a host deletes its Machine and its Node without
	// draining it, so drain the Node first; unparking it makes a new Machine,
	// which bootstraps the host again.
	// +optional
	Parked bool `json:"parked,omitempty"`

	// LendTo lends the host's runner runtime to another environment, by the
	// name the operator knows its cluster under (`--rack-lease-borrower`). The
	// host stays this operator's: its Machine, power, OS updates and bootstrap
	// from a reinstall. The other env's operator owns everything a runner
	// needs: tart-kubelet and its config, the VM egress firewall, cache
	// volumes, Tailscale and the Node, and rolls them out with that env's
	// deploys. The two operators hand the host over through a RackHostLease in
	// the borrowing cluster; see "A host lent to another env" in this
	// provider's AGENTS.md. Clearing it returns the host once the borrower has
	// drained it.
	// +optional
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	LendTo string `json:"lendTo,omitempty"`

	// NodeFleet is the `tuist.dev/fleet` label on the host's Node when it is not
	// the operator's fleet: a host lent to the runner pools of another fleet,
	// such as one another environment's server drives. Runner pools select Nodes
	// by that label, so the operator's own pools stop placing runners on the
	// host and pools selecting this value start. The Machine keeps the
	// operator's fleet, its name and its credentials. A change reaches the host
	// through the host-config drift loop.
	// +optional
	// +kubebuilder:validation:MaxLength=63
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`
	NodeFleet string `json:"nodeFleet,omitempty"`

	// NodeCluster registers the host's Node in another cluster: the host stays
	// in this operator's inventory (its Machine, power, OS updates and
	// bootstrap are this cluster's), but its tart-kubelet joins the cluster
	// whose kubeconfig the Secret holds, and that cluster's runner pools and
	// server drive its guests. This cluster then has no Node for the host, so
	// the Machine is kept off remediation and the host is not re-bootstrapped
	// for a missing Node. Drain the host's Node before setting it.
	//
	// This is the manual lend, where this operator pushes the runtime with the
	// other cluster's kubeconfig. LendTo replaces it; the two are exclusive.
	// +optional
	NodeCluster *RackHostNodeCluster `json:"nodeCluster,omitempty"`
}

// RackHostNodeCluster is the cluster a lent host's Node registers in.
type RackHostNodeCluster struct {
	// KubeconfigSecret names a Secret in the host's namespace whose
	// `kubeconfig` key is the kubeconfig tart-kubelet authenticates with: a
	// node identity the other cluster issued for this host's Machine name.
	// +kubebuilder:validation:MinLength=1
	KubeconfigSecret string `json:"kubeconfigSecret"`

	// CacheVolumesURL is the other cluster's server endpoint for macOS custom
	// cache volumes (`<server>/api/internal/runners/cache-volumes`). Empty
	// turns custom cache volumes off on the host.
	// +optional
	CacheVolumesURL string `json:"cacheVolumesURL,omitempty"`
}

// RackHostMachine is the sizing the host's RackAppleSiliconMachine carries.
// Each field falls back to the operator's global default when unset.
type RackHostMachine struct {
	// HostCPU is the CPU-core count advertised on the Node.
	// +optional
	HostCPU int `json:"hostCPU,omitempty"`

	// HostMemoryMB is the memory advertised on the Node: the box's RAM minus
	// the ~2 GB Virtualization.framework reserves for the host.
	// +optional
	HostMemoryMB int `json:"hostMemoryMB,omitempty"`

	// GuestCapacity is how many Tart guests the host is expected to run.
	// +optional
	GuestCapacity int `json:"guestCapacity,omitempty"`

	// MaxPods is the Pod ceiling tart-kubelet advertises.
	// +optional
	MaxPods int `json:"maxPods,omitempty"`

	// RunnerCacheVolumeGiB is the quota of the host's runner-cache volume. An
	// explicit 0 disables cache volumes on the host; unset inherits the
	// operator's default.
	// +optional
	RunnerCacheVolumeGiB *int `json:"runnerCacheVolumeGiB,omitempty"`
}

// RackSiteNodeLabel carries a rack host's site on its Machine. Cluster API
// syncs labels in the node.cluster.x-k8s.io domain from a Machine to its Node,
// where kube-state-metrics exposes it.
const RackSiteNodeLabel = "node.cluster.x-k8s.io/rack-site"

// RackHostLocation is the physical position of a host.
type RackHostLocation struct {
	// Site is the rack site (e.g. `ber1`). Load-bearing: it composes the
	// providerID, so it must be stable for the life of the host.
	// +optional
	Site string `json:"site,omitempty"`

	// Rack identifies the rack within the site.
	// +optional
	Rack string `json:"rack,omitempty"`

	// Shelf identifies the mount within the rack (a 3-up tray, in the BER1
	// build).
	// +optional
	Shelf string `json:"shelf,omitempty"`

	// PositionU is the lowest rack unit the mount occupies.
	// +optional
	PositionU int `json:"positionU,omitempty"`
}

// PowerOutletRef addresses one switched outlet: an outlet of a RackPDU in the
// host's namespace (`pdu`), the rack's form, or an endpoint of its own
// (`driver`, `host`, `credentialsSecretRef`), the prototypes' form.
// +kubebuilder:validation:XValidation:rule="has(self.pdu) != has(self.host)",message="set either pdu or host"
// +kubebuilder:validation:XValidation:rule="!has(self.pdu) || (!has(self.driver) && !has(self.credentialsSecretRef))",message="a pdu outlet takes its driver and credentials from the RackPDU"
// +kubebuilder:validation:XValidation:rule="!has(self.pdu) || (has(self.outlet) && self.outlet.matches('^[1-9][0-9]*$'))",message="a pdu outlet is its 1-based number on the PDU"
type PowerOutletRef struct {
	// PDU names a RackPDU in the host's namespace, whose controller adopted
	// it and owns its credentials, certificate pin and egress Service. Power
	// actions are refused while it is not Ready.
	// +kubebuilder:validation:MinLength=1
	// +optional
	PDU string `json:"pdu,omitempty"`

	// Driver selects the power backend of an endpoint named by `host`; unset
	// is `shelly`, the Shelly Gen2 RPC (with a Gen1 fallback), for home and
	// office prototypes only. The rack's PDUs are RackPDUs, named by `pdu`.
	// +kubebuilder:validation:Enum=shelly
	// +optional
	Driver string `json:"driver,omitempty"`

	// Host is the endpoint, as a host, host:port or `scheme://host`; a bare
	// host is plain HTTP. It is dialled directly.
	// +kubebuilder:validation:MinLength=1
	// +optional
	Host string `json:"host,omitempty"`

	// Outlet identifies the outlet. Driver-specific: for Shelly the switch
	// channel id, `"0"` on a single-channel plug; for a PDU the outlet's
	// 1-based number on it.
	// +kubebuilder:default="0"
	// +kubebuilder:validation:MaxLength=16
	Outlet string `json:"outlet,omitempty"`

	// CredentialsSecretRef names a Secret in the operator's namespace holding
	// `username` and `password` for the endpoint named by `host`. Optional
	// for an unauthenticated plug.
	// +optional
	CredentialsSecretRef *corev1.LocalObjectReference `json:"credentialsSecretRef,omitempty"`
}

// OutletDraw is an outlet's meter reading. A field the device does not report
// is unset.
type OutletDraw struct {
	// ActivePowerWatts is the real power drawn, in watts.
	// +optional
	ActivePowerWatts *resource.Quantity `json:"activePowerWatts,omitempty"`

	// ApparentPowerVA is the apparent power, in volt-amperes. A cord plugged in
	// to a machine that is off still reads a few VA, an empty outlet none.
	// +optional
	ApparentPowerVA *resource.Quantity `json:"apparentPowerVA,omitempty"`

	// CurrentAmps is the RMS current, in amperes.
	// +optional
	CurrentAmps *resource.Quantity `json:"currentAmps,omitempty"`
}

// RackHostStatus is the observed state of one physical host.
type RackHostStatus struct {
	// Machine is the name of the CAPI Machine and RackAppleSiliconMachine that
	// make this host a node, and of the Node they register: `<fleet>-<host>`.
	// +optional
	Machine string `json:"machine,omitempty"`

	// Power is the last observed outlet state: On, Off, or Unknown when the
	// host has no outlet configured or the driver could not reach it.
	// +optional
	Power string `json:"power,omitempty"`

	// OutletDraw is what the outlet's meter last read: the outlet's entry in its
	// RackPDU's status, or the endpoint's own meter for an outlet of its own.
	// Unset when there is no recent reading. The HostDrawing condition says
	// what it means for the host.
	// +optional
	OutletDraw *OutletDraw `json:"outletDraw,omitempty"`

	// LastPowerAction / LastPowerActionTime record the last action the
	// operator took on the outlet (`on`, `off`, `cycle`), so a host that
	// rebooted has a visible cause rather than looking like a spontaneous
	// panic.
	// +optional
	LastPowerAction string `json:"lastPowerAction,omitempty"`
	// +optional
	LastPowerActionTime *metav1.Time `json:"lastPowerActionTime,omitempty"`

	// Quarantined holds off bootstrapping the host after the machine
	// controller exhausted its bootstrap attempts on it. It is
	// controller-set and expires after the operator's
	// `--rackhost-quarantine-retry-after`, when bootstrap starts over.
	// +optional
	Quarantined bool `json:"quarantined,omitempty"`

	// QuarantineReason carries the failure that caused it.
	// +optional
	QuarantineReason string `json:"quarantineReason,omitempty"`

	// QuarantinedAt is when the quarantine was applied, and it is what lets the
	// quarantine expire. Clearing a quarantine by hand needs write access to
	// rackhosts/status, which a human reaching the cluster through the kubectl
	// gateway does not have.
	// +optional
	QuarantinedAt *metav1.Time `json:"quarantinedAt,omitempty"`

	// Lease is how far the host has been handed to another env, as this
	// operator recorded it. It outlives the host's Machine, so a Machine
	// made again while the host is lent picks the lease up rather than pushing
	// this env's runtime over the borrower's.
	// +optional
	Lease *RackHostLending `json:"lease,omitempty"`

	// Conditions are CAPI-style condition entries (PowerReachable, HostDrawing).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=rackhosts,scope=Namespaced,categories=cluster-api,shortName=rh
// +kubebuilder:printcolumn:name="Address",type=string,JSONPath=".spec.address"
// +kubebuilder:printcolumn:name="Machine",type=string,JSONPath=".status.machine"
// +kubebuilder:printcolumn:name="Power",type=string,JSONPath=".status.power"
// +kubebuilder:printcolumn:name="Watts",type=string,priority=1,JSONPath=".status.outletDraw.activePowerWatts"
// +kubebuilder:printcolumn:name="Quarantined",type=boolean,JSONPath=".status.quarantined"
// +kubebuilder:printcolumn:name="Parked",type=boolean,JSONPath=".spec.parked"
// +kubebuilder:printcolumn:name="LentTo",type=string,JSONPath=".status.lease.borrower"
// +kubebuilder:printcolumn:name="Lease",type=string,JSONPath=".status.lease.state"
// +kubebuilder:printcolumn:name="Serial",type=string,priority=1,JSONPath=".spec.serial"
// +kubebuilder:printcolumn:name="Site",type=string,priority=1,JSONPath=".spec.location.site"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RackHost is one physical Mac mini in a rack we operate.
type RackHost struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackHostSpec   `json:"spec,omitempty"`
	Status RackHostStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackHostList is a list of RackHost.
type RackHostList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackHost `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackHost{}, &RackHostList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface.
func (h *RackHost) GetConditions() clusterv1.Conditions {
	return h.Status.Conditions
}

func (h *RackHost) SetConditions(c clusterv1.Conditions) {
	h.Status.Conditions = c
}

// The states of a host this operator lends, in the order a lend passes
// through them. Returning a host goes Returning, Reclaimed, then no lease.
const (
	// LendingOffered: the RackHostLease exists in the borrowing cluster and the
	// host still runs this env's runtime, waiting for the borrower to accept.
	LendingOffered = "Offered"
	// LendingDraining: the borrower accepted; this env's Node is cordoned and
	// its running jobs finish before the runtime changes hands.
	LendingDraining = "Draining"
	// LendingLent: the runtime is the borrower's. This operator pushes
	// nothing to the host but the lease key.
	LendingLent = "Lent"
	// LendingReturning: the borrower was asked to drain the host and release it.
	LendingReturning = "Returning"
	// LendingReclaimed: the runtime is this env's again and bootstrap is
	// pushing it.
	LendingReclaimed = "Reclaimed"
)

// RackHostLending records a lend in progress or in force.
type RackHostLending struct {
	// Borrower is the env the host is lent to.
	Borrower string `json:"borrower"`

	// State is one of Offered, Draining, Lent, Returning or Reclaimed.
	State string `json:"state"`

	// KeyFingerprint is the SHA-256 fingerprint of the lease key authorized on
	// the host, empty until one is.
	// +optional
	KeyFingerprint string `json:"keyFingerprint,omitempty"`

	// BorrowerNode is the Node the borrower runs the host as, which is also
	// the host's tailnet device name while it is lent. Taking the host back
	// clears that device.
	// +optional
	BorrowerNode string `json:"borrowerNode,omitempty"`

	// Since is when State last changed.
	// +optional
	Since *metav1.Time `json:"since,omitempty"`

	// Message says what the lend is waiting for.
	// +optional
	Message string `json:"message,omitempty"`
}
