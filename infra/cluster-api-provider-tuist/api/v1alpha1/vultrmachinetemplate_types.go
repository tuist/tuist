package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// VultrMachineTemplateResource is the embedded "spec" CAPI's MachineSet
// controller clones from when scaling up a MachineDeployment.
type VultrMachineTemplateResource struct {
	Spec VultrMachineSpec `json:"spec"`
}

// VultrMachineTemplateSpec wraps the per-Machine spec into the template shape
// CAPI expects.
type VultrMachineTemplateSpec struct {
	Template VultrMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=vultrmachinetemplates,scope=Namespaced,categories=cluster-api,shortName=vumt

// VultrMachineTemplate is the template MachineDeployment and MachineSet objects
// clone Machines from.
type VultrMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              VultrMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// VultrMachineTemplateList is a list of VultrMachineTemplate.
type VultrMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []VultrMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&VultrMachineTemplate{}, &VultrMachineTemplateList{})
}
