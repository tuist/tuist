package v1alpha1

import (
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type KuraInstanceSpec struct {
	AccountHandle          string            `json:"accountHandle"`
	TenantID               string            `json:"tenantID"`
	Region                 string            `json:"region"`
	Image                  string            `json:"image"`
	Replicas               *int32            `json:"replicas,omitempty"`
	PublicHost             string            `json:"publicHost,omitempty"`
	GRPCPublicHost         string            `json:"grpcPublicHost,omitempty"`
	PeerPublicHost         string            `json:"peerPublicHost,omitempty"`
	GlobalDiscoveryDNSName string            `json:"globalDiscoveryDNSName,omitempty"`
	PeerTLSSecretName      string            `json:"peerTLSSecretName,omitempty"`
	StorageClassName       string            `json:"storageClassName,omitempty"`
	StorageSize            string            `json:"storageSize,omitempty"`
	NodeSelector           map[string]string `json:"nodeSelector,omitempty"`
	ExtraEnv               []corev1.EnvVar   `json:"extraEnv,omitempty"`
	ExtensionScript        string            `json:"extensionScript,omitempty"`
}

type KuraInstanceStatus struct {
	Phase            string       `json:"phase,omitempty"`
	PublicURL        string       `json:"publicURL,omitempty"`
	GRPCPublicURL    string       `json:"grpcPublicURL,omitempty"`
	ObservedImage    string       `json:"observedImage,omitempty"`
	ReadyReplicas    int32        `json:"readyReplicas,omitempty"`
	Message          string       `json:"message,omitempty"`
	LastReconciledAt *metav1.Time `json:"lastReconciledAt,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=kurainstances,scope=Namespaced,shortName=kura
// +kubebuilder:printcolumn:name="Phase",type=string,JSONPath=".status.phase"
// +kubebuilder:printcolumn:name="Host",type=string,JSONPath=".spec.publicHost"
// +kubebuilder:printcolumn:name="Ready",type=integer,JSONPath=".status.readyReplicas"
// +kubebuilder:printcolumn:name="Age",type="date",JSONPath=".metadata.creationTimestamp"
type KuraInstance struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   KuraInstanceSpec   `json:"spec,omitempty"`
	Status KuraInstanceStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true
type KuraInstanceList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []KuraInstance `json:"items"`
}

func init() {
	SchemeBuilder.Register(&KuraInstance{}, &KuraInstanceList{})
}
