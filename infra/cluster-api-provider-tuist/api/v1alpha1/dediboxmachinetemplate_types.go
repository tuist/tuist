package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// DediboxMachineTemplateResource is the embedded "spec" CAPI's MachineSet
// controller clones from when scaling up a MachineDeployment.
type DediboxMachineTemplateResource struct {
	Spec DediboxMachineSpec `json:"spec"`
}

// DediboxMachineTemplateSpec wraps the per-Machine spec into the template shape
// CAPI expects.
type DediboxMachineTemplateSpec struct {
	Template DediboxMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=dediboxmachinetemplates,scope=Namespaced,categories=cluster-api,shortName=dbmt

// DediboxMachineTemplate is the template MachineDeployment + MachineSet objects
// clone Machines from.
type DediboxMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              DediboxMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// DediboxMachineTemplateList is a list of DediboxMachineTemplate.
type DediboxMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []DediboxMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&DediboxMachineTemplate{}, &DediboxMachineTemplateList{})
}
