//go:build bench

package picos

import (
	"context"
	"os"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
)

// Run against a real switch:
//
//	PICOS_BENCH_ADDRESS=192.168.50.145 PICOS_BENCH_KEY=<private key> [PICOS_BENCH_PIN=SHA256:...] \
//	  go test -tags bench -run TestBench -v ./internal/picos/
func benchClient(t *testing.T) *Client {
	t.Helper()
	address := os.Getenv("PICOS_BENCH_ADDRESS")
	if address == "" {
		t.Skip("PICOS_BENCH_ADDRESS is not set")
	}
	pem, err := os.ReadFile(os.Getenv("PICOS_BENCH_KEY"))
	if err != nil {
		t.Fatal(err)
	}
	signer, err := ssh.ParsePrivateKey(pem)
	if err != nil {
		t.Fatal(err)
	}
	user := os.Getenv("PICOS_BENCH_USER")
	if user == "" {
		user = "tuist"
	}
	c := &Client{
		Dialer:  Dialer{User: user, Signer: signer, Timeout: 45 * time.Second},
		Address: address,
		Pin:     os.Getenv("PICOS_BENCH_PIN"),
	}
	t.Cleanup(c.Close)
	return c
}

func TestBenchReads(t *testing.T) {
	c := benchClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()

	out, err := c.RunCLI(ctx, []string{"show version"})
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("show version:\n%s", out)
	t.Logf("host key: %s", c.HostKey())

	data, err := c.RunningConfig(ctx, `<system xmlns="http://pica8.com/xorplus/system"><hostname/></system>`)
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("system hostname subtree: %s", data)

	if _, err := c.RunCLI(ctx, []string{"show system nonsense"}); err == nil {
		t.Fatal("a refused command returned no error")
	} else {
		t.Logf("refusal: %v", err)
	}
}

func TestBenchNetconfRepeat(t *testing.T) {
	for i := 0; i < 6; i++ {
		c := benchClient(t)
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		start := time.Now()
		_, err := c.RunningConfig(ctx, `<system xmlns="http://pica8.com/xorplus/system"><ztp/></system>`)
		cancel()
		c.Close()
		if err != nil {
			t.Fatalf("read %d after %v: %v", i, time.Since(start), err)
		}
		t.Logf("read %d in %v", i, time.Since(start).Round(time.Millisecond))
	}
}

// PICOS_BENCH_FILTER is a subtree filter; the reply goes to PICOS_BENCH_OUT.
func TestBenchDump(t *testing.T) {
	filter, out := os.Getenv("PICOS_BENCH_FILTER"), os.Getenv("PICOS_BENCH_OUT")
	if out == "" {
		t.Skip("PICOS_BENCH_OUT is not set")
	}
	c := benchClient(t)
	ctx, cancel := context.WithTimeout(context.Background(), time.Minute)
	defer cancel()
	data, err := c.RunningConfig(ctx, filter)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(out, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

// TestBenchConverge writes a ToR-like configuration on unused ports, checks
// it reads back with nothing left to do, and converges an empty spec, which
// deletes everything the controller owns again.
func TestBenchConverge(t *testing.T) {
	c := benchClient(t)
	e := &Engine{Dialer: c.Dialer, ConfirmAfter: 3 * time.Minute}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	rs := &v1alpha1.RackSwitch{Spec: v1alpha1.RackSwitchSpec{ManagementAddress: c.Address, Config: &v1alpha1.SwitchConfig{
		Hostname: "bench-s5860",
		VLANs:    []v1alpha1.VLAN{{ID: 10, Name: "machines"}, {ID: 4000, Name: "mgmt"}},
		LAGs:     []v1alpha1.LAG{{ID: 2, Name: "bench-lag", Ports: []int{30, 31}}},
		Ports: []v1alpha1.PortConfig{
			{Port: 5, Description: "bench access", NativeVLAN: 10},
			{Port: 6, Description: "bench trunk", NativeVLAN: 4000, TaggedVLANs: []int{10}},
			{Port: 30, TaggedVLANs: []int{10, 4000}},
			{Port: 31, TaggedVLANs: []int{10, 4000}},
		},
	}}}
	report, err := e.Converge(ctx, rs, rs.Spec.ManagementAddress, c.Pin, true)
	t.Logf("wrote %d lines: %v", len(report.Changes), report.Changes)
	if err != nil {
		t.Fatal(err)
	}
	report, err = e.Converge(ctx, rs, rs.Spec.ManagementAddress, c.Pin, false)
	if err != nil || len(report.Drift) > 0 {
		t.Fatalf("after converging: drift %v, err %v", report.Drift, err)
	}
	data, _ := c.RunningConfig(ctx, Filter)
	os.WriteFile(os.Getenv("PICOS_BENCH_OUT"), data, 0o644)

	rs.Spec.Config = &v1alpha1.SwitchConfig{}
	report, err = e.Converge(ctx, rs, rs.Spec.ManagementAddress, c.Pin, true)
	t.Logf("cleanup wrote %d lines: %v", len(report.Changes), report.Changes)
	if err != nil {
		t.Fatal(err)
	}
	if report, err = e.Converge(ctx, rs, rs.Spec.ManagementAddress, c.Pin, false); err != nil || len(report.Drift) > 0 {
		t.Fatalf("after cleanup: drift %v, err %v", report.Drift, err)
	}
}
