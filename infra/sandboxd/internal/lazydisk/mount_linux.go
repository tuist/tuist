//go:build linux

package lazydisk

import (
	"errors"
	"os"
	"syscall"
	"time"

	"github.com/hanwen/go-fuse/v2/fuse"
	"golang.org/x/sys/unix"
)

// Supported reports whether this process can mount FUSE file systems: it
// runs as root and /dev/fuse opens.
func Supported() bool {
	if os.Geteuid() != 0 {
		return false
	}
	f, err := os.OpenFile("/dev/fuse", os.O_RDWR, 0)
	if err != nil {
		return false
	}
	f.Close()
	return true
}

// Mount serves an Image as the regular file at a path, which must exist:
// the mount covers it. Owner is who the file appears to belong to;
// other users can open it too, the jailed Firecracker among them.
type Mount struct {
	path   string
	server *fuse.Server
	served chan struct{}
}

// MountImage mounts im over path, a regular file.
func MountImage(path string, im *Image, uid, gid uint32) (*Mount, error) {
	server, err := fuse.NewServer(&file{RawFileSystem: fuse.NewDefaultRawFileSystem(), image: im, owner: fuse.Owner{Uid: uid, Gid: gid}}, path, &fuse.MountOptions{
		AllowOther:        true,
		DirectMountStrict: true,
		FsName:            "sandboxd",
		Name:              "lazydisk",
		MaxWrite:          1 << 20,
		MaxBackground:     64,
		DisableXAttrs:     true,
	})
	if err != nil {
		return nil, err
	}
	m := &Mount{path: path, server: server, served: make(chan struct{})}
	go func() {
		defer close(m.served)
		server.Serve()
	}()
	return m, nil
}

// Detach unmounts the file lazily: a process that has it open keeps
// reading and writing it through the image until it closes it, and the
// path shows the file underneath again.
func (m *Mount) Detach() error {
	if err := unix.Unmount(m.path, unix.MNT_DETACH); err != nil && !errors.Is(err, unix.EINVAL) {
		return err
	}
	return nil
}

// Done is closed once the mount is gone everywhere: detached, and closed
// by its last user.
func (m *Mount) Done() <-chan struct{} { return m.served }

// Unmount detaches whatever is mounted at path, for a mount a previous
// daemon left behind.
func Unmount(path string) {
	_ = unix.Unmount(path, unix.MNT_DETACH)
}

// file is the mount's one node, the root, a regular file.
type file struct {
	fuse.RawFileSystem
	image *Image
	owner fuse.Owner
}

func (f *file) String() string { return "sandboxd-lazydisk" }

func (f *file) attr(out *fuse.Attr) {
	*out = fuse.Attr{Ino: fuse.FUSE_ROOT_ID, Size: uint64(f.image.Size()), Mode: syscall.S_IFREG | 0o600, Nlink: 1, Owner: f.owner, Blksize: 4096}
}

func (f *file) GetAttr(_ <-chan struct{}, in *fuse.GetAttrIn, out *fuse.AttrOut) fuse.Status {
	if in.NodeId != fuse.FUSE_ROOT_ID {
		return fuse.ENOENT
	}
	f.attr(&out.Attr)
	out.SetTimeout(time.Hour)
	return fuse.OK
}

// SetAttr answers the attributes without changing them; the image's size
// is fixed.
func (f *file) SetAttr(_ <-chan struct{}, in *fuse.SetAttrIn, out *fuse.AttrOut) fuse.Status {
	if in.Valid&fuse.FATTR_SIZE != 0 && int64(in.Size) != f.image.Size() {
		return fuse.EPERM
	}
	f.attr(&out.Attr)
	return fuse.OK
}

// Open bypasses the page cache: the guest caches what it reads itself, and
// the local file has its own.
func (f *file) Open(_ <-chan struct{}, _ *fuse.OpenIn, out *fuse.OpenOut) fuse.Status {
	out.OpenFlags = fuse.FOPEN_DIRECT_IO
	return fuse.OK
}

func (f *file) Read(_ <-chan struct{}, in *fuse.ReadIn, buf []byte) (fuse.ReadResult, fuse.Status) {
	n, err := f.image.ReadAt(buf[:min(int(in.Size), len(buf))], int64(in.Offset))
	if err != nil {
		return nil, fuse.EIO
	}
	return fuse.ReadResultData(buf[:n]), fuse.OK
}

func (f *file) Write(_ <-chan struct{}, in *fuse.WriteIn, data []byte) (uint32, fuse.Status) {
	n, err := f.image.WriteAt(data, int64(in.Offset))
	if err != nil {
		return uint32(n), fuse.EIO
	}
	return uint32(n), fuse.OK
}

func (f *file) Fallocate(_ <-chan struct{}, in *fuse.FallocateIn) fuse.Status {
	if err := f.image.EnsureRange(int64(in.Offset), int64(in.Length)); err != nil {
		return fuse.EIO
	}
	return fuse.ToStatus(syscall.Fallocate(int(f.image.file.Fd()), in.Mode, int64(in.Offset), int64(in.Length)))
}

func (f *file) Fsync(_ <-chan struct{}, _ *fuse.FsyncIn) fuse.Status {
	return fuse.ToStatus(f.image.Sync())
}

func (f *file) Flush(_ <-chan struct{}, _ *fuse.FlushIn) fuse.Status { return fuse.OK }

func (f *file) Release(_ <-chan struct{}, _ *fuse.ReleaseIn) {}
