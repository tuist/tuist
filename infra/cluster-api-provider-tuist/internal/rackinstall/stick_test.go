package rackinstall

import (
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
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
	bin, curlLog, seed, autoinstall, console, sys, announced, prev, calls, node, asked string
}

// stickWorld is what the live installer finds: a boot server that publishes
// an install for the machine's second NIC once it has been asked failures
// times (never, when failures is negative), or that cannot be reached at all,
// and a rack install on the disks or none.
type stickWorld struct {
	failures    int
	unreachable bool
	installed   bool
}

func newStickFakes(t *testing.T, failures int) stickFakes {
	return newStickWorld(t, stickWorld{failures: failures})
}

// newStickWorld stands in for the live installer with two NICs.
func newStickWorld(t *testing.T, w stickWorld) stickFakes {
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
		prev:        filepath.Join(dir, "prev"),
		calls:       filepath.Join(dir, "calls"),
		node:        filepath.Join(dir, "rack-node"),
		asked:       filepath.Join(dir, "asked"),
	}
	writeFakeSys(t, f.sys)
	published, err := UserData(edgeSeed())
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "published"), []byte(published), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(f.prev, "etc"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(f.prev, "etc", "tuist-rack-node"), []byte("node=ber1-edge\ntailnet_key=kOLD1CNTRL\n"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(f.bin, 0o755); err != nil {
		t.Fatal(err)
	}
	publishAfter := strconv.Itoa(w.failures)
	if w.failures < 0 {
		publishAfter = "1000000"
	}
	unreachable := "0"
	if w.unreachable {
		unreachable = "1"
	}
	lsblk := `:`
	if w.installed {
		lsblk = `echo "/dev/nvme0n1p2 ext4"`
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
[ ` + unreachable + ` = 0 ] || exit 7
[ "$url" = http://192.168.50.1:8480/tools/rack-node ] || exit 22
cp "` + filepath.Join(dir, "fake-rack-node") + `" "$out"`,
		"lsblk":  lsblk,
		"sleep":  `:`,
		"mount":  `echo "mount $*" >>"` + f.calls + `"`,
		"umount": `echo "umount $*" >>"` + f.calls + `"`,
		"chroot": `shift; exec "$@"`,
		"efibootmgr": `if [ $# -eq 0 ]; then
  printf 'BootCurrent: 0003\nBootOrder: 0003,0000,0001\nBoot0000* Ubuntu\tHD(1,GPT,x)\nBoot0001* UEFI: PXE IPv4\nBoot0003* UEFI: SanDisk, Partition 2\n'
else
  echo "efibootmgr $*" >>"` + f.calls + `"
fi`,
		"reboot": `echo "reboot $*" >>"` + f.calls + `"
kill -KILL $PPID`,
	}
	fakeNode := `case "$1" in
ek) echo MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtestek== ;;
seed)
  shift
  while [ $# -gt 0 ]; do case "$1" in --server) server="$2"; shift 2 ;; --out) out="$2"; shift 2 ;; *) break ;; esac; done
  [ "$server" = http://192.168.50.1:8480 ] || exit 1
  echo "$*" >>"` + f.asked + `"
  asked=$(wc -l <"` + f.asked + `")
  for mac in "$@"; do
    if [ "$mac" = 38-05-25-38-b5-b5 ] && [ "$asked" -gt ` + publishAfter + ` ]; then
      cp "` + filepath.Join(dir, "published") + `" "$out"
      echo "$mac"
      exit 0
    fi
  done
  exit 4 ;;
esac`
	if err := os.WriteFile(filepath.Join(dir, "fake-rack-node"), []byte("#!/bin/sh\n"+fakeNode+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	for name, body := range fakes {
		if err := os.WriteFile(filepath.Join(f.bin, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return f
}

func (f stickFakes) command(t *testing.T) *exec.Cmd {
	t.Helper()
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("no sh")
	}
	script := stickScript("http://192.168.50.1:8480", stickPaths{Seed: f.seed, Autoinstall: f.autoinstall, Console: f.console, Sys: f.sys, Node: f.node})
	cmd := exec.Command(sh, "-c", strings.ReplaceAll(script, "/run/tuist-prev", f.prev))
	cmd.Env = append(os.Environ(), "PATH="+f.bin+":"+os.Getenv("PATH"))
	return cmd
}

func (f stickFakes) run(t *testing.T) string {
	t.Helper()
	out, err := f.command(t).CombinedOutput()
	if err != nil {
		t.Fatalf("the stick's early-command failed: %v\n%s", err, out)
	}
	return string(out)
}

// runToReboot runs the early-command until it reboots the machine, and returns
// what it did on the way.
func (f stickFakes) runToReboot(t *testing.T) string {
	t.Helper()
	out, _ := f.command(t).CombinedOutput()
	calls, _ := os.ReadFile(f.calls)
	if !strings.Contains(string(calls), "reboot -f") {
		t.Fatalf("did not reboot; calls %q output %q", calls, out)
	}
	return string(calls)
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
	asked, _ := os.ReadFile(f.asked)
	if string(asked) != "58-47-ca-7a-1b-2c 38-05-25-38-b5-b5\n" {
		t.Errorf("did not ask for both NICs, lower-cased and hyphenated, through rack-node: %q", asked)
	}
	fetched, _ := os.ReadFile(f.curlLog)
	if string(fetched) != "http://192.168.50.1:8480/tools/rack-node\n" {
		t.Errorf("did not fetch rack-node from the boot server once: %q", fetched)
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
	// Ubuntu mounts /run noexec, so a rack-node kept there never runs.
	if strings.Contains(early, "node='/run/") {
		t.Error("the installer keeps rack-node under /run, which is mounted noexec")
	}
	for _, want := range []string{
		"server='http://192.168.50.1:8480'",
		`"$server/tools/rack-node"`,
		`"$node" seed --server "$server" --out /run/tuist-user-data $macs`,
		"cp /run/tuist-user-data /autoinstall.yaml",
		`grep -qx "tailnet_key=$id" /run/tuist-prev/etc/tuist-rack-node`,
		// With nothing published, it hands over to a
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
ek=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtestek==
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

// A rack host reboots through its install stick, which is first in its boot
// order so AMT can reinstall it by power-cycling it. With nothing published
// for it, the stick hands it back to its install as soon as the boot server
// says so.
func TestStickHandsAnInstalledMachineBackAtOnce(t *testing.T) {
	f := newStickWorld(t, stickWorld{failures: -1, installed: true})

	calls := f.runToReboot(t)

	if !strings.Contains(calls, "efibootmgr -q -n 0000\n") {
		t.Fatalf("did not boot the installed system next:\n%s", calls)
	}
	asked, _ := os.ReadFile(f.asked)
	if string(asked) != "58-47-ca-7a-1b-2c 38-05-25-38-b5-b5\n" {
		t.Fatalf("asked %q before handing over, want once for both NICs", asked)
	}
}

// A boot server the stick cannot reach does not say nothing is published, so
// the stick keeps asking for five minutes before it hands over: its DHCP may
// still be coming up, and a reinstall may be waiting.
func TestStickWaitsOutAnUnreachableBootServer(t *testing.T) {
	f := newStickWorld(t, stickWorld{failures: -1, unreachable: true, installed: true})

	f.runToReboot(t)

	asked, _ := os.ReadFile(f.curlLog)
	if n := strings.Count(string(asked), "/tools/rack-node\n"); n < 30 {
		t.Fatalf("tried %d times before handing over, want five minutes' worth", n)
	}
}

// A machine that is installed and has an install published is reinstalled.
func TestStickReinstallsAnInstalledMachine(t *testing.T) {
	f := newStickWorld(t, stickWorld{failures: 0, installed: true})

	f.run(t)

	if _, err := os.Stat(f.autoinstall); err != nil {
		t.Fatalf("did not install what is published: %v", err)
	}
}
