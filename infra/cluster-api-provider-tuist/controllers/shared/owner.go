package shared

import (
	"context"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/client"

	clusterv1 "sigs.k8s.io/cluster-api/api/core/v1beta1"
)

// OwnerMachine returns the v1beta1 Machine that owns obj.
//
// Cluster API 1.14's util.GetOwnerMachine reads the v1beta2 Machine. This
// provider's reconcilers and their fixtures still speak v1beta1, which the
// apiserver continues to serve.
func OwnerMachine(ctx context.Context, c client.Client, obj metav1.ObjectMeta) (*clusterv1.Machine, error) {
	for _, ref := range obj.GetOwnerReferences() {
		gv, err := schema.ParseGroupVersion(ref.APIVersion)
		if err != nil {
			return nil, err
		}
		if ref.Kind != "Machine" || gv.Group != clusterv1.GroupVersion.Group {
			continue
		}
		machine := &clusterv1.Machine{}
		if err := c.Get(ctx, client.ObjectKey{Namespace: obj.Namespace, Name: ref.Name}, machine); err != nil {
			return nil, err
		}
		return machine, nil
	}
	return nil, nil
}
