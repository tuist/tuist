module github.com/tuist/tuist/infra/stable-egress-controller

go 1.25

// NOTE: go.sum is intentionally absent in this draft — it can't be generated
// without network access. Run `go mod tidy` (CI does this) to populate the
// transitive requires + go.sum before the image builds.
require (
	github.com/hetznercloud/hcloud-go/v2 v2.17.0
	k8s.io/api v0.32.1
	k8s.io/apimachinery v0.32.1
	k8s.io/client-go v0.32.1
	sigs.k8s.io/controller-runtime v0.20.0
)
