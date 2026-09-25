package rackinstall

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"sigs.k8s.io/yaml"
)

// A stick's installer learns which install is its own from the marker.
func TestUserDataCarriesItsInstallID(t *testing.T) {
	out, _ := renderEdge(t)
	if !strings.HasPrefix(out, "#cloud-config\n# tuist-install-id: kTEST1CNTRL\n") {
		t.Fatalf("user-data does not start with the install ID:\n%s", out[:80])
	}
}

type stickFakes struct {
	bin, curlLog, seed, autoinstall, console, sys, announced string
}

// newStickFakes stands in for the live installer: two NICs, a boot server
// that publishes an install for the second one once it has been asked
// failures times, and no installed system on the disks.
func newStickFakes(t *testing.T, failures int) stickFakes {
	t.Helper()
	dir := t.TempDir()
	f := stickFakes{
		bin:         filepath.Join(dir, "bin"),
		curlLog:     filepath.Join(dir, "curl.log"),
		seed:        filepath.Join(dir, "user-data"),
		autoinstall: filepath.Join(dir, "autoinstall.yaml"),
		console:     filepath.Join(dir, "console"),
		sys:         filepath.Join(dir, "sys"),
		announced:   filepath.Join(dir, "announced"),
	}
	writeFakeSys(t, f.sys)
	published, err := UserData(edgeSeed())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "published"), []byte(published), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(f.bin, 0o755); err != nil {
		t.Fatal(err)
	}
	fakes := map[string]string{
		"ip": `cat <<'OUT'
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
2: enp2s0f0np0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 58:47:CA:7A:1B:2C brd ff:ff:ff:ff:ff:ff
3: enp89s0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\    link/ether 38:05:25:38:b5:b5 brd ff:ff:ff:ff:ff:ff
OUT`,
		"curl": `out= url= data=
while [ $# -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; --data-binary) data="$2"; shift 2 ;; http*) url="$1"; shift ;; *) shift ;; esac
done
if [ "$url" = http://192.168.50.1:8480/cgi-bin/announce ] && [ "$data" = @- ]; then
  { cat; echo ---; } >>"` + f.announced + `"
  exit 0
fi
echo "$url" >>"` + f.curlLog + `"
asked=$(grep -c 38-05-25-38-b5-b5 "` + f.curlLog + `")
case "$url" in
  http://192.168.50.1:8480/hosts/38-05-25-38-b5-b5/user-data)
    [ "$asked" -gt ` + string(rune('0'+failures)) + ` ] || exit 22
    cp "` + filepath.Join(dir, "published") + `" "$out" ;;
  *) exit 22 ;;
esac`,
		"lsblk": `:`,
		"sleep": `:`,
	}
	for name, body := range fakes {
		if err := os.WriteFile(filepath.Join(f.bin, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return f
}

func (f stickFakes) run(t *testing.T) string {
	t.Helper()
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("no sh")
	}
	script := stickScript("http://192.168.50.1:8480", stickPaths{Seed: f.seed, Autoinstall: f.autoinstall, Console: f.console, Sys: f.sys})
	cmd := exec.Command(sh, "-c", script)
	cmd.Env = append(os.Environ(), "PATH="+f.bin+":"+os.Getenv("PATH"))
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("the stick's early-command failed: %v\n%s", err, out)
	}
	return string(out)
}

// The stick installs what the boot server publishes for one of the machine's
// NICs, so one stick serves every host of a site.
func TestStickInstallsWhatTheBootServerPublishesForItsNIC(t *testing.T) {
	f := newStickFakes(t, 0)
	f.run(t)
	got, err := os.ReadFile(f.autoinstall)
	if err != nil {
		t.Fatalf("the published install is not the installer's: %v", err)
	}
	published, _ := UserData(edgeSeed())
	if string(got) != published {
		t.Fatalf("autoinstall.yaml is not the published seed:\n%s", got)
	}
	asked, _ := os.ReadFile(f.curlLog)
	if !strings.Contains(string(asked), "http://192.168.50.1:8480/hosts/58-47-ca-7a-1b-2c/user-data\n") {
		t.Errorf("did not ask for the other NIC, lower-cased and hyphenated: %q", asked)
	}
}

// A machine the boot server has nothing for yet, such as a new box declared
// after it was racked, waits for its install instead of failing.
func TestStickWaitsForAnInstallToBePublished(t *testing.T) {
	f := newStickFakes(t, 3)
	f.run(t)
	if _, err := os.Stat(f.autoinstall); err != nil {
		t.Fatalf("no install after it was published: %v", err)
	}
	console, _ := os.ReadFile(f.console)
	if !strings.Contains(string(console), "waiting for http://192.168.50.1:8480 to publish an install for this machine") {
		t.Errorf("console %q", console)
	}
}

type stickSeed struct {
	Autoinstall struct {
		Version       int
		EarlyCommands []string `json:"early-commands"`
	}
}

func TestStickUserData(t *testing.T) {
	out, err := StickUserData("http://192.168.50.1:8480")
	if err != nil {
		t.Fatal(err)
	}
	var seed stickSeed
	if err := yaml.Unmarshal([]byte(out), &seed); err != nil {
		t.Fatalf("user-data is not YAML: %v\n%s", err, out)
	}
	if !strings.HasPrefix(out, "#cloud-config\n") || seed.Autoinstall.Version != 1 || len(seed.Autoinstall.EarlyCommands) != 2 {
		t.Fatalf("user-data %s", out)
	}
	// The live system ejects its boot medium when the install reboots, and an
	// ejected stick has no medium until something loads it again, so the
	// operator could not boot it for the next reinstall.
	keep := seed.Autoinstall.EarlyCommands[1]
	for _, want := range []string{
		"/run/systemd/system/casper.service.d/",
		"ExecStart=\\nExecStart=/bin/true",
		"systemctl daemon-reload",
	} {
		if !strings.Contains(keep, want) {
			t.Errorf("second early-command lacks %q:\n%s", want, keep)
		}
	}
	early := seed.Autoinstall.EarlyCommands[0]
	for _, want := range []string{
		"server='http://192.168.50.1:8480'",
		`-o /run/tuist-user-data "$server/hosts/$path/user-data"`,
		"cp /run/tuist-user-data /autoinstall.yaml",
		`grep -qx "tailnet_key=$id" /run/tuist-prev/etc/tuist-rack-node`,
		// Booted with nothing published for five minutes, it hands over to a
		// rack install on the disks rather than holding the machine.
		"grep -q '^tailnet_key=' /run/tuist-prev/etc/tuist-rack-node",
		">>/dev/console",
	} {
		if !strings.Contains(early, want) {
			t.Errorf("early-command lacks %q", want)
		}
	}
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("no sh")
	}
	path := filepath.Join(t.TempDir(), "early.sh")
	if err := os.WriteFile(path, []byte(early), 0o600); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command(sh, "-n", path).CombinedOutput(); err != nil {
		t.Fatalf("early-command: %v\n%s", err, out)
	}

	for _, bad := range []string{"", "https://192.168.50.1", "http://192.168.50.1/'; reboot", "http://a b"} {
		if _, err := StickUserData(bad); err == nil {
			t.Errorf("rendered a stick for server %q", bad)
		}
	}
}

func TestStickNetworkConfigBringsUpEveryWiredPort(t *testing.T) {
	var cfg struct {
		Version   int
		Ethernets map[string]struct {
			Match    map[string]string
			DHCP4    bool `json:"dhcp4"`
			Optional bool
		}
	}
	if err := yaml.Unmarshal([]byte(StickNetworkConfig()), &cfg); err != nil {
		t.Fatal(err)
	}
	wired, ok := cfg.Ethernets["wired"]
	if cfg.Version != 2 || !ok || wired.Match["name"] != "e*" || !wired.DHCP4 || !wired.Optional {
		t.Fatalf("network-config %+v", cfg)
	}
	if StickMetaData() != "instance-id: tuist-install-stick\n" {
		t.Errorf("meta-data %q", StickMetaData())
	}
}

// writeFakeSys lays out the sysfs an MS-01's installer reads: its SMBIOS
// identity, an SFP+ port, the i226-LM and the loopback, which has no device.
func writeFakeSys(t *testing.T, sys string) {
	t.Helper()
	files := map[string]string{
		"class/dmi/id/product_uuid":           "44312E80-1DC6-11F1-853E-8F903547D200\n",
		"class/dmi/id/product_serial":         "MD148LS139QQMQE00070\n",
		"class/dmi/id/sys_vendor":             "Micro Computer (HK) Tech Limited\n",
		"class/dmi/id/product_name":           "Venus Series\n",
		"class/net/enp2s0f0np0/address":       "58:47:ca:7a:1b:2c\n",
		"class/net/enp2s0f0np0/device/device": "0x1572\n",
		"class/net/enp89s0/address":           "38:05:25:38:b5:b5\n",
		"class/net/enp89s0/device/device":     "0x125b\n",
		"class/net/lo/address":                "00:00:00:00:00:00\n",
		"bus/pci/drivers/i40e/.keep":          "",
		"bus/pci/drivers/igc/.keep":           "",
	}
	for name, content := range files {
		path := filepath.Join(sys, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for nic, driver := range map[string]string{"enp2s0f0np0": "i40e", "enp89s0": "igc"} {
		if err := os.Symlink(filepath.Join(sys, "bus/pci/drivers", driver), filepath.Join(sys, "class/net", nic, "device/driver")); err != nil {
			t.Fatal(err)
		}
	}
}

// A machine the boot server has nothing for announces its identity and NICs,
// so the operator can list it for someone to declare.
func TestStickAnnouncesAMachineWithNothingPublished(t *testing.T) {
	f := newStickFakes(t, 3)
	f.run(t)
	got, err := os.ReadFile(f.announced)
	if err != nil {
		t.Fatalf("no announcement: %v", err)
	}
	want := `uuid=44312e80-1dc6-11f1-853e-8f903547d200
serial=MD148LS139QQMQE00070
product=Micro Computer (HK) Tech Limited Venus Series
nic=58:47:ca:7a:1b:2c i40e 0x1572
nic=38:05:25:38:b5:b5 igc 0x125b
---
`
	if string(got) != want {
		t.Fatalf("announced:\n%s\nwant:\n%s", got, want)
	}
}

// A machine with an install published for it has nothing to announce.
func TestStickDoesNotAnnounceAMachineItInstalls(t *testing.T) {
	f := newStickFakes(t, 0)
	f.run(t)
	if _, err := os.Stat(f.announced); err == nil {
		t.Fatal("announced a machine with an install published")
	}
}
