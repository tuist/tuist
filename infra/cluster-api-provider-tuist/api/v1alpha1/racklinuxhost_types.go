package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackLinuxHostSpec is one x86 Linux machine we own, in a rack we operate. The
// host joins the tailnet by itself from its install stick, so it is found by
// its name and tags rather than dialled at an address.
type RackLinuxHostSpec struct {
	// Pool is the claim marker and the environment boundary: a
	// RackLinuxMachine claims a free host whose pool equals its adoptPool.
	// +optional
	Pool string `json:"pool,omitempty"`

	// Role decides the disk layout the install stick lays down and which
	// MachineDeployment claims the host.
	// +kubebuilder:validation:Enum=edge;services;storage
	// +optional
	Role string `json:"role,omitempty"`

	// Location is where the box is. `site` composes the providerID.
	// +optional
	Location RackHostLocation `json:"location,omitempty"`

	// SSHUser is the account the install creates, with the rack's fleet key
	// and passwordless sudo.
	// +kubebuilder:default=tuist
	SSHUser string `json:"sshUser,omitempty"`

	// Tailnet is the identity the host joins the tailnet as.
	// +optional
	Tailnet RackLinuxHostTailnet `json:"tailnet,omitempty"`
}

// RackLinuxHostTailnet is the identity a host's install key joins it as.
type RackLinuxHostTailnet struct {
	// Tags the host's device must carry, the tags its install key is minted
	// with. A device with the host's name and without all of them is not this
	// host.
	// +optional
	Tags []string `json:"tags,omitempty"`
}

// RackLinuxHostStatus is the observed state of one host.
type RackLinuxHostStatus struct {
	// ClaimedBy is the RackLinuxMachine holding this host.
	// +optional
	ClaimedBy string `json:"claimedBy,omitempty"`

	// ClaimedAt is when the current claim was taken.
	// +optional
	ClaimedAt *metav1.Time `json:"claimedAt,omitempty"`

	// Tailnet is the host's current tailnet device. Every install registers a
	// new device, so a new deviceID means the box was reinstalled.
	// +optional
	Tailnet *RackLinuxHostTailnetStatus `json:"tailnet,omitempty"`

	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// RackLinuxHostTailnetStatus is one tailnet device.
type RackLinuxHostTailnetStatus struct {
	// DeviceID is the Tailscale device ID.
	// +optional
	DeviceID string `json:"deviceID,omitempty"`

	// Name is the device's MagicDNS name.
	// +optional
	Name string `json:"name,omitempty"`

	// Address is the device's tailnet IPv4 address: what the operator dials
	// and what the kubelet advertises as the node's InternalIP.
	// +optional
	Address string `json:"address,omitempty"`

	// Connected reports whether the device is connected to the tailnet now.
	// +optional
	Connected bool `json:"connected,omitempty"`

	// Created is when the device registered.
	// +optional
	Created *metav1.Time `json:"created,omitempty"`

	// LastSeen is when the device was last connected.
	// +optional
	LastSeen *metav1.Time `json:"lastSeen,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=racklinuxhosts,scope=Namespaced,categories=cluster-api,shortName=rlh
// +kubebuilder:printcolumn:name="Pool",type=string,JSONPath=".spec.pool"
// +kubebuilder:printcolumn:name="Role",type=string,JSONPath=".spec.role"
// +kubebuilder:printcolumn:name="Tailnet",type=string,JSONPath=".status.tailnet.address"
// +kubebuilder:printcolumn:name="Connected",type=boolean,JSONPath=".status.tailnet.connected"
// +kubebuilder:printcolumn:name="ClaimedBy",type=string,JSONPath=".status.claimedBy"
// +kubebuilder:printcolumn:name="Site",type=string,priority=1,JSONPath=".spec.location.site"
// +kubebuilder:printcolumn:name="Device",type=string,priority=1,JSONPath=".status.tailnet.deviceID"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"

// RackLinuxHost is one x86 Linux machine in a rack we operate.
type RackLinuxHost struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   RackLinuxHostSpec   `json:"spec,omitempty"`
	Status RackLinuxHostStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// RackLinuxHostList is a list of RackLinuxHost.
type RackLinuxHostList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackLinuxHost `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackLinuxHost{}, &RackLinuxHostList{})
}

func (h *RackLinuxHost) GetConditions() clusterv1.Conditions {
	return h.Status.Conditions
}

func (h *RackLinuxHost) SetConditions(c clusterv1.Conditions) {
	h.Status.Conditions = c
}
