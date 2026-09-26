package linux

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// installerHost fakes what the boot-installer script reads on a running host:
// the firmware's boot entries (a stateful efibootmgr), its disks, and what
// mounting a USB disk finds.
type installerHost struct {
	bin, calls string
}

const installerEntries = `Boot0001* UEFI PXEv4 (MAC:5847CA7A1B2C)	PciRoot(0x0)/Pci(0x1c,0x0)/Pci(0x0,0x0)/MAC(5847ca7a1b2c,0)/IPv4(0.0.0.0,0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
Boot0002* UEFI HTTPv4 (MAC:38052538B5B5)	PciRoot(0x0)/Pci(0x1c,0x4)/Pci(0x0,0x0)/MAC(38052538b5b5,0)/IPv4(0.0.0.0,0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)/Uri()
Boot0003* UEFI PXEv4 (MAC:38052538B5B5)	PciRoot(0x0)/Pci(0x1c,0x4)/Pci(0x0,0x0)/MAC(38052538b5b5,0)/IPv4(0.0.0.0,0,DHCP,0.0.0.0,0.0.0.0,0.0.0.0)
Boot0004* Ubuntu	HD(1,GPT,5c1d6e2a-0000-0000-0000-000000000000,0x800,0x219800)/File(\EFI\ubuntu\shimx64.efi)
Boot0007* tuist install stick	HD(2,GPT,0badf00d-0000-0000-0000-000000000000,0x796998,0x27b0)/File(\EFI\BOOT\BOOTX64.EFI)
`

// newInstallerHost fakes a host with the given USB disks: "stick" is an
// install stick, "other" a USB disk with an EFI partition that is not one.
func newInstallerHost(t *testing.T, usb ...string) installerHost {
	t.Helper()
	dir := t.TempDir()
	h := installerHost{bin: filepath.Join(dir, "bin"), calls: filepath.Join(dir, "calls")}
	state := filepath.Join(dir, "entries")
	if err := os.WriteFile(state, []byte(installerEntries), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(h.bin, 0o755); err != nil {
		t.Fatal(err)
	}
	disks := "/dev/nvme0n1 nvme disk\n"
	parts := ""
	mounts := ""
	for i, kind := range usb {
		dev := "/dev/sd" + string(rune('a'+i))
		disks += dev + " usb disk\n"
		parts += `  ` + dev + `) printf '%s\n%s1 a2a0d0eb-e5b9-3344-87c0-68b6b72699c7\n%s2 C12A7328-F81F-11D2-BA4B-00A0C93EC93B\n' ` + dev + ` ` + dev + ` ` + dev + ` ;;` + "\n"
		if kind == "stick" {
			mounts += `  ` + dev + `) mkdir -p "$6/nocloud" && : >"$6/nocloud/tuist-install-stick" ;;` + "\n"
		} else {
			mounts += `  ` + dev + `) mkdir -p "$6/nocloud" ;;` + "\n"
		}
	}
	fakes := map[string]string{
		"efibootmgr": `echo "efibootmgr $*" >>"` + h.calls + `"
state="` + state + `"
case "$*" in
  ""|-v) printf 'BootCurrent: 0004\nBootOrder: 0004,0001,0002,0003\n'; cat "$state" ;;
  "-q -b "*" -B") grep -v "^Boot$3" "$state" >"$state.new"; mv "$state.new" "$state" ;;
  "-q -C "*) printf 'Boot0008* %s\tHD(%s,GPT,feedface-0000-0000-0000-000000000000,0x796998,0x27b0)/File(%s)\n' "$8" "$6" "${10}" >>"$state" ;;
esac`,
		"lsblk": `case "$*" in
  "-dnpo NAME,TRAN,TYPE") printf '` + strings.ReplaceAll(disks, "\n", `\n`) + `' ;;
  "-lnpo NAME,PARTTYPE "*) case "$3" in
` + parts + `  esac ;;
esac`,
		"mount": `case "$5" in
` + mounts + `  *) exit 32 ;;
esac`,
		"umount":    `rm -rf "$1/nocloud"`,
		"systemctl": `echo "systemctl $*" >>"` + h.calls + `"`,
		"sleep":     `:`,
	}
	for name, body := range fakes {
		if err := os.WriteFile(filepath.Join(h.bin, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return h
}

func (h installerHost) run(t *testing.T, mac string) (string, error) {
	t.Helper()
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	cmd := exec.Command(bash, "-s")
	cmd.Stdin = strings.NewReader(renderBootInstallerOnceScript(mac))
	cmd.Env = append(os.Environ(), "PATH="+h.bin+":"+os.Getenv("PATH"))
	out, err := cmd.CombinedOutput()
	return string(out), err
}

// rebooted waits for the script's delayed reboot and returns every call it
// made.
func (h installerHost) rebooted(t *testing.T, out string) string {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for {
		recorded, _ := os.ReadFile(h.calls)
		if strings.Contains(string(recorded), "systemctl reboot") {
			return string(recorded)
		}
		if time.Now().After(deadline) {
			t.Fatalf("no reboot; calls %q output %q", recorded, out)
		}
		time.Sleep(50 * time.Millisecond)
	}
}

// A host with the install stick boots it, through a boot entry of its own that
// stays out of BootOrder, replacing the one an earlier stick left.
func TestBootInstallerOnceBootsTheInstallStick(t *testing.T) {
	h := newInstallerHost(t, "other", "stick")
	out, err := h.run(t, svcMAC)
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	calls := h.rebooted(t, out)
	for _, want := range []string{
		"efibootmgr -q -b 0007 -B\n",
		`efibootmgr -q -C -d /dev/sdb -p 2 -L tuist install stick -l \EFI\BOOT\BOOTX64.EFI` + "\n",
		"efibootmgr -q -n 0008\n",
	} {
		if !strings.Contains(calls, want) {
			t.Errorf("calls lack %q:\n%s", want, calls)
		}
	}
	if strings.Contains(calls, "-d /dev/sda") || strings.Contains(calls, "-n 0003") {
		t.Errorf("booted something other than the stick:\n%s", calls)
	}
	if !strings.Contains(out, "BootNext=0008, the install stick /dev/sdb") {
		t.Errorf("output %q", out)
	}
}

// Without a stick, the host netboots from its boot NIC's PXEv4 entry.
func TestBootInstallerOnceNetbootsWithoutAStick(t *testing.T) {
	h := newInstallerHost(t, "other")
	out, err := h.run(t, svcMAC)
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	calls := h.rebooted(t, out)
	if !strings.Contains(calls, "efibootmgr -q -n 0003\n") || strings.Contains(calls, "-C") || strings.Contains(calls, "-B") {
		t.Fatalf("calls %q, want BootNext set to the PXEv4 entry of the boot NIC and no entry touched", calls)
	}
}

func TestBootInstallerOnceRefusesAHostWithNeither(t *testing.T) {
	h := newInstallerHost(t)
	out, err := h.run(t, "aa:bb:cc:dd:ee:ff")
	if err == nil || !strings.Contains(out, "no install stick and no IPv4 network boot entry for aa:bb:cc:dd:ee:ff") {
		t.Fatalf("err %v output %q", err, out)
	}
	if calls, _ := os.ReadFile(h.calls); strings.Contains(string(calls), "-n ") {
		t.Fatalf("set BootNext: %s", calls)
	}
}
