package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// Provisioning states of a RackLinuxHost.
const (
	// RackLinuxHostRegistering is a host declared but not yet on the tailnet,
	// with no install the operator can publish for it.
	RackLinuxHostRegistering = "Registering"
	// RackLinuxHostProvisioning is a host with an install published for it
	// that it has not run yet.
	RackLinuxHostProvisioning = "Provisioning"
	// RackLinuxHostProvisioned is a host on the tailnet running the install
	// its reinstallGeneration asks for.
	RackLinuxHostProvisioned = "Provisioned"
	// RackLinuxHostDeprovisioning is a deleted host being retired.
	RackLinuxHostDeprovisioning = "Deprovisioning"
)

// RackLinuxHostSpec is one x86 Linux machine we own, in a rack we operate. It
// is named after the machine's SMBIOS UUID, so the object is the box whatever
// it is called; the name it runs under is spec.hostname. The host joins the
// tailnet by itself from its install, netbooted or from a stick, and the
// operator makes it a node through the CAPI Machine it keeps for it.
type RackLinuxHostSpec struct {
	// Hostname is the name the host runs under: its operating system's, its
	// tailnet device's and its Node's. Changing it rejoins the host under the
	// new name.
	// +kubebuilder:validation:Pattern=`^[a-z0-9]([-a-z0-9]{0,61}[a-z0-9])?$`
	Hostname string `json:"hostname"`

	// Role decides the disk layout the install lays down.
	// +kubebuilder:validation:Enum=edge;services;storage
	Role string `json:"role"`

	// Location is where the box is. `site` composes the providerID.
	Location RackHostLocation `json:"location"`

	// SSHUser is the account the install creates, with the rack's fleet key
	// and passwordless sudo.
	// +kubebuilder:default=tuist
	SSHUser string `json:"sshUser,omitempty"`

	// Tailnet is the identity the host joins the tailnet as.
	Tailnet RackLinuxHostTailnet `json:"tailnet"`

	// BootMAC is the MAC address of the NIC the host netboots from, on the
	// rack's management segment. Unset, the operator takes the one the
	// machine announced as its management port (status.bootMAC).
	// +kubebuilder:validation:Pattern=`^([0-9a-f]{2}:){5}[0-9a-f]{2}$`
	// +optional
	BootMAC string `json:"bootMAC,omitempty"`

	// Node is what the host's Node registers with.
	// +optional
	Node RackLinuxHostNode `json:"node,omitempty"`

	// Online is whether the host should be powered on. The operator powers it
	// on or off through AMT to match.
	// +kubebuilder:default=true
	Online bool `json:"online"`

	// ReinstallGeneration reinstalls the host whenever it is raised above
	// status.provisioning.installedGeneration, which records the generation
	// the host's current install ran for.
	// +kubebuilder:validation:Minimum=0
	// +optional
	ReinstallGeneration int64 `json:"reinstallGeneration,omitempty"`

	// AMT is what the operator does with the host's Intel AMT, which shares
	// the management port and can power a host whose OS is gone.
	// +optional
	AMT RackLinuxHostAMT `json:"amt,omitempty"`
}

// RackLinuxHostNode is what a rack host's Node registers with.
type RackLinuxHostNode struct {
	// Labels are registered on top of the labels every rack Linux node
	// carries.
	// +optional
	Labels map[string]string `json:"labels,omitempty"`

	// Taints are registered with the Node.
	// +optional
	Taints []corev1.Taint `json:"taints,omitempty"`
}

// RackLinuxHostAMT is what the operator does with a host's Intel AMT.
type RackLinuxHostAMT struct {
	// Activate has the operator activate AMT in admin control mode, with the
	// fleet's provisioning certificate and an admin password it generates and
	// keeps in the Secret <name>-amt. Unset, the operator activates the AMT of
	// the hardware models the fleet lists (--rack-linux-amt-products).
	// Turning it off does not deactivate AMT.
	// +optional
	Activate *bool `json:"activate,omitempty"`

	// Address is the static IPv4 address, with its prefix length, the
	// operator gives activated AMT on the management segment, so AMT keeps
	// one address whatever happens to the host. Unset, the operator takes
	// one from the fleet's AMT address range.
	// +kubebuilder:validation:Pattern=`^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$`
	// +optional
	Address string `json:"address,omitempty"`

	// Gateway is the segment's gateway, which a static address needs. Unset,
	// the fleet's is used.
	// +kubebuilder:validation:Pattern=`^([0-9]{1,3}\.){3}[0-9]{1,3}$`
	// +optional
	Gateway string `json:"gateway,omitempty"`
}

// RackLinuxHostTailnet is the identity a host's install key joins it as.
type RackLinuxHostTailnet struct {
	// Tags the host's device must carry, the tags its install key is minted
	// with. A device with the host's hostname and without all of them is not
	// this host.
	// +kubebuilder:validation:MinItems=1
	Tags []string `json:"tags"`
}

// RackLinuxHostStatus is the observed state of one host.
type RackLinuxHostStatus struct {
	// BootMAC is the boot MAC in effect: spec.bootMAC, or the management port
	// the machine announced.
	// +optional
	BootMAC string `json:"bootMAC,omitempty"`

	// Hardware is what the machine announced about itself.
	// +optional
	Hardware *RackLinuxHostHardware `json:"hardware,omitempty"`

	// Provisioning is where the host is in its life: registering,
	// provisioning an install, provisioned, or deprovisioning.
	// +optional
	Provisioning RackLinuxHostProvisioningStatus `json:"provisioning,omitempty"`

	// Tailnet is the host's current tailnet device. Every install registers a
	// new device, so a new deviceID means the box was reinstalled.
	// +optional
	Tailnet *RackLinuxHostTailnetStatus `json:"tailnet,omitempty"`

	// Install is the install published for the host, until a new tailnet
	// device shows it has run.
	// +optional
	Install *RackLinuxHostInstallStatus `json:"install,omitempty"`

	// Power is the host's power state as AMT reports it.
	// +optional
	Power *RackLinuxHostPowerStatus `json:"power,omitempty"`

	// AMT is the host's Intel AMT as rpc reports it on the host.
	// +optional
	AMT *RackLinuxHostAMTStatus `json:"amt,omitempty"`

	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// RackLinuxHostHardware is what a machine announced about itself.
type RackLinuxHostHardware struct {
	// Product is the machine's SMBIOS vendor and product name.
	// +optional
	Product string `json:"product,omitempty"`

	// Serial is the machine's SMBIOS serial number.
	// +optional
	Serial string `json:"serial,omitempty"`
}

// RackLinuxHostProvisioningStatus is where a host is in its life.
type RackLinuxHostProvisioningStatus struct {
	// State is Registering, Provisioning, Provisioned or Deprovisioning.
	// +optional
	State string `json:"state,omitempty"`

	// InstalledGeneration is the reinstallGeneration the host's current
	// install ran for.
	// +optional
	InstalledGeneration int64 `json:"installedGeneration,omitempty"`

	// Message says what the host is waiting for.
	// +optional
	Message string `json:"message,omitempty"`

	// LastTransitionTime is when State last changed.
	// +optional
	LastTransitionTime *metav1.Time `json:"lastTransitionTime,omitempty"`
}

// RackLinuxHostInstallStatus is one published install.
type RackLinuxHostInstallStatus struct {
	// KeyID is the ID of the single-use join key the install carries.
	KeyID string `json:"keyID"`

	// BootMAC is the MAC address the install is published for.
	BootMAC string `json:"bootMAC"`

	// Generation is the reinstallGeneration the install is for.
	// +optional
	Generation int64 `json:"generation,omitempty"`

	// PreviousDeviceID is the host's tailnet device when the install was
	// published; a different device is the install having run.
	// +optional
	PreviousDeviceID string `json:"previousDeviceID,omitempty"`

	OfferedAt metav1.Time `json:"offeredAt"`

	// ExpiresAt is when the join key expires; an install still needed then is
	// published again with a new key.
	ExpiresAt metav1.Time `json:"expiresAt"`

	// HostKeyFingerprint is the SHA-256 fingerprint of the SSH host key the
	// install gives the host, which the operator trusts the new install by.
	// +optional
	HostKeyFingerprint string `json:"hostKeyFingerprint,omitempty"`

	// ServableAt is when a boot server holding the site's provisioning address
	// first served the install's boot script.
	// +optional
	ServableAt *metav1.Time `json:"servableAt,omitempty"`

	// ServedAt is when a boot server handed the install's seed out, which it
	// does once, to the machine whose DHCP lease is on one of the host's
	// NICs.
	// +optional
	ServedAt *metav1.Time `json:"servedAt,omitempty"`

	// ServedTo is the address and MAC the seed went to.
	// +optional
	ServedTo string `json:"servedTo,omitempty"`

	// TriggeredAt is when the operator rebooted the host into the install.
	// +optional
	TriggeredAt *metav1.Time `json:"triggeredAt,omitempty"`
}

// RackLinuxHostPowerStatus is a host's power state as AMT reports it.
type RackLinuxHostPowerStatus struct {
	// State is On or Off.
	// +optional
	State string `json:"state,omitempty"`

	// ObservedAt is when AMT reported it.
	// +optional
	ObservedAt *metav1.Time `json:"observedAt,omitempty"`
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

	// AssignedAddress is the static address the operator gives AMT, with its
	// prefix length: spec.amt.address, or one from the fleet's range.
	// +optional
	AssignedAddress string `json:"assignedAddress,omitempty"`

	// UUID is the machine's SMBIOS UUID as AMT reports it.
	// +optional
	UUID string `json:"uuid,omitempty"`

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
	// Action is on, off, or a tuist.dev/reboot value: cycle, reset or pxe.
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
// +kubebuilder:validation:XValidation:rule="self.metadata.name.matches('^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')",message="a RackLinuxHost is named after the machine's SMBIOS UUID, in lowercase"
// +kubebuilder:validation:XValidation:rule="self.spec.location.site != ''",message="spec.location.site is required; it composes the providerID"
// +kubebuilder:printcolumn:name="Hostname",type=string,JSONPath=".spec.hostname"
// +kubebuilder:printcolumn:name="Role",type=string,JSONPath=".spec.role"
// +kubebuilder:printcolumn:name="State",type=string,JSONPath=".status.provisioning.state"
// +kubebuilder:printcolumn:name="Tailnet",type=string,JSONPath=".status.tailnet.address"
// +kubebuilder:printcolumn:name="Connected",type=boolean,JSONPath=".status.tailnet.connected"
// +kubebuilder:printcolumn:name="Power",type=string,JSONPath=".status.power.state"
// +kubebuilder:printcolumn:name="Site",type=string,priority=1,JSONPath=".spec.location.site"
// +kubebuilder:printcolumn:name="BootMAC",type=string,priority=1,JSONPath=".status.bootMAC"
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
