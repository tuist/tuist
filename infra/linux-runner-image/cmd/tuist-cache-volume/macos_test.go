package main

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"testing"
)

func TestMacAttachAndDetach(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	response := macResponse{Directory: digest("volume"), ID: "lease", Warm: true}
	data, _ := json.Marshal(response)
	_ = os.WriteFile(filepath.Join(share, digest("key")+".request.response"), data, 0600)
	_ = os.Mkdir(filepath.Join(share, response.Directory), 0755)
	calls := 0
	command := func(args ...string) error {
		calls++
		if args[0] != "attach" && args[0] != "detach" {
			t.Fatal(args)
		}
		return nil
	}
	dir, id, warm, err := acquireMacAt("key", share, mount, command)
	if err != nil || dir != response.Directory || id != "lease" || !warm {
		t.Fatal(dir, id, warm, err)
	}
	if err = detachMacAt(share, mount, command); err != nil {
		t.Fatal(err)
	}
	marker, _ := os.ReadFile(filepath.Join(share, dir, ".detached"))
	if string(marker) != "lease" || calls != 2 {
		t.Fatal(string(marker), calls)
	}
}
func TestMacFailedDetachWithholdsPublication(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	scope := digest("volume")
	_ = os.Mkdir(filepath.Join(mount, scope), 0755)
	_ = os.Mkdir(filepath.Join(share, scope), 0755)
	_ = os.WriteFile(filepath.Join(mount, scope, ".tuist-volume"), []byte("lease"), 0600)
	if err := detachMacAt(share, mount, func(...string) error { return errors.New("busy") }); err == nil {
		t.Fatal("detach should fail")
	}
	if _, err := os.Stat(filepath.Join(share, scope, ".detached")); !os.IsNotExist(err) {
		t.Fatal("failed detach permitted publication")
	}
}
