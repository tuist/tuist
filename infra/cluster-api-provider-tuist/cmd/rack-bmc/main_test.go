package main

import (
	"bytes"
	"context"
	"errors"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/redfish/redfishtest"
)

func TestAdoption(t *testing.T) {
	bmc := redfishtest.New()
	srv := httptest.NewTLSServer(bmc)
	defer srv.Close()
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
	if !errors.As(err, &drift) || int(drift) != 3 || !strings.Contains(out, "Restore AC Power Loss: Power On: have Last State") {
		t.Fatalf("check as shipped: %v\n%s", err, out)
	}
	if _, err := runOut("apply"); err != nil {
		t.Fatal(err)
	}
	if _, err := runOut("power", "cycle"); err != nil {
		t.Fatal(err)
	}
	if out, err := runOut("check"); err != nil || !strings.Contains(out, "matches the baseline") {
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
}
