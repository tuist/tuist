package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// RackLinuxCandidateSpec is empty: a candidate is only what a machine
// announced about itself.
type RackLinuxCandidateSpec struct{}

// RackLinuxCandidateNIC is one network port a machine announced.
type RackLinuxCandidateNIC struct {
	// MAC is the port's MAC address.
	MAC string `json:"mac"`

	// Driver is the Linux driver bound to the port, such as igc or i40e.
	// +optional
	Driver string `json:"driver,omitempty"`

	// PCIDevice is the port's PCI device ID, such as 0x125b for an i226-LM.
	// +optional
	PCIDevice string `json:"pciDevice,omitempty"`
}

// RackLinuxCandidateStatus is what a machine's install stick announced to a
// rack's boot server while no install was published for it.
type RackLinuxCandidateStatus struct {
	// UUID is the machine's SMBIOS UUID, which is also the candidate's name.
	UUID string `json:"uuid"`

	// Serial is the machine's SMBIOS serial number, as printed on its label.
	// +optional
	Serial string `json:"serial,omitempty"`

	// Product is the machine's SMBIOS vendor and product name.
	// +optional
	Product string `json:"product,omitempty"`

	// NICs are the machine's network ports.
	// +optional
	NICs []RackLinuxCandidateNIC `json:"nics,omitempty"`

	// BootMAC is the MAC to declare as the host's bootMAC: its i226-LM, the port
	// on the management switch that carries AMT.
	// +optional
	BootMAC string `json:"bootMAC,omitempty"`

	// EK is its TPM's RSA endorsement key, base64 PKIX DER, and
	// EKFingerprint the key's SHA-256.
	// +optional
	EK string `json:"ek,omitempty"`
	// +optional
	EKFingerprint string `json:"ekFingerprint,omitempty"`

	// Site is the site of the edge whose boot server heard it.
	// +optional
	Site string `json:"site,omitempty"`

	// SeenBy is the edge whose boot server heard it last.
	// +optional
	SeenBy string `json:"seenBy,omitempty"`

	// Address is the address it announced from.
	// +optional
	Address string `json:"address,omitempty"`

	// FirstSeen and LastSeen bound its announcements.
	// +optional
	FirstSeen *metav1.Time `json:"firstSeen,omitempty"`
	// +optional
	LastSeen *metav1.Time `json:"lastSeen,omitempty"`

	// DeclaredAs is the hostname of the RackLinuxHost named after its UUID.
	// +optional
	DeclaredAs string `json:"declaredAs,omitempty"`

	// Conflict is the last announcement under the same UUID that did not
	// match what the machine first announced. What a machine announced first
	// is kept: the RackLinuxHost declaring the UUID takes its hardware from a
	// candidate only while it has no conflict.
	// +optional
	Conflict *RackLinuxCandidateConflict `json:"conflict,omitempty"`
}

// RackLinuxCandidateConflict is an announcement that did not match what the
// machine first announced.
type RackLinuxCandidateConflict struct {
	// Reason is what it announced differently.
	Reason string `json:"reason"`

	// Address is the address it came from, and SeenBy the edge that heard it.
	// +optional
	Address string `json:"address,omitempty"`
	// +optional
	SeenBy string `json:"seenBy,omitempty"`

	// At is when it came.
	At metav1.Time `json:"at"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=racklinuxcandidates,scope=Namespaced,categories=cluster-api,shortName=rlc
// +kubebuilder:printcolumn:name="Serial",type=string,JSONPath=".status.serial"
// +kubebuilder:printcolumn:name="BootMAC",type=string,JSONPath=".status.bootMAC"
// +kubebuilder:printcolumn:name="DeclaredAs",type=string,JSONPath=".status.declaredAs"
// +kubebuilder:printcolumn:name="LastSeen",type="date",JSONPath=".status.lastSeen"
// +kubebuilder:printcolumn:name="Conflict",type=string,JSONPath=".status.conflict.reason"
// +kubebuilder:printcolumn:name="Site",type=string,priority=1,JSONPath=".status.site"
// +kubebuilder:printcolumn:name="Product",type=string,priority=1,JSONPath=".status.product"
// +kubebuilder:printcolumn:name="SeenBy",type=string,priority=1,JSONPath=".status.seenBy"

// RackLinuxCandidate is a machine on a rack's management segment as its install
// stick announced it, named after its SMBIOS UUID: a box to declare in
// rackLinuxFleet.hosts by that UUID, rather than one whose MAC someone reads
// off its label. The RackLinuxHost declaring it takes its boot MAC and model
// from it. The operator keeps it from the stick's announcements, and drops an
// undeclared one after a week without one.
type RackLinuxCandidate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackLinuxCandidateSpec   `json:"spec,omitempty"`
	Status RackLinuxCandidateStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackLinuxCandidateList is a list of RackLinuxCandidate.
type RackLinuxCandidateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackLinuxCandidate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackLinuxCandidate{}, &RackLinuxCandidateList{})
}
