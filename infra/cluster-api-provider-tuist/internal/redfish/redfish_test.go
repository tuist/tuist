package redfish

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/redfish/redfishtest"
)

func newBMC(t *testing.T) (*redfishtest.BMC, *Client) {
	t.Helper()
	bmc := redfishtest.New()
	srv := httptest.NewTLSServer(bmc)
	t.Cleanup(srv.Close)
	sum := sha256.Sum256(srv.Certificate().Raw)
	return bmc, &Client{Endpoint: srv.URL, Username: "admin", Password: "Primeline1", TLSFingerprint: hex.EncodeToString(sum[:])}
}

func TestInventory(t *testing.T) {
	_, c := newBMC(t)
	inv, err := c.Inventory(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	if inv.UUID != "03de3d42-4a8e-9278-ee1a-a0ad9f25c75f" || inv.Serial != "TAS0CG000177" || inv.Model != "RS501A-E12-RS12U" {
		t.Errorf("identity: %+v", inv)
	}
	if inv.BMCMAC != "a0:ad:9f:25:c7:61" || inv.BMCVersion != "1.02.38" || inv.BIOSVersion != "1301" {
		t.Errorf("BMC: %+v", inv)
	}
	if inv.TPM != "TPM2_0" || inv.SecureBoot || inv.PowerState != "Off" {
		t.Errorf("state: %+v", inv)
	}
	var macs []string
	for _, n := range inv.NICs {
		macs = append(macs, n.MAC)
	}
	if got := strings.Join(macs, " "); got != "a0:ad:9f:25:c7:5f a0:ad:9f:25:c7:60 c0:b5:50:53:d8:c0 c0:b5:50:53:d8:c1" {
		t.Errorf("NICs: %s", got)
	}
}

func TestPinnedCertificate(t *testing.T) {
	_, c := newBMC(t)
	c.TLSFingerprint = strings.Repeat("ab", 32)
	if _, err := c.PowerState(context.Background()); err == nil || !strings.Contains(err.Error(), "not the pinned one") {
		t.Fatalf("a BMC with another certificate was trusted: %v", err)
	}
}

func TestBaselineAppliesAtPOST(t *testing.T) {
	bmc, c := newBMC(t)
	ctx := context.Background()
	drift, err := c.Check(ctx, Baseline)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, d := range drift {
		names = append(names, d.Attribute)
	}
	if got := strings.Join(names, " "); got != "AridApmLastState TER002 SecureBoot" {
		t.Fatalf("drift as shipped: %s", got)
	}
	if err := c.Apply(ctx, drift); err != nil {
		t.Fatal(err)
	}
	if drift, _ := c.Check(ctx, Baseline); len(drift) != 2 {
		t.Fatalf("the BIOS part applied before a POST: %+v", drift)
	}
	if err := c.Reset(ctx, ResetOn); err != nil {
		t.Fatal(err)
	}
	if drift, err := c.Check(ctx, Baseline); err != nil || len(drift) != 0 {
		t.Fatalf("drift after POST: %+v %v", drift, err)
	}
	bmc.Mu.Lock()
	defer bmc.Mu.Unlock()
	if !bmc.SecureBootActive {
		t.Error("Secure Boot is not active after the POST")
	}
}

// The BMC ships announcing itself with SSDP and leasing an address through
// the host's LAN port 2; adoption turns both off, with the host running.
func TestBMCBaseline(t *testing.T) {
	bmc, c := newBMC(t)
	ctx := context.Background()
	bmc.Mu.Lock()
	bmc.PowerOn = true
	bmc.Mu.Unlock()
	drift, err := c.CheckBMC(ctx, BMCBaseline)
	if err != nil {
		t.Fatal(err)
	}
	var names []string
	for _, d := range drift {
		names = append(names, d.Attribute)
	}
	if got := strings.Join(names, " "); got != "SSDP Sideband" {
		t.Fatalf("drift as shipped: %s", got)
	}
	if err := c.ApplyBMC(ctx, drift); err != nil {
		t.Fatal(err)
	}
	if drift, err := c.CheckBMC(ctx, BMCBaseline); err != nil || len(drift) != 0 {
		t.Fatalf("drift after apply: %+v %v", drift, err)
	}
	if err := c.ApplyBMC(ctx, nil); err != nil {
		t.Errorf("applying no drift wrote: %v", err)
	}
	bmc.Mu.Lock()
	defer bmc.Mu.Unlock()
	if bmc.SSDP || bmc.Sideband {
		t.Errorf("SSDP %t, sideband %t", bmc.SSDP, bmc.Sideband)
	}
}

func TestSetBIOS(t *testing.T) {
	bmc, c := newBMC(t)
	ctx := context.Background()
	if err := c.SetBIOS(ctx, Attributes{"SECB001": "Enabled"}); err == nil || !strings.Contains(err.Error(), "does not let Redfish set SECB001") {
		t.Errorf("an attribute the BIOS drops at POST was written: %v", err)
	}
	if err := c.SetBIOS(ctx, Attributes{"NoSuchThing": 1}); err == nil {
		t.Error("an unknown attribute was written")
	}
	bmc.Mu.Lock()
	bmc.PowerOn = true
	bmc.Mu.Unlock()
	if err := c.SetBIOS(ctx, Attributes{"AridApmLastState": "Power On"}); !errors.Is(err, ErrHostOn) {
		t.Errorf("writing with the host on: %v", err)
	}
	if err := c.BootOnce(ctx, BootCd); !errors.Is(err, ErrHostOn) {
		t.Errorf("a one-time boot with the host on: %v", err)
	}
}

func TestInsertCD(t *testing.T) {
	bmc, c := newBMC(t)
	ctx := context.Background()
	pollInterval = time.Millisecond
	for _, m := range []Media{
		{URL: "https://192.168.1.141:8443/tuist.iso", Username: "vm", Password: "x"},
		{URL: "https://192.168.1.141/tuist-preinstall.iso", Username: "vm", Password: "x"},
		{URL: "http://192.168.1.141/tuist.iso", Username: "vm", Password: "x"},
		{URL: "https://192.168.1.141/tuist.iso"},
	} {
		if err := c.InsertCD(ctx, m); err == nil {
			t.Errorf("%+v was inserted", m)
		}
	}
	m := Media{URL: "https://192.168.1.141/tuist_preinstall.iso", Username: "vm", Password: "x"}
	if err := c.InsertCD(ctx, m); err != nil {
		t.Fatal(err)
	}
	if image, err := c.CD(ctx); err != nil || image != "//192.168.1.141//tuist_preinstall.iso" {
		t.Fatalf("CD: %q %v", image, err)
	}
	// Remote media is already on: a second insert must not ask for it again.
	if err := c.InsertCD(ctx, m); err != nil {
		t.Fatal(err)
	}
	if err := c.BootOnce(ctx, BootCd); err != nil {
		t.Fatal(err)
	}
	if err := c.EjectCD(ctx); err != nil {
		t.Fatal(err)
	}
	bmc.Mu.Lock()
	defer bmc.Mu.Unlock()
	if bmc.Image != "" || bmc.Override != "Cd" {
		t.Errorf("image %q, override %q", bmc.Image, bmc.Override)
	}
}

func TestSetPassword(t *testing.T) {
	bmc, c := newBMC(t)
	ctx := context.Background()
	if err := c.SetPassword(ctx, "Administrator", "short"); err == nil {
		t.Error("a password the BMC refuses was sent")
	}
	if err := c.SetPassword(ctx, "Administrator", "abcdefghijklmnopqrst"); err != nil {
		t.Fatal(err)
	}
	if err := c.SetPassword(ctx, "nobody", "abcdefghijklmnopqrst"); err == nil {
		t.Error("an unknown account was changed")
	}
	bmc.Mu.Lock()
	defer bmc.Mu.Unlock()
	if bmc.Passwords["Administrator"] != "abcdefghijklmnopqrst" || bmc.Passwords["admin"] != "Primeline1" {
		t.Errorf("passwords: %v", bmc.Passwords)
	}
}

func TestResetRefusesPowerCycle(t *testing.T) {
	_, c := newBMC(t)
	if err := c.Reset(context.Background(), "PowerCycle"); err == nil {
		t.Error("PowerCycle, which the BMC lacks, was sent")
	}
}
