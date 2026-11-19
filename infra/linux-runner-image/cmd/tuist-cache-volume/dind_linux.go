//go:build linux

package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

const dockerDataRoot = "/var/lib/docker"

// dindMemoryFile is where the sidecar publishes its cgroup's memory for the
// runner's vitals.sh. /var/run is the dind-sock volume both containers mount;
// the runner cannot read the sidecar's cgroup, where job containers live.
const dindMemoryFile = "/var/run/tuist-dind-memory"

// publishDindMemory rewrites dindMemoryFile every three seconds, vitals.sh's
// default interval, for the life of the sidecar, with the process the guest
// kernel last killed for memory once there is one. It also keeps the job's
// containers first in line for the OOM killer. Best-effort: a sample it cannot
// read or write is skipped, never an error.
func publishDindMemory() {
	containers := &jobContainers{known: map[string]string{}, inspect: inspectDockerContainer}
	var mu sync.Mutex
	victim := ""
	go func() {
		watch := &oomWatch{}
		for {
			// The count before the sweep, so a kill it counts happened
			// before the sweep looked for the victim's process.
			kills := guestOOMKills("/proc/vmstat")
			_, processes := raiseJobContainerOOMScores("/proc")
			containers.observe(processes)
			// Only this privileged sidecar can read the kernel log, so it
			// names the victim for the runner's job-completed hook and the
			// metrics sampler.
			if named := watch.sweep(kills, processes, kernelLog, containers.describe); named != "" {
				mu.Lock()
				victim = named
				mu.Unlock()
			}
			time.Sleep(time.Second)
		}
	}()
	for {
		if line := dindMemory("/sys/fs/cgroup"); line != "" {
			mu.Lock()
			if victim != "" {
				line += " " + victim
			}
			mu.Unlock()
			if os.WriteFile(dindMemoryFile+".tmp", []byte(line+"\n"), 0o644) == nil {
				_ = os.Rename(dindMemoryFile+".tmp", dindMemoryFile)
			}
		}
		time.Sleep(3 * time.Second)
	}
}

// jobContainerOOMScoreAdj puts the job's containers first in line when the
// guest runs out of memory. Docker starts them at 0 while the Pod's own
// processes run at the kubelet's ~870, so the kernel used to kill the runner
// ("lost communication") and dockerd before the build's JVMs. At the maximum,
// the container process using the most memory goes first, the step fails with
// exit code 137 and the runner survives to report it.
const jobContainerOOMScoreAdj = "1000"

// jobProcess is a process of the job's containers as the last sweep saw it.
type jobProcess struct {
	pid    string
	name   string
	anonKB int64
	// container is the container's ID, or docker-build for a BuildKit step.
	container string
}

// raiseJobContainerOOMScores sets every process in dockerd's cgroup tree, the
// job's containers and BuildKit's build steps, to jobContainerOOMScoreAdj and
// returns how many it changed and the processes it found. Children inherit the
// score; the sweep catches each new container and `docker exec` within a second.
func raiseJobContainerOOMScores(proc string) (int, []jobProcess) {
	entries, err := os.ReadDir(proc)
	if err != nil {
		return 0, nil
	}
	raised := 0
	var processes []jobProcess
	for _, entry := range entries {
		if _, err := strconv.Atoi(entry.Name()); err != nil {
			continue
		}
		cgroup, err := os.ReadFile(filepath.Join(proc, entry.Name(), "cgroup"))
		if err != nil || !strings.HasPrefix(string(cgroup), "0::/docker/") {
			continue
		}
		if process, ok := sweptProcess(filepath.Join(proc, entry.Name()), strings.TrimSpace(string(cgroup))); ok {
			processes = append(processes, process)
		}
		path := filepath.Join(proc, entry.Name(), "oom_score_adj")
		if current, err := os.ReadFile(path); err != nil || strings.TrimSpace(string(current)) == jobContainerOOMScoreAdj {
			continue
		}
		if os.WriteFile(path, []byte(jobContainerOOMScoreAdj), 0o644) == nil {
			raised++
		}
	}
	return raised, processes
}

// sweptProcess reads a job container process's name and anonymous memory.
func sweptProcess(dir, cgroup string) (jobProcess, bool) {
	container := ""
	if strings.HasPrefix(cgroup, "0::/docker/buildkit/") {
		container = "docker-build"
	} else if match := dockerContainerCgroup.FindStringSubmatch(cgroup); match != nil {
		container = match[1]
	} else {
		return jobProcess{}, false
	}
	status, err := os.ReadFile(filepath.Join(dir, "status"))
	if err != nil {
		return jobProcess{}, false
	}
	process := jobProcess{pid: filepath.Base(dir), container: container}
	for _, line := range strings.Split(string(status), "\n") {
		if value, ok := strings.CutPrefix(line, "State:"); ok && strings.HasPrefix(strings.TrimSpace(value), "Z") {
			return jobProcess{}, false // exited: a killed victim waiting to be reaped
		} else if value, ok := strings.CutPrefix(line, "Name:"); ok {
			process.name = strings.TrimSpace(value)
		} else if value, ok := strings.CutPrefix(line, "RssAnon:"); ok {
			process.anonKB, _ = strconv.ParseInt(strings.TrimSuffix(strings.TrimSpace(value), " kB"), 10, 64)
		}
	}
	return process, process.name != ""
}

// guestOOMKills is the guest kernel's count of processes killed for memory,
// the oom_kill line of /proc/vmstat, or 0 when it cannot be read.
func guestOOMKills(vmstat string) int64 {
	data, _ := os.ReadFile(vmstat)
	for _, line := range strings.Split(string(data), "\n") {
		if value, ok := strings.CutPrefix(line, "oom_kill "); ok {
			n, _ := strconv.ParseInt(strings.TrimSpace(value), 10, 64)
			return n
		}
	}
	return 0
}

// kernelLog reads the guest kernel's ring buffer.
func kernelLog() string {
	size, err := unix.Klogctl(unix.SYSLOG_ACTION_SIZE_BUFFER, nil)
	if err != nil || size <= 0 {
		return ""
	}
	buffer := make([]byte, size)
	n, err := unix.Klogctl(unix.SYSLOG_ACTION_READ_ALL, buffer)
	if err != nil {
		return ""
	}
	return string(buffer[:n])
}

var (
	oomKilledProcess      = regexp.MustCompile(`Killed process \d+ \((.*)\) total-vm:\d+kB, anon-rss:(\d+)kB`)
	dockerContainerCgroup = regexp.MustCompile(`^0::/docker/([0-9a-f]{64})$`)
	unsafeName            = regexp.MustCompile(`[^A-Za-z0-9._-]`)
	unsafeContainer       = regexp.MustCompile(`[^A-Za-z0-9._/:@-]`)
)

// oomKill is the process the kernel log last reports killed for memory.
type oomKill struct {
	name   string
	anonKB int64
}

// latestOOMKill finds the last process the kernel log reports killed for
// memory, or false when it reports none.
func latestOOMKill(log string) (oomKill, bool) {
	matches := oomKilledProcess.FindAllStringSubmatch(log, -1)
	if len(matches) == 0 {
		return oomKill{}, false
	}
	last := matches[len(matches)-1]
	anonKB, _ := strconv.ParseInt(last[2], 10, 64)
	return oomKill{name: last[1], anonKB: anonKB}, true
}

// fields renders the kill as vitals fields. The job names its own processes
// and containers, so every value keeps only characters safe in a vitals line,
// a GitHub annotation and the sampler's JSON. describe names a container by ID.
//
// The kernel cannot name the victim's container: Docker's cgroups here have no
// memory controller of their own, so its log gives the dind sidecar's cgroup,
// and a PID from a namespace this sidecar cannot see. The victim is instead
// the process with its name that a sweep before the kill saw and a sweep after
// it no longer does; of several, the largest, as the kernel kills the largest.
// Memory alone cannot pick it: a runaway process grows by gigabytes in the
// second between sweeps. The second result is false when no such process
// vanished, and oom.victim.container is then absent.
func (k oomKill) fields(before, after []jobProcess, describe func(id string) string) (string, bool) {
	name := unsafeName.ReplaceAllString(k.name, "_")
	if name == "" {
		name = "unknown"
	}
	line := "oom.victim=" + name + " oom.victim.anon.kb=" + strconv.FormatInt(k.anonKB, 10)
	alive := map[string]bool{}
	for _, process := range after {
		alive[process.pid+" "+process.name] = true
	}
	var match *jobProcess
	for i := range before {
		process := &before[i]
		if process.name == k.name && !alive[process.pid+" "+process.name] && (match == nil || process.anonKB > match.anonKB) {
			match = process
		}
	}
	switch {
	case match == nil:
		return line, false
	case match.container == "docker-build":
		return line + " oom.victim.container=docker-build", true
	default:
		return line + " " + describe(match.container), true
	}
}

// oomWatch names each process the kernel kills for memory, from one sweep to
// the next.
type oomWatch struct {
	kills    int64
	previous []jobProcess
	// beforeKill is the last sweep before an unnamed kill, and attempts how
	// many more sweeps may still find its victim gone.
	beforeKill []jobProcess
	attempts   int
}

// oomWatchAttempts covers a victim that still shows for a sweep or two while
// it exits. Past them, the victim ran outside the job's containers, or started
// and died between two sweeps.
const oomWatchAttempts = 3

// sweep takes the kill count read before a sweep and the processes it found,
// and returns the victim's fields once it can name them, or "".
func (w *oomWatch) sweep(kills int64, processes []jobProcess, kernelLog func() string, describe func(string) string) string {
	defer func() { w.previous = processes }()
	if kills > w.kills {
		w.kills = kills
		w.beforeKill = w.previous
		w.attempts = oomWatchAttempts
	}
	if w.attempts == 0 {
		return ""
	}
	w.attempts--
	kill, ok := latestOOMKill(kernelLog())
	if !ok {
		return ""
	}
	line, named := kill.fields(w.beforeKill, processes, describe)
	if !named && w.attempts > 0 {
		return ""
	}
	w.attempts = 0
	return line
}

// jobContainers remembers the name and image of each container the sweep saw,
// so a kill can still be named after Docker removed the container it ended
// (`docker run --rm`, a job's service containers at cleanup).
type jobContainers struct {
	mu      sync.Mutex
	known   map[string]string // ID -> container and image fields
	inspect func(id string) (name, image string, err error)
}

// observe looks up each container not seen before that runs one of processes.
func (c *jobContainers) observe(processes []jobProcess) {
	for _, process := range processes {
		id := process.container
		if id == "docker-build" {
			continue
		}
		c.mu.Lock()
		_, seen := c.known[id]
		c.mu.Unlock()
		if seen {
			continue
		}
		name, image, err := c.inspect(id)
		if err != nil {
			continue // retried on the next sweep while it runs
		}
		fields := "oom.victim.container=" + containerField(strings.TrimPrefix(name, "/"))
		if image != "" {
			fields += " oom.victim.image=" + containerField(image)
		}
		c.mu.Lock()
		c.known[id] = fields
		c.mu.Unlock()
	}
}

// describe renders a container's fields, its short ID when it was never seen.
func (c *jobContainers) describe(id string) string {
	c.mu.Lock()
	fields, ok := c.known[id]
	c.mu.Unlock()
	if ok {
		return fields
	}
	return "oom.victim.container=" + id[:12]
}

func containerField(value string) string {
	value = unsafeContainer.ReplaceAllString(value, "_")
	if len(value) > 128 {
		value = value[:128]
	}
	if value == "" {
		return "unknown"
	}
	return value
}

// inspectDockerContainer asks the job's dockerd for a container's name and
// image through the docker CLI, as the rest of the supervisor does: an HTTP
// client here would be one more transport for the certificate-trust review.
func inspectDockerContainer(id string) (string, string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "docker", dockerArgs("", "container", "inspect", "--format", "{{.Name}}\t{{.Config.Image}}", id)...).Output()
	if err != nil {
		return "", "", fmt.Errorf("inspecting container %s: %w", id, err)
	}
	name, image, _ := strings.Cut(strings.TrimSpace(string(out)), "\t")
	return name, image, nil
}

// dindMemory renders the cgroup v2 memory of the cgroup at path as vitals.sh
// fields, in bytes like the runner's own mem.* fields.
func dindMemory(path string) string {
	read := func(name string) string {
		data, _ := os.ReadFile(filepath.Join(path, name))
		return strings.TrimSpace(string(data))
	}
	keyed := func(name string) map[string]string {
		values := map[string]string{}
		for _, line := range strings.Split(read(name), "\n") {
			if key, value, ok := strings.Cut(line, " "); ok {
				values[key] = value
			}
		}
		return values
	}
	current := read("memory.current")
	if current == "" {
		return ""
	}
	fields := []string{"dind.mem.current=" + current, "dind.mem.peak=" + read("memory.peak")}
	stat := keyed("memory.stat")
	for _, key := range []string{"anon", "file", "shmem", "file_dirty", "file_writeback", "kernel"} {
		fields = append(fields, "dind.mem."+key+"="+stat[key])
	}
	return strings.Join(append(fields, "dind.oom_kill="+keyed("memory.events")["oom_kill"]), " ")
}

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
	reset     bool
	base      dockerSnapshot
	ledger    dockerLedger
	run       func(context.Context, string, ...string) ([]byte, error)
	usedBytes func(string) (int64, error)
	trim      func(string) error // test seam; production uses syncfs + FITRIM
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
	go publishDindMemory()
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
	var snapshotErr error
	d.base, snapshotErr = d.snapshot(ctx, "")
	if snapshotErr != nil {
		return d.fallback(ctx, snapshotErr, true)
	}
	d.ledger = readDockerLedger(dockerLedgerFile(d.dataRoot))
	return nil
}

// fallback restores the ephemeral data root and reports cause.
func (d *daemon) fallback(ctx context.Context, cause error, mounted bool) error {
	d.stop()
	d.state, d.source = "ephemeral", ""
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
	cleanErr = errors.Join(cleanErr, d.trimDocker(ctx, d.dataRoot))
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
		if into == "head" {
			if trimErr := d.trimDocker(ctx, d.mergeRoot); trimErr != nil {
				into, err = "", trimErr
			}
		}
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
	plan := planDockerMerge(d.base.Images, branch, head)
	branchState, err := d.snapshot(ctx, "")
	if err != nil {
		return "", err
	}
	headState, err := d.snapshot(ctx, dockerMergeHost)
	if err != nil {
		return "", err
	}
	if branchState.BuildCache != d.base.BuildCache {
		// The daemon's BuildKit database is indivisible. Keep this job's new
		// build work and import the images the newer head added.
		plan.Into, plan.Move = "branch", nil
		for _, image := range head {
			if !containsString(branchState.Images, image.ID) && !containsString(d.base.Images, image.ID) {
				plan.Move = append(plan.Move, image.ID)
			}
		}
	} else if branchState.buildDiffers(d.base) && plan.Into == "" {
		plan.Into = "head"
	}
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
	if err := d.mergeBuildkitVolumes(ctx, plan.Into, branchState, headState); err != nil {
		return "", err
	}
	ledger := mergeDockerLedgers(readDockerLedger(ledgerPath), readDockerLedger(otherLedgerPath), plan.Move)
	if err := writeDockerLedger(ledgerPath, ledger); err != nil {
		return "", err
	}
	root := d.mergeRoot
	if plan.Into == "branch" {
		root = d.dataRoot
	}
	if err := d.retainDocker(ctx, to, root, ledger, dockerRetainedBytes); err != nil {
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
	if _, err := d.buildkitVolumes(ctx, "", d.dataRoot); err != nil {
		return err
	}
	if err := d.recordBuilderUse(ctx); err != nil {
		return err
	}
	if out, err := d.run(ctx, "docker", "volume", "prune", "-af", "--filter", "label!="+buildkitVolumeLabel); err != nil {
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
	if out, err := d.run(ctx, "docker", "builder", "prune", "-af", "--keep-storage", dockerBuildCacheBudget); err != nil {
		return fmt.Errorf("prune Docker build cache: %s: %w", strings.TrimSpace(string(out)), err)
	}
	if err := writeDockerLedger(dockerLedgerFile(d.dataRoot), plan.Keep); err != nil {
		return err
	}
	if err := d.retainDocker(ctx, "", d.dataRoot, plan.Keep, dockerRetainedBytes); err != nil {
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
	out, err = d.run(ctx, "docker", dockerArgs(host, "system", "df", "-v", "--format", "{{json .BuildCache}}")...)
	if err != nil {
		return dockerSnapshot{}, fmt.Errorf("inspect build cache: %w", err)
	}
	var records []buildCacheRecord
	if len(bytes.TrimSpace(out)) > 0 {
		if err := json.Unmarshal(out, &records); err != nil {
			return dockerSnapshot{}, fmt.Errorf("decode build cache: %w", err)
		}
	}
	snapshot.BuildCache = buildCacheFingerprint(records)
	root := d.dataRoot
	if host == dockerMergeHost {
		root = d.mergeRoot
	}
	snapshot.BuildVolumes, err = d.buildkitSnapshot(ctx, host, root)
	if err != nil {
		return dockerSnapshot{}, err
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
