package intercept

import "testing"

func TestNewOriginalDstNonNil(t *testing.T) {
	// The platform implementation (Linux SO_ORIGINAL_DST, macOS
	// DIOCNATLOOK, or the unsupported stub) must always be constructible.
	// The syscall bodies are validated on-device at rollout; here we only
	// assert wiring.
	if NewOriginalDst() == nil {
		t.Fatal("NewOriginalDst returned nil")
	}
}

func TestErrUnsupportedDefined(t *testing.T) {
	if ErrUnsupported == nil {
		t.Fatal("ErrUnsupported must be defined for fail-open handling")
	}
}
