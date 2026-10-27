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

// dockerLedgerFile is where a data root mounted at root keeps its ledger.
func dockerLedgerFile(root string) string { return filepath.Join(root, "tuist", "ledger.json") }

// sendDocker sends a request without descriptors to the sidecar's supervisor
// and returns its status: ok, or dockerReset for a data root it started empty.
func sendDocker(socket string, message dockerMessage) (string, error) {
	data, _ := json.Marshal(message)
	conn, err := net.DialUnix("unixpacket", nil, &net.UnixAddr{Name: socket, Net: "unixpacket"})
	if err != nil {
		return "", fmt.Errorf("docker cache helper unavailable: %w", err)
	}
	defer conn.Close()
	// A teardown may merge the job's images with a saved head first.
	deadline := 2 * time.Minute
	if message.Docker == "teardown" {
		deadline = 12 * time.Minute
	}
	_ = conn.SetDeadline(time.Now().Add(deadline))
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
	// dataRoot and mergeRoot are where the job's data root and a saved head's
	// clone are mounted.
	dataRoot, mergeRoot string
	cmd                 *exec.Cmd
	done                chan struct{}
	stopping            bool
	// state is ephemeral, volume, or finished once a volume was torn down.
	state  string
	source string
	// reset is set when the saved data root could not be mounted and the
	// job's branch was formatted empty instead.
	reset  bool
	base   dockerSnapshot
	ledger dockerLedger
	run    func(context.Context, string, ...string) ([]byte, error)
	// pipe runs the docker command from with its output as the docker command to's input.
	pipe func(ctx context.Context, from, to []string) error
}

// runDind is `tuist-cache-volume dind SOCKET ROOT EPHEMERAL -- dockerd ARGS...`.
func runDind(args []string) error {
	if len(args) < 5 || args[3] != "--" {
		return errors.New("usage: tuist-cache-volume dind SOCKET ROOT EPHEMERAL -- dockerd [ARGS...]")
	}
	d := &daemon{args: args[4:], root: args[1], ephemeral: args[2], state: "ephemeral", dataRoot: dockerDataRoot, mergeRoot: dockerMergeRoot, pipe: pipeDocker, run: func(ctx context.Context, name string, args ...string) ([]byte, error) {
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

func (d *daemon) ready(ctx context.Context) error { return d.readyAt(ctx, "") }

// readyAt waits for the dockerd listening at host, the job's when empty.
func (d *daemon) readyAt(ctx context.Context, host string) error {
	for {
		if _, err := d.run(ctx, "docker", dockerArgs(host, "info")...); err == nil {
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
		return "ok", d.teardown(message.Merge, message.Generation)
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
	if out, err := d.run(ctx, "umount", d.dataRoot); err != nil {
		return d.fallback(ctx, fmt.Errorf("unmount ephemeral data root: %s", strings.TrimSpace(string(out))), false)
	}
	if _, err := d.run(ctx, "mount", "-o", "loop", image, d.dataRoot); err != nil {
		// The saved data root is one this kernel refuses. The job starts its own
		// branch empty instead, and its teardown replaces the saved one.
		if out, err := d.run(ctx, "mkfs.ext4", append(slices.Clone(dockerFormatArgs), image)...); err != nil {
			return d.fallback(ctx, fmt.Errorf("format docker volume: %s", strings.TrimSpace(string(out))), false)
		}
		if out, err := d.run(ctx, "mount", "-o", "loop", image, d.dataRoot); err != nil {
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
	d.base, _ = d.snapshot(ctx, "")
	d.ledger = readDockerLedger(dockerLedgerFile(d.dataRoot))
	return nil
}

// fallback restores the ephemeral data root and reports cause.
func (d *daemon) fallback(ctx context.Context, cause error, mounted bool) error {
	d.stop()
	if mounted {
		_, _ = d.run(ctx, "umount", d.dataRoot)
	}
	_, _ = d.run(ctx, "mount", "-o", "loop", d.ephemeral, d.dataRoot)
	if err := d.start(); err != nil {
		return errors.Join(cause, err)
	}
	_ = d.ready(ctx)
	return cause
}

// teardown keeps only images and build cache, removes every registry
// reference, merges a changed data root with the saved head the host offered
// at merge, stops dockerd, unmounts the volume cleanly and writes the report
// the host reads. dockerd stays stopped: the pod is ending.
func (d *daemon) teardown(merge string, generation int64) error {
	if d.state != "volume" {
		return errors.New("no docker volume mounted")
	}
	d.state = "finished"
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()
	report := dockerTeardownReport{Images: []dockerReportedImage{}, Reset: d.reset}
	cleanErr := d.clean(ctx, &report)
	if cleanErr == nil && report.Changed && merge != "" && generation > 0 {
		// A failed merge leaves the data root as the job left it, which the host
		// withholds as superseded.
		if into, err := d.merge(ctx, merge, &report); err != nil {
			fmt.Fprintf(os.Stderr, "Tuist Docker cache: merging with the saved data root failed: %v\n", err)
		} else if into != "" {
			report.MergedGeneration, report.MergedInto = generation, into
		}
	}
	d.stop()
	unix.Sync()
	if out, err := d.run(ctx, "umount", d.dataRoot); err != nil {
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

const (
	dockerMergeRoot = "/var/lib/docker-merge"
	dockerMergeHost = "unix:///var/run/docker-merge.sock"
)

// merge makes one data root of the job's and the saved head's clone at source:
// a second dockerd runs on the clone and the images only one side keeps are
// loaded into the other, whichever moves fewer bytes. It returns the side that
// holds the union, "branch" or "head", or "" when the job kept nothing the
// head lacks, and fills the report from it. The job's dockerd still runs.
func (d *daemon) merge(ctx context.Context, source string, report *dockerTeardownReport) (into string, err error) {
	parts := strings.Split(source, "/")
	if len(parts) != 2 || !directoryPattern.MatchString(parts[0]) || parts[1] != dockerMergeImageName {
		return "", errors.New("invalid saved head")
	}
	image := filepath.Join(d.root, source)
	if info, err := os.Lstat(image); err != nil || !info.Mode().IsRegular() {
		return "", errors.New("saved head unavailable")
	}
	if err := os.MkdirAll(d.mergeRoot, 0700); err != nil {
		return "", err
	}
	if out, err := d.run(ctx, "mount", "-o", "loop", image, d.mergeRoot); err != nil {
		return "", fmt.Errorf("mount saved head: %s", strings.TrimSpace(string(out)))
	}
	defer func() {
		// The host publishes the head's clone only after a clean unmount.
		if out, unmountErr := d.run(context.Background(), "umount", d.mergeRoot); unmountErr != nil && into == "head" {
			into, err = "", fmt.Errorf("unmount saved head: %s", strings.TrimSpace(string(out)))
		}
	}()
	stop, err := d.startMergeDaemon(ctx)
	if err != nil {
		return "", err
	}
	defer stop()
	branch, err := d.images(ctx, "")
	if err != nil {
		return "", err
	}
	head, err := d.images(ctx, dockerMergeHost)
	if err != nil {
		return "", err
	}
	plan := planDockerMerge(branch, head)
	if plan.Into == "" {
		return "", nil
	}
	from, to, ledgerPath, otherLedgerPath := "", dockerMergeHost, dockerLedgerFile(d.mergeRoot), dockerLedgerFile(d.dataRoot)
	if plan.Into == "branch" {
		from, to, ledgerPath, otherLedgerPath = dockerMergeHost, "", dockerLedgerFile(d.dataRoot), dockerLedgerFile(d.mergeRoot)
	}
	if len(plan.Move) > 0 {
		references := make([]string, 0, len(plan.Move))
		for _, id := range plan.Move {
			references = append(references, dockerInternalReference(id))
		}
		if err := d.pipe(ctx, dockerArgs(from, append([]string{"save"}, references...)...), dockerArgs(to, "load", "-q")); err != nil {
			return "", fmt.Errorf("copy images: %w", err)
		}
	}
	ledger := mergeDockerLedgers(readDockerLedger(ledgerPath), readDockerLedger(otherLedgerPath), plan.Move)
	if err := writeDockerLedger(ledgerPath, ledger); err != nil {
		return "", err
	}
	images, err := d.images(ctx, to)
	if err != nil {
		return "", err
	}
	if remaining := remainingReferences(images); len(remaining) > 0 {
		return "", fmt.Errorf("merged images keep %s", strings.Join(remaining, ", "))
	}
	snapshot, err := d.snapshot(ctx, to)
	if err != nil {
		return "", err
	}
	report.Images = dockerReportImages(images, ledger)
	report.BuildCacheBytes = snapshot.BuildCacheBytes
	return plan.Into, nil
}

// startMergeDaemon runs a dockerd on the saved head's clone beside the job's,
// with its own socket and state and no networking, and returns how to stop it.
func (d *daemon) startMergeDaemon(ctx context.Context) (func(), error) {
	config := d.mergeRoot + ".json"
	if err := os.WriteFile(config, []byte("{}"), 0600); err != nil {
		return nil, err
	}
	cmd := exec.Command(d.args[0], "--config-file", config, "--data-root", d.mergeRoot, "--host", dockerMergeHost,
		"--exec-root", "/var/run/docker-merge", "--pidfile", "/var/run/docker-merge.pid", "--bridge", "none", "--iptables=false", "--ip6tables=false")
	cmd.Stdout, cmd.Stderr = os.Stderr, os.Stderr
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	done := make(chan struct{})
	go func() {
		_ = cmd.Wait()
		close(done)
	}()
	stop := func() {
		_ = cmd.Process.Signal(syscall.SIGTERM)
		select {
		case <-done:
		case <-time.After(30 * time.Second):
			_ = cmd.Process.Kill()
			<-done
		}
	}
	readyCtx, cancel := context.WithTimeout(ctx, time.Minute)
	defer cancel()
	if err := d.readyAt(readyCtx, dockerMergeHost); err != nil {
		stop()
		return nil, err
	}
	return stop, nil
}

// dockerArgs addresses a docker command to the dockerd at host, the job's
// when empty.
func dockerArgs(host string, args ...string) []string {
	if host == "" {
		return args
	}
	return append([]string{"--host", host}, args...)
}

// pipeDocker streams `docker from...` into `docker to...`.
func pipeDocker(ctx context.Context, from, to []string) error {
	source := exec.CommandContext(ctx, "docker", from...)
	sink := exec.CommandContext(ctx, "docker", to...)
	output, err := source.StdoutPipe()
	if err != nil {
		return err
	}
	sink.Stdin = output
	var sourceErr, sinkErr strings.Builder
	source.Stderr, sink.Stderr = &sourceErr, &sinkErr
	if err := sink.Start(); err != nil {
		return err
	}
	if err := source.Run(); err != nil {
		_ = sink.Wait()
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(sourceErr.String()))
	}
	if err := sink.Wait(); err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(sinkErr.String()))
	}
	return nil
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
	images, err := d.images(ctx, "")
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
	if err := writeDockerLedger(dockerLedgerFile(d.dataRoot), plan.Keep); err != nil {
		return err
	}
	final, err := d.snapshot(ctx, "")
	if err != nil {
		return err
	}
	if images, err = d.images(ctx, ""); err != nil {
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

func (d *daemon) images(ctx context.Context, host string) ([]dockerImage, error) {
	out, err := d.run(ctx, "docker", dockerArgs(host, "image", "ls", "-aq", "--no-trunc")...)
	if err != nil {
		return nil, fmt.Errorf("list images: %s", strings.TrimSpace(string(out)))
	}
	ids := uniqueFields(string(out))
	if len(ids) == 0 {
		return nil, nil
	}
	out, err = d.run(ctx, "docker", dockerArgs(host, append([]string{"image", "inspect"}, ids...)...)...)
	if err != nil {
		return nil, fmt.Errorf("inspect images: %s", strings.TrimSpace(string(out)))
	}
	var images []dockerImage
	if err := json.Unmarshal(out, &images); err != nil {
		return nil, err
	}
	return images, nil
}

func (d *daemon) snapshot(ctx context.Context, host string) (dockerSnapshot, error) {
	out, err := d.run(ctx, "docker", dockerArgs(host, "image", "ls", "-aq", "--no-trunc")...)
	if err != nil {
		return dockerSnapshot{}, fmt.Errorf("list images: %s", strings.TrimSpace(string(out)))
	}
	snapshot := dockerSnapshot{Images: uniqueFields(string(out))}
	if out, err := d.run(ctx, "docker", dockerArgs(host, "system", "df", "--format", "{{.Type}}\t{{.Size}}")...); err == nil {
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

func readDockerLedger(path string) dockerLedger {
	ledger := dockerLedger{}
	data, err := os.ReadFile(path)
	if err == nil {
		_ = json.Unmarshal(data, &ledger)
	}
	return ledger
}

func writeDockerLedger(path string, ledger dockerLedger) error {
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	data, err := json.Marshal(ledger)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}
