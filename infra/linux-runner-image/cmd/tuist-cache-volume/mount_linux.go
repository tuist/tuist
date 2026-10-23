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
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// The broker lives in the already privileged DinD sidecar inside the job's
// Kata VM. Passing descriptors avoids PID namespace assumptions and path races;
// neither the runner nor an ordinary Docker job container needs mount privileges.
func bindDirectory(socket, source, target string) error {
	data, _ := json.Marshal(source)
	return sendMount(socket, data, target)
}

// bindCheckout binds a checkout's working tree at the workspace, which is
// workspace relative to the work directory, in this namespace and the broker's.
// dockerd runs beside the broker, so container jobs see the same tree.
func bindCheckout(socket, source, workspace, target string) error {
	data, _ := json.Marshal(mountMessage{Source: source, Workspace: workspace})
	return sendMount(socket, data, target)
}

type mountMessage struct {
	Source    string `json:"source"`
	Workspace string `json:"workspace"`
}

func sendMount(socket string, data []byte, target string) error {
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
	// The work directory the cache root sits in, as this container mounts it.
	work, err := os.OpenRoot(filepath.Dir(root))
	if err != nil {
		return err
	}
	defer work.Close()
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
				if err := mountRequest(conn, sourceRoot, work); err != nil {
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

func mountRequest(conn *net.UnixConn, root, work *os.Root) error {
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
	source, workspace, err := parseMountRequest(data[:n])
	if err != nil {
		return err
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
	if workspace != "" {
		// The same directory as the client's target, as this container sees it.
		local, err := work.OpenFile(workspace, os.O_RDONLY|unix.O_DIRECTORY|unix.O_NOFOLLOW, 0)
		if err != nil {
			return err
		}
		defer local.Close()
		if !sameDirectory(int(local.Fd()), fds[1]) {
			return errors.New("workspace is not the client's target")
		}
		cmd.Args = append(cmd.Args, "local")
		cmd.ExtraFiles = append(cmd.ExtraFiles, local)
	}
	if output, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("mount worker: %s (%w)", strings.TrimSpace(string(output)), err)
	}
	return nil
}

// mountWorker binds fd 3 at fd 4 in the namespace of fd 5. With local, it first
// binds it at fd 6 in its own namespace too, and undoes that if the client's
// bind fails.
func mountWorker(local bool) error {
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
	undo := func() {}
	if local {
		own, err := os.Open("/proc/self/ns/mnt")
		if err != nil {
			return err
		}
		defer own.Close()
		localTree, err := unix.OpenTree(3, "", unix.OPEN_TREE_CLONE|unix.OPEN_TREE_CLOEXEC|unix.AT_EMPTY_PATH)
		if err != nil {
			return fmt.Errorf("clone mount tree: %w", err)
		}
		defer unix.Close(localTree)
		if err := emptyDirectory(6); err != nil {
			return err
		}
		if err := unix.MoveMount(localTree, "", 6, "", unix.MOVE_MOUNT_F_EMPTY_PATH|unix.MOVE_MOUNT_T_EMPTY_PATH); err != nil {
			return fmt.Errorf("attach local mount tree: %w", err)
		}
		undo = func() {
			if unix.Setns(int(own.Fd()), unix.CLONE_NEWNS) == nil {
				_ = unix.Unmount("/proc/self/fd/"+strconv.Itoa(localTree), unix.MNT_DETACH)
			}
		}
	}
	if err := unix.Setns(5, unix.CLONE_NEWNS); err != nil {
		undo()
		return fmt.Errorf("enter mount namespace: %w", err)
	}
	if err := emptyDirectory(4); err != nil {
		undo()
		return err
	}
	if err := unix.MoveMount(tree, "", 4, "", unix.MOVE_MOUNT_F_EMPTY_PATH|unix.MOVE_MOUNT_T_EMPTY_PATH); err != nil {
		undo()
		return fmt.Errorf("attach mount tree: %w", err)
	}
	return nil
}

// parseMountRequest accepts a volume source (a JSON string) or a checkout: its
// working tree and the workspace, relative to the work directory, to bind it at.
func parseMountRequest(data []byte) (string, string, error) {
	var source string
	if err := json.Unmarshal(data, &source); err == nil {
		parts := strings.Split(source, "/")
		if len(parts) != 2 || !directoryPattern.MatchString(parts[0]) || (parts[1] != "data" && !directoryPattern.MatchString(parts[1])) {
			return "", "", errors.New("invalid volume source")
		}
		return source, "", nil
	}
	var message mountMessage
	if err := json.Unmarshal(data, &message); err != nil {
		return "", "", errors.New("invalid mount request")
	}
	parts := strings.Split(message.Source, "/")
	if len(parts) != 2 || !directoryPattern.MatchString(parts[0]) || parts[1] != "checkout" {
		return "", "", errors.New("invalid checkout source")
	}
	first := strings.Split(message.Workspace, "/")[0]
	if !filepath.IsLocal(message.Workspace) || filepath.Clean(message.Workspace) != message.Workspace || strings.HasPrefix(first, ".") || first == "_tuist_cache" {
		return "", "", errors.New("invalid checkout workspace")
	}
	return message.Source, message.Workspace, nil
}

func sameDirectory(a, b int) bool {
	var first, second unix.Stat_t
	return unix.Fstat(a, &first) == nil && unix.Fstat(b, &second) == nil && first.Dev == second.Dev && first.Ino == second.Ino
}

func emptyDirectory(fd int) error {
	dup, err := unix.Openat(fd, ".", unix.O_RDONLY|unix.O_DIRECTORY|unix.O_CLOEXEC, 0)
	if err != nil {
		return fmt.Errorf("open mount target: %w", err)
	}
	target := os.NewFile(uintptr(dup), "target")
	entries, err := target.Readdirnames(1)
	target.Close()
	if len(entries) != 0 {
		return errors.New("cache target is no longer empty")
	}
	if err != nil && !errors.Is(err, io.EOF) {
		return err
	}
	return nil
}
