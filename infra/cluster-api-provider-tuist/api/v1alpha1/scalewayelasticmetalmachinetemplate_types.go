package v1alpha1

import metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

// ScalewayElasticMetalMachineTemplateResource is the embedded "spec" CAPI's
// MachineSet controller clones from when scaling up a MachineDeployment.
type ScalewayElasticMetalMachineTemplateResource struct {
	Spec ScalewayElasticMetalMachineSpec `json:"spec"`
}

// ScalewayElasticMetalMachineTemplateSpec wraps the per-Machine spec into the
// template shape CAPI expects.
type ScalewayElasticMetalMachineTemplateSpec struct {
	Template ScalewayElasticMetalMachineTemplateResource `json:"template"`
}

// +kubebuilder:object:root=true
// +kubebuilder:resource:path=scalewayelasticmetalmachinetemplates,scope=Namespaced,categories=cluster-api,shortName=semmt

// ScalewayElasticMetalMachineTemplate is the template MachineDeployment +
// MachineSet objects clone Machines from.
type ScalewayElasticMetalMachineTemplate struct {
	metav1.TypeMeta   `json:",inline"`
	metav1.ObjectMeta `json:"metadata,omitempty"`
	Spec              ScalewayElasticMetalMachineTemplateSpec `json:"spec,omitempty"`
}

// +kubebuilder:object:root=true

// ScalewayElasticMetalMachineTemplateList is a list of
// ScalewayElasticMetalMachineTemplate.
type ScalewayElasticMetalMachineTemplateList struct {
	metav1.TypeMeta `json:",inline"`
	metav1.ListMeta `json:"metadata,omitempty"`
	Items           []ScalewayElasticMetalMachineTemplate `json:"items"`
}

func init() {
	SchemeBuilder.Register(&ScalewayElasticMetalMachineTemplate{}, &ScalewayElasticMetalMachineTemplateList{})
}
