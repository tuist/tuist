package tart

import (
	"strings"
	"testing"
)

// The state ber1-runner-b04..b07 were in on 2026-10-14: every Pod failed with
// the bare timeout, and nothing in it said that a restart was the fix.
func TestGUISessionTimeoutErrorNamesSetupAssistantAndTheRecovery(t *testing.T) {
	msg := guiSessionTimeoutError(501, "_mbsetupuser").Error()
	for _, want := range []string{"uid 501", "_mbsetupuser", "Setup Assistant", "restart the host"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error %q does not contain %q", msg, want)
		}
	}
}

func TestGUISessionTimeoutErrorNamesAnyOtherConsoleHolder(t *testing.T) {
	msg := guiSessionTimeoutError(501, "root").Error()
	if !strings.Contains(msg, "console held by root") {
		t.Fatalf("error %q does not say who holds the console", msg)
	}
	if strings.Contains(msg, "Setup Assistant") {
		t.Fatalf("error %q blames Setup Assistant for a console it does not hold", msg)
	}
}

func TestGUISessionTimeoutErrorWithoutAConsoleOwner(t *testing.T) {
	msg := guiSessionTimeoutError(501, "").Error()
	if msg != "Aqua session for uid 501 did not come up within 30s after SIGHUP loginwindow" {
		t.Fatalf("error = %q", msg)
	}
}
