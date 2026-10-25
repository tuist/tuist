package rackinstall

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"sigs.k8s.io/yaml"
)

// deployWorld is the live installer the vendor boots: the image as a virtual
// CD, and the box's disks, each with its partitions' labels.
type deployWorld struct {
	// disks are "NAME SIZE TYPE RM TRAN" lines, as lsblk -dbnpo prints them.
	disks []string
	// parts are the target's partitions' labels, "-" for one without.
	parts   []string
	badCopy bool
	noTPM   bool
	dir     string
	cdrom   string
	mnt     string
	partDir string
	console string
	calls   string
	bin     string
	sys     string
}

func newDeployWorld(t *testing.T, w deployWorld) deployWorld {
	t.Helper()
	w.dir = t.TempDir()
	w.cdrom, w.mnt, w.partDir = filepath.Join(w.dir, "cdrom"), filepath.Join(w.dir, "mnt"), filepath.Join(w.dir, "by-partlabel")
	w.bin, w.sys = filepath.Join(w.dir, "bin"), filepath.Join(w.dir, "sys")
	for _, d := range []string{w.cdrom, w.mnt, w.partDir, w.bin} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	w.console, w.calls = filepath.Join(w.dir, "console"), filepath.Join(w.dir, "calls")
	if err := os.WriteFile(w.console, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	writeFakeSys(t, w.sys)
	for name, content := range map[string]string{
		"md5sum.txt":                   "x  ./casper/vmlinuz\n",
		"casper/vmlinuz":               "kernel",
		"boot/grub/grub.cfg":           "\tlinux\t/casper/vmlinuz  autoinstall \"ds=nocloud;s=/cdrom/nocloud/\" console=ttyS1,115200n8 console=tty0 nopersistent ---\n",
		"nocloud/user-data":            "deploy\n",
		ResidentSeedDir + "/user-data": "resident\n",
		"pool/main/e/efibootmgr/efibootmgr_18-1build2_amd64.deb": "deb",
		"tuist/rack-node": "#!/bin/sh\n[ \"$1\" = ek ] && " + map[bool]string{false: "echo " + fakeEK, true: "exit 1"}[w.noTPM] + "\n",
	} {
		path := filepath.Join(w.cdrom, name)
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(content), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(".", filepath.Join(w.cdrom, "ubuntu")); err != nil {
		t.Fatal(err)
	}
	partLines := ""
	for _, p := range w.parts {
		partLines += "part " + p + "\\n"
	}
	md5 := "exit 0"
	if w.badCopy {
		md5 = "exit 1"
	}
	log := `printf '%s %s\n' "$(basename "$0")" "$*" >>"` + w.calls + `"`
	fakes := map[string]string{
		"findmnt": `echo /dev/sr0`,
		"lsblk": `case "$*" in
"-no PKNAME /dev/sr0"|"-no LABEL /dev/sr0") ;;
"-dbnpo NAME,SIZE,TYPE,RM,TRAN") printf '%s\n' "/dev/sr0 4132962304 rom 1 usb" ` + quoteAll(w.disks) + ` ;;
"-nro TYPE "*) printf "` + strings.Repeat("part\\n", len(w.parts)) + `" ;;
"-nro LABEL "*) printf "` + partLines + `" | sed 's/^part //; s/^-$//' ;;
esac`,
		"wipefs":    `[ -z "` + strings.Join(w.parts, "") + `" ] || printf 'DEVICE OFFSET TYPE\nx 0x200 gpt\n'`,
		"sgdisk":    log + `; case "$*" in -n*) touch "` + filepath.Join(w.partDir, InstallerPartLabel) + `" ;; esac`,
		"partprobe": log,
		"udevadm":   log,
		"mkfs.vfat": log,
		"mount":     log,
		"umount":    log,
		// dpkg -x unpacks an efibootmgr that logs its calls.
		"dpkg": `[ "$1" = -x ] && [ -f "$2" ] || exit 2
mkdir -p "$3/usr/bin"
printf '#!/bin/sh\nprintf "%%s %%s\\n" efibootmgr "$*" >>"%s"\n' "` + w.calls + `" >"$3/usr/bin/efibootmgr"
chmod 755 "$3/usr/bin/efibootmgr"`,
		"poweroff": log,
		"sleep":    `:`,
		"md5sum":   md5,
		"sed":      `if [ "$1" = -i ]; then perl -pi -e "$2" "$3"; else exec /usr/bin/sed "$@"; fi`,
	}
	for name, body := range fakes {
		if err := os.WriteFile(filepath.Join(w.bin, name), []byte("#!/bin/sh\n"+body+"\n"), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return w
}

func quoteAll(lines []string) string {
	var q []string
	for _, l := range lines {
		q = append(q, "'"+l+"'")
	}
	return strings.Join(q, " ")
}

// fakeEK stands in for a TPM's RSA endorsement key, base64 PKIX DER.
const fakeEK = "Jg+YxDFxN1MX6cy0tT5m0qAilWUNPo8l92LJqOkN1R8a4diMDjmBGRnxrmQAXlDd"

func (w deployWorld) run(t *testing.T) (string, string) {
	t.Helper()
	sh, err := exec.LookPath("sh")
	if err != nil {
		t.Skip("no sh")
	}
	for _, tool := range []string{"perl", "tar", "base64", "sha256sum"} {
		if _, err := exec.LookPath(tool); err != nil {
			t.Skipf("no %s", tool)
		}
	}
	script := deployScript(deployPaths{Cdrom: w.cdrom, Consoles: w.console + " " + filepath.Join(w.dir, "ttyS1"), Sys: w.sys, Mount: w.mnt, PartDir: w.partDir, Run: w.dir, Tools: w.dir})
	// fail waits forever for someone to power the machine off; the test
	// ends it instead.
	script = strings.Replace(script, "while :; do sleep 3600; done", "exit 9", 1)
	cmd := exec.Command(sh, "-c", script)
	cmd.Env = append(os.Environ(), "PATH="+w.bin+":"+os.Getenv("PATH"))
	out, _ := cmd.CombinedOutput()
	calls, _ := os.ReadFile(w.calls)
	return string(out), string(calls)
}

func TestDeployWritesTheInstallerOntoABlankBootDrive(t *testing.T) {
	w := newDeployWorld(t, deployWorld{disks: []string{"/dev/nvme0n1 480103981056 disk 0 nvme"}})
	out, calls := w.run(t)
	for _, want := range []string{
		"sgdisk -n 1:1MiB:+4GiB -t 1:EF00 -c 1:tuist-installer /dev/nvme0n1",
		"mkfs.vfat -F 32 -n TUISTINST " + filepath.Join(w.partDir, InstallerPartLabel),
		`efibootmgr -q -c -d /dev/nvme0n1 -p 1 -L tuist installer -l \EFI\boot\bootx64.efi`,
		"poweroff -f",
	} {
		if !strings.Contains(calls, want+"\n") {
			t.Errorf("did not run %q; ran:\n%s", want, calls)
		}
	}
	seed, err := os.ReadFile(filepath.Join(w.mnt, "nocloud", "user-data"))
	if err != nil || string(seed) != "resident\n" {
		t.Errorf("the partition boots %q, not the resident seed: %v", seed, err)
	}
	if _, err := os.Stat(filepath.Join(w.mnt, ResidentSeedDir)); !os.IsNotExist(err) {
		t.Errorf("the resident seed is still under %s", ResidentSeedDir)
	}
	if _, err := os.Lstat(filepath.Join(w.mnt, "ubuntu")); !os.IsNotExist(err) {
		t.Errorf("the medium's ubuntu -> . link was copied onto FAT")
	}
	grub, _ := os.ReadFile(filepath.Join(w.mnt, "boot", "grub", "grub.cfg"))
	if !strings.Contains(string(grub), `autoinstall "ds=nocloud;s=/cdrom/nocloud/" console=ttyS1,115200n8 console=tty0 live-media=/dev/disk/by-label/TUISTINST nopersistent toram ---`) {
		t.Errorf("GRUB does not boot casper from the partition:\n%s", grub)
	}
	der, _ := base64.StdEncoding.DecodeString(fakeEK)
	sum := sha256.Sum256(der)
	fp := hex.EncodeToString(sum[:])
	sheet, _ := os.ReadFile(filepath.Join(w.mnt, "tuist", "unit-sheet.txt"))
	for _, want := range []string{
		"serial: MD148LS139QQMQE00070",
		"uuid: 44312e80-1dc6-11f1-853e-8f903547d200",
		"nic: 58:47:ca:7a:1b:2c i40e enp2s0f0np0",
		"nic: 38:05:25:38:b5:b5 igc enp89s0",
		"tpm ek sha256: " + fp,
		"tpm check code: " + fp[0:4] + "-" + fp[4:8] + "-" + fp[8:12] + "-" + fp[12:16],
	} {
		if !strings.Contains(string(sheet), want+"\n") {
			t.Errorf("the unit sheet lacks %q:\n%s", want, sheet)
		}
	}
	console, _ := os.ReadFile(w.console)
	if !strings.Contains(string(console), "tpm check code: ") || !strings.Contains(string(console), "DEPLOY OK") {
		t.Errorf("the console does not show the sheet and the result:\n%s\n%s", console, out)
	}
}

// On a storage node the boot drive is the small M.2, never the data drive.
func TestDeployPicksTheBootDriveOverTheDataDrive(t *testing.T) {
	w := newDeployWorld(t, deployWorld{disks: []string{
		"/dev/nvme1n1 12800000000000 disk 0 nvme",
		"/dev/nvme0n1 480103981056 disk 0 nvme",
		"/dev/sda 64000000000 disk 1 usb",
	}})
	_, calls := w.run(t)
	if !strings.Contains(calls, "-c 1:tuist-installer /dev/nvme0n1\n") || strings.Contains(calls, "nvme1n1") {
		t.Errorf("did not write the boot drive alone:\n%s", calls)
	}
}

// Booting the image on a box that runs anything destroys nothing.
func TestDeployRefusesADriveThatIsNotBlank(t *testing.T) {
	w := newDeployWorld(t, deployWorld{disks: []string{"/dev/nvme0n1 480103981056 disk 0 nvme"}, parts: []string{"-", "-", "-"}})
	out, calls := w.run(t)
	if strings.Contains(calls, "sgdisk") || strings.Contains(calls, "efibootmgr") {
		t.Errorf("wrote a drive that is not blank:\n%s", calls)
	}
	console, _ := os.ReadFile(w.console)
	if !strings.Contains(string(console), "DEPLOY FAILED: /dev/nvme0n1 is not blank (3 partitions") {
		t.Errorf("console:\n%s\n%s", console, out)
	}
}

// A newer image replaces the installer partition an older one wrote.
func TestDeployReplacesAnInstallerPartition(t *testing.T) {
	w := newDeployWorld(t, deployWorld{disks: []string{"/dev/nvme0n1 480103981056 disk 0 nvme"}, parts: []string{InstallerLabel}})
	_, calls := w.run(t)
	if !strings.Contains(calls, "sgdisk --zap-all /dev/nvme0n1\n") || !strings.Contains(calls, "poweroff -f\n") {
		t.Errorf("did not replace the installer partition:\n%s", calls)
	}
}

func TestDeployStopsOnABadCopy(t *testing.T) {
	w := newDeployWorld(t, deployWorld{disks: []string{"/dev/nvme0n1 480103981056 disk 0 nvme"}, badCopy: true})
	_, calls := w.run(t)
	if strings.Contains(calls, "efibootmgr") || strings.Contains(calls, "poweroff") {
		t.Errorf("went on after a bad copy:\n%s", calls)
	}
}

func TestDeploySaysWhenThereIsNoTPM(t *testing.T) {
	w := newDeployWorld(t, deployWorld{disks: []string{"/dev/nvme0n1 480103981056 disk 0 nvme"}, noTPM: true})
	w.run(t)
	sheet, _ := os.ReadFile(filepath.Join(w.mnt, "tuist", "unit-sheet.txt"))
	if !strings.Contains(string(sheet), "tpm: NONE FOUND\n") || strings.Contains(string(sheet), "check code") {
		t.Errorf("sheet:\n%s", sheet)
	}
}

func TestPreinstallDeployUserData(t *testing.T) {
	var seed stickSeed
	out := PreinstallDeployUserData()
	if err := yaml.Unmarshal([]byte(out), &seed); err != nil {
		t.Fatalf("user-data is not YAML: %v\n%s", err, out)
	}
	if seed.Autoinstall.Version != 1 || len(seed.Autoinstall.EarlyCommands) != 1 || !strings.Contains(seed.Autoinstall.EarlyCommands[0], "poweroff -f") {
		t.Fatalf("user-data:\n%s", out)
	}
	if sh, err := exec.LookPath("sh"); err == nil {
		if out, err := exec.Command(sh, "-n", "-c", seed.Autoinstall.EarlyCommands[0]).CombinedOutput(); err != nil {
			t.Fatalf("the early-command is not valid shell: %v\n%s", err, out)
		}
	}
}
