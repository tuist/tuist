//go:build !darwin

package podagent

import "net"

// setBoundInterface is a no-op off darwin: the macOS scoped-routing
// behaviour that bindDialToTargetInterface works around doesn't apply,
// and IP_BOUND_IF isn't portable. tart-kubelet only runs on macOS in
// production; this keeps the package buildable on Linux CI.
func setBoundInterface(_ int, _ net.IP, _ int) error { return nil }
