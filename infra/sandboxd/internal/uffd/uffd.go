//go:build linux

package uffd

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

const (
	pageSize = 4096

	// Linux userfaultfd ABI (include/uapi/linux/userfaultfd.h).
	ioctlCopy      = 0xC028AA03
	ioctlZeropage  = 0xC020AA04
	ioctlWake      = 0x8010AA02
	eventPagefault = 0x12
	msgSize        = 32

	chunkMissing   = 0
	chunkClaimed   = 1
	chunkInstalled = 2

	handshakeTimeout = 30 * time.Second
	fetchAttempts    = 3
)

// fetchBackoff is a variable so tests do not wait it out.
var fetchBackoff = time.Second

// Server is the page fault handler for one Firecracker process.
type Server struct {
	ln   *net.UnixListener
	path string

	src     Source
	opts    Options
	regions []Region
	fd      int
	state   []atomic.Uint32
	faultQ  chan int
	next    atomic.Int64
	loaded  sync.Once

	chunks, installed, faulted, filled atomic.Int64
	zero, faults, bytes                atomic.Int64
}

// Listen opens the socket Firecracker connects to, readable by its owner
// only: the caller hands it to the jail's user.
func Listen(path string) (*Server, error) {
	_ = os.Remove(path)
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: path, Net: "unix"})
	if err != nil {
		return nil, err
	}
	ln.SetUnlinkOnClose(true)
	if err := os.Chmod(path, 0o600); err != nil {
		ln.Close()
		return nil, err
	}
	return &Server{ln: ln, path: path, fd: -1}, nil
}

// Close stops accepting; an accepted Serve stops with its context.
func (s *Server) Close() error { return s.ln.Close() }

// Serve accepts Firecracker's handshake and installs src's pages until ctx
// ends or a chunk cannot be fetched. It answers nil only when ctx ended.
func (s *Server) Serve(ctx context.Context, src Source, opts Options) error {
	if opts.FaultWorkers <= 0 {
		opts.FaultWorkers = 1
	}
	s.src, s.opts = src, opts
	chunks := int((src.Size() + src.ChunkSize() - 1) / src.ChunkSize())
	s.state = make([]atomic.Uint32, chunks)
	s.chunks.Store(int64(chunks))
	s.faultQ = make(chan int, chunks)

	stop := context.AfterFunc(ctx, func() { s.ln.Close() })
	defer stop()
	if err := s.handshake(); err != nil {
		if ctx.Err() != nil {
			return nil
		}
		return err
	}
	defer syscall.Close(s.fd)

	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	var wg sync.WaitGroup
	for range opts.FaultWorkers {
		wg.Go(func() {
			for {
				select {
				case i := <-s.faultQ:
					if err := s.fetch(ctx, i, &s.faulted); err != nil {
						cancel(err)
						return
					}
				case <-ctx.Done():
					return
				}
			}
		})
	}
	for range opts.FillWorkers {
		wg.Go(func() {
			for ctx.Err() == nil {
				i := int(s.next.Add(1) - 1)
				if i >= chunks {
					return
				}
				if !s.state[i].CompareAndSwap(chunkMissing, chunkClaimed) {
					continue
				}
				if err := s.fetch(ctx, i, &s.filled); err != nil {
					cancel(err)
					return
				}
			}
		})
	}
	err := s.events(ctx)
	cancel(err)
	wg.Wait()
	if cause := context.Cause(ctx); !errors.Is(cause, context.Canceled) && cause != nil {
		return cause
	}
	return err
}

// Stats is a snapshot of what Serve installed so far.
func (s *Server) Stats() Stats {
	return Stats{
		Chunks: int(s.chunks.Load()), Faulted: int(s.faulted.Load()), Filled: int(s.filled.Load()),
		Zero: int(s.zero.Load()), Faults: s.faults.Load(), Bytes: s.bytes.Load(),
	}
}

func (s *Server) handshake() error {
	if err := s.ln.SetDeadline(time.Now().Add(handshakeTimeout)); err != nil {
		return err
	}
	conn, err := s.ln.AcceptUnix()
	if err != nil {
		return fmt.Errorf("waiting for firecracker: %w", err)
	}
	defer conn.Close()
	if err := conn.SetReadDeadline(time.Now().Add(handshakeTimeout)); err != nil {
		return err
	}
	buf := make([]byte, 64<<10)
	oob := make([]byte, syscall.CmsgSpace(4))
	n, oobn, flags, _, err := conn.ReadMsgUnix(buf, oob)
	if err != nil {
		return fmt.Errorf("reading the memory handshake: %w", err)
	}
	var fds []int
	if msgs, err := syscall.ParseSocketControlMessage(oob[:oobn]); err == nil {
		for _, msg := range msgs {
			if got, err := syscall.ParseUnixRights(&msg); err == nil {
				fds = append(fds, got...)
			}
		}
	}
	if flags&(syscall.MSG_TRUNC|syscall.MSG_CTRUNC) != 0 || len(fds) != 1 {
		for _, fd := range fds {
			syscall.Close(fd)
		}
		return fmt.Errorf("memory handshake: %d descriptors, flags %#x", len(fds), flags)
	}
	s.fd = fds[0]
	if err := json.Unmarshal(buf[:n], &s.regions); err != nil {
		syscall.Close(s.fd)
		return fmt.Errorf("memory handshake: %w", err)
	}
	var total uint64
	for _, r := range s.regions {
		if r.PageSize != pageSize || r.Base%pageSize != 0 || r.Size%pageSize != 0 || r.Offset != total {
			syscall.Close(s.fd)
			return fmt.Errorf("memory handshake: unsupported region %+v", r)
		}
		total += r.Size
	}
	if total != uint64(s.src.Size()) {
		syscall.Close(s.fd)
		return fmt.Errorf("memory handshake: guest has %d bytes of memory, the image %d", total, s.src.Size())
	}
	return syscall.SetNonblock(s.fd, true)
}

// events reads the guest's faults until ctx ends. A fault in a missing
// chunk queues it; one in an installed chunk can only follow a madvise
// that dropped the page (Firecracker's balloon), which reads back as zeros.
func (s *Server) events(ctx context.Context) error {
	wake, err := eventfd()
	if err != nil {
		return err
	}
	defer syscall.Close(wake)
	stop := context.AfterFunc(ctx, func() { signal(wake) })
	defer stop()
	buf := make([]byte, msgSize*64)
	poll := []pollFd{{fd: int32(s.fd), events: pollIn}, {fd: int32(wake), events: pollIn}}
	for {
		if err := pollWait(poll); err != nil {
			return err
		}
		if ctx.Err() != nil {
			return nil
		}
		if poll[0].revents&(pollErr|pollHup) != 0 {
			return ErrProcessGone
		}
		n, err := syscall.Read(s.fd, buf)
		if errors.Is(err, syscall.EAGAIN) || errors.Is(err, syscall.EINTR) {
			continue
		}
		if err != nil {
			return fmt.Errorf("reading faults: %w", err)
		}
		for off := 0; off+msgSize <= n; off += msgSize {
			msg := buf[off : off+msgSize]
			if msg[0] != eventPagefault {
				continue
			}
			s.faults.Add(1)
			addr := *(*uint64)(unsafe.Pointer(&msg[16])) &^ (pageSize - 1)
			offset, ok := s.offsetOf(addr)
			if !ok {
				continue
			}
			i := int(offset / uint64(s.src.ChunkSize()))
			if s.state[i].CompareAndSwap(chunkMissing, chunkClaimed) {
				s.faultQ <- i
			} else if s.state[i].Load() == chunkInstalled {
				if err := s.zeroPage(addr); err != nil {
					return err
				}
			}
		}
	}
}

func (s *Server) offsetOf(addr uint64) (uint64, bool) {
	for _, r := range s.regions {
		if addr >= r.Base && addr < r.Base+r.Size {
			return r.Offset + addr - r.Base, true
		}
	}
	return 0, false
}

func (s *Server) fetch(ctx context.Context, i int, counter *atomic.Int64) error {
	var data []byte
	var err error
	for attempt := 1; ; attempt++ {
		data, err = s.src.Chunk(ctx, i)
		if err == nil || ctx.Err() != nil || attempt == fetchAttempts {
			break
		}
		select {
		case <-time.After(time.Duration(attempt) * fetchBackoff):
		case <-ctx.Done():
		}
	}
	if err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return fmt.Errorf("fetching memory chunk %d: %w", i, err)
	}
	if err := s.install(i, data); err != nil {
		return err
	}
	s.state[i].Store(chunkInstalled)
	counter.Add(1)
	if data == nil {
		s.zero.Add(1)
	} else {
		s.bytes.Add(int64(len(data)))
	}
	if s.installed.Add(1) == s.chunks.Load() && s.opts.OnLoaded != nil {
		s.loaded.Do(func() { s.opts.OnLoaded(s.Stats()) })
	}
	return nil
}

// install maps chunk i into every region it overlaps and wakes the
// threads waiting on it.
func (s *Server) install(i int, data []byte) error {
	start := uint64(i) * uint64(s.src.ChunkSize())
	end := min(start+uint64(s.src.ChunkSize()), uint64(s.src.Size()))
	if data != nil && uint64(len(data)) != end-start {
		return fmt.Errorf("memory chunk %d is %d bytes, expected %d", i, len(data), end-start)
	}
	for _, r := range s.regions {
		lo, hi := max(start, r.Offset), min(end, r.Offset+r.Size)
		if lo >= hi {
			continue
		}
		dst := r.Base + lo - r.Offset
		var err error
		if data == nil {
			err = s.fill(dst, hi-lo, nil)
		} else {
			err = s.fill(dst, hi-lo, data[lo-start:hi-start])
		}
		if err != nil {
			return fmt.Errorf("installing memory chunk %d: %w", i, err)
		}
	}
	return nil
}

// fill copies src (or zeros, when src is nil) to [dst, dst+length),
// retrying what the kernel did not copy because the address space was
// changing, and skipping pages already present.
func (s *Server) fill(dst, length uint64, src []byte) error {
	for done := uint64(0); done < length; {
		var n int64
		var errno syscall.Errno
		if src == nil {
			n, errno = s.zeroRange(dst+done, length-done)
		} else {
			n, errno = s.copyRange(dst+done, src[done:length])
		}
		if n > 0 {
			done += uint64(n)
		}
		switch errno {
		case 0, syscall.EAGAIN:
		case syscall.EEXIST:
			// A page in the range is present already: step over it.
			if err := s.wake(dst+done, pageSize); err != nil {
				return err
			}
			done += pageSize
		case syscall.ESRCH, syscall.ENOENT:
			return ErrProcessGone
		default:
			return errno
		}
	}
	return nil
}

func (s *Server) copyRange(dst uint64, src []byte) (int64, syscall.Errno) {
	arg := struct {
		dst, src, len, mode uint64
		copy                int64
	}{dst: dst, src: uint64(uintptr(unsafe.Pointer(&src[0]))), len: uint64(len(src))}
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(s.fd), ioctlCopy, uintptr(unsafe.Pointer(&arg)))
	if arg.copy < 0 {
		return 0, errno
	}
	return arg.copy, errno
}

func (s *Server) zeroRange(dst, length uint64) (int64, syscall.Errno) {
	arg := struct {
		start, len, mode uint64
		zeropage         int64
	}{start: dst, len: length}
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(s.fd), ioctlZeropage, uintptr(unsafe.Pointer(&arg)))
	if arg.zeropage < 0 {
		return 0, errno
	}
	return arg.zeropage, errno
}

func (s *Server) zeroPage(addr uint64) error {
	_, errno := s.zeroRange(addr, pageSize)
	switch errno {
	case 0:
		return nil
	case syscall.EEXIST, syscall.EAGAIN:
		return s.wake(addr, pageSize)
	case syscall.ESRCH, syscall.ENOENT:
		return ErrProcessGone
	default:
		return errno
	}
}

func (s *Server) wake(addr, length uint64) error {
	arg := struct{ start, len uint64 }{addr, length}
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, uintptr(s.fd), ioctlWake, uintptr(unsafe.Pointer(&arg))); errno != 0 && errno != syscall.ENOENT {
		return errno
	}
	return nil
}

type pollFd struct {
	fd              int32
	events, revents int16
}

const (
	pollIn  = 0x1
	pollErr = 0x8
	pollHup = 0x10
)

func pollWait(fds []pollFd) error {
	for {
		_, _, errno := syscall.Syscall(syscall.SYS_POLL, uintptr(unsafe.Pointer(&fds[0])), uintptr(len(fds)), ^uintptr(0))
		if errno == syscall.EINTR {
			continue
		}
		if errno != 0 {
			return errno
		}
		return nil
	}
}

func eventfd() (int, error) {
	fd, _, errno := syscall.Syscall(syscall.SYS_EVENTFD2, 0, syscall.O_CLOEXEC|syscall.O_NONBLOCK, 0)
	if errno != 0 {
		return -1, errno
	}
	return int(fd), nil
}

func signal(fd int) {
	one := uint64(1)
	_, _ = syscall.Write(fd, (*[8]byte)(unsafe.Pointer(&one))[:])
}
