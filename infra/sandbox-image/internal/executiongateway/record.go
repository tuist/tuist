package executiongateway

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"sync"
	"sync/atomic"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// Action records: after the client has an executed action's result, the
// gateway sends the server a bounded record of what ran (the command, its
// environment with secret-looking values masked, platform, declared outputs,
// exit code, phase timestamps, dispatch path and VM, and the start of stdout
// and stderr), so users can inspect and reproduce remote actions. The server
// never reads the cache for them. Records are diagnostics and best effort:
// reading them happens off the client's path, and a full queue, a failed read
// or an unavailable server drops them, which only the metrics count.

const (
	requestMetadataHeader = "build.bazel.remote.execution.v2.requestmetadata-bin"
	recordQueue           = 1024
	recordReaders         = 4
	recordBatch           = 50
	recordBatchBytes      = 1 << 20
	recordFlush           = time.Second
	recordReadTimeout     = 10 * time.Second
	recordPostTimeout     = 10 * time.Second
	maxRecordCommand      = 1 << 20
	maxRecordArguments    = 64 << 10
	maxRecordPairs        = 32 << 10
	maxRecordOutputs      = 32 << 10
	maxRecordValue        = 4 << 10
	maxRecordLog          = 16 << 10
	masked                = "****"
)

var (
	secretName = regexp.MustCompile(`(?i)token|secret|password|key`)
	// A flag that takes its secret as the next argument, like --password.
	secretFlag = regexp.MustCompile(`(?i)^-{1,2}[A-Za-z0-9_.\-]*(token|secret|password|key)$`)
	assignment = regexp.MustCompile(`^(-{0,2}[A-Za-z0-9_.\-]+)=`)
)

type pair struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

type actionRecord struct {
	OperationID        string           `json:"operation_id"`
	ActionHash         string           `json:"action_hash"`
	ActionSize         int64            `json:"action_size"`
	InvocationID       string           `json:"invocation_id"`
	ToolName           string           `json:"tool_name"`
	ToolVersion        string           `json:"tool_version"`
	Mnemonic           string           `json:"mnemonic"`
	Target             string           `json:"target"`
	ConfigurationID    string           `json:"configuration_id"`
	ExecutionPath      string           `json:"execution_path"`
	SandboxID          string           `json:"sandbox_id"`
	Worker             string           `json:"worker"`
	MemoryGB           int              `json:"memory_gb"`
	TimeoutMS          int64            `json:"timeout_ms"`
	DoNotCache         bool             `json:"do_not_cache"`
	CachedResult       bool             `json:"cached_result"`
	Arguments          []string         `json:"arguments"`
	ArgumentsTruncated bool             `json:"arguments_truncated"`
	Environment        []pair           `json:"environment"`
	WorkingDirectory   string           `json:"working_directory"`
	Platform           []pair           `json:"platform"`
	OutputPaths        []string         `json:"output_paths"`
	OutputCount        int              `json:"output_count"`
	StatusCode         int32            `json:"status_code"`
	StatusMessage      string           `json:"status_message"`
	ExitCode           int32            `json:"exit_code"`
	Timestamps         map[string]int64 `json:"timestamps"`
	Stdout             string           `json:"stdout"`
	StdoutSize         int64            `json:"stdout_size"`
	StdoutTruncated    bool             `json:"stdout_truncated"`
	Stderr             string           `json:"stderr"`
	StderrSize         int64            `json:"stderr_size"`
	StderrTruncated    bool             `json:"stderr_truncated"`
	// The digests of streams longer than the record keeps, so the server can
	// ask for a copy of the rest (see logcopy.go).
	StdoutHash string `json:"stdout_hash,omitempty"`
	StderrHash string `json:"stderr_hash,omitempty"`
	// What the command used in its VM, which sizes its next run.
	Usage *worker.Usage `json:"usage,omitempty"`
}

// recording is what Execute knows about an action when it starts streaming
// its result: the scope it ran in, and the action and prefetched blobs when
// the prefetch read them.
type recording struct {
	account, project, auth string
	digest                 *re.Digest
	metadata               *re.RequestMetadata
	action                 *re.Action
	inputs                 string
	memory                 int
	path                   string
	// What the command used, when the VM measured it.
	usage *worker.Usage
}

type finishedAction struct {
	*recording
	op       operation
	response *re.ExecuteResponse
}

type recordScope struct{ account, project, auth string }

type recorder struct {
	queue chan finishedAction
	start sync.Once
	// reading counts queued and in-progress records. A WaitGroup would race:
	// streams still finishing can Add from zero while shutdown Waits.
	reading atomic.Int64
	mu      sync.Mutex
	batches map[recordScope][]json.RawMessage
	size    map[recordScope]int
	full    chan struct{}
}

func newRecorder() *recorder {
	return &recorder{queue: make(chan finishedAction, recordQueue), batches: map[recordScope][]json.RawMessage{}, size: map[recordScope]int{}, full: make(chan struct{}, 1)}
}

// newRecording reads the client's request metadata, which Bazel sends with
// each call; other clients may send none.
func newRecording(ctx context.Context, account, project, auth string, digest *re.Digest, action *re.Action, inputs string, memory int) *recording {
	r := &recording{account: account, project: project, auth: auth, digest: digest, action: action, inputs: inputs, memory: memory, metadata: &re.RequestMetadata{}}
	md, _ := metadata.FromIncomingContext(ctx)
	if values := md.Get(requestMetadataHeader); len(values) == 1 {
		_ = proto.Unmarshal([]byte(values[0]), r.metadata)
	}
	return r
}

// record queues the finished action for its record, never blocking the stream.
func (g *Gateway) record(r *recording, op operation, response *re.ExecuteResponse) {
	if r == nil {
		return
	}
	g.recorder.start.Do(func() {
		for range recordReaders {
			go g.readRecords()
		}
		go g.flushRecords()
	})
	g.recorder.reading.Add(1)
	select {
	case g.recorder.queue <- finishedAction{recording: r, op: op, response: response}:
	default:
		g.recorder.reading.Add(-1)
		g.metrics.records.WithLabelValues("dropped").Inc()
	}
}

func (g *Gateway) readRecords() {
	for action := range g.recorder.queue {
		g.complete(action)
		g.recorder.reading.Add(-1)
	}
}

// complete reads what the record still needs from the cache with the
// client's credential and adds it to its project's batch.
func (g *Gateway) complete(a finishedAction) {
	ctx, cancel := context.WithTimeout(context.Background(), recordReadTimeout)
	defer cancel()
	ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", a.auth, "x-tuist-account-handle", a.account))
	md := a.metadata
	record := actionRecord{
		OperationID: a.op.ID, ActionHash: a.digest.Hash, ActionSize: a.digest.SizeBytes,
		InvocationID: md.ToolInvocationId, ToolName: md.GetToolDetails().GetToolName(), ToolVersion: md.GetToolDetails().GetToolVersion(),
		Mnemonic: md.ActionMnemonic, Target: md.TargetId, ConfigurationID: md.ConfigurationId,
		ExecutionPath: a.path, SandboxID: a.op.SandboxID, MemoryGB: a.memory,
		StatusCode: a.response.GetStatus().GetCode(), StatusMessage: limit(a.response.GetStatus().GetMessage(), maxRecordValue),
		CachedResult: a.response.CachedResult, Timestamps: map[string]int64{},
		Usage: a.usage,
	}
	if record.InvocationID == "" {
		// Nothing on the server could find it.
		g.metrics.records.WithLabelValues("unattributed").Inc()
		return
	}
	var cas re.ContentAddressableStorageClient
	var stream bs.ByteStreamClient
	if url := g.endpoint(a.account, a.project); url != "" {
		if conn, err := g.conn(url); err == nil {
			cas, stream = re.NewContentAddressableStorageClient(conn), bs.NewByteStreamClient(conn)
		}
	}
	action := a.action
	if action == nil && cas != nil {
		action = &re.Action{}
		if readMessage(ctx, cas, a.project, a.digest, maxRecordCommand, action) != nil {
			action = nil
		}
	}
	complete := action != nil
	if action != nil {
		record.DoNotCache = action.DoNotCache
		record.TimeoutMS = action.GetTimeout().AsDuration().Milliseconds()
		command := prefetchedCommand(a.inputs, action.CommandDigest)
		if command == nil && cas != nil && worker.ValidDigest(action.CommandDigest) && action.CommandDigest.SizeBytes <= maxRecordCommand {
			command = &re.Command{}
			if readMessage(ctx, cas, a.project, action.CommandDigest, maxRecordCommand, command) != nil {
				command = nil
			}
		}
		complete = command != nil
		if command != nil {
			describeCommand(&record, command)
		}
		platform := action.Platform
		if platform == nil && command != nil {
			platform = command.Platform
		}
		for _, p := range platform.GetProperties() {
			record.Platform = appendPair(record.Platform, p.Name, p.Value, maxRecordValue)
		}
	}
	if result := a.response.Result; result != nil {
		record.ExitCode = result.ExitCode
		if md := result.ExecutionMetadata; md != nil {
			record.Worker = limit(md.Worker, 256)
			for name, t := range map[string]*timestamppb.Timestamp{
				"queued": md.QueuedTimestamp, "worker_start": md.WorkerStartTimestamp, "worker_completed": md.WorkerCompletedTimestamp,
				"input_fetch_start": md.InputFetchStartTimestamp, "input_fetch_completed": md.InputFetchCompletedTimestamp,
				"execution_start": md.ExecutionStartTimestamp, "execution_completed": md.ExecutionCompletedTimestamp,
				"output_upload_start": md.OutputUploadStartTimestamp, "output_upload_completed": md.OutputUploadCompletedTimestamp,
			} {
				if t != nil && t.CheckValid() == nil {
					record.Timestamps[name] = t.AsTime().UnixMicro()
				}
			}
		}
		var stdoutRead, stderrRead bool
		record.Stdout, record.StdoutSize, record.StdoutTruncated, stdoutRead = readLog(ctx, stream, a.project, result.StdoutRaw, result.StdoutDigest)
		record.Stderr, record.StderrSize, record.StderrTruncated, stderrRead = readLog(ctx, stream, a.project, result.StderrRaw, result.StderrDigest)
		complete = complete && stdoutRead && stderrRead
		record.StdoutHash, record.StderrHash = longLog(result.StdoutDigest), longLog(result.StderrDigest)
	}
	b, err := json.Marshal(record)
	if err != nil {
		g.metrics.records.WithLabelValues("failed").Inc()
		return
	}
	if !complete {
		g.metrics.records.WithLabelValues("incomplete").Inc()
	}
	g.add(recordScope{a.account, a.project, a.auth}, b)
}

func describeCommand(record *actionRecord, command *re.Command) {
	size := 0
	for _, argument := range maskArguments(command.Arguments) {
		if size+len(argument) > maxRecordArguments {
			record.ArgumentsTruncated = true
			break
		}
		size += len(argument)
		record.Arguments = append(record.Arguments, argument)
	}
	size = 0
	for _, v := range command.EnvironmentVariables {
		value := v.Value
		if secretName.MatchString(v.Name) {
			value = masked
		}
		if size += len(v.Name) + len(value); size > maxRecordPairs {
			break
		}
		record.Environment = appendPair(record.Environment, v.Name, value, maxRecordValue)
	}
	record.WorkingDirectory = limit(command.WorkingDirectory, maxRecordValue)
	paths := command.OutputPaths
	if len(paths) == 0 {
		// REAPI before 2.1 declares files and directories separately.
		paths = append(append([]string{}, command.OutputFiles...), command.OutputDirectories...)
	}
	// The paths stop at the record's bound; the count says how many there were.
	record.OutputCount = len(paths)
	size = 0
	for _, p := range paths {
		if size += len(p); size > maxRecordOutputs {
			break
		}
		record.OutputPaths = append(record.OutputPaths, p)
	}
}

// maskArguments masks the values of flags whose names look like secrets:
// --name=value and NAME=value, and the argument after a flag such as
// --password or --api-key. The server applies the same rules.
func maskArguments(arguments []string) []string {
	out := make([]string, len(arguments))
	next := false
	for i, argument := range arguments {
		switch m := assignment.FindStringSubmatch(argument); {
		case next:
			out[i], next = masked, false
		case m != nil && secretName.MatchString(m[1]):
			out[i] = m[0] + masked
		case m == nil && secretFlag.MatchString(argument):
			out[i], next = argument, true
		default:
			out[i] = argument
		}
	}
	return out
}

func appendPair(pairs []pair, name, value string, max int) []pair {
	return append(pairs, pair{Name: limit(name, 256), Value: limit(value, max)})
}

func limit(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}

// prefetchedCommand returns the command when the prefetch already read it.
func prefetchedCommand(inputs string, digest *re.Digest) *re.Command {
	if inputs == "" || !worker.ValidDigest(digest) {
		return nil
	}
	b, err := base64.StdEncoding.DecodeString(inputs)
	if err != nil {
		return nil
	}
	var seed re.BatchUpdateBlobsRequest
	if proto.Unmarshal(b, &seed) != nil {
		return nil
	}
	for _, blob := range seed.Requests {
		if blob.GetDigest().GetHash() == digest.Hash {
			var command re.Command
			if proto.Unmarshal(blob.Data, &command) == nil {
				return &command
			}
		}
	}
	return nil
}

func readMessage(ctx context.Context, cas re.ContentAddressableStorageClient, project string, d *re.Digest, max int64, m proto.Message) error {
	if !worker.ValidDigest(d) || d.SizeBytes > max {
		return fmt.Errorf("blob too large")
	}
	response, err := cas.BatchReadBlobs(ctx, &re.BatchReadBlobsRequest{InstanceName: project, Digests: []*re.Digest{d}, DigestFunction: re.DigestFunction_SHA256})
	if err != nil {
		return err
	}
	if len(response.Responses) != 1 || !matches(response.Responses[0], d) {
		return fmt.Errorf("blob unavailable")
	}
	return proto.Unmarshal(response.Responses[0].Data, m)
}

// readLog returns the start of an output stream, from the result when the
// worker inlined it, otherwise read from the cache up to maxRecordLog. ok is
// false when it could not be read.
func readLog(ctx context.Context, stream bs.ByteStreamClient, project string, raw []byte, d *re.Digest) (text string, size int64, truncated, ok bool) {
	if len(raw) > 0 {
		return string(raw[:min(len(raw), maxRecordLog)]), int64(len(raw)), len(raw) > maxRecordLog, true
	}
	if d == nil || d.SizeBytes == 0 {
		return "", 0, false, true
	}
	if stream == nil || !worker.ValidDigest(d) {
		return "", d.SizeBytes, false, false
	}
	reader, err := stream.Read(ctx, &bs.ReadRequest{ResourceName: fmt.Sprintf("%s/blobs/%s/%d", project, d.Hash, d.SizeBytes), ReadLimit: maxRecordLog})
	if err != nil {
		return "", d.SizeBytes, false, false
	}
	var out bytes.Buffer
	for out.Len() < maxRecordLog {
		chunk, err := reader.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return "", d.SizeBytes, false, false
		}
		out.Write(chunk.Data)
	}
	b := out.Bytes()[:min(out.Len(), maxRecordLog)]
	return string(b), d.SizeBytes, d.SizeBytes > int64(len(b)), true
}

func (g *Gateway) add(scope recordScope, record json.RawMessage) {
	r := g.recorder
	r.mu.Lock()
	r.batches[scope] = append(r.batches[scope], record)
	r.size[scope] += len(record)
	full := len(r.batches[scope]) >= recordBatch || r.size[scope] >= recordBatchBytes
	r.mu.Unlock()
	if full {
		select {
		case r.full <- struct{}{}:
		default:
		}
	}
}

func (g *Gateway) flushRecords() {
	ticker := time.NewTicker(recordFlush)
	defer ticker.Stop()
	for {
		select {
		case <-ticker.C:
		case <-g.recorder.full:
		}
		g.sendRecords(context.Background())
	}
}

// sendRecords posts every pending batch, each with the credential of the
// actions in it. A refused or failed batch is dropped, not retried.
func (g *Gateway) sendRecords(ctx context.Context) {
	r := g.recorder
	r.mu.Lock()
	batches := r.batches
	r.batches, r.size = map[recordScope][]json.RawMessage{}, map[recordScope]int{}
	r.mu.Unlock()
	for scope, records := range batches {
		for start := 0; start < len(records); start += recordBatch {
			batch := records[start:min(start+recordBatch, len(records))]
			result := "sent"
			if err := g.postRecords(ctx, scope, batch); err != nil {
				result = "failed"
				log.Printf("action records not delivered: %v", err)
			}
			g.metrics.records.WithLabelValues(result).Add(float64(len(batch)))
		}
	}
}

func (g *Gateway) postRecords(parent context.Context, scope recordScope, records []json.RawMessage) error {
	body, err := json.Marshal(map[string]any{"actions": records})
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(parent, recordPostTimeout)
	defer cancel()
	u := g.URL + "/api/remote-execution/" + url.PathEscape(scope.account) + "/" + url.PathEscape(scope.project) + "/actions"
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", scope.auth)
	request.Header.Set("Content-Type", "application/json")
	response, err := g.Client.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
		return fmt.Errorf("server answered %d", response.StatusCode)
	}
	// The server asks for copies of the logs it wants in full.
	var answer struct {
		LogUploads []logUpload `json:"log_uploads"`
	}
	if json.NewDecoder(io.LimitReader(response.Body, maxLogUploadsAnswer)).Decode(&answer) == nil {
		for _, upload := range answer.LogUploads {
			g.copyLog(scope, upload)
		}
	}
	return nil
}

// waitRecords reads the queued records and sends them, until ctx ends.
func (g *Gateway) waitRecords(ctx context.Context) {
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for g.recorder.reading.Load() > 0 && ctx.Err() == nil {
		select {
		case <-ticker.C:
		case <-ctx.Done():
		}
	}
	g.sendRecords(ctx)
}
