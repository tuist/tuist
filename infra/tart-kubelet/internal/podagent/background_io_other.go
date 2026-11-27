//go:build !darwin

package podagent

// withThrottledIO runs fn; only macOS has the thread I/O policy it sets there.
func withThrottledIO(fn func()) { fn() }
