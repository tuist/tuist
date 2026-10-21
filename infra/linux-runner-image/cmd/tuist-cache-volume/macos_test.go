package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
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
	makeShare(t, share, response.Directory)
	calls := 0
	attachImage := func(image, mountPoint string) error {
		calls++
		if image != filepath.Join(share, response.Directory, "cache.sparseimage") || mountPoint != filepath.Join(mount, response.Directory) {
			t.Fatal(image, mountPoint)
		}
		return nil
	}
	dir, id, warm, err := acquireMacAt(context.Background(), "key", 0, share, mount, attachImage)
	if err != nil || dir != response.Directory || id != "lease" || !warm {
		t.Fatal(dir, id, warm, err)
	}
	command := func(args ...string) error {
		calls++
		if args[0] != "detach" {
			t.Fatal(args)
		}
		return nil
	}
	if err = detachMacAt(share, mount, command, fakeMacMeasure, func(string, bool) {}, func() {}); err != nil {
		t.Fatal(err)
	}
	marker, _ := os.ReadFile(filepath.Join(share, dir, ".detached"))
	if string(marker) != "lease" || calls != 2 {
		t.Fatal(string(marker), calls)
	}
}

func TestMacRequestCarriesTheRequestedSizeOnlyWhenGiven(t *testing.T) {
	for size, want := range map[int64]string{0: `{"key":"key","uid":UID}`, 50_000_000_000: `{"key":"key","requested_volume_bytes":50000000000,"uid":UID}`} {
		share, mount := t.TempDir(), t.TempDir()
		requests := make(chan string, 1)
		done := make(chan struct{})
		go func() {
			defer close(done)
			for {
				paths, _ := filepath.Glob(filepath.Join(share, "*.request"))
				if len(paths) == 1 {
					data, _ := os.ReadFile(paths[0])
					requests <- string(data)
					_ = os.WriteFile(paths[0]+".response", []byte(`{"error":"unavailable","reason":"capacity"}`), 0600)
					return
				}
				time.Sleep(time.Millisecond)
			}
		}()
		if _, _, _, err := acquireMacAt(context.Background(), "key", size, share, mount, func(string, string) error { return nil }); err == nil {
			t.Fatal("unavailable volume attached")
		}
		<-done
		if got, want := <-requests, strings.ReplaceAll(want, "UID", fmt.Sprint(os.Getuid())); got != want {
			t.Fatalf("request = %s, want %s", got, want)
		}
	}
}

// fakeMacTools answers hdiutil, diskutil and plutil like macOS does for a
// sparse image whose disk the host grew from 20 to 50 GB.
type fakeMacTools struct {
	calls    []string
	limits   string
	failures map[string]error
}

func (f *fakeMacTools) run(_ context.Context, stdin []byte, name string, args ...string) ([]byte, error) {
	call := strings.Join(append([]string{name}, args...), " ")
	if name == "plutil" {
		return stdin, nil
	}
	f.calls = append(f.calls, call)
	for prefix, err := range f.failures {
		if strings.HasPrefix(call, prefix) {
			return nil, err
		}
	}
	switch {
	case strings.HasPrefix(call, "hdiutil attach"):
		return []byte(`{"system-entities":[{"dev-entry":"/dev/disk6","content-hint":"GUID_partition_scheme"},{"dev-entry":"/dev/disk6s1","content-hint":"EFI"},{"dev-entry":"/dev/disk6s2","content-hint":"Apple_APFS"},{"dev-entry":"/dev/disk7s1","content-hint":"41504653-0000-11AA-AA11-00306543ECAC","volume-kind":"apfs"},{"dev-entry":"/dev/disk7","content-hint":"EF57347C-0000-11AA-AA11-00306543ECAC"}]}`), nil
	case strings.HasPrefix(call, "diskutil apfs resizeContainer disk7 limits"):
		return []byte(f.limits), nil
	}
	return nil, nil
}

func TestMacAttachGrowsTheContainerBeforeMounting(t *testing.T) {
	tools := &fakeMacTools{limits: `{"CurrentSize":19999997952,"MaximumSize":49999998976}`}
	if err := attachGrownMacImage(context.Background(), "cache.sparseimage", "/mount", tools.run); err != nil {
		t.Fatal(err)
	}
	want := []string{
		"hdiutil attach cache.sparseimage -owners off -nobrowse -nomount -plist",
		"diskutil apfs resizeContainer disk7 limits -plist",
		"diskutil apfs resizeContainer disk7 0",
		"diskutil mount nobrowse -mountPoint /mount /dev/disk7s1",
	}
	if fmt.Sprint(tools.calls) != fmt.Sprint(want) {
		t.Fatalf("calls = %q", tools.calls)
	}
}

func TestMacAttachLeavesAFullContainerAsItIs(t *testing.T) {
	tools := &fakeMacTools{limits: `{"CurrentSize":19999997952,"MaximumSize":19999997952}`}
	if err := attachGrownMacImage(context.Background(), "cache.sparseimage", "/mount", tools.run); err != nil {
		t.Fatal(err)
	}
	for _, call := range tools.calls {
		if call == "diskutil apfs resizeContainer disk7 0" {
			t.Fatal("resized a container that already fills its disk")
		}
	}
}

func TestMacAttachMountsAtTheOldSizeWhenGrowingFails(t *testing.T) {
	tools := &fakeMacTools{limits: `{"CurrentSize":19999997952,"MaximumSize":49999998976}`, failures: map[string]error{"diskutil apfs resizeContainer disk7 0": errors.New("resize failed")}}
	if err := attachGrownMacImage(context.Background(), "cache.sparseimage", "/mount", tools.run); err != nil {
		t.Fatal(err)
	}
	if last := tools.calls[len(tools.calls)-1]; last != "diskutil mount nobrowse -mountPoint /mount /dev/disk7s1" {
		t.Fatal(tools.calls)
	}
}

func TestMacAttachDetachesTheImageWhenMountingFails(t *testing.T) {
	tools := &fakeMacTools{limits: `{"CurrentSize":1,"MaximumSize":1}`, failures: map[string]error{"diskutil mount": errors.New("mount failed")}}
	if err := attachGrownMacImage(context.Background(), "cache.sparseimage", "/mount", tools.run); err == nil {
		t.Fatal("reported a failed mount as attached")
	}
	if last := tools.calls[len(tools.calls)-1]; last != "hdiutil detach /dev/disk6 -quiet" {
		t.Fatal(tools.calls)
	}
}
func TestMacFailedDetachWithholdsPublication(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	scope := digest("volume")
	_ = os.Mkdir(filepath.Join(mount, scope), 0755)
	makeShare(t, share, scope)
	_ = os.WriteFile(filepath.Join(mount, scope, ".tuist-volume"), []byte("lease"), 0600)
	if err := detachMacAt(share, mount, func(...string) error { return errors.New("busy") }, fakeMacMeasure, func(string, bool) {}, func() {}); err == nil {
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
	_, _, _, err := acquireMacAt(ctx, "key", 0, share, mount, func(string, string) error {
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
	makeShare(t, share, response.Directory)
	respondMac(t, share, data)
	for range 2 {
		ctx, cancel := context.WithTimeout(context.Background(), time.Second)
		_, _, warm, err := acquireMacAt(ctx, "key", 0, share, mount, func(string, string) error { return nil })
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
	makeShare(t, share, scope)
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
	}, func(string) (int64, int64, error) { measurements++; return int64(measurements), 20, nil }, func(string, bool) {}, func() {})
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
	makeShare(t, share, response.Directory)
	var attached []string
	result := checkoutMacAt(context.Background(), workspace, share, filepath.Join(t.TempDir(), "state.json"), func(args ...string) error {
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
	if result := checkoutMacAt(context.Background(), workspace, share, filepath.Join(t.TempDir(), "state.json"), never); result != "unavailable (cold)" {
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
	if result := checkoutMacAt(context.Background(), workspace, share, filepath.Join(t.TempDir(), "state.json"), never); !strings.HasPrefix(result, "skipped") {
		t.Fatal(result)
	}
	if result := checkoutMacAt(context.Background(), "relative/path", share, filepath.Join(t.TempDir(), "state.json"), never); !strings.HasPrefix(result, "skipped") {
		t.Fatal(result)
	}
}

func TestMacCheckoutTimesOutWithoutAnAnswer(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
	defer cancel()
	never := func(...string) error { t.Fatal("attached without an answer"); return nil }
	if result := checkoutMacAt(ctx, filepath.Join(t.TempDir(), "repo"), t.TempDir(), filepath.Join(t.TempDir(), "state.json"), never); result != "unavailable (timeout)" {
		t.Fatal(result)
	}
}

func TestMacCheckoutSanitizesHostReasons(t *testing.T) {
	share := t.TempDir()
	respondMac(t, share, []byte(`{"error":"unavailable","reason":"::error::injected"}`))
	never := func(...string) error { return errors.New("unexpected") }
	if result := checkoutMacAt(context.Background(), filepath.Join(t.TempDir(), "repo"), share, filepath.Join(t.TempDir(), "state.json"), never); result != "unavailable (error)" {
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
		_, _, _, err := acquireMacAt(context.Background(), "key", 0, share, mount, func(string, string) error {
			t.Fatal("mounted an unavailable volume")
			return nil
		})
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Fatal(reason, err)
		}
	}
}

func TestMacBusyDetachReleasesHoldersBeforePublishing(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	scope := digest("volume")
	_ = os.Mkdir(filepath.Join(mount, scope), 0755)
	makeShare(t, share, scope)
	_ = os.WriteFile(filepath.Join(mount, scope, ".tuist-volume"), []byte("lease"), 0600)
	held := true
	var releases []bool
	err := detachMacAt(share, mount, func(args ...string) error {
		if strings.Contains(strings.Join(args, " "), "force") {
			t.Fatal("force detach allowed")
		}
		if held {
			return errors.New("hdiutil: exit status 16 ()")
		}
		return nil
	}, fakeMacMeasure, func(base string, kill bool) {
		if base != filepath.Join(mount, scope) {
			t.Fatal(base)
		}
		releases = append(releases, kill)
		held = false
	}, func() {})
	if err != nil || fmt.Sprint(releases) != "[false]" {
		t.Fatal(releases, err)
	}
	marker, _ := os.ReadFile(filepath.Join(share, scope, ".detached"))
	if string(marker) != "lease" {
		t.Fatal(string(marker))
	}
}

func TestMacKillsHoldersThatOutliveTermination(t *testing.T) {
	share, mount := t.TempDir(), t.TempDir()
	scope := digest("volume")
	_ = os.Mkdir(filepath.Join(mount, scope), 0755)
	makeShare(t, share, scope)
	_ = os.WriteFile(filepath.Join(mount, scope, ".tuist-volume"), []byte("lease"), 0600)
	held := true
	var releases []bool
	err := detachMacAt(share, mount, func(...string) error {
		if held {
			return errors.New("hdiutil: exit status 16 ()")
		}
		return nil
	}, fakeMacMeasure, func(_ string, kill bool) {
		releases = append(releases, kill)
		held = held && !kill
	}, func() {})
	if err != nil || fmt.Sprint(releases) != "[false true]" {
		t.Fatal(releases, err)
	}
	if _, err := os.Stat(filepath.Join(share, scope, ".detached")); err != nil {
		t.Fatal(err)
	}
}

func TestMacHoldersParsesLsofFields(t *testing.T) {
	out := "p812\nctuist\nf4\nftxt\np901\ncmise\nfcwd\n"
	got := parseMacHolders([]byte(out))
	if fmt.Sprint(got) != "[{812 tuist} {901 mise}]" {
		t.Fatal(got)
	}
	if got := parseMacHolders(nil); len(got) != 0 {
		t.Fatal(got)
	}
}

// makeShare creates a volume's share directory with the image the host links into it.
func makeShare(t *testing.T, share, dir string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Join(share, dir), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(share, dir, "cache.sparseimage"), nil, 0644); err != nil {
		t.Fatal(err)
	}
}
