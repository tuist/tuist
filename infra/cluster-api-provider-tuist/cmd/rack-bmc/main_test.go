package main

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/redfish/redfishtest"
)

// fakeIPMI is the BMC's IPMI over LAN as shipped: every cipher suite but 0
// open to administrators, and serial-over-LAN forcing nothing.
type fakeIPMI struct {
	privs                      string
	forceEncryption, forceAuth bool
	calls                      []string
}

func (f *fakeIPMI) run(_ context.Context, host, user string, args ...string) (string, error) {
	f.calls = append(f.calls, strings.Join(args, " "))
	switch strings.Join(args, " ") {
	case "lan print 1":
		return "IP Address Source       : DHCP Address\nRMCP+ Cipher Suites     : 0,1,2,3,6,7,8,11,12,15,16,17\nCipher Suite Priv Max   : " + f.privs + "\n                        :     X=Cipher Suite Unused\n", nil
	case "sol info 1":
		return fmt.Sprintf("Enabled                         : true\nForce Encryption                : %t\nForce Authentication            : %t\n", f.forceEncryption, f.forceAuth), nil
	case "sol set force-encryption true 1":
		f.forceEncryption = true
	case "sol set force-authentication true 1":
		f.forceAuth = true
	default:
		if p, ok := strings.CutPrefix(strings.Join(args, " "), "lan set 1 cipher_privs "); ok {
			f.privs = p
			return "", nil
		}
		return "", fmt.Errorf("unexpected ipmitool %v", args)
	}
	return "", nil
}

func TestAdoption(t *testing.T) {
	bmc := redfishtest.New()
	srv := httptest.NewTLSServer(bmc)
	defer srv.Close()
	ipmi := &fakeIPMI{privs: "XaaaaaaaaaaaXXX"}
	ipmitool = ipmi.run
	t.Setenv("RACK_BMC_PASSWORD", "Primeline1")
	ctx := context.Background()
	runOut := func(args ...string) (string, error) {
		var out bytes.Buffer
		err := run(ctx, append([]string{"-bmc", srv.URL}, args...), strings.NewReader("abcdefghijklmnopqrst\n"), &out)
		return out.String(), err
	}

	out, err := runOut("inventory")
	if err != nil || !strings.Contains(out, "uuid: 03de3d42-4a8e-9278-ee1a-a0ad9f25c75f\n") || !strings.Contains(out, "bmc mac: a0:ad:9f:25:c7:61\n") {
		t.Fatalf("inventory: %v\n%s", err, out)
	}
	out, err = runOut("check")
	var drift driftError
	if !errors.As(err, &drift) || int(drift) != 8 || !strings.Contains(out, "Restore AC Power Loss: Power On: have Last State") ||
		!strings.Contains(out, "NC-SI sideband on LAN port 2: off: have true") || !strings.Contains(out, "IPMI cipher suites: 17 only: have XaaaaaaaaaaaXXX") {
		t.Fatalf("check as shipped: %v\n%s", err, out)
	}
	if _, err := runOut("apply"); err != nil {
		t.Fatal(err)
	}
	if _, err := runOut("power", "cycle"); err != nil {
		t.Fatal(err)
	}
	if out, err := runOut("check"); err != nil || !strings.Contains(out, "the BIOS, BMC and IPMI match the baseline") {
		t.Fatalf("check after a POST: %v\n%s", err, out)
	}
	if _, err := runOut("rotate", "admin"); err != nil {
		t.Fatal(err)
	}
	bmc.Mu.Lock()
	defer bmc.Mu.Unlock()
	if bmc.Passwords["admin"] != "abcdefghijklmnopqrst" {
		t.Errorf("admin's password was not rotated")
	}
	if got := strings.Join(bmc.Resets, " "); got != "ForceOff On" {
		t.Errorf("resets: %s", got)
	}
	if bmc.SSDP || bmc.Sideband {
		t.Errorf("SSDP %t, sideband %t after apply", bmc.SSDP, bmc.Sideband)
	}
	if ipmi.privs != "XXXXXXXXXXXaXXX" || !ipmi.forceEncryption || !ipmi.forceAuth {
		t.Errorf("IPMI after apply: %+v", ipmi)
	}
}

func TestCipherPrivileges(t *testing.T) {
	if got := cipherPrivileges(strings.Split("0,1,2,3,6,7,8,11,12,15,16,17", ",")); got != "XXXXXXXXXXXaXXX" {
		t.Errorf("as the RS501A lists its suites: %s", got)
	}
	if got := cipherPrivileges([]string{"3", "17"}); got != "XaXXXXXXXXXXXXX" {
		t.Errorf("a shorter list: %s", got)
	}
}
