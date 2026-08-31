package podagent

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"
)

// The status share is a writable virtio-fs mount the guest owns, and the guest
// runs untrusted customer CI. Every reader below therefore takes an
// attacker-chosen path holding attacker-chosen content. A symlink makes the
// host resolve and read some other file on the guest's behalf; a FIFO parks the
// host inside the open itself until something writes to the other end, wedging
// the reconcile for as long as the guest cares to hold it.
var guestStatusReaders = []struct {
	name string
	file string
	// content is content this reader accepts. Used twice: as the symlink
	// target's body, so a rejected read proves the link was not followed
	// rather than proving the target merely failed to parse; and as the
	// well-formed file that must keep being accepted.
	content string
	// accepted reports whether the reader came back with something the
	// caller would act on.
	accepted func(statusDir string) bool
}{
	{
		name:    "runner-rc",
		file:    runnerExitFile,
		content: "7\n",
		accepted: func(d string) bool {
			_, ok := readRunnerExit(d)
			return ok
		},
	},
	{
		name:    "runner-rc mtime",
		file:    runnerExitFile,
		content: "7\n",
		accepted: func(d string) bool {
			_, ok := readRunnerExitTime(d)
			return ok
		},
	},
	{
		name:     "volume-upload-ms",
		file:     uploadMillisFile,
		content:  "4200\n",
		accepted: func(d string) bool { return readUploadMillis(d) != -1 },
	},
	{
		name:     "cache-fill-percent",
		file:     fillPercentFile,
		content:  "42\n",
		accepted: func(d string) bool { return readFillPercent(d) != -1 },
	},
	{
		name:     "cache-subtree-kib",
		file:     subtreeUsageFile,
		content:  "Binaries\t3000\ncas\t8000\n",
		accepted: func(d string) bool { return readSubtreeUsage(d) != nil },
	},
	{
		name:     "cache-promote-result",
		file:     promoteResultFile,
		content:  "accepted 9\n",
		accepted: func(d string) bool { return readPromoteResult(d).Result != "" },
	},
	{
		name:     "volume-head.json",
		file:     volumeHeadFile,
		content:  `{"generation":9,"digest":"deadbeef","download_url":"https://example.invalid/head"}`,
		accepted: func(d string) bool { return readVolumeHead(d) != nil },
	},
	{
		name:    "cache-dirty",
		file:    dirtyMarkerFile,
		content: "1\n",
		accepted: func(d string) bool {
			present, _ := readDirtyMarker(d)
			return present
		},
	},
	{
		name:    "runner-heartbeat",
		file:    runnerHeartbeatFile,
		content: heartbeatStatePolling + "\n",
		accepted: func(d string) bool {
			_, _, ok := readRunnerHeartbeat(d)
			return ok
		},
	},
}

// The happy path is the whole point of the hardening being narrow: a guest that
// writes a plain file must keep being read exactly as before.
func TestGuestStatusReadersAcceptRegularFile(t *testing.T) {
	for _, tc := range guestStatusReaders {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.WriteFile(filepath.Join(dir, tc.file), []byte(tc.content), 0o644); err != nil {
				t.Fatalf("write: %v", err)
			}
			if !tc.accepted(dir) {
				t.Error("reader rejected a well-formed guest file")
			}
		})
	}
}

func TestGuestStatusReadersRejectSymlink(t *testing.T) {
	for _, tc := range guestStatusReaders {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			secret := filepath.Join(t.TempDir(), "host-secret")
			if err := os.WriteFile(secret, []byte(tc.content), 0o600); err != nil {
				t.Fatalf("write secret: %v", err)
			}
			if err := os.Symlink(secret, filepath.Join(dir, tc.file)); err != nil {
				t.Fatalf("symlink: %v", err)
			}
			if tc.accepted(dir) {
				t.Error("guest symlink to a host file was followed")
			}
		})
	}
}

func TestGuestStatusReadersDoNotBlockOnFIFO(t *testing.T) {
	for _, tc := range guestStatusReaders {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := syscall.Mkfifo(filepath.Join(dir, tc.file), 0o600); err != nil {
				t.Skipf("mkfifo unsupported: %v", err)
			}

			done := make(chan bool, 1)
			go func() { done <- tc.accepted(dir) }()

			select {
			case ok := <-done:
				if ok {
					t.Error("reader accepted a FIFO")
				}
			case <-time.After(5 * time.Second):
				t.Fatal("reader blocked on a guest-planted FIFO")
			}
		})
	}
}

func TestGuestStatusReadersRejectDirectory(t *testing.T) {
	for _, tc := range guestStatusReaders {
		t.Run(tc.name, func(t *testing.T) {
			dir := t.TempDir()
			if err := os.Mkdir(filepath.Join(dir, tc.file), 0o755); err != nil {
				t.Fatalf("mkdir: %v", err)
			}
			if tc.accepted(dir) {
				t.Error("reader accepted a directory")
			}
		})
	}
}
