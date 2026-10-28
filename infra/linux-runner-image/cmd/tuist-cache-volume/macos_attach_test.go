package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func fastAttachRetry(t *testing.T) {
	t.Helper()
	previous := macAttachRetry
	macAttachRetry = time.Millisecond
	t.Cleanup(func() { macAttachRetry = previous })
}

func TestMacRetriesATransientAttachFailure(t *testing.T) {
	fastAttachRetry(t)
	share, mount := t.TempDir(), t.TempDir()
	response := macResponse{Directory: digest("volume"), ID: "lease", Warm: true}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	makeShare(t, share, response.Directory)
	var calls []string
	command := func(args ...string) error {
		calls = append(calls, args[0])
		if args[0] == "attach" && len(calls) == 1 {
			return errors.New("hdiutil attach: exit status 1 (attach failed - Resource temporarily unavailable)")
		}
		return nil
	}
	if _, _, _, err := acquireMacAt(context.Background(), "key", 0, share, mount, attachUnenlarged(command)); err != nil {
		t.Fatal(err)
	}
	if strings.Join(calls, ",") != "attach,detach,attach" {
		t.Fatal(calls)
	}
	if _, err := os.Stat(filepath.Join(share, response.Directory, ".attach-error")); !os.IsNotExist(err) {
		t.Fatal("recorded an error for an attach that succeeded")
	}
}

func TestMacRecordsTheReasonWhenAttachKeepsFailing(t *testing.T) {
	fastAttachRetry(t)
	share, mount := t.TempDir(), t.TempDir()
	response := macResponse{Directory: digest("volume"), ID: "lease"}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	makeShare(t, share, response.Directory)
	attaches := 0
	command := func(args ...string) error {
		if args[0] == "attach" {
			attaches++
			return errors.New("hdiutil attach: exit status 1 (attach failed - Resource busy)")
		}
		return nil
	}
	_, _, _, err := acquireMacAt(context.Background(), "key", 0, share, mount, attachUnenlarged(command))
	if err == nil || !strings.Contains(err.Error(), "Resource busy") || attaches != macAttachAttempts {
		t.Fatal(err, attaches)
	}
	recorded, _ := os.ReadFile(filepath.Join(share, response.Directory, ".attach-error"))
	if !strings.Contains(string(recorded), "Resource busy") {
		t.Fatalf("%q", recorded)
	}
	if _, err := os.Stat(filepath.Join(share, response.Directory, ".mounted")); !os.IsNotExist(err) {
		t.Fatal("reported a mount that never happened")
	}
}

func TestMacCheckoutRetriesATransientAttachFailure(t *testing.T) {
	fastAttachRetry(t)
	share := t.TempDir()
	workspace := filepath.Join(t.TempDir(), "repo")
	response := macResponse{Directory: digest("checkout"), ID: "lease"}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	makeShare(t, share, response.Directory)
	attaches := 0
	result := checkoutMacAt(context.Background(), workspace, share, filepath.Join(t.TempDir(), "state.json"), func(args ...string) error {
		if args[0] == "attach" {
			attaches++
			if attaches == 1 {
				return errors.New("hdiutil attach: exit status 1 ()")
			}
		}
		return nil
	})
	if result != "reused" || attaches != 2 {
		t.Fatal(result, attaches)
	}
}

func TestMacDetachWithholdsAVolumeWhoseImageCannotBeFlushed(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	scope := digest("volume")
	_ = os.MkdirAll(filepath.Join(share, scope), 0755)
	_ = os.MkdirAll(filepath.Join(mount, scope), 0755)
	_ = os.WriteFile(filepath.Join(mount, scope, ".tuist-volume"), []byte("lease"), 0600)
	if err := detachMacAt(share, mount, func(...string) error { return nil }, fakeMacMeasure, func(string, bool) {}, func() {}); err == nil {
		t.Fatal("detach should fail without an image to flush")
	}
	for _, name := range []string{".usage", ".detached"} {
		if _, err := os.Stat(filepath.Join(share, scope, name)); !os.IsNotExist(err) {
			t.Fatal("unflushed volume marked for publication:", name)
		}
	}
}

// attachUnenlarged attaches through command an image the host did not enlarge.
func attachUnenlarged(command func(...string) error) func(string, string) error {
	unenlarged := func(context.Context, []byte, string, ...string) ([]byte, error) {
		return nil, errors.New("no image info")
	}
	return func(image, mountPoint string) error {
		return attachMacVolume(context.Background(), image, mountPoint, unenlarged, command)
	}
}
