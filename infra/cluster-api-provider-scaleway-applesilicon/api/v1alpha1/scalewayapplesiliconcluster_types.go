package v1alpha1

import (
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
)

// ScalewayAppleSiliconClusterSpec is mostly empty — the Mac minis join
// an existing Tuist k8s cluster (Hetzner-backed control plane via
// Syself), so we don't manage cluster-level networking, load
// balancers, or the API server. CAPI core requires this resource to
// exist for the parent Cluster object to validate, so we provide it
// as a stub plus the one knob we need: the API server endpoint Mac
// minis dial when joining.
type ScalewayAppleSiliconClusterSpec struct {
	// ControlPlaneEndpoint is the cluster's API server. Stays static
	// across scale events; populated by whatever stood up the Linux
	// control plane (Syself for our managed clusters).
	// +optional
	ControlPlaneEndpoint clusterv1.APIEndpoint `json:"controlPlaneEndpoint,omitempty"`
}

// ScalewayAppleSiliconClusterStatus is similarly minimal.
type ScalewayAppleSiliconClusterStatus struct {
	// Ready signals to CAPI core that the infra-provider side of
	// cluster bring-up is complete. Always true for us — there's no
	// real cluster bring-up to do; we're just adding nodes.
	// +optional
	Ready bool `json:"ready,omitempty"`

	// +optional
	Conditions clusterv1.Conditions `json:"conditions,omitempty"`
}

// +kubebuilder:object:root=true
// +kubebuilder:subresource:status
// +kubebuilder:resource:path=scalewayapplesiliconclusters,scope=Namespaced,categories=cluster-api,shortName=sasc
// +kubebuilder:printcolumn:name="Endpoint",type=string,JSONPath=".spec.controlPlaneEndpoint.host"
// +kubebuilder:printcolumn:name="Ready",type=boolean,JSONPath=".status.ready"

// ScalewayAppleSiliconCluster is the cluster-level stub the CAPI Cluster
// resource references via `infrastructureRef`.
type ScalewayAppleSiliconCluster struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`

	Spec   ScalewayAppleSiliconClusterSpec   `json:"spec,omitempty"`
	Status ScalewayAppleSiliconClusterStatus `json:"status,omitempty"`
}

// +kubebuilder:object:root=true

// ScalewayAppleSiliconClusterList is a list of ScalewayAppleSiliconCluster.
type ScalewayAppleSiliconClusterList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ScalewayAppleSiliconCluster `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ScalewayAppleSiliconCluster{}, &ScalewayAppleSiliconClusterList{})
}

func (c *ScalewayAppleSiliconCluster) GetConditions() clusterv1.Conditions {
	return c.Status.Conditions
}

func (c *ScalewayAppleSiliconCluster) SetConditions(conditions clusterv1.Conditions) {
	c.Status.Conditions = conditions
}
