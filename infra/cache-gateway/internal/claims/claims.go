// Package claims models the verified tenant cache token and the
// GitHub-equivalent ref-scope rules derived from it. The Tuist server
// is the sole issuer (it holds the private key); the gateway only ever
// verifies with the configured public key. Every storage prefix and
// scope predicate is derived from these verified claims, never from
// request input.
package claims

// Claims is the verified payload of a tenant cache token. The gateway
// trusts these fields only after the Ed25519 signature and expiry have
// been validated (see Verifier).
type Claims struct {
	// AccountID is the Tuist account (org) the job belongs to. It is the
	// only tenant identifier that ever becomes a storage path segment.
	AccountID uint64 `json:"account_id"`
	// Repo is "owner/repo".
	Repo string `json:"repo"`
	// Fleet is the runner fleet (e.g. "tuist-runners").
	Fleet string `json:"fleet"`
	// Ref is the creating ref of the job, e.g. "refs/heads/feature-x".
	// Cache entries are written under this scope.
	Ref string `json:"ref"`
	// DefaultBranch is the repo's default branch ref, e.g.
	// "refs/heads/main". A read falls back to it (trusted jobs only).
	DefaultBranch string `json:"default_branch"`
	// BaseRef is the PR base ref when the job is a pull request, else "".
	BaseRef string `json:"base_ref"`
	// UntrustedFork marks a job triggered from a fork PR. Such a job may
	// only read entries written under its own ref; it never reads the
	// base or default-branch scope. This is the fork-isolation boundary.
	UntrustedFork bool `json:"untrusted_fork"`
	// WorkflowJobID is the GitHub workflow_job id (the token subject).
	WorkflowJobID uint64 `json:"workflow_job_id"`
	// IssuedAt / ExpiresAt are unix seconds.
	IssuedAt  int64 `json:"iat"`
	ExpiresAt int64 `json:"exp"`
}
