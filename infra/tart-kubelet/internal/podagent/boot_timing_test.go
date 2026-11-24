package podagent

import (
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"testing"
	"time"
)

func writeBootMark(t *testing.T, dir, name string, at time.Time) {
	t.Helper()
	path := filepath.Join(dir, name)
	if err := os.WriteFile(path, nil, 0o644); err != nil {
		t.Fatalf("write %s: %v", name, err)
	}
	if err := os.Chtimes(path, at, at); err != nil {
		t.Fatalf("chtimes %s: %v", name, err)
	}
}

func TestBootTimingFields(t *testing.T) {
	created := time.Date(2026, 10, 29, 6, 50, 42, 0, time.UTC)
	run := created.Add(400 * time.Millisecond)
	ip := run.Add(5700 * time.Millisecond)

	t.Run("waits for the first poll", func(t *testing.T) {
		dir := t.TempDir()
		writeBootMark(t, dir, bootAgentFile, ip.Add(3*time.Second))
		if _, ok := bootTimingFields(created, run, ip, dir); ok {
			t.Fatal("reported a boot before the guest polled")
		}
	})

	t.Run("reports every stage", func(t *testing.T) {
		dir := t.TempDir()
		writeBootMark(t, dir, bootAgentFile, ip.Add(3*time.Second))
		writeBootMark(t, dir, bootPollerFile, ip.Add(3500*time.Millisecond))
		writeBootMark(t, dir, bootFirstPollFile, ip.Add(4750*time.Millisecond))

		fields, ok := bootTimingFields(created, run, ip, dir)
		if !ok {
			t.Fatal("no boot timing after the first poll")
		}
		want := []any{
			"createdToRun", 0.4,
			"runToIP", 5.7,
			"ipToAgent", 3.0,
			"agentToPoller", 0.5,
			"pollerToFirstPoll", 1.25,
			"runToFirstPoll", 10.45,
			"createdToFirstPoll", 10.85,
		}
		if !reflect.DeepEqual(fields, want) {
			t.Fatalf("fields = %v, want %v", fields, want)
		}
	})

	t.Run("leaves out the stages of a missing marker", func(t *testing.T) {
		dir := t.TempDir()
		writeBootMark(t, dir, bootPollerFile, ip.Add(3500*time.Millisecond))
		writeBootMark(t, dir, bootFirstPollFile, ip.Add(4750*time.Millisecond))

		fields, _ := bootTimingFields(created, run, ip, dir)
		want := []any{
			"createdToRun", 0.4,
			"runToIP", 5.7,
			"pollerToFirstPoll", 1.25,
			"runToFirstPoll", 10.45,
			"createdToFirstPoll", 10.85,
		}
		if !reflect.DeepEqual(fields, want) {
			t.Fatalf("fields = %v, want %v", fields, want)
		}
	})

	t.Run("ignores a marker that is not a plain file", func(t *testing.T) {
		dir := t.TempDir()
		if err := os.Symlink(filepath.Join(t.TempDir(), "elsewhere"), filepath.Join(dir, bootFirstPollFile)); err != nil {
			t.Fatalf("symlink: %v", err)
		}
		if _, ok := bootTimingFields(created, run, ip, dir); ok {
			t.Fatal("followed a symlinked marker")
		}
	})
}

func TestGuestReportsBootStages(t *testing.T) {
	share := t.TempDir()
	script := guestShellScript(t, `STATUS_SHARE="$1"; report_boot_stage first-poll`, "report_boot_stage")
	if out, err := exec.Command("bash", "-c", script, "bash", share).CombinedOutput(); err != nil {
		t.Fatalf("report_boot_stage: %v: %s", err, out)
	}
	if _, ok := readBootMark(share, bootFirstPollFile); !ok {
		t.Fatal("no first-poll marker in the status share")
	}

	missing := filepath.Join(t.TempDir(), "absent")
	if out, err := exec.Command("bash", "-c", script, "bash", missing).CombinedOutput(); err != nil {
		t.Fatalf("report_boot_stage without a share: %v: %s", err, out)
	}
	if _, err := os.Stat(missing); !os.IsNotExist(err) {
		t.Fatalf("created %s without a share: %v", missing, err)
	}
}

func TestJobStartFields(t *testing.T) {
	claimed := time.Date(2026, 11, 20, 4, 49, 39, 0, time.UTC)
	claim := func(t *testing.T, dir, state string) {
		t.Helper()
		path := filepath.Join(dir, runnerHeartbeatFile)
		if err := os.WriteFile(path, []byte(state), 0o644); err != nil {
			t.Fatal(err)
		}
		if err := os.Chtimes(path, claimed, claimed); err != nil {
			t.Fatal(err)
		}
	}

	t.Run("splits a late job into GitHub's part and the VM's", func(t *testing.T) {
		dir := t.TempDir()
		claim(t, dir, heartbeatStateClaimed)
		writeBootMark(t, dir, bootListenerFile, claimed.Add(1500*time.Millisecond))
		writeBootMark(t, dir, bootJobMessageFile, claimed.Add(210*time.Second))
		writeBootMark(t, dir, bootJobStartedFile, claimed.Add(214250*time.Millisecond))

		fields, ok := jobStartFields(dir)
		if !ok {
			t.Fatal("no job start fields")
		}
		want := []any{
			"claimedToListener", 1.5,
			"listenerToJobMessage", 208.5,
			"jobMessageToJobStarted", 4.25,
			"claimedToJobStarted", 214.25,
		}
		if !reflect.DeepEqual(fields, want) {
			t.Fatalf("fields = %v, want %v", fields, want)
		}
	})

	t.Run("reports how far a job that never started got", func(t *testing.T) {
		dir := t.TempDir()
		claim(t, dir, heartbeatStateClaimed)
		writeBootMark(t, dir, bootListenerFile, claimed.Add(2*time.Second))

		fields, ok := jobStartFields(dir)
		if want := []any{"claimedToListener", 2.0}; !ok || !reflect.DeepEqual(fields, want) {
			t.Fatalf("fields = %v (%v), want %v", fields, ok, want)
		}
	})

	t.Run("nothing for a runner that never claimed", func(t *testing.T) {
		dir := t.TempDir()
		claim(t, dir, heartbeatStatePolling)
		writeBootMark(t, dir, bootListenerFile, claimed.Add(2*time.Second))
		if fields, ok := jobStartFields(dir); ok {
			t.Fatalf("fields = %v for an unclaimed runner", fields)
		}
	})
}
