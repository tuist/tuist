//go:build linux

package main

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"slices"
	"strings"
	"testing"
)

// fakeDaemon runs `sleep` as dockerd and answers every other command from
// mounts, which reports whether each `mount` succeeds, in order.
func fakeDaemon(t *testing.T, mounts ...bool) (*daemon, string, *[]string) {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, dockerTestScope), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, dockerTestScope, dockerImageName), nil, 0600); err != nil {
		t.Fatal(err)
	}
	var calls []string
	d := &daemon{args: []string{"sleep", "60"}, root: root, ephemeral: "/ephemeral.img", state: "ephemeral", dataRoot: t.TempDir(), mergeRoot: filepath.Join(t.TempDir(), "merge")}
	d.usedBytes = func(string) (int64, error) { return 0, nil }
	d.trim = func(string) error { return nil }
	d.run = func(_ context.Context, name string, args ...string) ([]byte, error) {
		calls = append(calls, strings.Join(append([]string{name}, args...), " "))
		if name == "mount" && len(args) == 4 && args[3] == d.dataRoot && strings.HasSuffix(args[2], dockerImageName) {
			ok := mounts[0]
			mounts = mounts[1:]
			if !ok {
				return []byte("mounting /dev/loop0 on /var/lib/docker failed: Invalid argument"), errors.New("exit status 255")
			}
		}
		return nil, nil
	}
	t.Cleanup(func() { d.mu.Lock(); d.stop(); d.mu.Unlock() })
	return d, dockerTestScope + "/" + dockerImageName, &calls
}

func TestSwitchFormatsADataRootTheKernelRefuses(t *testing.T) {
	d, source, calls := fakeDaemon(t, false, true)
	reply, err := d.handle(dockerMessage{Docker: "switch", Source: source})
	if err != nil || reply != dockerReset {
		t.Fatalf("switch: %q, %v", reply, err)
	}
	if !d.reset || d.state != "volume" {
		t.Fatalf("reset %t, state %s", d.reset, d.state)
	}
	formatted := false
	for _, call := range *calls {
		if strings.HasPrefix(call, "mkfs.ext4 "+strings.Join(dockerFormatArgs, " ")) && strings.HasSuffix(call, source) {
			formatted = true
		}
	}
	if !formatted {
		t.Fatalf("the refused data root was not formatted: %v", *calls)
	}
}

func TestSwitchFallsBackWhenTheFormattedRootStillFailsToMount(t *testing.T) {
	d, source, calls := fakeDaemon(t, false, false)
	if _, err := d.handle(dockerMessage{Docker: "switch", Source: source}); err == nil {
		t.Fatal("switched onto a data root that failed to mount")
	}
	if d.state != "ephemeral" {
		t.Fatalf("state %s", d.state)
	}
	if !strings.Contains(strings.Join(*calls, "\n"), "mount -o loop /ephemeral.img "+d.dataRoot) {
		t.Fatalf("did not return to the ephemeral data root: %v", *calls)
	}
}

func TestSwitchKeepsASavedDataRootThatMounts(t *testing.T) {
	d, source, calls := fakeDaemon(t, true)
	reply, err := d.handle(dockerMessage{Docker: "switch", Source: source})
	if err != nil || reply != "ok" || d.reset {
		t.Fatalf("switch: %q, %v, reset %t", reply, err, d.reset)
	}
	for _, call := range *calls {
		if strings.HasPrefix(call, "mkfs") {
			t.Fatalf("formatted a data root that mounted: %v", *calls)
		}
	}
}

// mergingDaemon is a supervisor whose job's data root keeps branch and whose
// saved head's clone keeps head, with the job switched onto its data root and
// the head's clone beside it.
func mergingDaemon(t *testing.T, branch, head []dockerImage, pipeErr error) (*daemon, *[][]string) {
	t.Helper()
	d, source, _ := fakeDaemon(t, true)
	if _, err := d.handle(dockerMessage{Docker: "switch", Source: source}); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(d.root, dockerTestScope, dockerMergeImageName), nil, 0600); err != nil {
		t.Fatal(err)
	}
	inspect := func(images []dockerImage) []byte {
		data, _ := json.Marshal(images)
		return data
	}
	ids := func(images []dockerImage) []byte {
		var lines []string
		for _, image := range images {
			lines = append(lines, image.ID)
		}
		return []byte(strings.Join(lines, "\n"))
	}
	d.run = func(_ context.Context, name string, args ...string) ([]byte, error) {
		images := branch
		if len(args) > 1 && args[0] == "--host" {
			images, args = head, args[2:]
		}
		if name != "docker" || len(args) < 2 {
			return nil, nil
		}
		switch strings.Join(args[:2], " ") {
		case "image ls":
			return ids(images), nil
		case "image inspect":
			return inspect(images), nil
		}
		return nil, nil
	}
	var piped [][]string
	d.pipe = func(_ context.Context, from, to []string) error {
		piped = append(piped, from, to)
		return pipeErr
	}
	return d, &piped
}

func internalImage(id string, size int64) dockerImage {
	return dockerImage{ID: id, RepoTags: []string{dockerInternalReference(id)}, Size: size}
}

func readTeardownReport(t *testing.T, d *daemon) dockerTeardownReport {
	t.Helper()
	var report dockerTeardownReport
	data, err := os.ReadFile(filepath.Join(d.root, dockerTestScope, dockerReport))
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &report); err != nil {
		t.Fatal(err)
	}
	return report
}

func TestTeardownMergesTheJobsNewImageIntoTheSavedHead(t *testing.T) {
	alpine, postgres, flutter := internalImage(dockerID("a"), 8_000_000), internalImage(dockerID("b"), 450_000_000), internalImage(dockerID("c"), 6_000_000_000)
	d, piped := mergingDaemon(t, []dockerImage{alpine, postgres}, []dockerImage{postgres, flutter}, nil)
	if _, err := d.handle(dockerMessage{Docker: "teardown", Merge: dockerTestScope + "/" + dockerMergeImageName, Generation: 4}); err != nil {
		t.Fatal(err)
	}
	want := [][]string{{"save", dockerInternalReference(alpine.ID)}, {"--host", dockerMergeHost, "load", "-q"}}
	if !reflect.DeepEqual(*piped, want) {
		t.Fatalf("piped %v", *piped)
	}
	report := readTeardownReport(t, d)
	if report.MergedGeneration != 4 || report.MergedInto != "head" || !report.Clean || !report.Changed {
		t.Fatalf("report %+v", report)
	}
	if _, err := os.Stat(dockerLedgerFile(d.mergeRoot)); err != nil {
		t.Fatalf("the saved head's ledger was not merged: %v", err)
	}
}

func TestTeardownWithoutAMergeLeavesTheDataRootAsTheJobLeftIt(t *testing.T) {
	alpine, postgres, flutter := internalImage(dockerID("a"), 8_000_000), internalImage(dockerID("b"), 450_000_000), internalImage(dockerID("c"), 6_000_000_000)
	for name, test := range map[string]struct {
		branch, head []dockerImage
		pipeErr      error
	}{
		"the copy failed":        {branch: []dockerImage{alpine, postgres}, head: []dockerImage{postgres, flutter}, pipeErr: errors.New("load failed")},
		"nothing the head lacks": {branch: []dockerImage{postgres}, head: []dockerImage{alpine, postgres}},
	} {
		t.Run(name, func(t *testing.T) {
			d, _ := mergingDaemon(t, test.branch, test.head, test.pipeErr)
			if _, err := d.handle(dockerMessage{Docker: "teardown", Merge: dockerTestScope + "/" + dockerMergeImageName, Generation: 4}); err != nil {
				t.Fatal(err)
			}
			if report := readTeardownReport(t, d); report.MergedGeneration != 0 || report.MergedInto != "" || !report.Clean {
				t.Fatalf("report %+v", report)
			}
		})
	}
}

func TestTeardownRebasesADataRootThatAlreadyHoldsTheSavedHead(t *testing.T) {
	alpine, postgres := internalImage(dockerID("a"), 8_000_000), internalImage(dockerID("b"), 450_000_000)
	d, piped := mergingDaemon(t, []dockerImage{alpine, postgres}, []dockerImage{postgres}, nil)
	if _, err := d.handle(dockerMessage{Docker: "teardown", Merge: dockerTestScope + "/" + dockerMergeImageName, Generation: 4}); err != nil {
		t.Fatal(err)
	}
	if len(*piped) != 0 {
		t.Fatalf("copied %v", *piped)
	}
	if report := readTeardownReport(t, d); report.MergedGeneration != 4 || report.MergedInto != "branch" {
		t.Fatalf("report %+v", report)
	}
}

// vitals.sh appends the published line verbatim, so its field names and
// byte units are what the runner's death forensics read.
func TestDindMemoryRendersTheSidecarCgroupAsVitalsFields(t *testing.T) {
	cgroup := t.TempDir()
	for name, content := range map[string]string{
		"memory.current": "36000000000\n",
		"memory.peak":    "36500000000\n",
		"memory.stat":    "anon 30000000000\nfile 5000000000\nkernel 400000000\nshmem 7000\nfile_dirty 120000\nfile_writeback 0\nanon_thp 0\n",
		"memory.events":  "low 0\nhigh 0\nmax 0\noom 2\noom_kill 1\noom_group_kill 0\n",
	} {
		if err := os.WriteFile(filepath.Join(cgroup, name), []byte(content), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	want := "dind.mem.current=36000000000 dind.mem.peak=36500000000 dind.mem.anon=30000000000 dind.mem.file=5000000000 dind.mem.shmem=7000 dind.mem.file_dirty=120000 dind.mem.file_writeback=0 dind.mem.kernel=400000000 dind.oom_kill=1"
	if got := dindMemory(cgroup); got != want {
		t.Fatalf("got  %s\nwant %s", got, want)
	}
	if got := dindMemory(t.TempDir()); got != "" {
		t.Fatalf("a cgroup without memory accounting published %q", got)
	}
}

func TestRaiseJobContainerOOMScoresPutsOnlyDockerProcessesFirst(t *testing.T) {
	proc := t.TempDir()
	for pid, process := range map[string][2]string{
		"10": {"0::/docker/3f1c\n", "0\n"},        // job container
		"11": {"0::/docker/buildkit/x9\n", "0\n"}, // BuildKit build step
		"12": {"0::/\n", "872\n"},                 // dockerd, shim, the supervisor
		"13": {"0::/docker/3f1c\n", "1000\n"},     // already raised
		"14": {"0::/dockerish/a\n", "0\n"},        // not dockerd's tree
		"15": {"0::/docker/" + strings.Repeat("ab", 32) + "\n", "0\n"},
		"16": {"0::/docker/" + strings.Repeat("ab", 32) + "\n", "1000\n"}, // exited, not yet reaped
	} {
		if err := os.MkdirAll(filepath.Join(proc, pid), 0o755); err != nil {
			t.Fatal(err)
		}
		_ = os.WriteFile(filepath.Join(proc, pid, "cgroup"), []byte(process[0]), 0o644)
		_ = os.WriteFile(filepath.Join(proc, pid, "oom_score_adj"), []byte(process[1]), 0o644)
		status := "Name:\tp" + pid + "\nUmask:\t0022\nRssAnon:\t  " + pid + "00 kB\nRssFile:\t 1 kB\n"
		_ = os.WriteFile(filepath.Join(proc, pid, "status"), []byte(status), 0o644)
	}
	_ = os.WriteFile(filepath.Join(proc, "16", "status"), []byte("Name:\tp16\nState:\tZ (zombie)\n"), 0o644)
	_ = os.MkdirAll(filepath.Join(proc, "self"), 0o755)
	raised, processes := raiseJobContainerOOMScores(proc)
	if raised != 3 {
		t.Fatalf("raised %d processes, want 3", raised)
	}
	// The sweep remembers the live processes it can name a container for: a
	// full container ID or a build step, not the fixture's short IDs. An
	// exited process counts as gone, so a killed victim is not seen alive.
	slices.SortFunc(processes, func(a, b jobProcess) int { return strings.Compare(a.name, b.name) })
	want := []jobProcess{{pid: "11", name: "p11", anonKB: 1100, container: "docker-build"}, {pid: "15", name: "p15", anonKB: 1500, container: strings.Repeat("ab", 32)}}
	if !slices.Equal(processes, want) {
		t.Errorf("processes = %+v, want %+v", processes, want)
	}
	for pid, want := range map[string]string{"10": "1000", "11": "1000", "12": "872", "13": "1000", "14": "0", "15": "1000"} {
		got, _ := os.ReadFile(filepath.Join(proc, pid, "oom_score_adj"))
		if strings.TrimSpace(string(got)) != want {
			t.Errorf("pid %s oom_score_adj = %q, want %s", pid, got, want)
		}
	}
}

func killedLine(pid, task, anon string) string {
	return "<3>[ 2100.7] Out of memory: Killed process " + pid + " (" + task + ") total-vm:40000000kB, anon-rss:" + anon +
		"kB, file-rss:1024kB, shmem-rss:0kB, UID:0 pgtables:60000kB oom_score_adj:1000\n"
}

func TestOOMVictimIsTheProcessWithItsNameThatVanished(t *testing.T) {
	gradle := strings.Repeat("3f", 32)
	idle := strings.Repeat("7a", 32)
	removed := strings.Repeat("9c", 32)
	containers := &jobContainers{known: map[string]string{}, inspect: func(id string) (string, string, error) {
		switch id {
		case gradle:
			return "/gradle-build", "gradle:8-jdk21@sha256:abc", nil
		case idle:
			return "/idle", "alpine:3.20", nil
		}
		return "", "", errors.New("no such container")
	}}
	// The sweep before the kill. The victim was smaller than a process that
	// survives, as a runaway process is a second before it is killed.
	before := []jobProcess{
		{pid: "40", name: "tail", anonKB: 300_000, container: idle},
		{pid: "41", name: "tail", anonKB: 200_000, container: gradle},
		{pid: "42", name: "node", anonKB: 2, container: removed},
		{pid: "43", name: "cc1plus", anonKB: 3, container: "docker-build"},
		{pid: "44", name: "cc1plus", anonKB: 1, container: removed},
	}
	containers.observe(before)
	survivors := func(gone ...string) []jobProcess {
		var after []jobProcess
		for _, process := range before {
			if !slices.Contains(gone, process.pid) {
				after = append(after, process)
			}
		}
		return after
	}
	for _, tc := range []struct {
		name, log string
		after     []jobProcess
		want      string
		named     bool
	}{
		{"the vanished one of two with the name", killedLine("812", "Runner.Worker", "130000") + killedLine("9", "tail", "1542784"), survivors("41"),
			"oom.victim=tail oom.victim.anon.kb=1542784 oom.victim.container=gradle-build oom.victim.image=gradle:8-jdk21@sha256:abc", true},
		{"a container that was never described", killedLine("9", "node", "2"), survivors("42"),
			"oom.victim=node oom.victim.anon.kb=2 oom.victim.container=" + removed[:12], true},
		// Several vanished: the kernel killed the largest.
		{"the largest of several that vanished", killedLine("5", "cc1plus", "3"), survivors("43", "44"),
			"oom.victim=cc1plus oom.victim.anon.kb=3 oom.victim.container=docker-build", true},
		// Still listed while it exits: not named yet.
		{"a victim not yet gone", killedLine("9", "tail", "1542784"), before, "oom.victim=tail oom.victim.anon.kb=1542784", false},
		// No job container ran it: the runner container, outside Docker.
		{"a process outside the job's containers", killedLine("812", "Runner.Worker", "130000"), survivors(),
			"oom.victim=Runner.Worker oom.victim.anon.kb=130000", false},
		// A job names its own processes, so the name must not break a vitals
		// line or start a workflow command.
		{"a hostile name", "Out of memory: Killed process 7 (a b::error%0A) total-vm:1kB, anon-rss:2kB, file-rss:0kB", survivors(),
			"oom.victim=a_b__error_0A oom.victim.anon.kb=2", false},
	} {
		kill, ok := latestOOMKill(tc.log)
		if !ok {
			t.Fatalf("%s: no kill in the log", tc.name)
		}
		if got, named := kill.fields(before, tc.after, containers.describe); got != tc.want || named != tc.named {
			t.Errorf("%s: got %q, %v; want %q, %v", tc.name, got, named, tc.want, tc.named)
		}
	}
	if _, ok := latestOOMKill("<6>[ 1.0] nothing to see\n"); ok {
		t.Fatal("a log without an OOM kill named a victim")
	}
}

func TestOOMWatchWaitsForTheVictimToExit(t *testing.T) {
	gradle := strings.Repeat("3f", 32)
	describe := func(id string) string { return "oom.victim.container=" + id[:4] }
	running := []jobProcess{{pid: "41", name: "java", anonKB: 1, container: gradle}}
	log := ""
	kernelLog := func() string { return log }

	watch := &oomWatch{}
	if got := watch.sweep(0, running, kernelLog, describe); got != "" {
		t.Fatalf("named %q before any kill", got)
	}
	// Counted, but the victim still shows while it exits.
	log = killedLine("9", "java", "5")
	if got := watch.sweep(1, running, kernelLog, describe); got != "" {
		t.Fatalf("named %q while the victim still ran", got)
	}
	// Gone from the next sweep: named from the sweep before the kill.
	if got, want := watch.sweep(1, nil, kernelLog, describe), "oom.victim=java oom.victim.anon.kb=5 oom.victim.container=3f3f"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
	if got := watch.sweep(1, nil, kernelLog, describe); got != "" {
		t.Fatalf("named %q again", got)
	}

	// A victim no sweep saw in a container is named without one, once the
	// attempts run out.
	log = killedLine("10", "Runner.Worker", "7")
	var got string
	for range oomWatchAttempts {
		got = watch.sweep(2, nil, kernelLog, describe)
	}
	if want := "oom.victim=Runner.Worker oom.victim.anon.kb=7"; got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestJobContainersKeepNamesSafeAndBounded(t *testing.T) {
	id := strings.Repeat("ab", 32)
	containers := &jobContainers{known: map[string]string{}, inspect: func(string) (string, string, error) {
		return "/x y\n::error::", strings.Repeat("i", 200), nil
	}}
	containers.observe([]jobProcess{{name: "x", container: id}})
	if got, want := containers.describe(id), "oom.victim.container=x_y_::error:: oom.victim.image="+strings.Repeat("i", 128); got != want {
		t.Fatalf("got %q, want %q", got, want)
	}
}

func TestGuestOOMKillsReadsVmstat(t *testing.T) {
	vmstat := filepath.Join(t.TempDir(), "vmstat")
	_ = os.WriteFile(vmstat, []byte("pgfault 12\noom_kill 3\nthp_fault_alloc 0\n"), 0o644)
	if got := guestOOMKills(vmstat); got != 3 {
		t.Fatalf("got %d, want 3", got)
	}
	if got := guestOOMKills(filepath.Join(t.TempDir(), "missing")); got != 0 {
		t.Fatalf("an unreadable vmstat reported %d kills", got)
	}
}
