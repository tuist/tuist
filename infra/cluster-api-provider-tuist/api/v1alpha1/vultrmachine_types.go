package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// VultrMachineSpec is the desired state of one Vultr bare-metal server backing
// a customer-facing Kura cache region. It joins as an ordinary Linux worker Node
// via the provider-generated self-join cloud-init, and it adopts a pre-ordered
// server rather than ordering one inline, like the OVH and Dedibox kinds.
//
// Vultr is here because South America has no OVH, Scaleway or Hetzner presence,
// and it differs from the other Linux kinds in two ways that shape this type.
//
// Adoption is by TAG, not by a name prefix. `GET /v2/bare-metals` filters
// server-side on label, tag and region, but the label filter matches exactly:
// querying the label `tuist-kura-vultr-production` returns nothing for a box
// labelled `tuist-kura-vultr-production-sa-west`. So there is no server-side
// equivalent of the OVH displayName prefix, and the fleet marker is a tag, which
// is the Dedibox shape.
//
// The install cannot produce the disk layout. Vultr exposes no partitioning
// control and its installer offers only RAID 1 across both disks or no RAID,
// neither of which is the mirrored root plus separate XFS /data the cluster
// gates on. The box is therefore converted after install, which is a lifecycle
// stage the other kinds do not have. See docs/vultr-baremetal-support.md.
type VultrMachineSpec struct {
	// ProviderID, set by the controller after the self-join completes, takes the
	// shape `vultr://<region>/<instance-id>`. A foreign providerID host
	// (`vultr`) so the Hetzner CCM never reaps the node, the same guard the other
	// bare-metal kinds use. CAPI core expects this to populate, or the parent
	// Machine never goes Ready.
	// +optional
	ProviderID *string `json:"providerID,omitempty"`

	// Region is the Vultr region code the server lives in (`scl` for Santiago).
	// Scopes adoption and composes the providerID.
	// +kubebuilder:default=scl
	Region string `json:"region,omitempty"`

	// Plan is the Vultr bare-metal plan adoption is restricted to (e.g.
	// `vbm-6c-32gb-amd`), so a fleet only claims boxes of the intended shape.
	// Empty adopts any free box carrying the tag in the region. Worth setting:
	// the plans differ in whether their disks are NVMe or SSD, and the cache
	// wants NVMe.
	// +optional
	Plan string `json:"plan,omitempty"`

	// OSID is the Vultr numeric OS id the controller reinstalls with (2284 is
	// Ubuntu 24.04 LTS x64). Numeric rather than a label because the reinstall
	// endpoint takes no OS argument at all: it reinstalls whatever the box
	// already carries, so this records what the pool was ordered with and lets
	// the controller refuse a box that does not match.
	// +kubebuilder:default=2284
	OSID int32 `json:"osID,omitempty"`

	// AdoptTag is the tag a pre-ordered server must carry for the controller to
	// claim it for this fleet. It is the ENVIRONMENT BOUNDARY: one Vultr account
	// holds every env's boxes and region+plan repeat across envs, so this marker,
	// set by prep as its final step, is what keeps a staging fleet from adopting
	// a prod box. Enforced as required by the fleet helm template rather than the
	// CRD: a required CRD field breaks helm rollbacks to revisions predating it.
	// +optional
	AdoptTag string `json:"adoptTag,omitempty"`

	// FleetName groups Machines that share one SSH key. Set by the MachineTemplate
	// so every Machine the MachineDeployment clones derives the SAME fleet key the
	// operator authorized on the pre-ordered pool boxes; without it the
	// per-Machine-name key would not match a pre-ordered box, and the bootstrap
	// SSH would fail.
	// +optional
	FleetName string `json:"fleetName,omitempty"`

	// NodeTaints are passed to the kubelet's `--register-with-taints` in the
	// generated self-join. Cache regions leave this empty; the region's
	// nodeSelector and pool label do the placement.
	// +optional
	NodeTaints []corev1.Taint `json:"nodeTaints,omitempty"`

	// EgressBudgetMbps is the throughput, in Mbps, this box may assign across the
	// Kura pods it hosts. When set, the controller advertises it as the Node's
	// `tuist.dev/egress-mbps` extended resource so the scheduler bin-packs cache
	// pods by assigned peak throughput and never oversubscribes the box. Zero
	// leaves the resource unadvertised.
	//
	// Unlike OVH there is no discovery path: Vultr exposes no per-box egress
	// reading, and what actually binds is the plan's monthly transfer quota (10 TB
	// on vbm-6c-32gb-amd) rather than the 25 Gbit/s the NIC links at. So this is
	// always the configured value.
	// +optional
	EgressBudgetMbps int32 `json:"egressBudgetMbps,omitempty"`
}

// VultrMachineStatus is the observed state of the Machine.
type VultrMachineStatus struct {
	// Ready is true once the server has joined the cluster and its Node reports
	// Ready=True. CAPI core reads this to mark the parent Machine Ready.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// InstanceID is the Vultr-assigned bare-metal id (a UUID), used for install
	// polling, the conversion, release and status.
	// +optional
	InstanceID string `json:"instanceID,omitempty"`

	// Addresses surfaces the server's public address and hostname for kubectl
	// describe and event correlation.
	// +optional
	Addresses []clusterv1.MachineAddress `json:"addresses,omitempty"`

	// Phase tracks lifecycle: Pending | Adopting | Installing | Converting |
	// Provisioning | Bootstrapping | Ready | Deleting | Failed. Operator-facing
	// only; CAPI core drives off Ready and Conditions.
	//
	// Converting has no counterpart in the other Linux kinds. It is where the box
	// is given the mirrored-root-plus-XFS-/data layout the install cannot produce.
	// +optional
	Phase string `json:"phase,omitempty"`

	// Converted records that this box has been through the disk conversion and
	// its /data can carry project quotas. Keyed by InstanceID so a machine that
	// moves to another box, or a box that has since been reinstalled, is never
	// credited with its predecessor's conversion.
	// +optional
	Converted *ConversionStatus `json:"converted,omitempty"`

	// FailureReason / FailureMessage are set on terminal failures.
	// +optional
	FailureReason *string `json:"failureReason,omitempty"`
	// +optional
	FailureMessage *string `json:"failureMessage,omitempty"`

	// Conditions are CAPI-style condition entries (Provisioned, NodeReady).
	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`

	// BootstrapAttempts counts consecutive bootstrap failures on the current
	// server. Reset on a successful bootstrap or whenever InstanceID changes.
	// +optional
	BootstrapAttempts int32 `json:"bootstrapAttempts,omitempty"`

	// BootstrapRebootIssued records that a recovery reboot has already been
	// triggered for the current server, so retries do not re-reboot it. Cleared
	// when InstanceID changes or on a successful bootstrap.
	// +optional
	BootstrapRebootIssued bool `json:"bootstrapRebootIssued,omitempty"`
}

// ConversionStatus is the disk conversion the box was last put through.
type ConversionStatus struct {
	// InstanceID is the box this status describes. A status recorded against
	// another box is discarded, so a re-adopted machine is never credited with
	// its predecessor's conversion.
	InstanceID string `json:"instanceID"`

	// DataDevice is the leg handed to /data, and DataFilesystem what it was
	// formatted as. Recorded so an operator can see which disk the cache lives on
	// without reaching the box.
	// +optional
	DataDevice string `json:"dataDevice,omitempty"`
	// +optional
	DataFilesystem string `json:"dataFilesystem,omitempty"`

	// QuotaEnforced is whether /data came back as a separate XFS filesystem
	// mounted with project quotas. False means the box will host cache volumes
	// that nothing bounds, which is the condition the self-join refuses on.
	// +optional
	QuotaEnforced bool `json:"quotaEnforced,omitempty"`

	// ConvertedAt is when the conversion last completed; AttemptedAt the last
	// attempt, successful or not, which bounds the next one.
	// +optional
	ConvertedAt *metav1.Time `json:"convertedAt,omitempty"`
	// +optional
	AttemptedAt *metav1.Time `json:"attemptedAt,omitempty"`

	// Attempts counts consecutive failed conversions on this box. Reset on
	// success.
	// +optional
	Attempts int32 `json:"attempts,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=vultrmachines,scope=Namespaced,categories=cluster-api,shortName=vum
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="ProviderID",type=string,JSONPath=".spec.providerID"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"
// +kubebuilder:printcolumn:name="Quota",type=boolean,JSONPath=".status.converted.quotaEnforced"
// +kubebuilder:printcolumn:name="Data",type=string,JSONPath=".status.converted.dataDevice",priority=1
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// VultrMachine is one Vultr bare-metal server in the cluster.
type VultrMachine struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   VultrMachineSpec   `json:"spec,omitempty"`
	Status VultrMachineStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// VultrMachineList is a list of VultrMachine.
type VultrMachineList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []VultrMachine `json:"items"`
}

func init() {
	SchemeBuilder.Register(&VultrMachine{}, &VultrMachineList{})
}

// GetConditions / SetConditions implement the CAPI conditions.Setter interface
// so the controller can use util/conditions helpers.
func (m *VultrMachine) GetConditions() clusterv1.Conditions {
	return m.Status.Conditions
}

func (m *VultrMachine) SetConditions(c clusterv1.Conditions) {
	m.Status.Conditions = c
}
