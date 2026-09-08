package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// StaticAppleSiliconMachineTemplateResource is the embedded "spec" CAPI's
// MachineSet controller clones from when scaling up a MachineDeployment.
type StaticAppleSiliconMachineTemplateResource struct {
	Spec StaticAppleSiliconMachineSpec `json:"spec"`
}

// StaticAppleSiliconMachineTemplateSpec wraps the per-Machine spec into the
// template shape CAPI expects.
type StaticAppleSiliconMachineTemplateSpec struct {
	Template StaticAppleSiliconMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=staticapplesiliconmachinetemplates,scope=Namespaced,categories=cluster-api,shortName=sasmt

// StaticAppleSiliconMachineTemplate is the template MachineDeployment +
// MachineSet objects clone Machines from. Scaling the fleet is a replica count
// against this one template because nothing host-specific lives in it: the
// per-box facts are on the RackHost objects the clones then claim.
type StaticAppleSiliconMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              StaticAppleSiliconMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// StaticAppleSiliconMachineTemplateList is a list of
// StaticAppleSiliconMachineTemplate.
type StaticAppleSiliconMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []StaticAppleSiliconMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&StaticAppleSiliconMachineTemplate{}, &StaticAppleSiliconMachineTemplateList{})
}
