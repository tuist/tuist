package podagent

import "testing"

func TestHostBridgeIPForVM_RejectsInvalidIP(t *testing.T) {
	if _, err := HostBridgeIPForVM("not-an-ip"); err == nil {
		t.Fatal("expected an error for an unparseable VM IP")
	}
}

func TestHostBridgeIPForVM_FindsDirectlyConnectedInterface(t *testing.T) {
	// The loopback interface is always up with 127.0.0.1/8, so the host's own
	// address on the subnet carrying 127.0.0.1 is 127.0.0.1 itself. This
	// exercises the "find the interface whose subnet contains the VM IP and
	// return its address" path without depending on a vmnet bridge existing.
	got, err := HostBridgeIPForVM("127.0.0.1")
	if err != nil {
		t.Fatalf("unexpected error resolving loopback: %v", err)
	}
	if got != "127.0.0.1" {
		t.Fatalf("host bridge IP for 127.0.0.1 = %q, want 127.0.0.1", got)
	}
}

func TestHostBridgeIPForVM_NoConnectedInterface(t *testing.T) {
	// 203.0.113.0/24 is TEST-NET-3 (RFC 5737); no host interface should be
	// directly connected to it, so resolution must fail rather than return a
	// bogus address.
	if _, err := HostBridgeIPForVM("203.0.113.7"); err == nil {
		t.Fatal("expected an error when no interface is directly connected to the VM IP")
	}
}
