//go:build linux

package diskallocator

import (
	"os"
	"path/filepath"
	"testing"
)

func TestProvisionerVolumeRoot(t *testing.T) {
	root := t.TempDir()
	mount, alias, other := filepath.Join(root, "data"), filepath.Join(root, "provisioner"), filepath.Join(root, "provisioner-other")
	for _, dir := range []string{mount, alias, other, filepath.Join(alias, "pvc"), filepath.Join(mount, "pvc")} {
		if err := os.MkdirAll(dir, 0700); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.Symlink(other, filepath.Join(alias, "escape")); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, path string
		allow      bool
	}{
		{"native path", filepath.Join(mount, "pvc"), true},
		{"provisioner path", filepath.Join(alias, "pvc"), true},
		{"sibling prefix", other, false},
		{"symlink", filepath.Join(alias, "escape"), false},
		{"root itself", alias, false},
		{"missing path", filepath.Join(alias, "missing"), false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			x := XFS{Mount: mount, VolumeRoot: alias}
			_, err := x.volumePath(Volume{ID: "fixture", Path: tc.path})
			if (err == nil) != tc.allow {
				t.Fatalf("allowed=%v, want %v: %v", err == nil, tc.allow, err)
			}
		})
	}
	x := XFS{Mount: mount}
	if _, err := x.volumePath(Volume{ID: "fixture", Path: filepath.Join(alias, "pvc")}); err == nil {
		t.Fatal("accepted unconfigured alias")
	}
	x.VolumeRoot = filepath.Join(alias, "escape")
	if _, err := x.volumePath(Volume{ID: "fixture", Path: filepath.Join(mount, "pvc")}); err == nil {
		t.Fatal("accepted symlink root")
	}
}

func TestParseKernelQuotaReport(t *testing.T) {
	quotas, err := parseReport("#0 64 0 0 00 [--------]\n#1001 6291456 8388608 8388608 00 [--------]\n")
	if err != nil {
		t.Fatal(err)
	}
	if quotas[1001].Used != 6*GiB || quotas[1001].Limit != 8*GiB {
		t.Fatal(quotas)
	}
	for _, report := range []string{"#1 1", "#1 nope 0 2", "#1 1 0 0\n#1 1 0 0", "#1 18446744073709551615 0 1"} {
		if _, err := parseReport(report); err == nil {
			t.Fatalf("accepted malformed report %q", report)
		}
	}
}

func TestInodeReportDistinguishesReleasedProjectFromEmptyDirectory(t *testing.T) {
	inodes, err := parseReportUnits("#1001 0 0 0 00 [--------]\n#1002 1 0 0 00 [--------]\n", 1)
	if err != nil {
		t.Fatal(err)
	}
	if inodes[1001].Used != 0 || inodes[1002].Used != 1 {
		t.Fatalf("inode counts must retain the empty-directory charge: %v", inodes)
	}
}
