package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// OVHDedicatedMachineTemplateResource is the embedded "spec" CAPI's MachineSet
// controller clones from when scaling up a MachineDeployment.
type OVHDedicatedMachineTemplateResource struct {
	Spec OVHDedicatedMachineSpec `json:"spec"`
}

// OVHDedicatedMachineTemplateSpec wraps the per-Machine spec into the template
// shape CAPI expects.
type OVHDedicatedMachineTemplateSpec struct {
	Template OVHDedicatedMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=ovhdedicatedmachinetemplates,scope=Namespaced,categories=cluster-api,shortName=odmt

// OVHDedicatedMachineTemplate is the template MachineDeployment + MachineSet
// objects clone Machines from.
type OVHDedicatedMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              OVHDedicatedMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// OVHDedicatedMachineTemplateList is a list of OVHDedicatedMachineTemplate.
type OVHDedicatedMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []OVHDedicatedMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&OVHDedicatedMachineTemplate{}, &OVHDedicatedMachineTemplateList{})
}
