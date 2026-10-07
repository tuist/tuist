package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

// RackCardManagedBy names who changes a rack power device's management card.
// +kubebuilder:validation:Enum=controller;standalone
type RackCardManagedBy string

const (
	// RackCardManagedByController is a device its controller adopts and keeps
	// configured.
	RackCardManagedByController RackCardManagedBy = "controller"
	// RackCardManagedByStandalone is a device the controller never contacts.
	RackCardManagedByStandalone RackCardManagedBy = "standalone"
)

// RackCardDrift is how a device compared with its spec when last verified.
// +kubebuilder:validation:Enum=unknown;none;drifted
type RackCardDrift string

const (
	RackCardDriftUnknown RackCardDrift = "unknown"
	RackCardDriftNone    RackCardDrift = "none"
	RackCardDriftDrifted RackCardDrift = "drifted"
)

// RackCardStatus is what a controller observed of a rack power device's
// management card, the part every such device shares: adoption, the
// certificate pin, the credentials it generated and the card's identity.
type RackCardStatus struct {
	// Adopted is whether the controller configured the card: its
	// administrator password, its licence agreement, the controller's account
	// and the device's settings.
	// +optional
	Adopted bool `json:"adopted,omitempty"`

	// Reachable is whether the card answered the last reconcile.
	// +optional
	Reachable bool `json:"reachable,omitempty"`

	// TLSFingerprint is the SHA-256 of the certificate the card presented at
	// first contact, which every later connection is pinned to.
	// +optional
	TLSFingerprint string `json:"tlsFingerprint,omitempty"`

	// PresentedFingerprint is the certificate the card presents when it no
	// longer matches TLSFingerprint.
	// +optional
	PresentedFingerprint string `json:"presentedFingerprint,omitempty"`

	// CredentialsSecret is the Secret the controller generated: the
	// administrator's password, the controller's account and the pin. It
	// outlives the object.
	// +optional
	CredentialsSecret string `json:"credentialsSecret,omitempty"`

	// Model, SerialNumber and FirmwareVersion are the management card's, as
	// it reports them.
	// +optional
	Model string `json:"model,omitempty"`
	// +optional
	SerialNumber string `json:"serialNumber,omitempty"`
	// +optional
	FirmwareVersion string `json:"firmwareVersion,omitempty"`

	// ObservedGeneration is the generation the card was last converged to.
	// +optional
	ObservedGeneration int64 `json:"observedGeneration,omitempty"`

	// Drift is how the card compared with the spec when last verified.
	// +optional
	Drift RackCardDrift `json:"drift,omitempty"`

	// LastVerified is when the card was last read.
	// +optional
	LastVerified *metav1.Time `json:"lastVerified,omitempty"`

	// Message says what the last reconcile found.
	// +optional
	Message string `json:"message,omitempty"`
}
