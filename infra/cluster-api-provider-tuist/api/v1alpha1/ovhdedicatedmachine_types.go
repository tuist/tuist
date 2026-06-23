package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// OVHDedicatedMachineSpec is the desired state of one OVHcloud dedicated
// (bare-metal) server backing a customer-facing Kura cache region. Like the
// Scaleway Elastic Metal kind it joins as an ordinary Linux worker Node via the
// provider-generated self-join cloud-init, and like the Apple Silicon kind it
// adopts a pre-ordered server rather than ordering one inline — OVH ordering is
// a multi-step cart/checkout flow, so the operator pre-orders capacity and the
// controller claims a free box by display-name prefix, then drives the OS
// install + self-join.
//
// Unlike Elastic Metal there is no Scaleway Private Network: a single
// customer-facing box serves public cache traffic over its public IP, so no
// VLAN bring-up happens (the shared self-join is rendered with VLAN 0). The
// private intra-region mesh over OVH vRack is a multi-box follow-up (VRackID).
type OVHDedicatedMachineSpec struct {
	// ProviderID, set by the controller after the self-join completes, takes
	// the shape `ovh://<datacenter>/<service-name>` — a foreign providerID host
	// (`ovh`) so the Hetzner CCM never reaps the node, the same guard the
	// Scaleway bare-metal kind uses. CAPI core expects this to populate, or the
	// parent Machine never goes Ready.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// Datacenter is the OVH region code the server lives in (e.g. `vin` for
	// Vint Hill VA, `hil` for Hillsboro OR, `gra`/`rbx` for the EU sites). Used
	// to scope adoption and to compose the providerID.
	// +kubebuilder:default=vin
	Datacenter string `json:"datacenter,omitempty"`

	// Offer is the OVH commercial range the controller restricts adoption to
	// (e.g. `advance-3`). Informational + an adoption filter so a fleet only
	// claims boxes of the intended shape; empty adopts any free pre-ordered box
	// under the prefix.
	// +optional
	Offer string `json:"offer,omitempty"`

	// OS is informational in the out-of-band install model: the operator installs
	// this image on the box before adoption (the controller never drives the OVH
	// install API). Retained to document the fleet's expected OS.
	// +kubebuilder:default=ubuntu_24.04
	OS string `json:"os,omitempty"`

	// AdoptDisplayNamePrefix is the OVH-side reverse-DNS prefix the controller
	// scans to claim a pre-ordered, operator-installed server for this Machine
	// (mirrors the Apple Silicon kind's adoptPoolPrefix). Required: without it
	// the controller has no pool to adopt from and OVH has no inline-order path.
	AdoptDisplayNamePrefix string `json:"adoptDisplayNamePrefix"`

	// FleetName groups Machines that share one SSH key, like the Apple Silicon
	// kind. Set by the MachineTemplate so every Machine the MachineDeployment
	// clones derives the SAME fleet key the operator authorizes on the
	// pre-ordered pool boxes; without it the per-Machine-name key would not match
	// a pre-ordered box (or a box re-adopted after a previous Machine released
	// it), so the bootstrap SSH would fail.
	// +optional
	FleetName string `json:"fleetName,omitempty"`

	// NodeTaints are passed to the kubelet's `--register-with-taints` in the
	// generated self-join. Customer-facing Kura regions leave this empty (the
	// region's nodeSelector + pool label do the placement); a dedicated-pool
	// taint can ride here when a region needs isolation.
	// +optional
	NodeTaints []corev1.Taint `json:"nodeTaints,omitempty"`

	// VRackID is the OVH vRack the server is attached to for the private
	// intra-region mesh. Unused at Qty-1 (a single public box needs no private
	// fabric); wired in the multi-box HA follow-up alongside the failover IP.
	// +optional
	VRackID string `json:"vRackID,omitempty"`

	// EgressBudgetMbps is the throughput, in Mbps, this box may assign across
	// the Kura pods it hosts — its NIC ceiling minus headroom. When set, the
	// controller advertises it as the Node's `tuist.dev/egress-mbps` extended
	// resource so the scheduler bin-packs cache pods by their assigned peak
	// throughput and never oversubscribes the box (the multi-box distribution
	// follow-up; the per-pod `kubernetes.io/egress-bandwidth` annotation is the
	// matching NIC-level enforcement). Zero leaves the resource unadvertised.
	// +optional
	EgressBudgetMbps int32 `json:"egressBudgetMbps,omitempty"`
}

// Bootstrap is provider-generated, identical in shape to the Scaleway bare-metal
// kind: the reconciler mints a kubelet token kubeconfig and renders the shared
// self-join script that installs kubelet and self-registers the node against the
// externally managed control plane. The OVH-specific differences the controller
// handles are adoption (claim a pre-ordered box by reverse-DNS prefix), the
// readiness wait (Status.Phase = AwaitingInstall until the operator-installed box
// reports a healthy state), and the install login user (with sudo). There is no
// PN-VLAN step — OVH delivers no Scaleway-style Private Network, so the self-join
// runs with VLAN 0.

// OVHDedicatedMachineStatus is the observed state of the Machine.
type OVHDedicatedMachineStatus struct {
	// Ready is true once the server has joined the cluster and its Node reports
	// Ready=True. CAPI core reads this to mark the parent Machine Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// ServiceName is the OVH-assigned dedicated-server service name (e.g.
	// `nsXXXXXX.ip-A-B-C.eu`), used for install polling, delete, and status.
	// +optional
	ServiceName string `json:"serviceName,omitempty"`

	// Addresses surfaces the server's public address + hostname for kubectl
	// describe / event correlation.
	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// Phase tracks lifecycle: Pending | Adopting | Installing | Provisioning |
	// Bootstrapping | Ready | Deleting | Failed. Operator-facing only; CAPI core
	// drives off Ready + Conditions.
	// +optional
	Phase string `json:"phase,omitempty"`

	// FailureReason / FailureMessage are set on terminal failures.
	// +optional
	FailureReason *string `json:"failureReason,omitempty"`
	// +optional
	FailureMessage *string `json:"failureMessage,omitempty"`

	// Conditions are CAPI-style condition entries (Provisioned, NodeReady).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`

	// BootstrapAttempts counts consecutive bootstrap failures on the current
	// server. Reset on a successful bootstrap or whenever the underlying
	// ServiceName changes.
	// +optional
	BootstrapAttempts int32 `json:"bootstrapAttempts,omitempty"`

	// BootstrapRebootIssued records that a recovery reboot has already been
	// triggered for the current server, so retries don't re-reboot it. Cleared
	// when the ServiceName changes or on successful bootstrap.
	// +optional
	BootstrapRebootIssued bool `json:"bootstrapRebootIssued,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=ovhdedicatedmachines,scope=Namespaced,categories=cluster-api,shortName=odm
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="ProviderID",type=string,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// OVHDedicatedMachine is one OVHcloud dedicated server in the cluster.
type OVHDedicatedMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   OVHDedicatedMachineSpec   `json:"spec,omitempty"`
	Status OVHDedicatedMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// OVHDedicatedMachineList is a list of OVHDedicatedMachine.
type OVHDedicatedMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []OVHDedicatedMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&OVHDedicatedMachine{}, &OVHDedicatedMachineList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface
// so the controller can use util/conditions helpers.
func (m *OVHDedicatedMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *OVHDedicatedMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
