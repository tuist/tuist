package driver

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

const (
	testNode     = "node-a"
	testVolumeID = "pvc-0b5a7f7e-3c1d-4b8e-9f2a-6d4c1e2b3a59"
	testLoop     = "/dev/loop7"
)

var testKey = bytes.Repeat([]byte{0x5a}, 32)

type call struct {
	cmd    string
	stdin  []byte
	out    string
	err    error
	effect func()
}

type fakeRunner struct {
	t        *testing.T
	expected []call
	n        int
}

func (f *fakeRunner) expect(calls ...call) { f.expected = append(f.expected, calls...) }

func (f *fakeRunner) Run(_ context.Context, stdin []byte, name string, args ...string) ([]byte, error) {
	f.t.Helper()
	got := strings.Join(append([]string{name}, args...), " ")
	if f.n >= len(f.expected) {
		f.t.Errorf("unexpected command %q", got)
		return nil, &CommandError{Command: got, ExitCode: 99}
	}
	c := f.expected[f.n]
	f.n++
	if got != c.cmd {
		f.t.Errorf("command %d = %q, want %q", f.n, got, c.cmd)
	}
	if !bytes.Equal(stdin, c.stdin) {
		f.t.Errorf("command %q stdin = %x, want %x", got, stdin, c.stdin)
	}
	if c.effect != nil {
		c.effect()
	}
	return []byte(c.out), c.err
}

func (f *fakeRunner) verify() {
	f.t.Helper()
	for _, c := range f.expected[f.n:] {
		f.t.Errorf("expected command was not run: %q", c.cmd)
	}
}

type fakeMounts struct{ mounts []Mount }

func (f *fakeMounts) Mounts() ([]Mount, error) { return append([]Mount(nil), f.mounts...), nil }

func (f *fakeMounts) add(m Mount) { f.mounts = append(f.mounts, m) }

func (f *fakeMounts) remove(mountPoint string) {
	for i := len(f.mounts) - 1; i >= 0; i-- {
		if f.mounts[i].MountPoint == mountPoint {
			f.mounts = append(f.mounts[:i], f.mounts[i+1:]...)
			return
		}
	}
}

type fakeHost struct {
	stats   FSStats
	devices map[string]string
}

func (f *fakeHost) FSStats(string) (FSStats, error) { return f.stats, nil }

func (f *fakeHost) DeviceNumber(path string) (string, error) {
	if n, ok := f.devices[path]; ok {
		return n, nil
	}
	return "", os.ErrNotExist
}

type fakeKeys struct {
	err       error
	active    int
	requested []int
	issued    [][]byte
}

// Fetch mirrors the server: version 0 serves the active version, any other
// version is served as asked.
func (f *fakeKeys) Fetch(_ context.Context, _ string, version int) ([]byte, int, error) {
	f.requested = append(f.requested, version)
	if f.err != nil {
		return nil, 0, f.err
	}
	served := version
	if served == 0 {
		served = f.active
	}
	key := append([]byte(nil), testKey...)
	f.issued = append(f.issued, key)
	return key, served, nil
}

func (e *env) writeKeyVersion(content string) {
	e.t.Helper()
	if err := os.WriteFile(e.v.keyVersion, []byte(content), 0o600); err != nil {
		e.t.Fatal(err)
	}
}

func (e *env) keyVersionFile() string {
	e.t.Helper()
	data, err := os.ReadFile(e.v.keyVersion)
	if err != nil {
		e.t.Fatal(err)
	}
	return string(data)
}

func (f *fakeKeys) assertZeroed(t *testing.T) {
	t.Helper()
	for _, key := range f.issued {
		if !bytes.Equal(key, make([]byte, len(key))) {
			t.Errorf("key buffer was not zeroed after use")
		}
	}
}

type env struct {
	t       *testing.T
	dir     string
	staging string
	d       *Driver
	runner  *fakeRunner
	mounts  *fakeMounts
	host    *fakeHost
	keys    *fakeKeys
	v       volume
}

func newEnv(t *testing.T, options ...func(*Config)) *env {
	t.Helper()
	dir, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	e := &env{
		t:       t,
		dir:     dir,
		staging: filepath.Join(dir, "staging"),
		runner:  &fakeRunner{t: t},
		mounts:  &fakeMounts{},
		host:    &fakeHost{stats: FSStats{AvailableBytes: 1 << 40}, devices: map[string]string{}},
		keys:    &fakeKeys{active: 1},
	}
	cfg := Config{
		NodeID:       testNode,
		StateDir:     dir,
		ReserveBytes: 20 << 30,
		Keys:         e.keys,
		Runner:       e.runner,
		Mounts:       e.mounts,
		Host:         e.host,
	}
	for _, option := range options {
		option(&cfg)
	}
	e.d, err = New(cfg)
	if err != nil {
		t.Fatal(err)
	}
	e.v, err = e.d.volume(testVolumeID)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(e.runner.verify)
	return e
}

func (e *env) writeImage(size int64) {
	e.t.Helper()
	if err := os.WriteFile(e.v.image, nil, 0o600); err != nil {
		e.t.Fatal(err)
	}
	if err := os.Truncate(e.v.image, size); err != nil {
		e.t.Fatal(err)
	}
}

func (e *env) writeMarker() {
	e.t.Helper()
	if err := os.WriteFile(e.v.marker, nil, 0o600); err != nil {
		e.t.Fatal(err)
	}
}

func (e *env) exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

func (e *env) volumeMount(mountPoint string) Mount {
	return Mount{MajorMinor: "252:3", MountPoint: mountPoint, FSType: "xfs", Source: e.v.mapperPath()}
}

func exitWith(code int) error {
	return &CommandError{Command: "fake", ExitCode: code}
}

func requireCode(t *testing.T, err error, want codes.Code) {
	t.Helper()
	if got := status.Code(err); got != want {
		t.Fatalf("code = %v (%v), want %v", got, err, want)
	}
}
