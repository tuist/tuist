package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// StaticAppleSiliconMachineSpec is the desired state of one Mac mini we own.
//
// It is the adopt-only sibling of ScalewayAppleSiliconMachine: same host
// bootstrap, same host-config drift loop, same tailnet egress Service — but the
// host comes from a RackHost in the cluster's own inventory rather than from a
// provider's server list, and there is no order, no reinstall and no release
// path, because nobody bills us per host and no API can wipe one.
//
// Everything about the HOST lives on the RackHost (address, serial, outlet,
// position). Everything about the WORKLOAD lives here (sizing, fleet
// membership, kubelet version). That split is the point of having two kinds: a
// MachineDeployment clones this spec N times, and a spec carrying an address
// could not be cloned more than once.
type StaticAppleSiliconMachineSpec struct {
	// ProviderID, set by the controller once a RackHost is claimed, takes the
	// shape `static-applesilicon://<site>/<serial>` — composed from the two
	// durable physical facts, so re-cabling a host to a new address does not
	// change its identity to CAPI. CAPI core expects this to populate; without
	// it the parent Machine never goes Ready. The scheme is deliberately
	// foreign to the Hetzner CCM so it never reaps the node, the same guard
	// every other kind here uses.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// AdoptPool is the RackHost pool this Machine claims from — the analog of
	// the Scaleway kind's adoptPoolPrefix. The controller claims the first free
	// RackHost whose `spec.pool` matches.
	//
	// Optional on purpose, even though every chart-rendered MachineTemplate
	// sets it. A required field here is a schema constraint on a resource CAPI
	// CLONES, so a MachineTemplate that lacks it fails
	// `InfrastructureTemplateCloningFailed` on every MachineSet scale-up — and
	// that drift stays invisible until the next scale-up, which is typically
	// an operator recovering a host by deleting its Machine. The controller
	// surfaces an empty value as a `NoAdoptPool` condition instead of scanning
	// every RackHost in the namespace.
	// +optional
	AdoptPool string `json:"adoptPool,omitempty"`

	// FleetName groups Machines that share an SSH key and a sudo password. Set
	// by the MachineTemplate to the parent MachineDeployment's name. Unlike the
	// Scaleway fleets, the keypair is NOT minted in-cluster: rack hosts are
	// provisioned out of band by MDM, which authorizes a key the operator never
	// generated, so the fleet Secret is synced from 1Password by ESO and the
	// controller only ever reads it.
	// +optional
	FleetName string `json:"fleetName,omitempty"`

	// KubeletVersion override; defaults to the operator's chart-level value
	// when empty.
	// +optional
	KubeletVersion string `json:"kubeletVersion,omitempty"`

	// HostCPU is the CPU-core count the host advertises on the Node it
	// registers (Node.Status.Capacity), via tart-kubelet's `--host-cpu`. Falls
	// back to the operator's global default when unset.
	//
	// Per-Machine for the same reason it is on the Scaleway kind, and more so
	// here: a rack fills up over time and the boxes bought in month 12 are not
	// the boxes bought in month 1.
	// +optional
	HostCPU int `json:"hostCPU,omitempty"`

	// HostMemoryMB is the memory advertised on the Node — the box's RAM minus
	// the ~2 GB Apple's Virtualization.framework reserves for the host, below
	// which `tart run` fails with `memorySize > maximumAllowedMemorySize`.
	// Falls back to the operator's global default when unset.
	// +optional
	HostMemoryMB int `json:"hostMemoryMB,omitempty"`

	// GuestCapacity is how many Tart guests this host is expected to run
	// concurrently. It sizes the per-guest host resources (the VNC relay port
	// range, the disk-pressure goldens floor); it does not create capacity,
	// which HostCPU/HostMemoryMB and Tart's own two-guest SLA ceiling bind
	// first. Falls back to the operator's global default when unset.
	// +optional
	GuestCapacity int `json:"guestCapacity,omitempty"`

	// MaxPods is the Pod ceiling tart-kubelet advertises (`--max-pods`). Sized
	// as guests x 2 + 1: a Pod stays bound to its Node after it finishes, so
	// each guest slot can transiently hold its running Pod plus a predecessor
	// GC has not collected, and the +1 is margin. Falls back to the operator's
	// global default when unset.
	// +optional
	MaxPods int `json:"maxPods,omitempty"`

	// RunnerCacheVolumeGiB is the quota (GiB) of the dedicated APFS volume
	// bootstrap provisions to hold per-account cache-volume images. Unset
	// (nil) falls back to the operator's global default; an explicit 0
	// disables cache volumes on this host entirely.
	//
	// A pointer, unlike its sizing siblings, because 0 is a meaningful value
	// here and nonsense for them. Staging a new host cold and enabling the
	// cache once it is validated is how this feature gets rolled out, and with
	// a scalar that intent would collapse into "unset" and silently inherit
	// the fleet default — which matters more on a rack than on rented
	// capacity, since the prototype box has a 256 GB disk that cannot hold the
	// fleet's normal quota at all.
	// +optional
	RunnerCacheVolumeGiB *int `json:"runnerCacheVolumeGiB,omitempty"`
}

// StaticAppleSiliconMachineStatus is the observed state of the Machine.
type StaticAppleSiliconMachineStatus struct {
	// HostAgentStatus carries the phase, terminal-failure fields and
	// host-config drift bookkeeping shared with the Scaleway macOS kind.
	HostAgentStatus `json:",inline"`

	// Ready is set to true once bootstrap has completed and tart-kubelet is
	// registering the Node. CAPI core reads this to mark the parent Machine
	// Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// RackHost is the name of the claimed RackHost, empty before the claim.
	// It is the Machine's half of the binding whose other half is that host's
	// `status.claimedBy`; the delete path releases exactly this host.
	// +optional
	RackHost string `json:"rackHost,omitempty"`

	// Addresses surfaces the host's address so kubectl describe and event
	// correlation can map back to a physical box.
	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// Conditions are CAPI-style condition entries (Provisioned, Bootstrapped).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=staticapplesiliconmachines,scope=Namespaced,categories=cluster-api,shortName=sasm
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="RackHost",type=string,JSONPath=".status.rackHost"
// +kubebuilder:printcolumn:name="ProviderID",type=string,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// StaticAppleSiliconMachine is one Mac mini we own, joined as a cluster Node.
type StaticAppleSiliconMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   StaticAppleSiliconMachineSpec   `json:"spec,omitempty"`
	Status StaticAppleSiliconMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// StaticAppleSiliconMachineList is a list of StaticAppleSiliconMachine.
type StaticAppleSiliconMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []StaticAppleSiliconMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&StaticAppleSiliconMachine{}, &StaticAppleSiliconMachineList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface.
func (m *StaticAppleSiliconMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *StaticAppleSiliconMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
