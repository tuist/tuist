package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// ScalewayAppleSiliconMachineTemplateResource is the embedded "spec"
// CAPI's MachineSet controller clones from when scaling up a
// MachineDeployment.
type ScalewayAppleSiliconMachineTemplateResource struct {
	Spec ScalewayAppleSiliconMachineSpec `json:"spec"`
}

// ScalewayAppleSiliconMachineTemplateSpec wraps the per-Machine spec
// into the template shape CAPI expects.
type ScalewayAppleSiliconMachineTemplateSpec struct {
	Template ScalewayAppleSiliconMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=scalewayapplesiliconmachinetemplates,scope=Namespaced,categories=cluster-api,shortName=sammt

// ScalewayAppleSiliconMachineTemplate is the template
// MachineDeployment + MachineSet objects clone Machines from.
type ScalewayAppleSiliconMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              ScalewayAppleSiliconMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// ScalewayAppleSiliconMachineTemplateList is a list of
// ScalewayAppleSiliconMachineTemplate.
type ScalewayAppleSiliconMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ScalewayAppleSiliconMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ScalewayAppleSiliconMachineTemplate{}, &ScalewayAppleSiliconMachineTemplateList{})
}
