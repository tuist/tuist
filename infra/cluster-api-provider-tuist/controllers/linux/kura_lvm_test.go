package linux

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
)

// Execute the actual conversion against a durable fake block-device state.
// Only host commands are replaced; the journal, retry flow and fstab writes
// run in a temporary filesystem, including failures between destructive steps.
func TestKuraLVMConversion(t *testing.T) {
	for _, interruption := range []string{"", "wipefs", "pvcreate", "vgcreate", "lvcreate", "mkfs.xfs", "mount"} {
		t.Run("resume_after_"+interruption, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.MkdirAll(filepath.Join(dir, "data"), 0755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(dir, "fstab"), []byte("UUID=old "+dir+"/data xfs defaults 0 0\nUUID=root / ext4 defaults 0 1\n"), 0644); err != nil {
				t.Fatal(err)
			}
			if interruption != "" {
				os.WriteFile(filepath.Join(dir, "fail"), []byte(interruption), 0644)
			}
			run := func() ([]byte, error) {
				script := strings.NewReplacer("/var/lib/tuist", dir+"/state", "/etc/fstab", dir+"/fstab", "/data", dir+"/data").Replace(kuraLVMSetupScript)
				// Do not rewrite the LV name or LVM query, which are not host paths.
				script = strings.ReplaceAll(script, "/dev/kura-volumes"+dir+"/data", "/dev/kura-volumes/data")
				script = strings.ReplaceAll(script, "$vg"+dir+"/data", "$vg/data")
				cmd := exec.Command("bash", "-c", lvmTestHost+"\n"+script+"\nkura_lvm_setup")
				cmd.Env = append(os.Environ(), "TEST_LVM_ROOT="+dir)
				return cmd.CombinedOutput()
			}
			out, err := run()
			if interruption != "" {
				if err == nil {
					t.Fatalf("expected interruption after %s: %s", interruption, out)
				}
				out, err = run()
			}
			if err != nil {
				t.Fatalf("conversion: %v\n%s", err, out)
			}
			before, _ := os.ReadFile(filepath.Join(dir, "commands"))
			if out, err := run(); err != nil {
				t.Fatalf("idempotent retry: %v\n%s", err, out)
			}
			after, _ := os.ReadFile(filepath.Join(dir, "commands"))
			for _, destructive := range []string{"wipefs", "pvcreate", "vgcreate", "lvcreate", "mkfs.xfs"} {
				expected := 1
				if destructive == "wipefs" && interruption == "wipefs" {
					expected = 2
				}
				if strings.Count(string(before), destructive+"\n") != expected || strings.Count(string(after), destructive+"\n") != expected {
					t.Fatalf("%s must happen exactly once across retries:\n%s", destructive, after)
				}
			}
			fstab, _ := os.ReadFile(filepath.Join(dir, "fstab"))
			if strings.Count(string(fstab), "UUID=data-lv") != 1 || strings.Contains(string(fstab), "UUID=old") || !strings.Contains(string(fstab), "prjquota") || !strings.Contains(string(fstab), "UUID=root") {
				t.Fatalf("fstab: %s", fstab)
			}
		})
	}
}

func TestKuraLVMRefusesExistingData(t *testing.T) {
	for _, reason := range []string{"workload", "joined", "kubelet"} {
		t.Run(reason, func(t *testing.T) {
			dir := t.TempDir()
			os.MkdirAll(dir+"/data", 0755)
			os.MkdirAll(dir+"/state", 0755)
			file := dir + "/data/cache"
			if reason == "joined" {
				file = dir + "/state/joined-node"
			}
			if reason == "kubelet" {
				file = dir + "/kubelet"
			}
			os.WriteFile(file, []byte("existing"), 0644)
			script := strings.NewReplacer("/var/lib/tuist", dir+"/state", "/data", dir+"/data").Replace(kuraLVMSetupScript)
			cmd := exec.Command("bash", "-c", lvmTestHost+"\n"+script+"\nkura_lvm_setup")
			cmd.Env = append(os.Environ(), "TEST_LVM_ROOT="+dir)
			if out, err := cmd.CombinedOutput(); err == nil {
				t.Fatalf("accepted existing %s: %s", reason, out)
			}
			if commands, _ := os.ReadFile(dir + "/commands"); len(commands) != 0 {
				t.Fatalf("mutated existing host: %s", commands)
			}
		})
	}
}

func TestKuraLVMUnmountedInstallerData(t *testing.T) {
	for _, scenario := range []string{"empty", "populated", "ambiguous", "missing", "mounted-elsewhere", "shadowed-directory"} {
		t.Run(scenario, func(t *testing.T) {
			dir := t.TempDir()
			os.MkdirAll(dir+"/data", 0755)
			os.WriteFile(dir+"/fstab", []byte("UUID=root / ext4 defaults 0 1\n"), 0644)
			os.WriteFile(dir+"/unmounted", nil, 0644)
			candidates := "/dev/md127 xfs\n/dev/md127 xfs\n"
			if scenario == "missing" {
				candidates = "/dev/md0 ext4\n"
			}
			if scenario == "ambiguous" {
				candidates += "/dev/md126 xfs\n"
			}
			os.WriteFile(dir+"/candidates", []byte(candidates), 0644)
			if scenario == "populated" || scenario == "mounted-elsewhere" {
				os.WriteFile(dir+"/"+scenario, nil, 0644)
			}
			if scenario == "shadowed-directory" {
				os.WriteFile(dir+"/data/cache", []byte("existing"), 0644)
			}
			script := strings.NewReplacer("/var/lib/tuist", dir+"/state", "/etc/fstab", dir+"/fstab", "/data", dir+"/data").Replace(kuraLVMSetupScript)
			script = strings.ReplaceAll(script, "/dev/kura-volumes"+dir+"/data", "/dev/kura-volumes/data")
			script = strings.ReplaceAll(script, "$vg"+dir+"/data", "$vg/data")
			cmd := exec.Command("bash", "-c", lvmTestHost+"\n"+script+"\nkura_lvm_setup")
			cmd.Env = append(os.Environ(), "TEST_LVM_ROOT="+dir)
			out, err := cmd.CombinedOutput()
			commands, _ := os.ReadFile(dir + "/commands")
			if scenario == "empty" {
				if err != nil || !strings.Contains(string(commands), "inspect-readonly\n") || !strings.Contains(string(commands), "vgcreate\n") {
					t.Fatalf("fresh unmounted install: %v\n%s\n%s", err, out, commands)
				}
			} else {
				if err == nil || strings.Contains(string(commands), "wipefs") {
					t.Fatalf("unsafe discovery accepted: %v\n%s\n%s", err, out, commands)
				}
				if _, err := os.Stat(dir + "/unmounted"); err != nil {
					t.Fatal("failed inspection must not leave the filesystem mounted")
				}
			}
		})
	}
}

func TestKuraLVMBootstrapOrdering(t *testing.T) {
	for _, key := range []string{kuraCacheTaintKey, "tuist.dev/runner-cache"} {
		script := renderLinuxBootstrapScript(linuxCloudInitOptions{NodeName: "node", Taints: []corev1.Taint{{Key: key, Effect: corev1.TaintEffectNoSchedule}}})
		guard, lvm, quota := strings.Index(script, "already joined as"), strings.Index(script, "kura_lvm_setup()"), strings.Index(script, dataProjectQuotaPath)
		if guard < 0 || lvm < guard || quota < lvm {
			t.Fatal("conversion must follow joined guard and precede quotas/binds")
		}
	}
	if strings.Contains(renderLinuxBootstrapScript(linuxCloudInitOptions{NodeName: "runner"}), "kura_lvm_setup()") {
		t.Fatal("non-cache host must not convert storage")
	}
}

const lvmTestHost = `
set -euo pipefail
r="$TEST_LVM_ROOT"
step() {
  echo "$1" >> "$r/commands"
  if [ -f "$r/fail" ] && [ "$(cat "$r/fail")" = "$1" ]; then rm "$r/fail"; exit 42; fi
}
[() { if [[ "${1:-}" == -b ]]; then return 0; fi; builtin [ "$@"; }
sync() { :; }
systemctl() { if [ "${1:-}" = is-active ]; then [ -f "$r/kubelet" ]; else :; fi; }
vgs() { [ -f "$r/vg" ]; }
pvs() { [ -f "$r/pv" ] || return 1; if [ -f "$r/vg" ]; then echo kura-volumes; fi; }
lvs() { [ -f "$r/lv" ]; }
mountpoint() { [ ! -f "$r/unmounted" ]; }
findmnt() {
  case "$*" in
    *FSTYPE*) echo xfs;;
    *SOURCE*) if [ "${@: -1}" = / ]; then echo /dev/md0; elif [ -f "$r/mounted-lv" ]; then echo /dev/kura-volumes/data; else echo /dev/md127; fi;;
  esac
}
readlink() { echo "${@: -1}"; }
lsblk() {
  if [[ "$*" == *NAME,FSTYPE* ]]; then cat "$r/candidates";
  elif [ -f "$r/mounted-elsewhere" ]; then echo /occupied; fi
}
umount() { touch "$r/unmounted"; }
mount() {
  rm -f "$r/unmounted"
  if [[ "$*" == *ro,norecovery* ]]; then
    step inspect-readonly
    if [ -f "$r/populated" ]; then touch "$r/data/cache"; fi
  else
    touch "$r/mounted-lv"; step mount
  fi
}
wipefs() { step wipefs; }
pvcreate() { touch "$r/pv"; step pvcreate; }
vgcreate() { touch "$r/vg"; step vgcreate; }
lvcreate() { touch "$r/lv"; step lvcreate; }
vgchange() { :; }
blkid() { case "$*" in *TYPE*) [ -f "$r/formatted" ] && echo xfs;; *UUID*) echo data-lv;; esac; }
mkfs.xfs() { touch "$r/formatted"; step mkfs.xfs; }
`
