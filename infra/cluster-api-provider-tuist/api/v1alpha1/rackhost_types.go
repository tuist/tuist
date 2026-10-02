package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
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

// PowerOutletRef addresses one switched outlet.
type PowerOutletRef struct {
	// Driver selects the power backend. `shelly` speaks the Shelly Gen2 RPC
	// (with a Gen1 fallback) and is for home and office prototypes only: it is
	// the BER1 prototype's PDU stand-in, not a rack driver. A colo rack's
	// switched PDUs get their own driver rather than being forced through this
	// one.
	// +kubebuilder:default=shelly
	// +kubebuilder:validation:Enum=shelly
	Driver string `json:"driver,omitempty"`

	// Host is the PDU / plug endpoint, as a host or host:port. Plain HTTP by
	// default; give it an `https://` prefix to force TLS.
	// +optional
	Host string `json:"host,omitempty"`

	// Outlet identifies the outlet on that endpoint. Driver-specific; for
	// Shelly it is the switch channel id, `"0"` on a single-channel plug.
	// +kubebuilder:default="0"
	Outlet string `json:"outlet,omitempty"`

	// CredentialsSecretRef names a Secret in the operator's namespace holding
	// `username` and `password` for the endpoint's HTTP auth. Optional: an
	// unauthenticated plug on a management VLAN needs none. Several hosts
	// normally point at the same Secret, since a PDU has one credential and
	// many outlets.
	// +optional
	CredentialsSecretRef *corev1.LocalObjectReference `json:"credentialsSecretRef,omitempty"`
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

	// Conditions are CAPI-style condition entries (PowerReachable).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=rackhosts,scope=Namespaced,categories=cluster-api,shortName=rh
// +kubebuilder:printcolumn:name="Address",type=string,JSONPath=".spec.address"
// +kubebuilder:printcolumn:name="Machine",type=string,JSONPath=".status.machine"
// +kubebuilder:printcolumn:name="Power",type=string,JSONPath=".status.power"
// +kubebuilder:printcolumn:name="Quarantined",type=boolean,JSONPath=".status.quarantined"
// +kubebuilder:printcolumn:name="Parked",type=boolean,JSONPath=".spec.parked"
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
