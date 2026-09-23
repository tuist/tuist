package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// RackLinuxMachineTemplateResource is what a MachineSet clones.
type RackLinuxMachineTemplateResource struct {
	Spec RackLinuxMachineSpec `json:"spec"`
}

// RackLinuxMachineTemplateSpec holds the template.
type RackLinuxMachineTemplateSpec struct {
	Template RackLinuxMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=racklinuxmachinetemplates,scope=Namespaced,categories=cluster-api,shortName=rlmt

// RackLinuxMachineTemplate is the template a rack Linux MachineDeployment
// clones RackLinuxMachines from.
type RackLinuxMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              RackLinuxMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// RackLinuxMachineTemplateList is a list of RackLinuxMachineTemplate.
type RackLinuxMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackLinuxMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackLinuxMachineTemplate{}, &RackLinuxMachineTemplateList{})
}
