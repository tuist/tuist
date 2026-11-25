package linux

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// The devmapper values must land in the devmapper section that `containerd
// config default` emits, and only there: the erofs section right after it has
// its own root_path.
func TestKataDevmapperContainerdConfigEditsOnlyTheDevmapperSection(t *testing.T) {
	config := `  [plugins.'io.containerd.snapshotter.v1.devmapper']
    root_path = ''
    pool_name = ''
    base_image_size = ''
    async_remove = false
    discard_blocks = false
    fs_type = ''

  [plugins.'io.containerd.snapshotter.v1.erofs']
    root_path = ''
    ovl_mount_options = []
`
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte(config), 0600); err != nil {
		t.Fatal(err)
	}
	if out, err := exec.Command("sed", "-i", kataDevmapperContainerdConfig, path).CombinedOutput(); err != nil {
		t.Fatalf("sed: %v\n%s", err, out)
	}
	got, _ := os.ReadFile(path)
	want := `  [plugins.'io.containerd.snapshotter.v1.devmapper']
    root_path = '/data/kata-devmapper/containerd'
    pool_name = 'tuist-kata-pool'
    base_image_size = '100GB'
    async_remove = false
    discard_blocks = false
    fs_type = ''

  [plugins.'io.containerd.snapshotter.v1.erofs']
    root_path = ''
    ovl_mount_options = []
`
	if string(got) != want {
		t.Fatalf("config =\n%s\nwant\n%s", got, want)
	}
}

func TestKataSetupBlockRootfs(t *testing.T) {
	off := kataSetup("sudo ", "sudo -E ", true, true, false)
	for _, unwanted := range []string{"devmapper", kataBlockRootfsDropInPath, "thin-provisioning-tools"} {
		if strings.Contains(off, unwanted) {
			t.Fatalf("fleets without KataBlockRootfs must render no %q, got:\n%s", unwanted, off)
		}
	}

	on := kataSetup("sudo ", "sudo -E ", true, true, true)
	// The snapshotter is a handler setting, not one of the shim's options: in
	// the options table containerd would pass it to the shim and CRI would keep
	// creating the handler's containers on overlayfs.
	handler := on[strings.Index(on, "runtimes.kata-qemu]"):strings.Index(on, "runtimes.kata-qemu.options]")]
	if !strings.Contains(handler, "\nsnapshotter = \"devmapper\"\n") {
		t.Fatalf("expected the kata-qemu handler to use devmapper, got:\n%s", handler)
	}
	// The pool must exist before bootstrap restarts containerd, and the Kata
	// drop-in must land with it.
	for _, want := range []string{"systemctl start tuist-kata-devmapper.service", kataBlockRootfsDropInPath, "disable_block_device_use = false"} {
		if !strings.Contains(on, want) {
			t.Fatalf("expected %q in the setup, got:\n%s", want, on)
		}
	}
}
