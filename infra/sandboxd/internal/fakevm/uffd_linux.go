package fakevm

import (
	"encoding/json"
	"fmt"
	"net"
	"syscall"
	"unsafe"
)

// guestMemory does Firecracker's side of a Uffd snapshot load: it maps
// size bytes of anonymous memory, registers them with a userfaultfd (user
// mode only, which needs no privilege) and hands the descriptor and layout
// to the memory server listening on sock.
func guestMemory(sock string, size int64) ([]byte, func(), error) {
	const (
		sysUserfaultfd = 323
		userModeOnly   = 1
		ioctlAPI       = 0xC018AA3F
		ioctlRegister  = 0xC020AA00
		modeMissing    = 1
	)
	fd, _, errno := syscall.Syscall(sysUserfaultfd, syscall.O_CLOEXEC|syscall.O_NONBLOCK|userModeOnly, 0, 0)
	if errno != 0 {
		return nil, nil, fmt.Errorf("userfaultfd: %w", errno)
	}
	api := [3]uint64{0xAA, 0, 0}
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, ioctlAPI, uintptr(unsafe.Pointer(&api))); errno != 0 {
		syscall.Close(int(fd))
		return nil, nil, fmt.Errorf("UFFDIO_API: %w", errno)
	}
	mem, err := syscall.Mmap(-1, 0, int(size), syscall.PROT_READ|syscall.PROT_WRITE, syscall.MAP_PRIVATE|syscall.MAP_ANONYMOUS|syscall.MAP_NORESERVE)
	if err != nil {
		syscall.Close(int(fd))
		return nil, nil, err
	}
	release := func() {
		_ = syscall.Munmap(mem)
		syscall.Close(int(fd))
	}
	base := uint64(uintptr(unsafe.Pointer(&mem[0])))
	register := [4]uint64{base, uint64(size), modeMissing, 0}
	if _, _, errno := syscall.Syscall(syscall.SYS_IOCTL, fd, ioctlRegister, uintptr(unsafe.Pointer(&register))); errno != 0 {
		release()
		return nil, nil, fmt.Errorf("UFFDIO_REGISTER: %w", errno)
	}
	conn, err := net.DialUnix("unix", nil, &net.UnixAddr{Name: sock, Net: "unix"})
	if err != nil {
		release()
		return nil, nil, err
	}
	defer conn.Close()
	regions, _ := json.Marshal([]map[string]uint64{{"base_host_virt_addr": base, "size": uint64(size), "offset": 0, "page_size": 4096}})
	if _, _, err := conn.WriteMsgUnix(regions, syscall.UnixRights(int(fd)), nil); err != nil {
		release()
		return nil, nil, err
	}
	return mem, release, nil
}
