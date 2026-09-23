package main

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/rack-switch-controller/internal/converge"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada/omadatest"
)

const object = `apiVersion: tuist.dev/v1alpha1
kind: RackSwitch
metadata:
  name: ber1-tor-b
spec:
  site: ber1
  role: tor
  model: sx3832
  managementAddress: 192.168.0.12
  applyOrder: 1
  configRevision: 5ef04ee11ceedbe0
  mac: d4:d6:df:03:d8:b2
  managedBy: controller
  config:
    hostname: ber1-tor-b
    managementVlan: 1
    managementPrefixLength: 24
    gateway: 192.168.0.10
    spanningTree: rstp
    ports:
      - {port: 1}
      - {port: 2, description: isl ber1-tor-a}
`

var deviceAccount = omada.Login{Username: "tuist", Password: "Device-Pass1!"}

func writeFiles(t *testing.T, files map[string]string) string {
	t.Helper()
	dir := t.TempDir()
	for name, content := range files {
		if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	return dir
}

func credentialsDir(t *testing.T) string {
	return writeFiles(t, map[string]string{
		"client-id":       omadatest.ClientID,
		"client-secret":   omadatest.ClientSecret,
		"device-username": deviceAccount.Username,
		"device-password": deviceAccount.Password,
	})
}

func TestApplyAdoptsAndConvergesOneSwitch(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	fake.AddSwitch(omadatest.Switch{MAC: "d4:d6:df:03:d8:b2", State: omadatest.Pending, Ports: omadatest.Ports(2), Logins: []omada.Login{converge.DefaultFactoryLogin}})
	rs, err := readRackSwitch(filepath.Join(writeFiles(t, map[string]string{"rsw.yaml": object}), "rsw.yaml"))
	if err != nil {
		t.Fatal(err)
	}
	creds, err := converge.LoadCredentials(credentialsDir(t))
	if err != nil {
		t.Fatal(err)
	}
	var out bytes.Buffer
	a := applier{
		engine: &converge.Engine{
			Omada:             omada.New(fake.URL, func() (string, string, error) { return creds.ClientID, creds.ClientSecret, nil }),
			Site:              omadatest.SiteName,
			ControllerAddress: "100.84.132.92",
		},
		creds: creds,
		out:   &out,
		now:   time.Now,
	}

	if err := a.run(context.Background(), rs); err != nil {
		t.Fatalf("%v\n%s", err, out.String())
	}
	want := `site ber1:
  device host: 100.84.132.92
  site SSH: on, port 22
  device account: the configured login (replaces every adopted switch's login)
ber1-tor-b: adopting with the site's device account
ber1-tor-b: the controller reports adopting with the site's device account failed; trying the factory login
ber1-tor-b: adopting with the factory login
ber1-tor-b is adopted with the factory login
ber1-tor-b (D4-D6-DF-03-D8-B2):
  hostname: D4-D6-DF-03-D8-B2 -> ber1-tor-b
  port 2: Port2 -> isl ber1-tor-a
  spanning tree: rstp (written; the API cannot read it back)
ber1-tor-b matches revision 5ef04ee11ceedbe0 as far as the API reads back
verify the rest with: mise run rack:fleet diff ber1-tor-b
`
	if out.String() != want {
		t.Fatalf("output:\n%s\nwant:\n%s", out.String(), want)
	}
	if strings.Contains(out.String(), deviceAccount.Password) {
		t.Fatal("the output carries the device account's password")
	}
}

func TestApplyRefusesAStandaloneSwitch(t *testing.T) {
	path := filepath.Join(writeFiles(t, map[string]string{"rsw.yaml": strings.Replace(object, "managedBy: controller", "managedBy: standalone", 1)}), "rsw.yaml")
	var stdout, stderr bytes.Buffer
	code := runApply([]string{"--object", path, "--site", "ber1", "--controller-address", "100.84.132.92", "--credentials-dir", credentialsDir(t)}, &stdout, &stderr)
	if code != 1 || !strings.Contains(stderr.String(), "ber1-tor-b is not managedBy: controller") {
		t.Fatalf("code = %d, stderr = %s", code, stderr.String())
	}
}

func TestApplyRunsAgainstAConnectedSwitchFromTheCommandLine(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	fake.AddSwitch(omadatest.Switch{
		MAC: "d4:d6:df:03:d8:b2", State: omadatest.Connected, Hostname: "ber1-tor-b", Ports: omadatest.Ports(2),
		Networks: []map[string]any{omadatest.ManagementInterface(omada.IPModeDHCP, "192.168.0.82", "255.255.255.0", "192.168.0.1")},
	})
	path := filepath.Join(writeFiles(t, map[string]string{"rsw.yaml": object}), "rsw.yaml")

	var stdout, stderr bytes.Buffer
	code := runApply([]string{
		"--object", path, "--omada-url", fake.URL, "--site", omadatest.SiteName,
		"--controller-address", "100.84.132.92", "--credentials-dir", credentialsDir(t),
	}, &stdout, &stderr)
	if code != 0 {
		t.Fatalf("code = %d, stderr = %s", code, stderr.String())
	}
	for _, want := range []string{
		"management address: dhcp (192.168.0.82) -> 192.168.0.12 255.255.255.0 gateway 192.168.0.10",
		"port 2: Port2 -> isl ber1-tor-a",
	} {
		if !strings.Contains(stdout.String(), want) {
			t.Fatalf("stdout = %s, want %q", stdout.String(), want)
		}
	}
}

func TestReadRackSwitchNeedsAMAC(t *testing.T) {
	_, err := readRackSwitch(filepath.Join("..", "..", "..", "rack-switch-fleet", "k8s", "ber1", "ber1-tor-b.yaml"))
	if err == nil || !strings.Contains(err.Error(), "has no spec.mac") {
		t.Fatalf("err = %v", err)
	}
}
