package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// RackLinuxHostSpec is one x86 Linux machine we own, in a rack we operate. The
// host joins the tailnet by itself from its install, netbooted or from a
// stick, so it is found by its name and tags rather than dialled at an
// address.
type RackLinuxHostSpec struct {
	// Pool is the claim marker and the environment boundary: a
	// RackLinuxMachine claims a free host whose pool equals its adoptPool.
	// +optional
	Pool string `json:"pool,omitempty"`

	// Role decides the disk layout the install lays down and which
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

	// BootMAC is the MAC address of the NIC the host netboots from, on the rack's
	// management segment. The operator publishes an install for it while the
	// host is not on the tailnet, and when the tuist.dev/reinstall annotation
	// requests one. An edge host runs the netboot server, so it is installed
	// from a stick instead.
	// +kubebuilder:validation:Pattern=`^([0-9a-f]{2}:){5}[0-9a-f]{2}$`
	// +optional
	BootMAC string `json:"bootMAC,omitempty"`

	// AMT is what the operator does with the host's Intel AMT, which shares
	// the management port and can power-cycle a host whose OS is gone.
	// +optional
	AMT *RackLinuxHostAMT `json:"amt,omitempty"`
}

// RackLinuxHostAMT is what the operator does with a host's Intel AMT.
type RackLinuxHostAMT struct {
	// Activate has the operator activate AMT in admin control mode, with the
	// fleet's provisioning certificate and an admin password it generates
	// and keeps in the Secret <host>-amt. Turning it off does not deactivate
	// AMT.
	// +optional
	Activate bool `json:"activate,omitempty"`

	// Address is the static IPv4 address, with its prefix length, the
	// operator gives activated AMT on the management segment, so AMT keeps
	// one address whatever happens to the host. Unset, AMT takes one by DHCP.
	// +kubebuilder:validation:Pattern=`^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$`
	// +optional
	Address string `json:"address,omitempty"`

	// Gateway is the segment's gateway, which a static address needs.
	// +kubebuilder:validation:Pattern=`^([0-9]{1,3}\.){3}[0-9]{1,3}$`
	// +optional
	Gateway string `json:"gateway,omitempty"`
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

	// Install is the install published for the host to netboot, until a new
	// tailnet device shows it has run.
	// +optional
	Install *RackLinuxHostInstallStatus `json:"install,omitempty"`

	// AMT is the host's Intel AMT as rpc reports it on the host.
	// +optional
	AMT *RackLinuxHostAMTStatus `json:"amt,omitempty"`

	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// RackLinuxHostInstallStatus is one published install.
type RackLinuxHostInstallStatus struct {
	// KeyID is the ID of the single-use join key the install carries.
	KeyID string `json:"keyID"`

	// BootMAC is the MAC address the install is published for.
	BootMAC string `json:"bootMAC"`

	// PreviousDeviceID is the host's tailnet device when the install was
	// published; a different device is the install having run.
	// +optional
	PreviousDeviceID string `json:"previousDeviceID,omitempty"`

	OfferedAt metav1.Time `json:"offeredAt"`

	// ExpiresAt is when the join key expires; an install still needed then is
	// published again with a new key.
	ExpiresAt metav1.Time `json:"expiresAt"`

	// TriggeredAt is when the operator set the running host to netboot once
	// and rebooted it, for a requested reinstall.
	// +optional
	TriggeredAt *metav1.Time `json:"triggeredAt,omitempty"`
}

// RackLinuxHostAMTStatus is the host's Intel AMT.
type RackLinuxHostAMTStatus struct {
	// ControlMode is AMT's activation state: pre-provisioning, client or
	// admin.
	// +optional
	ControlMode string `json:"controlMode,omitempty"`

	// Version is the AMT firmware's.
	// +optional
	Version string `json:"version,omitempty"`

	// Link is the wired link AMT sees on the management port: up or down.
	// +optional
	Link string `json:"link,omitempty"`

	// Address is AMT's own IPv4 address on the management port.
	// +optional
	Address string `json:"address,omitempty"`

	// ObservedAt is when the operator last read AMT's state.
	// +optional
	ObservedAt *metav1.Time `json:"observedAt,omitempty"`

	// LastActivation is when the operator last tried to activate AMT.
	// +optional
	LastActivation *metav1.Time `json:"lastActivation,omitempty"`

	// ActivationError is why that attempt failed.
	// +optional
	ActivationError string `json:"activationError,omitempty"`

	// MEBxPasswordSet reports that the operator replaced MEBx's factory
	// password with the one it keeps in the host's AMT Secret.
	// +optional
	MEBxPasswordSet bool `json:"mebxPasswordSet,omitempty"`

	// LastConfiguration is when the operator last configured activated AMT
	// (its MEBx password, its address), and ConfigurationError why that
	// failed.
	// +optional
	LastConfiguration *metav1.Time `json:"lastConfiguration,omitempty"`

	// +optional
	ConfigurationError string `json:"configurationError,omitempty"`

	// LastPowerAction is the last power change the operator asked AMT for.
	// +optional
	LastPowerAction *RackLinuxHostAMTPowerAction `json:"lastPowerAction,omitempty"`
}

// RackLinuxHostAMTPowerAction is one power change asked of a host's AMT.
type RackLinuxHostAMTPowerAction struct {
	// Action is the tuist.dev/amt-power value: on, off, cycle or reset.
	Action string `json:"action"`

	// At is when the operator asked.
	At metav1.Time `json:"at"`

	// Via is the host whose SSH session reached AMT.
	// +optional
	Via string `json:"via,omitempty"`

	// Error is why the change was not made.
	// +optional
	Error string `json:"error,omitempty"`
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
// +kubebuilder:printcolumn:name="Install",type=string,priority=1,JSONPath=".status.install.keyID"
// +kubebuilder:printcolumn:name="AMT",type=string,priority=1,JSONPath=".status.amt.controlMode"
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
