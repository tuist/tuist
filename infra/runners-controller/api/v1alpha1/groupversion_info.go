// Package v1alpha1 contains the Tuist runner-pool CRD.
//
// Runner Pods are managed by a dedicated controller that runs in
// the cluster (deployed alongside the Tuist server). The split
// keeps the Phoenix server out of the Pod-CRUD path: the server
// owns the dispatch endpoint + JIT mint; the controller owns Pod
// lifecycle. Authentication is via per-Pod ServiceAccount tokens
// validated through the Kubernetes TokenReview API, so credential
// state lives in k8s natively rather than in a separate Postgres
// table.
//
// One CRD:
//
//   - RunnerPool — declarative spec for "I want N pre-bound warm
//     runners on this fleet." Helm renders one CR per fleet
//     (today one). The controller materialises Pods + per-Pod
//     ServiceAccounts as direct owner-ref children of the pool —
//     no `RunnerAssignment` intermediate.
//
// Runner availability is gated server-side by the `:runners`
// feature flag, not in K8s. The dispatch endpoint evaluates it
// per webhook.
//
// API group: `tuist.dev/v1alpha1`. Short name: `rpool`.
package v1alpha1

import (
	"k8s.io/apimachinery/pkg/runtime/schema"
	"sigs.k8s.io/controller-runtime/pkg/scheme"
)

var (
	GroupVersion  = schema.GroupVersion{Group: "tuist.dev", Version: "v1alpha1"}
	SchemeBuilder = &scheme.Builder{GroupVersion: GroupVersion}
	AddToScheme   = SchemeBuilder.AddToScheme
)
