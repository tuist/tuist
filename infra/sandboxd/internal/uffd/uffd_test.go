//go:build linux

package uffd

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/rand/v2"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"
	"testing"
	"time"
	"unsafe"
)

// The test binary doubles as the Firecracker side: it maps the guest's
// memory as two anonymous regions, registers them with a userfaultfd, sends
// the descriptor and layout over the socket the way Firecracker does, then
// reads the memory back and prints its digest.
func TestMain(m *testing.M) {
	if sock := os.Getenv("UFFD_TEST_GUEST"); sock != "" {
		if err := guest(sock); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		os.Exit(0)
	}
	// Some CI kernels and sandboxes leave userfaultfd out; every test here
	// needs it.
	fd, _, errno := syscall.Syscall(323, syscall.O_CLOEXEC|uffdUser, 0, 0)
	if errno != 0 {
		fmt.Fprintln(os.Stderr, "skipping: this kernel has no unprivileged userfaultfd:", errno)
		os.Exit(0)
	}
	syscall.Close(int(fd))
	os.Exit(m.Run())
}

const (
	testChunk  = 1 << 20
	testSize   = 8<<20 + 64<<10
	testSplit  = 3<<20 + 4096
	uffdUser   = 1
	ioctlAPI   = 0xC018AA3F
	ioctlReg   = 0xC020AA00
	modeMissed = 1
)

func guest(sock string) error {
	fd, _, errno := syscall.Syscall(323, syscall.O_CLOEXEC|syscall.O_NONBLOCK|uffdUser, 0, 0)
	if errno != 0 {
		return fmt.Errorf("userfaultfd: %w", errno)
	}
	api := [3]uint64{0xAA, 0, 0}
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, ioctlAPI, uintptr(unsafe.Pointer(&api))); errno != 0 {
		return fmt.Errorf("UFFDIO_API: %w", errno)
	}
	var regions []Region
	var mems [][]byte
	offset := uint64(0)
	for _, size := range []int{testSplit, testSize - testSplit} {
		mem, err := syscall.Mmap(-1, 0, size, syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_PRIVATE|syscall.MAP_ANONYMOUS)
		if err != nil {
			return err
		}
		base := uint64(uintptr(unsafe.Pointer(&mem[0])))
		reg := [4]uint64{base, uint64(size), modeMissed, 0}
		if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, ioctlReg, uintptr(unsafe.Pointer(&reg))); errno != 0 {
			return fmt.Errorf("UFFDIO_REGISTER: %w", errno)
		}
		regions = append(regions, Region{Base: base, Size: uint64(size), Offset: offset, PageSize: pageSize})
		mems = append(mems, mem)
		offset += uint64(size)
	}
	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: sock, Net: "unix"})
	if err != nil {
		return err
	}
	data, _ := json.Marshal(regions)
	if _, _, err := conn.WriteMsgUnix(data, syscall.UnixRights(int(fd)), nil); err != nil {
		return err
	}
	conn.Close()
	// Wait for the parent's go-ahead on stdin, then touch the memory.
	var line string
	if _, err := fmt.Scanln(&line); err != nil {
		return err
	}
	hash := sha256.New()
	if line == "all" {
		for _, mem := range mems {
			hash.Write(mem)
		}
	} else {
		at, _ := strconv.Atoi(line)
		for _, mem := range mems {
			if at < len(mem) {
				hash.Write(mem[at : at+pageSize])
				break
			}
			at -= len(mem)
		}
	}
	fmt.Println(hex.EncodeToString(hash.Sum(nil)))
	return nil
}

type memSource struct {
	data  []byte
	zero  map[int]bool
	fail  atomic.Bool
	calls atomic.Int64
}

func newSource() *memSource {
	data := make([]byte, testSize)
	rng := rand.New(rand.NewPCG(1, 2))
	for i := range data {
		data[i] = byte(rng.IntN(256))
	}
	src := &memSource{data: data, zero: map[int]bool{2: true, 6: true}}
	for i := range src.zero {
		clear(data[i*testChunk : (i+1)*testChunk])
	}
	return src
}

func (m *memSource) Size() int64      { return testSize }
func (m *memSource) ChunkSize() int64 { return testChunk }
func (m *memSource) Chunk(ctx context.Context, i int) ([]byte, error) {
	m.calls.Add(1)
	if m.fail.Load() {
		return nil, errors.New("store unavailable")
	}
	if m.zero[i] {
		return nil, nil
	}
	return m.data[i*testChunk : min((i+1)*testChunk, testSize)], nil
}

type run struct {
	srv   *Server
	cmd   *exec.Cmd
	stdin *os.File
	out   *bytes.Buffer
	// done closes when Serve returns, with its answer in err.
	done chan struct{}
	err  error
}

func start(t *testing.T, src Source, opts Options) *run {
	t.Helper()
	sock := filepath.Join(t.TempDir(), "mem.sock")
	srv, err := Listen(sock)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	run := &run{srv: srv, done: make(chan struct{})}
	go func() {
		run.err = srv.Serve(ctx, src, opts)
		close(run.done)
	}()
	cmd := exec.Command(os.Args[0], "-test.run=^$")
	cmd.Env = append(os.Environ(), "UFFD_TEST_GUEST="+sock)
	r, w, _ := os.Pipe()
	out := &bytes.Buffer{}
	cmd.Stdin, cmd.Stdout, cmd.Stderr = r, out, out
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	r.Close()
	t.Cleanup(func() {
		w.Close()
		_ = cmd.Process.Kill()
		_ = cmd.Wait()
		cancel()
		<-run.done
	})
	run.cmd, run.stdin, run.out = cmd, w, out
	return run
}

func (r *run) touch(t *testing.T, what string) string {
	t.Helper()
	fmt.Fprintln(r.stdin, what)
	waited := make(chan error, 1)
	go func() { waited <- r.cmd.Wait() }()
	select {
	case err := <-waited:
		if err != nil {
			t.Fatalf("guest: %v: %s", err, r.out)
		}
	case <-r.done:
		t.Fatalf("serve ended while the guest waited: %v", r.err)
	case <-time.After(20 * time.Second):
		t.Fatalf("guest still waiting on its memory: %+v", r.srv.Stats())
	}
	return strings.TrimSpace(r.out.String())
}

func digest(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

func TestFaultsFetchOnlyTheChunksTheGuestTouches(t *testing.T) {
	src := newSource()
	r := start(t, src, Options{FaultWorkers: 2})
	// The page straddles nothing, but its chunk starts in the first region
	// and ends in the second.
	at := testSplit + 2*pageSize
	if got := r.touch(t, strconv.Itoa(at)); got != digest(src.data[at:at+pageSize]) {
		t.Fatalf("guest read the wrong page")
	}
	if stats := r.srv.Stats(); stats.Faulted != 1 || stats.Filled != 0 || src.calls.Load() != 1 {
		t.Fatalf("stats %+v after %d fetches, expected one faulted chunk", stats, src.calls.Load())
	}
}

func TestEveryPageReadsBackThroughFaults(t *testing.T) {
	src := newSource()
	r := start(t, src, Options{FaultWorkers: 4})
	if got := r.touch(t, "all"); got != digest(src.data) {
		t.Fatalf("guest memory differs from the image")
	}
	if stats := r.srv.Stats(); stats.Faulted != 9 || stats.Zero != 2 {
		t.Fatalf("stats %+v", stats)
	}
}

func TestFillInstallsEverythingBeforeTheGuestLooks(t *testing.T) {
	src := newSource()
	loaded := make(chan Stats, 1)
	r := start(t, src, Options{FaultWorkers: 1, FillWorkers: 2, OnLoaded: func(s Stats) { loaded <- s }})
	var stats Stats
	select {
	case stats = <-loaded:
	case <-time.After(20 * time.Second):
		t.Fatal("fill never finished")
	}
	if stats.Filled != 9 || stats.Faulted != 0 || stats.Bytes != testSize-2*testChunk {
		t.Fatalf("stats %+v", stats)
	}
	src.fail.Store(true)
	if got := r.touch(t, "all"); got != digest(src.data) {
		t.Fatalf("guest memory differs from the image")
	}
}

func TestServeFailsWhenAChunkCannotBeFetched(t *testing.T) {
	fetchBackoff = time.Millisecond
	src := newSource()
	src.fail.Store(true)
	r := start(t, src, Options{FaultWorkers: 1})
	fmt.Fprintln(r.stdin, "0")
	select {
	case <-r.done:
		if r.err == nil || !strings.Contains(r.err.Error(), "store unavailable") {
			t.Fatalf("serve answered %v", r.err)
		}
	case <-time.After(20 * time.Second):
		t.Fatal("serve kept waiting on a chunk it cannot fetch")
	}
	if calls := src.calls.Load(); calls != fetchAttempts {
		t.Fatalf("%d fetches, expected %d", calls, fetchAttempts)
	}
}
