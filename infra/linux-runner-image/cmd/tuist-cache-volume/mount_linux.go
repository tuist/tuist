//go:build linux

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"runtime"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// The broker lives in the already privileged DinD sidecar inside the job's
// Kata VM. Passing descriptors avoids PID namespace assumptions and path races;
// neither the runner nor an ordinary Docker job container needs mount privileges.
func bindDirectory(socket, source, target string) error {
	ns, err := os.Open("/proc/self/ns/mnt")
	if err != nil {
		return err
	}
	defer ns.Close()
	fd, err := unix.Open(target, unix.O_PATH|unix.O_DIRECTORY|unix.O_NOFOLLOW|unix.O_CLOEXEC, 0)
	if err != nil {
		return err
	}
	defer unix.Close(fd)
	conn, err := net.DialUnix("unixpacket", nil, &net.UnixAddr{Name: socket, Net: "unixpacket"})
	if err != nil {
		return fmt.Errorf("cache mount helper unavailable (runner image/controller upgrade required): %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(30 * time.Second))
	data, _ := json.Marshal(source)
	if _, _, err = conn.WriteMsgUnix(data, unix.UnixRights(int(ns.Fd()), fd), nil); err != nil {
		return err
	}
	response := make([]byte, 4096)
	n, err := conn.Read(response)
	if err != nil {
		return err
	}
	if string(response[:n]) != "ok" {
		return fmt.Errorf("cache bind mount failed: %s", response[:n])
	}
	return nil
}

func serveMounts(socket, root string) error {
	if os.Geteuid() != 0 {
		return errors.New("mount helper must run as root inside the job VM")
	}
	sourceRoot, err := os.OpenRoot(root)
	if err != nil {
		return err
	}
	defer sourceRoot.Close()
	listener, err := net.ListenUnix("unixpacket", &net.UnixAddr{Name: socket, Net: "unixpacket"})
	if err != nil {
		return err
	}
	defer listener.Close()
	if err = os.Chmod(socket, 0666); err != nil {
		return err
	}
	slots := make(chan struct{}, 8)
	for {
		conn, err := listener.AcceptUnix()
		if err != nil {
			return err
		}
		select {
		case slots <- struct{}{}:
			go func() {
				defer func() { <-slots; conn.Close() }()
				_ = conn.SetDeadline(time.Now().Add(30 * time.Second))
				if err := mountRequest(conn, sourceRoot); err != nil {
					_, _ = conn.Write([]byte(err.Error()))
				} else {
					_, _ = conn.Write([]byte("ok"))
				}
			}()
		default:
			_, _ = conn.Write([]byte("mount helper busy"))
			conn.Close()
		}
	}
}

func mountRequest(conn *net.UnixConn, root *os.Root) error {
	data, control := make([]byte, 4096), make([]byte, unix.CmsgSpace(8*4))
	n, oobn, flags, _, err := conn.ReadMsgUnix(data, control)
	if err != nil {
		return err
	}
	messages, err := unix.ParseSocketControlMessage(control[:oobn])
	if err != nil {
		return err
	}
	var fds []int
	defer func() {
		for _, fd := range fds {
			unix.Close(fd)
		}
	}()
	for _, message := range messages {
		rights, err := unix.ParseUnixRights(&message)
		if err != nil {
			return err
		}
		for _, fd := range rights {
			unix.CloseOnExec(fd)
		}
		fds = append(fds, rights...)
	}
	if flags&(unix.MSG_TRUNC|unix.MSG_CTRUNC) != 0 || len(fds) != 2 {
		return errors.New("expected mount namespace and target directory descriptors")
	}
	var source string
	if err = json.Unmarshal(data[:n], &source); err != nil {
		return errors.New("invalid mount request")
	}
	parts := strings.Split(source, "/")
	if len(parts) != 2 || !directoryPattern.MatchString(parts[0]) || (parts[1] != "data" && !directoryPattern.MatchString(parts[1])) {
		return errors.New("invalid volume source")
	}
	// os.Root bounds all resolution to this pod's UID-scoped cache subtree.
	directory, err := root.OpenFile(source, os.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW, 0)
	if err != nil {
		return err
	}
	defer directory.Close()
	kind, err := unix.IoctlRetInt(fds[0], unix.NS_GET_NSTYPE)
	if err != nil || kind != unix.CLONE_NEWNS {
		return errors.New("invalid mount namespace descriptor")
	}
	// The files supplied to ExtraFiles must stay open until the worker exits.
	// Duplicate them so ownership remains with the request's descriptor cleanup.
	nsFD, err := unix.FcntlInt(uintptr(fds[0]), unix.F_DUPFD_CLOEXEC, 0)
	if err != nil {
		return err
	}
	ns := os.NewFile(uintptr(nsFD), "namespace")
	defer ns.Close()
	targetFD, err := unix.FcntlInt(uintptr(fds[1]), unix.F_DUPFD_CLOEXEC, 0)
	if err != nil {
		return err
	}
	targetCopy := os.NewFile(uintptr(targetFD), "target")
	defer targetCopy.Close()
	executable, err := os.Executable()
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	cmd := exec.CommandContext(ctx, executable, "mount-worker")
	cmd.ExtraFiles = []*os.File{directory, targetCopy, ns}
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("mount worker: %s (%w)", strings.TrimSpace(string(output)), err)
	}
	return nil
}

func mountWorker() error {
	runtime.LockOSThread()
	// This subprocess exits immediately afterward: never return its switched
	// thread to Go's thread pool or switch the long-lived broker's namespace.
	if err := unix.Unshare(unix.CLONE_FS); err != nil {
		return fmt.Errorf("unshare filesystem context: %w", err)
	}
	// Clone while still in the source namespace; OpenTree cannot clone a mount
	// belonging to another namespace. The detached tree can then move across.
	// Descriptor-only APIs also work when the target's /proc cannot see us.
	tree, err := unix.OpenTree(3, "", unix.OPEN_TREE_CLONE|unix.OPEN_TREE_CLOEXEC|unix.AT_EMPTY_PATH)
	if err != nil {
		return fmt.Errorf("clone mount tree: %w", err)
	}
	defer unix.Close(tree)
	if err := unix.Setns(5, unix.CLONE_NEWNS); err != nil {
		return fmt.Errorf("enter mount namespace: %w", err)
	}
	fd, err := unix.Openat(4, ".", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open mount target: %w", err)
	}
	target := os.NewFile(uintptr(fd), "target")
	entries, err := target.Readdirnames(1)
	target.Close()
	if len(entries) != 0 {
		return errors.New("cache target is no longer empty")
	}
	if err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	if err := unix.MoveMount(tree, "", 4, "", unix.MOVE_MOUNT_F_EMPTY_PATH|unix.MOVE_MOUNT_T_EMPTY_PATH); err != nil {
		return fmt.Errorf("attach mount tree: %w", err)
	}
	return nil
}
