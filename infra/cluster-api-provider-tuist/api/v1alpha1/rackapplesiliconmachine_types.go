package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackAppleSiliconMachineSpec is one Mac mini we own as a node. The RackHost
// controller creates it, and the CAPI Machine that owns it, for each RackHost.
//
// It is the adopt-only sibling of ScalewayAppleSiliconMachine: same host
// bootstrap, same host-config drift loop, same tailnet egress Service, but the
// host is a RackHost in the cluster's own inventory rather than a server from
// a provider's list, and there is no order, no reinstall and no release path,
// because nobody bills us per host and no API can wipe one.
type RackAppleSiliconMachineSpec struct {
	// ProviderID takes the shape `rack-applesilicon://<site>/<serial>`;
	// composed from the two durable physical facts, so re-cabling a host to a
	// new address does not change its identity to CAPI. CAPI core expects this
	// to populate; without it the parent Machine never goes Ready. The scheme
	// is deliberately foreign to the Hetzner CCM so it never reaps the node,
	// the same guard every other kind here uses.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// Host is the RackHost this machine is.
	// +optional
	Host string `json:"host,omitempty"`

	// FleetName groups Machines that share an SSH key and a sudo password: the
	// operator's `--rackhost-fleet-name`. Unlike the Scaleway fleets, the
	// keypair is NOT minted in-cluster: rack hosts are provisioned out of band
	// by MDM, which authorizes a key the operator never generated, so the
	// fleet Secret is synced from 1Password by ESO and the controller only
	// ever reads it.
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

	// HostMemoryMB is the memory advertised on the Node: the box's RAM minus
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
	// as guests x 2 + 1: a Pod stays bound to its Node after it finishes and the
	// scheduler counts it against pods capacity until GC deletes it, so each
	// guest slot can transiently hold its running Pod plus a predecessor, and
	// the +1 is margin. It is not the concurrent-VM limit; Apple's cap of two is
	// enforced by Tart. Falls back to the operator's global default when unset.
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
	// the fleet default, which matters more on a rack than on rented
	// capacity, since the prototype box has a 256 GB disk that cannot hold the
	// fleet's normal quota at all.
	// +optional
	RunnerCacheVolumeGiB *int `json:"runnerCacheVolumeGiB,omitempty"`
}

// RackAppleSiliconMachineStatus is the observed state of the Machine.
type RackAppleSiliconMachineStatus struct {
	// HostAgentStatus carries the phase, terminal-failure fields and
	// host-config drift bookkeeping shared with the Scaleway macOS kind.
	HostAgentStatus `json:",inline"`

	// Ready is set to true once bootstrap has completed and tart-kubelet is
	// registering the Node. CAPI core reads this to mark the parent Machine
	// Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

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
// +kubebuilder:resource:path=rackapplesiliconmachines,scope=Namespaced,categories=cluster-api,shortName=rasm
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="Host",type=string,JSONPath=".spec.host"
// +kubebuilder:printcolumn:name="ProviderID",type=string,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RackAppleSiliconMachine is one Mac mini we own, joined as a cluster Node.
type RackAppleSiliconMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackAppleSiliconMachineSpec   `json:"spec,omitempty"`
	Status RackAppleSiliconMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackAppleSiliconMachineList is a list of RackAppleSiliconMachine.
type RackAppleSiliconMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackAppleSiliconMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackAppleSiliconMachine{}, &RackAppleSiliconMachineList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface.
func (m *RackAppleSiliconMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *RackAppleSiliconMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
