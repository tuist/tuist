// Package v1alpha1 contains the Tuist runner-pool CRDs.
//
// Runner Pods are managed by a dedicated controller that runs in
// the cluster (deployed alongside the Tuist server). The split
// keeps the Phoenix server out of the Pod-CRUD path: the server
// owns pool config + JIT minting + dispatch endpoint; the
// controller owns Pod lifecycle. Authentication is via per-Pod
// ServiceAccount tokens validated through the Kubernetes
// TokenReview API, so credential state lives in k8s natively
// rather than in a separate Postgres table.
//
// Two CRDs:
//
//   - RunnerPool — declarative spec for "I want N pre-bound
//     warm runners for this pool, with these labels and runner
//     group." One per customer pool; helm renders them from
//     `Tuist.Runners.PoolConfig`.
//
//   - RunnerAssignment — one per Pod. Lightweight metadata
//     (which pool, what triggered it). Carries no credentials —
//     the dispatch token / JIT pattern is replaced by SA-token
//     auth. The Pod's ServiceAccount is the trust anchor.
//
// API group: `tuist.dev/v1alpha1`. Short names: `rpool`, `rassign`.
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
