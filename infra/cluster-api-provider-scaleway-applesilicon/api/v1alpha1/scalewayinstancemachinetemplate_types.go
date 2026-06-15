package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// ScalewayInstanceMachineTemplateResource is the embedded "spec" CAPI's
// MachineSet controller clones from when scaling up a MachineDeployment.
type ScalewayInstanceMachineTemplateResource struct {
	Spec ScalewayInstanceMachineSpec `json:"spec"`
}

// ScalewayInstanceMachineTemplateSpec wraps the per-Machine spec into the
// template shape CAPI expects.
type ScalewayInstanceMachineTemplateSpec struct {
	Template ScalewayInstanceMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=scalewayinstancemachinetemplates,scope=Namespaced,categories=cluster-api,shortName=simt

// ScalewayInstanceMachineTemplate is the template MachineDeployment +
// MachineSet objects clone Machines from.
type ScalewayInstanceMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              ScalewayInstanceMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// ScalewayInstanceMachineTemplateList is a list of
// ScalewayInstanceMachineTemplate.
type ScalewayInstanceMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ScalewayInstanceMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ScalewayInstanceMachineTemplate{}, &ScalewayInstanceMachineTemplateList{})
}
