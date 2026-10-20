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

func TestMacCommandKeepsImageHelperOutsideJobCleanup(t *testing.T) {
	bin := t.TempDir()
	script := "#!/bin/sh\n" +
		"test -z \"${RUNNER_TRACKING_ID+x}\" || exit 42\n" +
		"test \"$TUIST_TEST_HDIUTIL\" = preserved || exit 43\n" +
		"test \"$1\" = attach || exit 44\n"
	if err := os.WriteFile(filepath.Join(bin, "hdiutil"), []byte(script), 0700); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", bin+string(os.PathListSeparator)+os.Getenv("PATH"))
	t.Setenv("RUNNER_TRACKING_ID", "job-owned-processes")
	t.Setenv("TUIST_TEST_HDIUTIL", "preserved")
	if err := macCommandContext(context.Background(), "attach", "cache.sparseimage"); err != nil {
		t.Fatal(err)
	}
	if os.Getenv("RUNNER_TRACKING_ID") != "job-owned-processes" {
		t.Fatal("changed job process tracking outside hdiutil")
	}
}

func TestMacAttachAndDetach(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	response := macResponse{Directory: digest("volume"), ID: "lease", Warm: true}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	_ = os.Mkdir(filepath.Join(share, response.Directory), 0755)
	calls := 0
	command := func(args ...string) error {
		calls++
		if args[0] != "attach" && args[0] != "detach" {
			t.Fatal(args)
		}
		return nil
	}
	dir, id, warm, err := acquireMacAt(context.Background(), "key", share, mount, command)
	if err != nil || dir != response.Directory || id != "lease" || !warm {
		t.Fatal(dir, id, warm, err)
	}
	if err = detachMacAt(share, mount, command, fakeMacMeasure, func() {}); err != nil {
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
	if err := detachMacAt(share, mount, func(...string) error { return errors.New("busy") }, fakeMacMeasure, func() {}); err == nil {
		t.Fatal("detach should fail")
	}
	if _, err := os.Stat(filepath.Join(share, scope, ".detached")); !os.IsNotExist(err) {
		t.Fatal("failed detach permitted publication")
	}
}

func TestMacCancelledAcquisitionNeverMountsLateResponse(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	data, _ := json.Marshal(macResponse{Directory: digest("volume"), ID: "lease"})
	_ = os.WriteFile(filepath.Join(share, digest("key")+".request.response"), data, 0600)
	_, _, _, err := acquireMacAt(ctx, "key", share, mount, func(...string) error {
		t.Fatal("mounted after cancellation")
		return nil
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatal(err)
	}
}

func TestMacRejectsReplaceableNodeModulesTarget(t *testing.T) {
	if !errors.Is(validateMacTargets([]string{"project/node_modules"}), errInvalidPath) {
		t.Fatal("accepted node_modules")
	}
	if err := validateMacTargets([]string{".npm", ".gradle/caches"}); err != nil {
		t.Fatal(err)
	}
}

func fakeMacMeasure(string) (int64, int64, error) { return 3, 20_000_000_000, nil }
func respondMac(t *testing.T, share string, data []byte) {
	t.Helper()
	done := make(chan struct{})
	t.Cleanup(func() { close(done) })
	go func() {
		ticker := time.NewTicker(time.Millisecond)
		defer ticker.Stop()
		for {
			select {
			case <-done:
				return
			case <-ticker.C:
			}
			paths, _ := filepath.Glob(filepath.Join(share, "*.request"))
			for _, path := range paths {
				if _, err := os.Stat(path + ".response"); os.IsNotExist(err) {
					_ = os.WriteFile(path+".response", data, 0600)
				}
			}
		}
	}()
}

func TestMacRetryIgnoresStaleResponseAndCleansMailbox(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	stale := filepath.Join(share, digest("key")+".request.response")
	_ = os.WriteFile(stale, []byte(`{"error":"unavailable"}`), 0600)
	response := macResponse{Directory: digest("volume"), ID: "lease", Warm: true}
	data, _ := json.Marshal(response)
	_ = os.Mkdir(filepath.Join(share, response.Directory), 0755)
	respondMac(t, share, data)
	for range 2 {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		_, _, warm, err := acquireMacAt(ctx, "key", share, mount, func(...string) error { return nil })
		cancel()
		if err != nil || !warm {
			t.Fatal(warm, err)
		}
	}
	files, _ := os.ReadDir(share)
	for _, f := range files {
		if strings.HasSuffix(f.Name(), ".request") {
			t.Fatal("request retained", f.Name())
		}
	}
}

func TestMacBusyDetachRetriesBeforePublishing(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	scope := digest("volume")
	_ = os.Mkdir(filepath.Join(mount, scope), 0755)
	_ = os.Mkdir(filepath.Join(share, scope), 0755)
	_ = os.WriteFile(filepath.Join(mount, scope, ".tuist-volume"), []byte("lease"), 0600)
	calls, measurements := 0, 0
	err := detachMacAt(share, mount, func(args ...string) error {
		calls++
		if strings.Contains(strings.Join(args, " "), "force") {
			t.Fatal("force detach allowed")
		}
		if calls < 3 {
			return errors.New("busy")
		}
		return nil
	}, func(string) (int64, int64, error) { measurements++; return int64(measurements), 20, nil }, func() {})
	if err != nil || calls != 3 || measurements != 3 {
		t.Fatal(calls, measurements, err)
	}
	data, _ := os.ReadFile(filepath.Join(share, scope, ".usage"))
	var usage map[string]any
	_ = json.Unmarshal(data, &usage)
	if usage["used_bytes"] != float64(3) || usage["id"] != "lease" {
		t.Fatal(string(data))
	}
	marker, _ := os.ReadFile(filepath.Join(share, scope, ".detached"))
	if string(marker) != "lease" {
		t.Fatal(string(marker))
	}
}

func TestMacCheckoutMountsAtTheWorkspace(t *testing.T) {
	share := t.TempDir()
	workspace := filepath.Join(t.TempDir(), "repo", "repo")
	response := macResponse{Directory: digest("checkout"), ID: "lease", Warm: true}
	data, _ := json.Marshal(response)
	respondMac(t, share, data)
	_ = os.Mkdir(filepath.Join(share, response.Directory), 0755)
	var attached []string
	result := checkoutMacAt(context.Background(), workspace, share, func(args ...string) error {
		attached = args
		return nil
	})
	if result != "reused" {
		t.Fatal(result)
	}
	if attached[0] != "attach" || attached[1] != filepath.Join(share, response.Directory, "cache.sparseimage") || attached[len(attached)-1] != workspace {
		t.Fatal(attached)
	}
	if marker, _ := os.ReadFile(filepath.Join(share, response.Directory, ".mounted")); string(marker) != "lease" {
		t.Fatal("the host was not told the branch is mounted")
	}
	if entries, _ := os.ReadDir(workspace); len(entries) != 0 {
		t.Fatal("wrote into the workspace")
	}
}

func TestMacCheckoutLeavesTheWorkspaceAloneWhenUnavailable(t *testing.T) {
	share := t.TempDir()
	workspace := filepath.Join(t.TempDir(), "repo")
	respondMac(t, share, []byte(`{"error":"unavailable","reason":"cold"}`))
	never := func(...string) error { t.Fatal("attached without a checkout"); return nil }
	if result := checkoutMacAt(context.Background(), workspace, share, never); result != "unavailable (cold)" {
		t.Fatal(result)
	}
	if _, err := os.Stat(workspace); !os.IsNotExist(err) {
		t.Fatal("created the workspace")
	}
}

func TestMacCheckoutNeverMountsOverExistingContent(t *testing.T) {
	share := t.TempDir()
	workspace := t.TempDir()
	_ = os.WriteFile(filepath.Join(workspace, "file"), nil, 0644)
	never := func(...string) error { t.Fatal("mounted over a workspace"); return nil }
	if result := checkoutMacAt(context.Background(), workspace, share, never); !strings.HasPrefix(result, "skipped") {
		t.Fatal(result)
	}
	if result := checkoutMacAt(context.Background(), "relative/path", share, never); !strings.HasPrefix(result, "skipped") {
		t.Fatal(result)
	}
}

func TestMacCheckoutTimesOutWithoutAnAnswer(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	never := func(...string) error { t.Fatal("attached without an answer"); return nil }
	if result := checkoutMacAt(ctx, filepath.Join(t.TempDir(), "repo"), t.TempDir(), never); result != "unavailable (timeout)" {
		t.Fatal(result)
	}
}

func TestMacCheckoutSanitizesHostReasons(t *testing.T) {
	share := t.TempDir()
	respondMac(t, share, []byte(`{"error":"unavailable","reason":"::error::injected"}`))
	never := func(...string) error { return errors.New("unexpected") }
	if result := checkoutMacAt(context.Background(), filepath.Join(t.TempDir(), "repo"), share, never); result != "unavailable (error)" {
		t.Fatal(result)
	}
}

func TestMacUnavailableExplainsTheHostReason(t *testing.T) {
	for reason, want := range map[string]string{
		"timeout":           "still downloading",
		"capacity":          "no room",
		"denied":            "did not authorize",
		"execution_pending": "not yet reported which job",
		"":                  "cache unavailable",
	} {
		share, mount := t.TempDir(), t.TempDir()
		data, _ := json.Marshal(macResponse{Error: "unavailable", Reason: reason})
		respondMac(t, share, data)
		_, _, _, err := acquireMacAt(context.Background(), "key", share, mount, func(...string) error {
			t.Fatal("mounted an unavailable volume")
			return nil
		})
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Fatal(reason, err)
		}
	}
}
