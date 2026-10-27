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

const internetBootServer = "https://rack-boot.example.dev"

var larchWAN = StaticWAN{Site: "larch", Address: "149.6.170.31/31", Gateway: "149.6.170.30", VLAN: 4001}

// residentWorld is a preinstalled box at a site whose only way out is the
// carrier's static handoff, which answers on gatewayDev alone, and whose
// internet boot server publishes the box's install once it is online.
type residentWorld struct {
	gatewayDev string
	// taken is the WAN address already being held, by the site's other edge.
	taken bool
	// keep publishes an install that keeps the installer partition, onto a
	// drive that still holds a previous install's partitions.
	keep  bool
	dir   string
	paths stickPaths
	calls string
	asked string
}

func newResidentWorld(t *testing.T, w residentWorld) residentWorld {
	t.Helper()
	w.dir = t.TempDir()
	bin, medium := filepath.Join(w.dir, "bin"), filepath.Join(w.dir, "medium")
	w.calls, w.asked = filepath.Join(w.dir, "calls"), filepath.Join(w.dir, "asked")
	w.paths = stickPaths{Seed: filepath.Join(w.dir, "user-data"), Autoinstall: filepath.Join(w.dir, "autoinstall.yaml"),
		Console: filepath.Join(w.dir, "console"), Sys: filepath.Join(w.dir, "sys"), Node: filepath.Join(w.dir, "rack-node"),
		Uptime: filepath.Join(w.dir, "uptime"), Medium: medium, Dev: filepath.Join(w.dir, "dev")}
	// The installer partition, by its label.
	if err := os.MkdirAll(filepath.Join(w.dir, "dev", "disk", "by-label"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(w.dir, "dev", "nvme0n1p1"), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(filepath.Join(w.dir, "dev", "nvme0n1p1"), filepath.Join(w.dir, "dev", "disk", "by-label", InstallerLabel)); err != nil {
		t.Fatal(err)
	}
	writeFakeSys(t, w.paths.Sys)
	for nic, carrier := range map[string]string{"enp2s0f0np0": "1\n", "enp89s0": "0\n"} {
		if err := os.WriteFile(filepath.Join(w.paths.Sys, "class/net", nic, "carrier"), []byte(carrier), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	for _, d := range []string{bin, filepath.Join(medium, "tuist")} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(w.paths.Uptime, []byte("1000.00 0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	seed := edgeSeed()
	seed.ResidentInstaller = w.keep
	published, err := UserData(seed)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(w.dir, "published"), []byte(published), 0o600); err != nil {
		t.Fatal(err)
	}
	route := filepath.Join(w.dir, "route")
	taken := "0"
	if w.taken {
		taken = "1"
	}
	log := `printf '%s %s\n' "$(basename "$0")" "$*" >>"` + w.calls + `"`
	fakes := map[string]string{
		"ip": log + `
case "$*" in
"-4 route show default") cat "` + route + `" 2>/dev/null ;;
"route add default via "*) echo "default via $5 dev $7" >"` + route + `" ;;
"-o link show") printf '2: enp2s0f0np0: <UP> mtu 1500\\    link/ether 58:47:ca:7a:1b:2c brd ff:ff:ff:ff:ff:ff\n3: enp89s0: <UP> mtu 1500\\    link/ether 38:05:25:38:b5:b5 brd ff:ff:ff:ff:ff:ff\n' ;;
esac`,
		"busybox": log + `
[ "$1" = arping ] || exit 1
case "$*" in *" -D "*) [ ` + taken + ` = 0 ] ;; *) case "$*" in *"-I ` + w.gatewayDev + ` "*) exit 0 ;; *) exit 1 ;; esac ;; esac`,
		"resolvectl": log,
		"curl":       `exit 7`,
		"sleep":      `awk '{printf "%.2f 0\n", $1 + '"$1"'}' "` + w.paths.Uptime + `" >"` + w.paths.Uptime + `.n" && mv "` + w.paths.Uptime + `.n" "` + w.paths.Uptime + `"`,
		"lsblk": `case "$*" in
"-no PKNAME "*) echo nvme0n1 ;;
"-bdno SIZE /dev/nvme0n1") echo 480103981056 ;;
esac`,
		// The drive holds the installer and the install before this one.
		"sgdisk": log + `
[ "$1" = -p ] && printf 'Number  Start (sector)    End (sector)  Size       Code  Name\n   1            2048         8390655   4.0 GiB     EF00  tuist-installer\n   2         8390656        10487807   1024.0 MiB  EF00\n   3        10487808        14682111   2.0 GiB     8300\n   4        14682112       937701375   440.1 GiB   8300\n'
exit 0`,
		"partprobe": log,
		"udevadm":   log,
		"sed":       `if [ "$1" = -i ]; then perl -pi -e "$2" "$3"; else exec /usr/bin/sed "$@"; fi`,
	}
	for name, body := range fakes {
		if err := os.WriteFile(filepath.Join(bin, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	// The site's boot server does not exist yet; the internet's publishes the
	// install once the box is online.
	node := `case "$1" in
ek) echo ` + fakeEK + ` ;;
seed)
  shift
  while [ $# -gt 0 ]; do case "$1" in --server) server="$2"; shift 2 ;; --out) out="$2"; shift 2 ;; *) break ;; esac; done
  echo "$server" >>"` + w.asked + `"
  [ "$server" = ` + internetBootServer + ` ] && [ -s "` + route + `" ] || exit 1
  cp "` + filepath.Join(w.dir, "published") + `" "$out"
  echo "$2"
  exit 0 ;;
esac`
	if err := os.WriteFile(filepath.Join(medium, "tuist", "rack-node"), []byte("#!/bin/sh\n"+node+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	return w
}

func (w residentWorld) run(t *testing.T, wans []StaticWAN) (string, error) {
	t.Helper()
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("no sh")
	}
	script := stickScript(stickConfig{Servers: []string{"http://192.168.50.1:8480", internetBootServer}, WANs: wans}, w.paths)
	// It would wait for an install for ever; a test ends after a few passes.
	script = strings.Replace(script, "  sleep 10\ndone", "  sleep 10\n  [ $(($(uptime) - started)) -lt 120 ] || exit 3\ndone", 1)
	cmd := exec.Command(sh, "-c", strings.ReplaceAll(script, "/run/tuist-prev", filepath.Join(w.dir, "prev")))
	cmd.Env = append(os.Environ(), "PATH="+filepath.Join(w.dir, "bin")+":"+os.Getenv("PATH"))
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// The first edge of a site has no DHCP and no boot server on site: it takes
// the site's static WAN on the port the carrier's handoff reaches, on the
// site's VLAN when the switch tags it, and asks the internet's boot server.
func TestResidentTakesTheSitesStaticWANAndAsksTheInternet(t *testing.T) {
	w := newResidentWorld(t, residentWorld{gatewayDev: "enp2s0f0np0.4001"})
	if out, err := w.run(t, []StaticWAN{larchWAN}); err != nil {
		t.Fatalf("did not install: %v\n%s", err, out)
	}
	calls, _ := os.ReadFile(w.calls)
	for _, want := range []string{
		// Untagged first, which a factory switch passes; its gateway is silent.
		"ip addr add 149.6.170.31/31 dev enp2s0f0np0",
		"ip addr del 149.6.170.31/31 dev enp2s0f0np0",
		"ip link add link enp2s0f0np0 name enp2s0f0np0.4001 type vlan id 4001",
		"ip addr add 149.6.170.31/31 dev enp2s0f0np0.4001",
		"ip route add default via 149.6.170.30 dev enp2s0f0np0.4001",
		"resolvectl dns enp2s0f0np0.4001 1.1.1.1 8.8.8.8",
	} {
		if !strings.Contains(string(calls), want+"\n") {
			t.Errorf("did not run %q:\n%s", want, calls)
		}
	}
	if strings.Contains(string(calls), "enp89s0") {
		t.Errorf("tried a port with no link:\n%s", calls)
	}
	if _, err := os.Stat(w.paths.Autoinstall); err != nil {
		t.Fatalf("did not install what the internet boot server published: %v", err)
	}
	asked, _ := os.ReadFile(w.asked)
	if !strings.HasPrefix(string(asked), "http://192.168.50.1:8480\n"+internetBootServer+"\n") {
		t.Errorf("asked %q, want the site's boot server before the internet's", asked)
	}
	console, _ := os.ReadFile(w.paths.Console)
	if !strings.Contains(string(console), "took larch's static WAN 149.6.170.31/31 on enp2s0f0np0.4001, through 149.6.170.30") {
		t.Errorf("console:\n%s", console)
	}
}

// The site's other edge already holds the WAN address: a second box must not
// take it from under it.
func TestResidentLeavesAStaticWANSomeoneHolds(t *testing.T) {
	w := newResidentWorld(t, residentWorld{gatewayDev: "enp2s0f0np0", taken: true})
	if _, err := w.run(t, []StaticWAN{larchWAN}); err == nil {
		t.Fatal("installed without a way out")
	}
	calls, _ := os.ReadFile(w.calls)
	if strings.Contains(string(calls), "ip addr add") || strings.Contains(string(calls), "ip route add") {
		t.Errorf("took an address someone holds:\n%s", calls)
	}
}

func TestResidentUserData(t *testing.T) {
	out, err := ResidentUserData([]string{"http://192.168.50.1:8480", internetBootServer}, []StaticWAN{larchWAN})
	if err != nil {
		t.Fatal(err)
	}
	var seed stickSeed
	if err := yaml.Unmarshal([]byte(out), &seed); err != nil {
		t.Fatalf("user-data is not YAML: %v\n%s", err, out)
	}
	early := seed.Autoinstall.EarlyCommands[0]
	for _, want := range []string{
		"servers='http://192.168.50.1:8480 " + internetBootServer + "'",
		"larch 149.6.170.31/31 149.6.170.30 4001\n",
		"cp /cdrom/tuist/rack-node",
	} {
		if !strings.Contains(early, want) {
			t.Errorf("early-command lacks %q", want)
		}
	}
	if sh, err := exec.LookPath("sh"); err == nil {
		if out, err := exec.Command(sh, "-n", "-c", early).CombinedOutput(); err != nil {
			t.Fatalf("not valid shell: %v\n%s", err, out)
		}
	}
	for _, bad := range [][]string{nil, {"ftp://x"}, {"https://x/path"}} {
		if _, err := ResidentUserData(bad, nil); err == nil {
			t.Errorf("servers %q were accepted", bad)
		}
	}
	if _, err := ResidentUserData([]string{internetBootServer}, []StaticWAN{{Site: "larch", Address: "149.6.170.31", Gateway: "149.6.170.30", VLAN: 4001}}); err == nil {
		t.Error("a WAN address without a prefix was accepted")
	}
}

// An install that keeps the installer partition goes onto the drive the
// partition is on, in all the space after it: the installer deletes every
// other partition, which the install cannot on a drive it keeps, and fills in
// the drive and the space left.
func TestResidentKeepsItsPartitionAndClearsTheRest(t *testing.T) {
	w := newResidentWorld(t, residentWorld{gatewayDev: "enp2s0f0np0", keep: true})
	if out, err := w.run(t, []StaticWAN{larchWAN}); err != nil {
		t.Fatalf("did not install: %v\n%s", err, out)
	}
	calls, _ := os.ReadFile(w.calls)
	for _, n := range []string{"2", "3", "4"} {
		if !strings.Contains(string(calls), "sgdisk -d "+n+" /dev/nvme0n1\n") {
			t.Errorf("did not delete partition %s:\n%s", n, calls)
		}
	}
	if strings.Contains(string(calls), "sgdisk -d 1 ") {
		t.Errorf("deleted the installer partition:\n%s", calls)
	}
	installed, err := os.ReadFile(w.paths.Autoinstall)
	if err != nil {
		t.Fatal(err)
	}
	rest := (480103981056/1048576 - 1 - 4096 - 1024 - 2048 - 2) * 1048576
	for _, want := range []string{"match: {path: /dev/nvme0n1}", "number: 4, size: " + strconv.Itoa(rest) + "}", "id: installer, device: disk0, number: 1, offset: 1048576, size: 4294967296, preserve: true"} {
		if !strings.Contains(string(installed), want) {
			t.Errorf("the install lacks %q", want)
		}
	}
	if strings.Contains(string(installed), InstallerDiskPlaceholder) || strings.Contains(string(installed), InstallerRestPlaceholder) {
		t.Errorf("a placeholder is left in the install")
	}
}
