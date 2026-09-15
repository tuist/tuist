package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// RackAppleSiliconMachineTemplateResource is the embedded "spec" CAPI's
// MachineSet controller clones from when scaling up a MachineDeployment.
type RackAppleSiliconMachineTemplateResource struct {
	Spec RackAppleSiliconMachineSpec `json:"spec"`
}

// RackAppleSiliconMachineTemplateSpec wraps the per-Machine spec into the
// template shape CAPI expects.
type RackAppleSiliconMachineTemplateSpec struct {
	Template RackAppleSiliconMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=rackapplesiliconmachinetemplates,scope=Namespaced,categories=cluster-api,shortName=rasmt

// RackAppleSiliconMachineTemplate is the template MachineDeployment +
// MachineSet objects clone Machines from. Scaling the fleet is a replica count
// against this one template because nothing host-specific lives in it: the
// per-box facts are on the RackHost objects the clones then claim.
type RackAppleSiliconMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              RackAppleSiliconMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// RackAppleSiliconMachineTemplateList is a list of
// RackAppleSiliconMachineTemplate.
type RackAppleSiliconMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []RackAppleSiliconMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&RackAppleSiliconMachineTemplate{}, &RackAppleSiliconMachineTemplateList{})
}
