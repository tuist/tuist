//go:build linux

package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

const dockerDataRoot = "/var/lib/docker"
const dockerLedgerPath = dockerDataRoot + "/tuist/ledger.json"

// sendDocker sends a request without descriptors to the sidecar's supervisor
// and returns its status: ok, or dockerReset for a data root it started empty.
func sendDocker(socket string, message dockerMessage) (string, error) {
	data, _ := json.Marshal(message)
	conn, err := net.DialUnix("unixpacket", nil, &net.UnixAddr{Name: socket, Net: "unixpacket"})
	if err != nil {
		return "", fmt.Errorf("docker cache helper unavailable: %w", err)
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(2 * time.Minute))
	if _, err = conn.Write(data); err != nil {
		return "", err
	}
	response := make([]byte, 4096)
	n, err := conn.Read(response)
	if err != nil {
		return "", err
	}
	switch reply := string(response[:n]); reply {
	case "ok", dockerReset:
		return reply, nil
	default:
		return "", errors.New(reply)
	}
}

// daemon supervises dockerd in the privileged sidecar: it runs the mount broker,
// starts dockerd on the ephemeral data root, moves it onto the job's Docker
// volume when the hook asks, and cleans and unmounts that volume after the job.
type daemon struct {
	mu        sync.Mutex
	args      []string
	root      string
	ephemeral string
	cmd       *exec.Cmd
	done      chan struct{}
	stopping  bool
	// state is ephemeral, volume, or finished once a volume was torn down.
	state  string
	source string
	// reset is set when the saved data root could not be mounted and the
	// job's branch was formatted empty instead.
	reset  bool
	base   dockerSnapshot
	ledger dockerLedger
	run    func(context.Context, string, ...string) ([]byte, error)
}

// runDind is `tuist-cache-volume dind SOCKET ROOT EPHEMERAL -- dockerd ARGS...`.
func runDind(args []string) error {
	if len(args) < 5 || args[3] != "--" {
		return errors.New("usage: tuist-cache-volume dind SOCKET ROOT EPHEMERAL -- dockerd [ARGS...]")
	}
	d := &daemon{args: args[4:], root: args[1], ephemeral: args[2], state: "ephemeral", run: func(ctx context.Context, name string, args ...string) ([]byte, error) {
		return exec.CommandContext(ctx, name, args...).CombinedOutput()
	}}
	signals := make(chan os.Signal, 1)
	signal.Notify(signals, syscall.SIGTERM, syscall.SIGINT)
	if err := d.start(); err != nil {
		return err
	}
	_ = os.Remove(args[0])
	go func() {
		if err := serveMounts(args[0], args[1], d.handle); err != nil {
			fmt.Fprintf(os.Stderr, "mount helper stopped: %v\n", err)
			os.Exit(1)
		}
	}()
	<-signals
	d.mu.Lock()
	defer d.mu.Unlock()
	d.stop()
	return nil
}

// start runs dockerd. An exit nobody asked for ends the supervisor with its
// code, so the sidecar restarts as it did when dockerd was its process.
func (d *daemon) start() error {
	cmd := exec.Command(d.args[0], d.args[1:]...)
	cmd.Stdout, cmd.Stderr = os.Stdout, os.Stderr
	if err := cmd.Start(); err != nil {
		return err
	}
	done := make(chan struct{})
	d.cmd, d.done = cmd, done
	go func() {
		err := cmd.Wait()
		close(done)
		d.mu.Lock()
		expected := d.stopping || d.cmd != cmd
		d.mu.Unlock()
		if !expected {
			fmt.Fprintf(os.Stderr, "dockerd exited: %v\n", err)
			os.Exit(cmd.ProcessState.ExitCode())
		}
	}()
	return nil
}

// stop ends dockerd. The caller holds the lock.
func (d *daemon) stop() {
	if d.cmd == nil {
		return
	}
	d.stopping = true
	_ = d.cmd.Process.Signal(syscall.SIGTERM)
	d.mu.Unlock()
	select {
	case <-d.done:
	case <-time.After(30 * time.Second):
		_ = d.cmd.Process.Kill()
		<-d.done
	}
	d.mu.Lock()
	d.cmd, d.stopping = nil, false
}

func (d *daemon) ready(ctx context.Context) error {
	for {
		if _, err := d.run(ctx, "docker", "info"); err == nil {
			return nil
		}
		select {
		case <-ctx.Done():
			return errors.New("dockerd did not start")
		case <-time.After(200 * time.Millisecond):
		}
	}
}

func (d *daemon) handle(message dockerMessage) (string, error) {
	d.mu.Lock()
	defer d.mu.Unlock()
	switch message.Docker {
	case "switch":
		if err := d.switchRoot(message.Source); err != nil {
			return "", err
		}
		if d.reset {
			return dockerReset, nil
		}
		return "ok", nil
	case "teardown":
		return "ok", d.teardown()
	}
	return "", errors.New("invalid docker request")
}

// switchRoot moves dockerd onto the volume image at source, relative to the
// pod's cache directory. dockerd has run no container yet. On any failure it
// returns to the ephemeral data root.
func (d *daemon) switchRoot(source string) error {
	if d.state != "ephemeral" {
		return errors.New("data root already switched")
	}
	parts := strings.Split(source, "/")
	if len(parts) != 2 || !directoryPattern.MatchString(parts[0]) || parts[1] != dockerImageName {
		return errors.New("invalid docker volume source")
	}
	image := filepath.Join(d.root, source)
	if info, err := os.Lstat(image); err != nil || !info.Mode().IsRegular() {
		return errors.New("docker volume image unavailable")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	defer cancel()
	d.stop()
	if out, err := d.run(ctx, "umount", dockerDataRoot); err != nil {
		return d.fallback(ctx, fmt.Errorf("unmount ephemeral data root: %s", strings.TrimSpace(string(out))), false)
	}
	if _, err := d.run(ctx, "mount", "-o", "loop", image, dockerDataRoot); err != nil {
		// The saved data root is one this kernel refuses. The job starts its own
		// branch empty instead, and its teardown replaces the saved one.
		if out, err := d.run(ctx, "mkfs.ext4", append(slices.Clone(dockerFormatArgs), image)...); err != nil {
			return d.fallback(ctx, fmt.Errorf("format docker volume: %s", strings.TrimSpace(string(out))), false)
		}
		if out, err := d.run(ctx, "mount", "-o", "loop", image, dockerDataRoot); err != nil {
			return d.fallback(ctx, fmt.Errorf("mount docker volume: %s", strings.TrimSpace(string(out))), false)
		}
		d.reset = true
	}
	if err := d.start(); err != nil {
		return d.fallback(ctx, err, true)
	}
	if err := d.ready(ctx); err != nil {
		return d.fallback(ctx, err, true)
	}
	d.state, d.source = "volume", source
	d.base, _ = d.snapshot(ctx)
	d.ledger = readDockerLedger()
	return nil
}

// fallback restores the ephemeral data root and reports cause.
func (d *daemon) fallback(ctx context.Context, cause error, mounted bool) error {
	d.stop()
	if mounted {
		_, _ = d.run(ctx, "umount", dockerDataRoot)
	}
	_, _ = d.run(ctx, "mount", "-o", "loop", d.ephemeral, dockerDataRoot)
	if err := d.start(); err != nil {
		return errors.Join(cause, err)
	}
	_ = d.ready(ctx)
	return cause
}

// teardown keeps only images and build cache, removes every registry
// reference, stops dockerd, unmounts the volume cleanly and writes the report
// the host reads. dockerd stays stopped: the pod is ending.
func (d *daemon) teardown() error {
	if d.state != "volume" {
		return errors.New("no docker volume mounted")
	}
	d.state = "finished"
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	report := dockerTeardownReport{Images: []dockerReportedImage{}, Reset: d.reset}
	cleanErr := d.clean(ctx, &report)
	d.stop()
	unix.Sync()
	if out, err := d.run(ctx, "umount", dockerDataRoot); err != nil {
		cleanErr = errors.Join(cleanErr, fmt.Errorf("unmount: %s", strings.TrimSpace(string(out))))
	} else {
		report.Clean = cleanErr == nil
	}
	data, _ := json.Marshal(report)
	path := filepath.Join(d.root, strings.Split(d.source, "/")[0], dockerReport)
	if err := os.WriteFile(path, data, 0644); err != nil {
		return errors.Join(cleanErr, err)
	}
	return cleanErr
}

func (d *daemon) clean(ctx context.Context, report *dockerTeardownReport) error {
	containerImages := map[string]bool{}
	if out, err := d.run(ctx, "docker", "ps", "-aq", "--no-trunc"); err == nil {
		if ids := strings.Fields(string(out)); len(ids) > 0 {
			if out, err := d.run(ctx, "docker", append([]string{"container", "inspect", "--format", "{{.Image}}"}, ids...)...); err == nil {
				for _, image := range strings.Fields(string(out)) {
					containerImages[image] = true
				}
			}
			if out, err := d.run(ctx, "docker", append([]string{"rm", "-f", "-v"}, ids...)...); err != nil {
				return fmt.Errorf("remove containers: %s", strings.TrimSpace(string(out)))
			}
		}
	} else {
		return fmt.Errorf("list containers: %s", strings.TrimSpace(string(out)))
	}
	if out, err := d.run(ctx, "docker", "volume", "prune", "-af"); err != nil {
		return fmt.Errorf("remove volumes: %s", strings.TrimSpace(string(out)))
	}
	if out, err := d.run(ctx, "docker", "network", "prune", "-f"); err != nil {
		return fmt.Errorf("remove networks: %s", strings.TrimSpace(string(out)))
	}
	images, err := d.images(ctx)
	if err != nil {
		return err
	}
	plan := planDockerTeardown(images, containerImages, d.ledger, time.Now())
	for _, id := range plan.Tag {
		if out, err := d.run(ctx, "docker", "image", "tag", id, dockerInternalReference(id)); err != nil {
			return fmt.Errorf("keep image: %s", strings.TrimSpace(string(out)))
		}
	}
	// Removing an image's last tag also drops its digest references, so one can
	// be gone by its turn. What counts is that none remains, checked below.
	for _, reference := range plan.Untag {
		_, _ = d.run(ctx, "docker", "image", "rm", reference)
	}
	for _, id := range plan.Remove {
		_, _ = d.run(ctx, "docker", "image", "rm", "-f", id)
	}
	_, _ = d.run(ctx, "docker", "image", "prune", "-f")
	_, _ = d.run(ctx, "docker", "builder", "prune", "-f", "--keep-storage", dockerBuildCacheBudget)
	if err := writeDockerLedger(plan.Keep); err != nil {
		return err
	}
	final, err := d.snapshot(ctx)
	if err != nil {
		return err
	}
	if images, err = d.images(ctx); err != nil {
		return err
	}
	if remaining := remainingReferences(images); len(remaining) > 0 {
		return fmt.Errorf("untag images: %s remain", strings.Join(remaining, ", "))
	}
	report.Images = dockerReportImages(images, plan.Keep)
	report.BuildCacheBytes = final.BuildCacheBytes
	report.Changed = final.differs(d.base) || plan.Stale || d.reset
	return nil
}

func (d *daemon) images(ctx context.Context) ([]dockerImage, error) {
	out, err := d.run(ctx, "docker", "image", "ls", "-aq", "--no-trunc")
	if err != nil {
		return nil, fmt.Errorf("list images: %s", strings.TrimSpace(string(out)))
	}
	ids := uniqueFields(string(out))
	if len(ids) == 0 {
		return nil, nil
	}
	out, err = d.run(ctx, "docker", append([]string{"image", "inspect"}, ids...)...)
	if err != nil {
		return nil, fmt.Errorf("inspect images: %s", strings.TrimSpace(string(out)))
	}
	var images []dockerImage
	if err := json.Unmarshal(out, &images); err != nil {
		return nil, err
	}
	return images, nil
}

func (d *daemon) snapshot(ctx context.Context) (dockerSnapshot, error) {
	out, err := d.run(ctx, "docker", "image", "ls", "-aq", "--no-trunc")
	if err != nil {
		return dockerSnapshot{}, fmt.Errorf("list images: %s", strings.TrimSpace(string(out)))
	}
	snapshot := dockerSnapshot{Images: uniqueFields(string(out))}
	if out, err := d.run(ctx, "docker", "system", "df", "--format", "{{.Type}}\t{{.Size}}"); err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			if kind, size, ok := strings.Cut(line, "\t"); ok && kind == "Build Cache" {
				snapshot.BuildCacheBytes, _ = parseHumanSize(size)
			}
		}
	}
	return snapshot, nil
}

func uniqueFields(value string) []string {
	var unique []string
	for _, field := range strings.Fields(value) {
		if !containsString(unique, field) {
			unique = append(unique, field)
		}
	}
	return unique
}

func containsString(values []string, value string) bool {
	for _, v := range values {
		if v == value {
			return true
		}
	}
	return false
}

func readDockerLedger() dockerLedger {
	ledger := dockerLedger{}
	data, err := os.ReadFile(dockerLedgerPath)
	if err == nil {
		_ = json.Unmarshal(data, &ledger)
	}
	return ledger
}

func writeDockerLedger(ledger dockerLedger) error {
	if err := os.MkdirAll(filepath.Dir(dockerLedgerPath), 0700); err != nil {
		return err
	}
	data, err := json.Marshal(ledger)
	if err != nil {
		return err
	}
	return os.WriteFile(dockerLedgerPath, data, 0600)
}
