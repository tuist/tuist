package bootstrap

import (
	"context"
	"errors"
	"strings"
	"testing"
)

func ioregWithSerial(serial string) string {
	return "+-o Mac16,11  <class IOPlatformExpertDevice>\n    {\n      \"IOPlatformSerialNumber\" = \"" + serial + "\"\n    }\n"
}

func TestCheckHostSerialAcceptsTheExpectedHost(t *testing.T) {
	if err := checkHostSerial("K9YLWQHQM2", ioregWithSerial("K9YLWQHQM2")); err != nil {
		t.Fatalf("checkHostSerial = %v, want nil", err)
	}
}

// The case found racking the first BER1 tray: the box still holding an address
// on an old lease answered for its neighbour's inventory record.
func TestCheckHostSerialRefusesAnotherHost(t *testing.T) {
	err := checkHostSerial("JC332QMX73", ioregWithSerial("K9YLWQHQM2"))
	var mismatch *HostIdentityMismatchError
	if !errors.As(err, &mismatch) {
		t.Fatalf("checkHostSerial = %v, want a HostIdentityMismatchError", err)
	}
	if mismatch.Expected != "JC332QMX73" || mismatch.Reported != "K9YLWQHQM2" {
		t.Errorf("mismatch = %#v", mismatch)
	}
	if !strings.Contains(err.Error(), `"K9YLWQHQM2", not "JC332QMX73"`) {
		t.Errorf("error %q does not name both serials", err)
	}
}

func TestCheckHostSerialRefusesAnUnreadableAnswer(t *testing.T) {
	err := checkHostSerial("JC332QMX73", "ioreg: command not found")
	if err == nil {
		t.Fatal("checkHostSerial accepted output with no serial in it")
	}
	var mismatch *HostIdentityMismatchError
	if errors.As(err, &mismatch) {
		t.Errorf("an unreadable answer is not a mismatch: %v", err)
	}
}

// Rented hosts carry no expected serial and are never asked for one.
func TestVerifyHostSerialSkipsAHostWithNoExpectedSerial(t *testing.T) {
	if err := verifyHostSerial(context.Background(), nil, ""); err != nil {
		t.Fatalf("verifyHostSerial = %v, want nil without dialling", err)
	}
}

func TestExpectedSerialIsPerHost(t *testing.T) {
	fleet := Config{HostCPU: 12}
	a := fleet.WithPerHost(PerHost{ExpectedSerial: "K9YLWQHQM2"})
	b := fleet.WithPerHost(PerHost{ExpectedSerial: "JC332QMX73"})
	if a.ExpectedSerial != "K9YLWQHQM2" {
		t.Fatalf("WithPerHost dropped ExpectedSerial: %q", a.ExpectedSerial)
	}
	if HostConfigHash(a) != HostConfigHash(b) {
		t.Error("ExpectedSerial changed the fleet-wide host config hash, so every rack host would drift from every other")
	}
}
