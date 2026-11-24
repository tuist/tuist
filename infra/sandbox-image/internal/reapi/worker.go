package reapi

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	rpc "google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type Worker struct {
	CAS   *CAS
	Root  string
	Image string
	// MemoryGB is the guest memory of the VM; zero means DefaultMemoryGB.
	MemoryGB int
	// OOMKills reads the kernel's OOM kill counter; nil reads /proc/vmstat.
	OOMKills func() (int64, bool)
	// Production always drops to the unprivileged build user. Tests run as
	// their invoking user, against a temporary directory and an in-memory CAS.
	Credential *syscall.Credential
	// Start launches the action's command; nil uses exec.Cmd.Start.
	Start func(*exec.Cmd) error
	// Meter measures the command's usage, reported in the result's
	// auxiliary metadata (UsageKind); nil measures nothing.
	Meter   Meter
	entries int
	// Streamed inputs by digest: the first path downloads a blob, later paths
	// with the same digest copy that file instead of reading it again.
	streamedMu sync.Mutex
	streamed   map[string]*streamedInput
}

type streamedInput struct {
	done chan struct{}
	path string
	err  error
}

// Execute reports whether the result may be published to the action cache.
// Publication is the caller's job, after the client already has the result.
// It never looks the action up: clients check the action cache before Execute.
func (w *Worker) Execute(ctx context.Context, digest *re.Digest) (*re.ExecuteResponse, bool) {
	result, cacheable, err := w.execute(ctx, digest)
	response := &re.ExecuteResponse{Result: result, Status: &rpc.Status{}}
	if err != nil {
		code := status.Code(err)
		if errors.Is(err, context.DeadlineExceeded) {
			code = codes.DeadlineExceeded
		}
		if errors.Is(err, context.Canceled) {
			code = codes.Canceled
		}
		if code == codes.Unknown {
			code = codes.Internal
		}
		// Paths and command output belong in CAS, not in control-plane errors.
		response.Status = status.Convert(err).Proto()
		response.Status.Code = int32(code)
		response.Status.Message = code.String()
	}
	if proto.Size(response) > MaxResponse {
		return &re.ExecuteResponse{Status: &rpc.Status{Code: int32(codes.ResourceExhausted), Message: "action result too large"}}, false
	}
	return response, err == nil && cacheable
}

func (w *Worker) execute(ctx context.Context, digest *re.Digest) (*re.ActionResult, bool, error) {
	metadata := &re.ExecutedActionMetadata{Worker: "firecracker-linux-amd64", WorkerStartTimestamp: timestamppb.Now()}
	metadata.InputFetchStartTimestamp = timestamppb.Now()
	var action re.Action
	if err := w.CAS.Message(ctx, digest, &action); err != nil {
		return nil, false, err
	}
	var command re.Command
	var input re.Directory
	if err := w.CAS.Messages(ctx, []*re.Digest{action.CommandDigest, action.InputRootDigest}, []proto.Message{&command, &input}); err != nil {
		return nil, false, err
	}
	if err := w.validate(&action, &command); err != nil {
		return nil, false, err
	}
	if err := os.Mkdir(w.Root, 0755); err != nil && !(os.IsExist(err) && emptyDirectory(w.Root)) {
		return nil, false, err
	}
	root, err := os.OpenRoot(w.Root)
	if err != nil {
		return nil, false, err
	}
	defer root.Close()
	if err = w.own(root, "."); err != nil {
		return nil, false, err
	}
	w.streamed = nil
	if err = w.materialize(ctx, root, &input); err != nil {
		return nil, false, err
	}
	// Never start the command with the host's blob channel open.
	if err = w.CAS.SealHost(ctx); err != nil {
		return nil, false, status.Error(codes.Unavailable, "sealing host blob access")
	}
	metadata.InputFetchCompletedTimestamp = timestamppb.Now()
	outputs := command.OutputPaths
	if len(outputs) == 0 {
		outputs = append(append([]string{}, command.OutputFiles...), command.OutputDirectories...)
	}
	for _, p := range outputs {
		if !relative(p, false) {
			return nil, false, status.Error(codes.InvalidArgument, "invalid output path")
		}
		if err = w.mkdir(root, path.Dir(path.Join(command.WorkingDirectory, p))); err != nil {
			return nil, false, err
		}
	}
	if !relative(command.WorkingDirectory, true) {
		return nil, false, status.Error(codes.InvalidArgument, "invalid working directory")
	}
	working := command.WorkingDirectory
	if working == "" {
		working = "."
	}
	info, err := root.Stat(working)
	if err != nil || !info.IsDir() {
		return nil, false, status.Error(codes.InvalidArgument, "missing working directory")
	}
	// Logs are outside the unprivileged build user's writable workspace.
	stdout, err := os.CreateTemp("", "rbe-stdout-")
	if err != nil {
		return nil, false, err
	}
	defer os.Remove(stdout.Name())
	defer stdout.Close()
	stderr, err := os.CreateTemp("", "rbe-stderr-")
	if err != nil {
		return nil, false, err
	}
	defer os.Remove(stderr.Name())
	defer stderr.Close()
	// Bazel gives every test its size's timeout, up to an hour for
	// "eternal" tests that finish in seconds, so a longer request runs
	// with the VM's ceiling instead of failing before it starts.
	limit := MaxTimeout
	if action.Timeout != nil && action.Timeout.AsDuration() < limit {
		limit = action.Timeout.AsDuration()
	}
	runCtx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()
	// The guest's /tmp is a tmpfs in VM memory, half its size. Temporary files
	// go next to the input root instead, on the workspace disk, unless the
	// action chooses its own directory.
	tmp, err := os.MkdirTemp(filepath.Dir(w.Root), filepath.Base(w.Root)+".tmp-")
	if err != nil {
		return nil, false, err
	}
	defer os.RemoveAll(tmp)
	if w.Credential != nil {
		if err = os.Chown(tmp, int(w.Credential.Uid), int(w.Credential.Gid)); err != nil {
			return nil, false, err
		}
	}
	env := make([]string, 0, len(command.EnvironmentVariables)+1)
	ownTmp := false
	for _, v := range command.EnvironmentVariables {
		env = append(env, v.Name+"="+v.Value)
		ownTmp = ownTmp || v.Name == "TMPDIR"
	}
	if !ownTmp {
		env = append(env, "TMPDIR="+tmp)
	}
	program, err := commandPath(command.Arguments[0], env, filepath.Join(w.Root, working))
	if err != nil {
		return nil, false, err
	}
	errLog := &limitedLog{file: stderr}
	cmd := &exec.Cmd{Path: program, Args: command.Arguments, Dir: filepath.Join(w.Root, working), Env: env,
		Stdout: &limitedLog{file: stdout}, Stderr: errLog,
		SysProcAttr: &syscall.SysProcAttr{Setpgid: true, Credential: w.Credential}, WaitDelay: time.Second}
	oomBefore, oomKnown := w.oomKills()
	// A guest that cannot meter the command still runs it, unmeasured.
	meter := w.Meter
	if meter != nil && meter.Prepare(cmd) != nil {
		meter = nil
	}
	started := time.Now()
	if err = w.start(cmd); err != nil {
		return nil, false, err
	}
	if meter != nil {
		meter.Start()
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	timedOut := false
	select {
	case err = <-done:
	case <-runCtx.Done():
		timedOut = true
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		err = <-done
	}
	// Descendants may have closed stdout already; kill the whole group before
	// collecting outputs. The controller destroys the VM before releasing it.
	_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
	if err != nil {
		var exit *exec.ExitError
		if !errors.As(err, &exit) {
			return nil, false, err
		}
	}
	exitCode := cmd.ProcessState.ExitCode()
	if exitCode < 0 {
		exitCode = 128
	}
	metadata.ExecutionStartTimestamp = timestamppb.New(started)
	metadata.ExecutionCompletedTimestamp = timestamppb.Now()
	if meter != nil {
		if usage, ok := meter.Stop(); ok {
			if a, err := usageMetadata(usage); err == nil {
				metadata.AuxiliaryMetadata = append(metadata.AuxiliaryMetadata, a)
			}
		}
	}
	metadata.OutputUploadStartTimestamp = timestamppb.Now()
	result := &re.ActionResult{ExitCode: int32(exitCode), ExecutionMetadata: metadata}
	if timedOut {
		result.ExitCode = 124
	} else if result.ExitCode != 0 {
		oomAfter, ok := w.oomKills()
		killed := int64(0)
		if oomKnown && ok {
			killed = oomAfter - oomBefore
		}
		// Neither the OOM killer nor a signal leaves a message of its own, and
		// wrappers such as rules_rust's process_wrapper exit 1 without one.
		_, _ = errLog.Write([]byte(w.failureNote(cmd.ProcessState, killed)))
	}
	uploads := newOutputUploads(w.CAS)
	if result.StdoutDigest, err = uploads.log(stdout); err != nil {
		return nil, false, err
	}
	if result.StderrDigest, err = uploads.log(stderr); err != nil {
		return nil, false, err
	}
	for _, p := range outputs {
		if err = w.collect(root, path.Join(working, p), p, result, uploads); err != nil {
			return nil, false, err
		}
		if proto.Size(result) > MaxResponse {
			return nil, false, status.Error(codes.ResourceExhausted, "action result too large")
		}
	}
	if err = uploads.send(ctx); err != nil {
		return nil, false, err
	}
	if timedOut {
		metadata.OutputUploadCompletedTimestamp = timestamppb.Now()
		metadata.WorkerCompletedTimestamp = timestamppb.Now()
		return result, false, context.DeadlineExceeded
	}
	// These timestamps describe the worker, excluding controller VM creation
	// and cleanup. Cached results deliberately retain the original execution.
	metadata.OutputUploadCompletedTimestamp = timestamppb.Now()
	metadata.WorkerCompletedTimestamp = timestamppb.Now()
	return result, result.ExitCode == 0 && !action.DoNotCache, nil
}

func (w *Worker) start(cmd *exec.Cmd) error {
	if w.Start != nil {
		return w.Start(cmd)
	}
	return cmd.Start()
}

func (w *Worker) validate(a *re.Action, c *re.Command) error {
	if len(c.Arguments) == 0 || c.Arguments[0] == "" || len(c.Arguments) > 4096 {
		return status.Error(codes.InvalidArgument, "invalid argv")
	}
	if a.Timeout != nil && (a.Timeout.CheckValid() != nil || a.Timeout.AsDuration() <= 0) {
		return status.Error(codes.InvalidArgument, "invalid timeout")
	}
	platform := a.Platform
	if platform == nil {
		platform = c.Platform
	}
	properties := map[string]string{}
	for _, p := range platform.GetProperties() {
		if _, ok := properties[p.Name]; ok {
			return status.Error(codes.InvalidArgument, "duplicate platform property")
		}
		properties[p.Name] = p.Value
	}
	memory, err := MemoryGB(platform)
	if err != nil {
		return err
	}
	required := 3
	if _, ok := properties[MemoryProperty]; ok {
		required++
	}
	if len(properties) != required || properties["OSFamily"] != "Linux" || properties["Arch"] != "amd64" || properties["tuist-image"] != w.Image || w.Image == "" {
		return status.Error(codes.FailedPrecondition, "unsupported execution platform")
	}
	if memory > w.memoryGB() {
		return status.Error(codes.FailedPrecondition, "the action needs a larger VM")
	}
	seen := map[string]bool{}
	for _, v := range c.EnvironmentVariables {
		if v.Name == "" || strings.ContainsAny(v.Name, "=\x00") || strings.ContainsRune(v.Value, 0) || seen[v.Name] {
			return status.Error(codes.InvalidArgument, "invalid environment")
		}
		seen[v.Name] = true
	}
	if len(c.OutputPaths) > 0 && (len(c.OutputFiles) > 0 || len(c.OutputDirectories) > 0) {
		return status.Error(codes.InvalidArgument, "mixed output declarations")
	}
	return nil
}

// MemoryProperty sizes the VM an action runs in: the guest memory in GB, with
// one vCPU per 2 GB. Actions without it run with DefaultMemoryGB.
const MemoryProperty = "tuist-memory-gb"

const DefaultMemoryGB = 4

// MaxTimeout is the longest an action's command runs, within the server's
// 13-minute execution lease.
const MaxTimeout = 10 * time.Minute

// MemorySizesGB are the VM sizes workers offer, smallest first.
var MemorySizesGB = []int{2, 4, 8, 16}

// MemoryGB returns the VM memory a platform asks for.
func MemoryGB(p *re.Platform) (int, error) {
	value, found := "", false
	for _, property := range p.GetProperties() {
		if property.Name != MemoryProperty {
			continue
		}
		if found {
			return 0, status.Error(codes.InvalidArgument, "duplicate platform property")
		}
		value, found = property.Value, true
	}
	if !found {
		return DefaultMemoryGB, nil
	}
	gb, err := strconv.Atoi(value)
	if err != nil || strconv.Itoa(gb) != value || !slices.Contains(MemorySizesGB, gb) {
		return 0, status.Error(codes.InvalidArgument, MemoryProperty+" must be 2, 4, 8 or 16")
	}
	return gb, nil
}

func (w *Worker) memoryGB() int {
	if w.MemoryGB == 0 {
		return DefaultMemoryGB
	}
	return w.MemoryGB
}

func (w *Worker) oomKills() (int64, bool) {
	if w.OOMKills != nil {
		return w.OOMKills()
	}
	b, err := os.ReadFile("/proc/vmstat")
	if err != nil {
		return 0, false
	}
	for _, line := range strings.Split(string(b), "\n") {
		if v, ok := strings.CutPrefix(line, "oom_kill "); ok {
			n, err := strconv.ParseInt(v, 10, 64)
			return n, err == nil
		}
	}
	return 0, false
}

// failureNote explains a failed command that the OOM killer or a signal
// ended, for the client to print with the action's stderr.
func (w *Worker) failureNote(state *os.ProcessState, oomKilled int64) string {
	memory := w.memoryGB()
	if oomKilled > 0 {
		note := fmt.Sprintf("\ntuist: this action ran out of memory: the kernel's OOM killer ended %d of its processes in a remote execution VM with %d GB.", oomKilled, memory)
		if i := slices.Index(MemorySizesGB, memory); i >= 0 && i+1 < len(MemorySizesGB) {
			larger := MemorySizesGB[i+1]
			note += fmt.Sprintf(" Run it in a larger VM by adding exec_properties = {%q: %q} to its target.", MemoryProperty, strconv.Itoa(larger))
		} else {
			note += " That is the largest VM size."
		}
		return note + "\n"
	}
	if ws, ok := state.Sys().(syscall.WaitStatus); ok && ws.Signaled() {
		return fmt.Sprintf("\ntuist: the action's command was killed by signal %d (%s).\n", int(ws.Signal()), ws.Signal())
	}
	return ""
}

func relative(p string, empty bool) bool {
	return (empty && p == "") || (p != "" && p != "." && !strings.ContainsAny(p, "\\\x00") && !path.IsAbs(p) && path.Clean(p) == p && p != ".." && !strings.HasPrefix(p, "../"))
}
func name(p string) bool { return relative(p, false) && !strings.Contains(p, "/") }
func safeLink(p, target string) bool {
	return target != "" && !path.IsAbs(target) && !strings.ContainsAny(target, "\\\x00") && relative(path.Clean(path.Join(path.Dir(p), target)), true)
}
func (w *Worker) count() error {
	w.entries++
	if w.entries > MaxEntries {
		return status.Error(codes.ResourceExhausted, "too many filesystem entries")
	}
	return nil
}
func (w *Worker) own(root *os.Root, p string) error {
	if w.Credential == nil {
		return nil
	}
	return root.Chown(p, int(w.Credential.Uid), int(w.Credential.Gid))
}
func (w *Worker) mkdir(root *os.Root, p string) error {
	if p == "." || p == "" {
		return nil
	}
	if !relative(p, false) {
		return status.Error(codes.InvalidArgument, "invalid directory")
	}
	current := ""
	for _, part := range strings.Split(p, "/") {
		current = path.Join(current, part)
		if err := root.Mkdir(current, 0755); err != nil && !os.IsExist(err) {
			return err
		}
		if err := w.own(root, current); err != nil {
			return err
		}
	}
	return nil
}

// inputFile is one file of the input tree at its path below the input root.
type inputFile struct {
	path string
	node *re.FileNode
}

type inputDirectory struct {
	path string
	dir  *re.Directory
}

// materialize lays out the input tree in two passes. The walk reads the tree a
// level at a time, the level's distinct directories in parallel batches, so a
// tree costs one round trip per level rather than one per directory. Then the
// files of every directory download together (see materializeFiles). Symlinks
// come last, once nothing is written below the root any more.
func (w *Worker) materialize(ctx context.Context, root *os.Root, input *re.Directory) error {
	var files []inputFile
	var links [][2]string
	level := []inputDirectory{{path: ".", dir: input}}
	for depth := 0; len(level) > 0; depth++ {
		if depth > 128 {
			return status.Error(codes.ResourceExhausted, "input tree too deep")
		}
		var children []inputDirectory
		var digests []*re.Digest
		unique := map[string]int{}
		var childDigest []int
		for _, n := range level {
			if err := w.count(); err != nil {
				return err
			}
			seen := map[string]bool{}
			check := func(n string) error {
				if !name(n) || seen[n] {
					return status.Error(codes.InvalidArgument, "invalid or duplicate directory entry")
				}
				seen[n] = true
				return w.count()
			}
			for _, f := range n.dir.Files {
				if err := check(f.Name); err != nil {
					return err
				}
				files = append(files, inputFile{path: path.Join(n.path, f.Name), node: f})
			}
			for _, d := range n.dir.Directories {
				if err := check(d.Name); err != nil {
					return err
				}
				child := path.Join(n.path, d.Name)
				if err := w.mkdir(root, child); err != nil {
					return err
				}
				key := d.Digest.GetHash() + "/" + strconv.FormatInt(d.Digest.GetSizeBytes(), 10)
				i, ok := unique[key]
				if !ok {
					i = len(digests)
					unique[key] = i
					digests = append(digests, d.Digest)
				}
				children = append(children, inputDirectory{path: child})
				childDigest = append(childDigest, i)
			}
			for _, s := range n.dir.Symlinks {
				if err := check(s.Name); err != nil {
					return err
				}
				link := path.Join(n.path, s.Name)
				if !safeLink(link, s.Target) {
					return status.Error(codes.InvalidArgument, "escaping symlink")
				}
				links = append(links, [2]string{link, s.Target})
			}
		}
		dirs, err := w.readDirectories(ctx, digests)
		if err != nil {
			return err
		}
		for i := range children {
			children[i].dir = dirs[childDigest[i]]
		}
		level = children
	}
	if err := w.materializeFiles(ctx, root, files); err != nil {
		return err
	}
	for _, link := range links {
		if err := root.Symlink(link[1], link[0]); err != nil {
			return err
		}
	}
	return nil
}

// readDirectories reads directory messages in bounded batches, several at once.
func (w *Worker) readDirectories(ctx context.Context, digests []*re.Digest) ([]*re.Directory, error) {
	dirs := make([]*re.Directory, len(digests))
	for i := range dirs {
		dirs[i] = &re.Directory{}
	}
	runs := inputBatches(len(digests), func(i int) int64 { return digests[i].GetSizeBytes() })
	err := inParallel(ctx, len(runs), inputDownloadConcurrency, func(ctx context.Context, r int) error {
		messages := make([]proto.Message, 0, len(runs[r]))
		batch := make([]*re.Digest, 0, len(runs[r]))
		for _, i := range runs[r] {
			batch = append(batch, digests[i])
			messages = append(messages, dirs[i])
		}
		return w.CAS.Messages(ctx, batch, messages)
	})
	return dirs, err
}

// inputBatches groups inputs into runs that one BatchReadBlobs carries: at
// most inputBatchEntries inputs and inputBatchBytes, in input order. An input
// over inputBatchFileBytes gets a run of its own.
func inputBatches(n int, size func(int) int64) [][]int {
	var runs [][]int
	var run []int
	var total int64
	for i := range n {
		s := size(i)
		if s > inputBatchFileBytes {
			runs = append(runs, []int{i})
			continue
		}
		if len(run) == inputBatchEntries || total+s > inputBatchBytes {
			runs = append(runs, run)
			run, total = nil, 0
		}
		run = append(run, i)
		total += s
	}
	if len(run) > 0 {
		runs = append(runs, run)
	}
	return runs
}

const inputDownloadConcurrency = 8

// materializeFiles downloads the input files of the whole tree. Small files
// share batches across directories; large files, and every file when the CAS
// has no BatchReadBlobs, stream one blob per call. Batches and streams share
// one bound, so at most inputDownloadConcurrency batch responses are live.
// It returns only after every download stopped, before any command starts.
func (w *Worker) materializeFiles(ctx context.Context, root *os.Root, files []inputFile) error {
	for _, f := range files {
		if !ValidDigest(f.node.Digest) {
			return status.Error(codes.InvalidArgument, "invalid input digest")
		}
	}
	batchable := w.CAS.Blobs != nil && !w.CAS.noBatch.Load()
	var small, streamed []inputFile
	for _, f := range files {
		if batchable && f.node.Digest.SizeBytes <= inputBatchFileBytes {
			small = append(small, f)
		} else {
			streamed = append(streamed, f)
		}
	}
	runs := inputBatches(len(small), func(i int) int64 { return small[i].node.Digest.SizeBytes })
	return inParallel(ctx, len(runs)+len(streamed), inputDownloadConcurrency, func(ctx context.Context, i int) error {
		if i >= len(runs) {
			f := streamed[i-len(runs)]
			return w.materializeFile(ctx, root, f.path, f.node)
		}
		batch := make([]inputFile, len(runs[i]))
		for j, k := range runs[i] {
			batch[j] = small[k]
		}
		return w.materializeBatch(ctx, root, batch)
	})
}

func (w *Worker) materializeBatch(ctx context.Context, root *os.Root, files []inputFile) error {
	digests := make([]*re.Digest, len(files))
	for i, f := range files {
		digests[i] = f.node.Digest
	}
	data, err := w.CAS.ReadBatch(ctx, digests)
	if errors.Is(err, errBatchUnsupported) {
		for _, f := range files {
			if err := w.materializeFile(ctx, root, f.path, f.node); err != nil {
				return err
			}
		}
		return nil
	}
	if err != nil {
		return err
	}
	for i, f := range files {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := w.materializeContent(root, f.path, f.node, func(out io.Writer) error {
			_, err := io.Copy(out, bytes.NewReader(data[i]))
			return err
		}); err != nil {
			return err
		}
	}
	return nil
}

// inParallel calls fn for 0 to n-1, at most limit at a time. The first error
// cancels the calls still running and skips the rest; it is returned once
// every started call has returned.
func inParallel(ctx context.Context, n, limit int, fn func(context.Context, int) error) error {
	if n == 0 {
		return ctx.Err()
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	next := make(chan int)
	var workers sync.WaitGroup
	var once sync.Once
	var firstErr error
	for range min(limit, n) {
		workers.Go(func() {
			for i := range next {
				if ctx.Err() != nil {
					continue
				}
				if err := fn(ctx, i); err != nil {
					once.Do(func() {
						firstErr = err
						cancel()
					})
				}
			}
		})
	}
enqueue:
	for i := range n {
		select {
		case next <- i:
		case <-ctx.Done():
			break enqueue
		}
	}
	close(next)
	workers.Wait()
	if firstErr != nil {
		return firstErr
	}
	return ctx.Err()
}

// An input tree can hold one large blob at several paths, such as a
// toolchain's shared libraries, so each digest is read from the CAS once per
// action and copied locally for its other paths.
func (w *Worker) materializeFile(ctx context.Context, root *os.Root, p string, f *re.FileNode) error {
	key := f.Digest.Hash + "/" + strconv.FormatInt(f.Digest.SizeBytes, 10)
	w.streamedMu.Lock()
	if w.streamed == nil {
		w.streamed = map[string]*streamedInput{}
	}
	first, ok := w.streamed[key]
	if !ok {
		first = &streamedInput{done: make(chan struct{}), path: p}
		w.streamed[key] = first
	}
	w.streamedMu.Unlock()
	if !ok {
		first.err = w.materializeContent(root, p, f, func(out io.Writer) error { return w.CAS.Read(ctx, f.Digest, out) })
		close(first.done)
		return first.err
	}
	select {
	case <-first.done:
	case <-ctx.Done():
		return ctx.Err()
	}
	if first.err != nil {
		return first.err
	}
	return w.materializeContent(root, p, f, func(out io.Writer) error {
		in, err := root.Open(first.path)
		if err != nil {
			return err
		}
		defer in.Close()
		n, err := io.Copy(out, in)
		if err == nil && n != f.Digest.SizeBytes {
			err = status.Error(codes.DataLoss, "local input copy size mismatch")
		}
		return err
	})
}

func (w *Worker) materializeContent(root *os.Root, p string, f *re.FileNode, read func(io.Writer) error) error {
	mode := os.FileMode(0644)
	if f.IsExecutable {
		mode = 0755
	}
	h, err := root.OpenFile(p, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
	if err != nil {
		return err
	}
	err = read(h)
	closeErr := h.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return w.own(root, p)
}

func (w *Worker) collect(root *os.Root, p, output string, result *re.ActionResult, uploads *outputUploads) error {
	info, err := root.Lstat(p)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	if info.Mode()&os.ModeSymlink != 0 {
		target, err := root.Readlink(p)
		if err != nil {
			return err
		}
		if !safeLink(p, target) {
			return status.Error(codes.InvalidArgument, "escaping output symlink")
		}
		result.OutputSymlinks = append(result.OutputSymlinks, &re.OutputSymlink{Path: output, Target: target})
		return nil
	}
	if info.IsDir() {
		tree := &re.Tree{}
		dir, err := w.outputDirectory(root, p, tree, 0, uploads)
		if err != nil {
			return err
		}
		tree.Root = dir
		digest, err := uploads.message(tree)
		if err != nil {
			return err
		}
		result.OutputDirectories = append(result.OutputDirectories, &re.OutputDirectory{Path: output, TreeDigest: digest})
		return nil
	}
	if !info.Mode().IsRegular() {
		return status.Error(codes.InvalidArgument, "unsupported output file type")
	}
	digest, err := uploads.file(root, p)
	if err != nil {
		return err
	}
	result.OutputFiles = append(result.OutputFiles, &re.OutputFile{Path: output, Digest: digest, IsExecutable: info.Mode()&0111 != 0})
	return nil
}

func (w *Worker) outputDirectory(root *os.Root, p string, tree *re.Tree, depth int, uploads *outputUploads) (*re.Directory, error) {
	if depth > 128 {
		return nil, status.Error(codes.ResourceExhausted, "output tree too deep")
	}
	f, err := root.Open(p)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	dir := &re.Directory{}
	for {
		entries, readErr := f.ReadDir(128)
		if readErr != nil && readErr != io.EOF {
			return nil, readErr
		}
		for _, e := range entries {
			if err = w.count(); err != nil {
				return nil, err
			}
			child := path.Join(p, e.Name())
			info, err := root.Lstat(child)
			if err != nil {
				return nil, err
			}
			switch {
			case info.Mode()&os.ModeSymlink != 0:
				target, err := root.Readlink(child)
				if err != nil {
					return nil, err
				}
				if !safeLink(child, target) {
					return nil, status.Error(codes.InvalidArgument, "escaping output symlink")
				}
				dir.Symlinks = append(dir.Symlinks, &re.SymlinkNode{Name: e.Name(), Target: target})
			case info.IsDir():
				sub, err := w.outputDirectory(root, child, tree, depth+1, uploads)
				if err != nil {
					return nil, err
				}
				digest, err := uploads.message(sub)
				if err != nil {
					return nil, err
				}
				tree.Children = append(tree.Children, sub)
				dir.Directories = append(dir.Directories, &re.DirectoryNode{Name: e.Name(), Digest: digest})
			case info.Mode().IsRegular():
				digest, err := uploads.file(root, child)
				if err != nil {
					return nil, err
				}
				dir.Files = append(dir.Files, &re.FileNode{Name: e.Name(), Digest: digest, IsExecutable: info.Mode()&0111 != 0})
			default:
				return nil, status.Error(codes.InvalidArgument, "unsupported output file type")
			}
		}
		if proto.Size(tree)+proto.Size(dir) > MaxMetadata {
			return nil, status.Error(codes.ResourceExhausted, "output tree too large")
		}
		if readErr == io.EOF {
			break
		}
	}
	sort.Slice(dir.Files, func(i, j int) bool { return dir.Files[i].Name < dir.Files[j].Name })
	sort.Slice(dir.Directories, func(i, j int) bool { return dir.Directories[i].Name < dir.Directories[j].Name })
	sort.Slice(dir.Symlinks, func(i, j int) bool { return dir.Symlinks[i].Name < dir.Symlinks[j].Name })
	return dir, nil
}

// A noisy compiler cannot fill the workspace disk with logs. Exceeding the
// limit fails execution rather than returning silently truncated log blobs.
type limitedLog struct {
	file    *os.File
	written int64
}

func (l *limitedLog) Write(p []byte) (int, error) {
	if l.written+int64(len(p)) > 64<<20 {
		return 0, status.Error(codes.ResourceExhausted, "action log too large")
	}
	n, err := l.file.Write(p)
	l.written += int64(n)
	return n, err
}

func commandPath(program string, env []string, cwd string) (string, error) {
	if strings.ContainsRune(program, 0) {
		return "", status.Error(codes.InvalidArgument, "invalid executable")
	}
	if strings.Contains(program, "/") {
		if filepath.IsAbs(program) {
			return program, nil
		}
		return filepath.Join(cwd, program), nil
	}
	for _, v := range env {
		if strings.HasPrefix(v, "PATH=") {
			for _, p := range filepath.SplitList(strings.TrimPrefix(v, "PATH=")) {
				if !filepath.IsAbs(p) {
					p = filepath.Join(cwd, p)
				}
				candidate := filepath.Join(p, program)
				if i, err := os.Stat(candidate); err == nil && i.Mode().IsRegular() && i.Mode()&0111 != 0 {
					return candidate, nil
				}
			}
		}
	}
	return "", status.Error(codes.InvalidArgument, fmt.Sprintf("executable %q is absent from action PATH", program))
}

// A prepared VM may already hold the action root, created empty so its
// filesystem metadata is warm. Anything else in its place is refused.
func emptyDirectory(p string) bool {
	info, err := os.Lstat(p)
	if err != nil || !info.IsDir() {
		return false
	}
	f, err := os.Open(p)
	if err != nil {
		return false
	}
	defer f.Close()
	_, err = f.Readdirnames(1)
	return err == io.EOF
}
