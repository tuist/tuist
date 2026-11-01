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
	"sort"
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
	// Production always drops to the unprivileged build user. Tests run as
	// their invoking user, against a temporary directory and an in-memory CAS.
	Credential *syscall.Credential
	// Start launches the action's command; nil uses exec.Cmd.Start.
	Start   func(*exec.Cmd) error
	entries int
}

// Execute reports whether the result may be published to the action cache.
// Publication is the caller's job, after the client already has the result.
func (w *Worker) Execute(ctx context.Context, digest *re.Digest, skipCache bool) (*re.ExecuteResponse, bool) {
	result, cached, cacheable, err := w.execute(ctx, digest, skipCache)
	response := &re.ExecuteResponse{Result: result, CachedResult: cached, Status: &rpc.Status{}}
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

func (w *Worker) execute(ctx context.Context, digest *re.Digest, skipCache bool) (*re.ActionResult, bool, bool, error) {
	metadata := &re.ExecutedActionMetadata{Worker: "firecracker-linux-amd64", WorkerStartTimestamp: timestamppb.Now()}
	metadata.InputFetchStartTimestamp = timestamppb.Now()
	var action re.Action
	if err := w.CAS.Message(ctx, digest, &action); err != nil {
		return nil, false, false, err
	}
	var command re.Command
	var input re.Directory
	if err := w.CAS.Messages(ctx, []*re.Digest{action.CommandDigest, action.InputRootDigest}, []proto.Message{&command, &input}); err != nil {
		return nil, false, false, err
	}
	if err := w.validate(&action, &command); err != nil {
		return nil, false, false, err
	}
	if !skipCache && !action.DoNotCache {
		result, err := w.CAS.Actions.GetActionResult(ctx, &re.GetActionResultRequest{InstanceName: w.CAS.Instance, ActionDigest: digest, DigestFunction: re.DigestFunction_SHA256})
		if err == nil {
			return result, true, false, nil
		}
		if status.Code(err) != codes.NotFound {
			return nil, false, false, err
		}
	}
	if err := os.Mkdir(w.Root, 0755); err != nil {
		return nil, false, false, err
	}
	root, err := os.OpenRoot(w.Root)
	if err != nil {
		return nil, false, false, err
	}
	defer root.Close()
	if err = w.own(root, "."); err != nil {
		return nil, false, false, err
	}
	if err = w.materialize(ctx, root, ".", &input, 0); err != nil {
		return nil, false, false, err
	}
	metadata.InputFetchCompletedTimestamp = timestamppb.Now()
	outputs := command.OutputPaths
	if len(outputs) == 0 {
		outputs = append(append([]string{}, command.OutputFiles...), command.OutputDirectories...)
	}
	for _, p := range outputs {
		if !relative(p, false) {
			return nil, false, false, status.Error(codes.InvalidArgument, "invalid output path")
		}
		if err = w.mkdir(root, path.Dir(path.Join(command.WorkingDirectory, p))); err != nil {
			return nil, false, false, err
		}
	}
	if !relative(command.WorkingDirectory, true) {
		return nil, false, false, status.Error(codes.InvalidArgument, "invalid working directory")
	}
	working := command.WorkingDirectory
	if working == "" {
		working = "."
	}
	info, err := root.Stat(working)
	if err != nil || !info.IsDir() {
		return nil, false, false, status.Error(codes.InvalidArgument, "missing working directory")
	}
	// Logs are outside the unprivileged build user's writable workspace.
	stdout, err := os.CreateTemp("", "rbe-stdout-")
	if err != nil {
		return nil, false, false, err
	}
	defer os.Remove(stdout.Name())
	defer stdout.Close()
	stderr, err := os.CreateTemp("", "rbe-stderr-")
	if err != nil {
		return nil, false, false, err
	}
	defer os.Remove(stderr.Name())
	defer stderr.Close()
	limit := 10 * time.Minute
	if action.Timeout != nil {
		limit = action.Timeout.AsDuration()
	}
	runCtx, cancel := context.WithTimeout(ctx, limit)
	defer cancel()
	env := make([]string, 0, len(command.EnvironmentVariables))
	for _, v := range command.EnvironmentVariables {
		env = append(env, v.Name+"="+v.Value)
	}
	program, err := commandPath(command.Arguments[0], env, filepath.Join(w.Root, working))
	if err != nil {
		return nil, false, false, err
	}
	cmd := &exec.Cmd{Path: program, Args: command.Arguments, Dir: filepath.Join(w.Root, working), Env: env,
		Stdout: &limitedLog{file: stdout}, Stderr: &limitedLog{file: stderr},
		SysProcAttr: &syscall.SysProcAttr{Setpgid: true, Credential: w.Credential}, WaitDelay: time.Second}
	started := time.Now()
	if err = w.start(cmd); err != nil {
		return nil, false, false, err
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
			return nil, false, false, err
		}
	}
	exitCode := cmd.ProcessState.ExitCode()
	if exitCode < 0 {
		exitCode = 128
	}
	metadata.ExecutionStartTimestamp = timestamppb.New(started)
	metadata.ExecutionCompletedTimestamp = timestamppb.Now()
	metadata.OutputUploadStartTimestamp = timestamppb.Now()
	result := &re.ActionResult{ExitCode: int32(exitCode), ExecutionMetadata: metadata}
	if timedOut {
		result.ExitCode = 124
	}
	if result.StdoutDigest, err = w.uploadLog(ctx, stdout); err != nil {
		return nil, false, false, err
	}
	if result.StderrDigest, err = w.uploadLog(ctx, stderr); err != nil {
		return nil, false, false, err
	}
	for _, p := range outputs {
		if err = w.collect(ctx, root, path.Join(working, p), p, result); err != nil {
			return nil, false, false, err
		}
		if proto.Size(result) > MaxResponse {
			return nil, false, false, status.Error(codes.ResourceExhausted, "action result too large")
		}
	}
	if timedOut {
		metadata.OutputUploadCompletedTimestamp = timestamppb.Now()
		metadata.WorkerCompletedTimestamp = timestamppb.Now()
		return result, false, false, context.DeadlineExceeded
	}
	// These timestamps describe the worker, excluding controller VM creation
	// and cleanup. Cached results deliberately retain the original execution.
	metadata.OutputUploadCompletedTimestamp = timestamppb.Now()
	metadata.WorkerCompletedTimestamp = timestamppb.Now()
	return result, false, result.ExitCode == 0 && !action.DoNotCache, nil
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
	if a.Timeout != nil && (a.Timeout.CheckValid() != nil || a.Timeout.AsDuration() <= 0 || a.Timeout.AsDuration() > 10*time.Minute) {
		return status.Error(codes.InvalidArgument, "timeout must be at most ten minutes")
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
	if len(properties) != 3 || properties["OSFamily"] != "Linux" || properties["Arch"] != "amd64" || properties["tuist-image"] != w.Image || w.Image == "" {
		return status.Error(codes.FailedPrecondition, "unsupported execution platform")
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

func (w *Worker) materialize(ctx context.Context, root *os.Root, p string, dir *re.Directory, depth int) error {
	if depth > 128 {
		return status.Error(codes.ResourceExhausted, "input tree too deep")
	}
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
	for _, f := range dir.Files {
		if err := check(f.Name); err != nil {
			return err
		}
	}
	if err := w.materializeFiles(ctx, root, p, dir.Files); err != nil {
		return err
	}
	for _, d := range dir.Directories {
		if err := check(d.Name); err != nil {
			return err
		}
	}
	// Sibling directories are read together, a bounded batch at a time, so
	// at most one batch per level is held while descending.
	for start := 0; start < len(dir.Directories); {
		end := start
		var size int64
		for end < len(dir.Directories) && end-start < inputBatchEntries && size+dir.Directories[end].Digest.GetSizeBytes() <= inputBatchBytes {
			size += dir.Directories[end].Digest.GetSizeBytes()
			end++
		}
		end = max(end, start+1)
		nodes := dir.Directories[start:end]
		digests := make([]*re.Digest, len(nodes))
		children := make([]proto.Message, len(nodes))
		for i, d := range nodes {
			digests[i] = d.Digest
			children[i] = &re.Directory{}
		}
		if err := w.CAS.Messages(ctx, digests, children); err != nil {
			return err
		}
		for i, d := range nodes {
			child := path.Join(p, d.Name)
			if err := w.mkdir(root, child); err != nil {
				return err
			}
			if err := w.materialize(ctx, root, child, children[i].(*re.Directory), depth+1); err != nil {
				return err
			}
		}
		start = end
	}
	for _, s := range dir.Symlinks {
		if err := check(s.Name); err != nil {
			return err
		}
		link := path.Join(p, s.Name)
		if !safeLink(link, s.Target) {
			return status.Error(codes.InvalidArgument, "escaping symlink")
		}
		if err := root.Symlink(s.Target, link); err != nil {
			return err
		}
	}
	return nil
}

const inputDownloadConcurrency = 8

// Batch small inputs to amortize RPC overhead. Large files and peers without
// BatchReadBlobs retain bounded streaming. Batches are serial so only one
// response buffer is live, regardless of directory size.
func (w *Worker) materializeFiles(ctx context.Context, root *os.Root, p string, files []*re.FileNode) error {
	for _, f := range files {
		if !ValidDigest(f.Digest) {
			return status.Error(codes.InvalidArgument, "invalid input digest")
		}
	}
	var streaming []*re.FileNode
	for start := 0; start < len(files); {
		end := start
		var size int64
		for end < len(files) && end-start < inputBatchEntries && files[end].Digest.SizeBytes <= inputBatchFileBytes && size+files[end].Digest.SizeBytes <= inputBatchBytes {
			size += files[end].Digest.SizeBytes
			end++
		}
		if end == start {
			streaming = append(streaming, files[start])
			start++
			continue
		}
		digests := make([]*re.Digest, end-start)
		for i, f := range files[start:end] {
			digests[i] = f.Digest
		}
		data, err := w.CAS.ReadBatch(ctx, digests)
		if errors.Is(err, errBatchUnsupported) {
			streaming = append(streaming, files[start:]...)
			break
		}
		if err != nil {
			return err
		}
		for i, f := range files[start:end] {
			if err := ctx.Err(); err != nil {
				return err
			}
			if err := w.materializeContent(root, path.Join(p, f.Name), f, func(out io.Writer) error {
				_, err := io.Copy(out, bytes.NewReader(data[i]))
				return err
			}); err != nil {
				return err
			}
		}
		start = end
	}
	return w.streamFiles(ctx, root, p, streaming)
}

// Directory traversal and entry accounting stay serial. Only independent files
// within one directory download concurrently, with a fixed per-action bound.
// Wait for every reader to close before returning an error or starting a command.
func (w *Worker) streamFiles(ctx context.Context, root *os.Root, p string, files []*re.FileNode) error {
	if len(files) == 0 {
		return ctx.Err()
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	jobs := make(chan *re.FileNode)
	var workers sync.WaitGroup
	var once sync.Once
	var firstErr error
	for range min(inputDownloadConcurrency, len(files)) {
		workers.Go(func() {
			for f := range jobs {
				if err := ctx.Err(); err != nil {
					return
				}
				if err := w.materializeFile(ctx, root, path.Join(p, f.Name), f); err != nil {
					once.Do(func() {
						firstErr = err
						cancel()
					})
					return
				}
			}
		})
	}
enqueue:
	for _, f := range files {
		select {
		case jobs <- f:
		case <-ctx.Done():
			break enqueue
		}
	}
	close(jobs)
	workers.Wait()
	if firstErr != nil {
		return firstErr
	}
	return ctx.Err()
}

func (w *Worker) materializeFile(ctx context.Context, root *os.Root, p string, f *re.FileNode) error {
	return w.materializeContent(root, p, f, func(out io.Writer) error { return w.CAS.Read(ctx, f.Digest, out) })
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

func (w *Worker) collect(ctx context.Context, root *os.Root, p, output string, result *re.ActionResult) error {
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
		dir, err := w.outputDirectory(ctx, root, p, tree, 0)
		if err != nil {
			return err
		}
		tree.Root = dir
		digest, err := w.CAS.WriteMessage(ctx, tree)
		if err != nil {
			return err
		}
		result.OutputDirectories = append(result.OutputDirectories, &re.OutputDirectory{Path: output, TreeDigest: digest})
		return nil
	}
	if !info.Mode().IsRegular() {
		return status.Error(codes.InvalidArgument, "unsupported output file type")
	}
	f, err := root.Open(p)
	if err != nil {
		return err
	}
	defer f.Close()
	digest, err := w.CAS.Write(ctx, f)
	if err != nil {
		return err
	}
	result.OutputFiles = append(result.OutputFiles, &re.OutputFile{Path: output, Digest: digest, IsExecutable: info.Mode()&0111 != 0})
	return nil
}

func (w *Worker) outputDirectory(ctx context.Context, root *os.Root, p string, tree *re.Tree, depth int) (*re.Directory, error) {
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
				sub, err := w.outputDirectory(ctx, root, child, tree, depth+1)
				if err != nil {
					return nil, err
				}
				digest, err := w.CAS.WriteMessage(ctx, sub)
				if err != nil {
					return nil, err
				}
				tree.Children = append(tree.Children, sub)
				dir.Directories = append(dir.Directories, &re.DirectoryNode{Name: e.Name(), Digest: digest})
			case info.Mode().IsRegular():
				file, err := root.Open(child)
				if err != nil {
					return nil, err
				}
				digest, err := w.CAS.Write(ctx, file)
				file.Close()
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

// REAPI represents an empty log with neither inline bytes nor a digest. Avoid
// two authenticated CAS uploads for the common case of a silent compiler.
// Non-empty logs still live in CAS, outside the bounded control-plane response.
func (w *Worker) uploadLog(ctx context.Context, file *os.File) (*re.Digest, error) {
	info, err := file.Stat()
	if err != nil {
		return nil, err
	}
	if info.Size() == 0 {
		return nil, nil
	}
	return w.CAS.Write(ctx, file)
}
