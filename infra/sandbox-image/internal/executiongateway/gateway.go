// Package executiongateway exposes REAPI while the Tuist control plane owns
// scheduling, authorization, account quotas and Firecracker placement.
package executiongateway

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"log"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"

	lro "cloud.google.com/go/longrunning/autogen/longrunningpb"
	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"github.com/bazelbuild/remote-apis/build/bazel/semver"
	"github.com/prometheus/client_golang/prometheus"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	rpc "google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type Gateway struct {
	re.UnimplementedExecutionServer
	re.UnimplementedCapabilitiesServer
	URL    string
	Client *http.Client
	// Dial opens action-cache connections; tests replace it.
	Dial func(endpoint string) (*grpc.ClientConn, error)
	// ActionReadBudget is how long Execute keeps trying to read an action
	// for its VM size; tests shorten it.
	ActionReadBudget time.Duration
	slots            chan struct{}

	publications chan struct{}
	pending      sync.WaitGroup
	mu           sync.Mutex
	conns        map[string]*grpc.ClientConn
	// Each project's cache endpoint, learned from capability checks.
	endpoints map[string]endpoint
	// Each project's size keys that automatic sizing runs in more than a
	// default VM, which a lease cannot hold (see sized).
	sized map[string]map[string]bool
	// Cache endpoints that answered GetTree with Unimplemented.
	noTree map[string]bool
	// Direct claims a leased VM's exec on its node; it has no timeout of
	// its own because the claim lasts as long as the action.
	Direct         *http.Client
	projects       map[string]*projectLeases
	authorizations map[[32]byte]time.Time
	// Registry holds the gateway's metrics for the process to serve.
	Registry *prometheus.Registry
	metrics  *metrics
	recorder *recorder
	// LogUploads copies long action logs to object storage. It has its own
	// connections so copies never queue behind, or ahead of, control-plane
	// calls; tests replace its transport.
	LogUploads *http.Client
	logs       *logCopier
}

const maxStreams = 512

type endpoint struct {
	url     string
	expires time.Time
	// The control plane grants this project's VMs as leases.
	leases bool
}

func New(serverURL string) *Gateway {
	// Every admitted stream may hold a server connection, including long polls.
	transport := http.DefaultTransport.(*http.Transport).Clone()
	transport.MaxIdleConnsPerHost = maxStreams
	registry := prometheus.NewRegistry()
	return &Gateway{Registry: registry, metrics: newMetrics(registry), URL: strings.TrimRight(serverURL, "/"), Client: &http.Client{Transport: transport, Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, Dial: worker.Dial, ActionReadBudget: 2 * time.Minute, slots: make(chan struct{}, maxStreams), publications: make(chan struct{}, 256), conns: map[string]*grpc.ClientConn{}, endpoints: map[string]endpoint{}, sized: map[string]map[string]bool{}, noTree: map[string]bool{}, Direct: &http.Client{Transport: transport.Clone()}, projects: map[string]*projectLeases{}, authorizations: map[[32]byte]time.Time{}, recorder: newRecorder(), LogUploads: &http.Client{Transport: http.DefaultTransport.(*http.Transport).Clone(), CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, logs: newLogCopier()}
}
func (g *Gateway) Register(s *grpc.Server) {
	re.RegisterExecutionServer(s, g)
	re.RegisterCapabilitiesServer(s, g)
}

var segment = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9_.-]{0,99}$`)
var uuid = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

func scope(ctx context.Context, instance string) (string, string, error) {
	md, _ := metadata.FromIncomingContext(ctx)
	accounts := md.Get("x-tuist-account-handle")
	auth := md.Get("authorization")
	if len(auth) != 1 || !strings.HasPrefix(auth[0], "Bearer ") || len(auth[0]) <= 7 || len(auth[0]) > 16384 {
		return "", "", status.Error(codes.Unauthenticated, "one bearer credential is required")
	}
	if len(accounts) != 1 || !segment.MatchString(accounts[0]) || !segment.MatchString(instance) {
		return "", "", status.Error(codes.InvalidArgument, "account header and project instance are required")
	}
	return accounts[0], auth[0], nil
}

// requestMetadata returns the invocation, mnemonic and target Bazel names an
// action by, which the control plane shows while the action is queued or
// running. They are descriptive only: absent, malformed or oversized values
// are left out, never a reason to refuse the action.
func requestMetadata(ctx context.Context) map[string]string {
	md, _ := metadata.FromIncomingContext(ctx)
	values := md.Get("build.bazel.remote.execution.v2.requestmetadata-bin")
	var m re.RequestMetadata
	if len(values) != 1 || proto.Unmarshal([]byte(values[0]), &m) != nil {
		return nil
	}
	out := map[string]string{}
	for key, value := range map[string]string{"invocation_id": m.ToolInvocationId, "mnemonic": m.ActionMnemonic, "target": m.TargetId} {
		if value != "" && len(value) <= maxMetadataBytes && utf8.ValidString(value) {
			out[key] = value
		}
	}
	return out
}

const maxMetadataBytes = 1024

// The project's sized keys can run to 2,000 entries, so only the gateway asks
// for them: Struo clients read the same capabilities and cap their size.
const capabilitiesSuffix = "/capabilities?sized_keys=1"

type operation struct {
	QueuedAtUnixUS int64 `json:"queued_at_unix_us"`
	// What the control plane waited on while the action was queued, in ms by
	// cause. Diagnostics only: logged on the action phases line.
	QueueWaitsMS map[string]int64 `json:"queue_waits_ms"`
	ID           string           `json:"id"`
	State        string           `json:"state"`
	Response     string           `json:"response"`
	Code         int32            `json:"code"`
	Message      string           `json:"message"`
	Image        string           `json:"image"`
	Done         bool             `json:"done"`
	// Set on successful results that the action cache should store.
	Cacheable   bool   `json:"cacheable"`
	ActionHash  string `json:"action_hash"`
	ActionSize  int64  `json:"action_size"`
	CASEndpoint string `json:"cas_endpoint"`
	Leases      bool   `json:"leases"`
	// Capabilities: the size keys the server sizes above a default VM.
	SizedKeys []string `json:"sized_keys"`
	// The VM that ran the action, for its record.
	SandboxID string `json:"sandbox_id"`
}

func (g *Gateway) call(ctx context.Context, method, account, project, suffix, auth string, body any) (operation, error) {
	var out operation
	b, err := json.Marshal(body)
	if err != nil {
		return out, err
	}
	u := g.URL + "/api/remote-execution/" + url.PathEscape(account) + "/" + url.PathEscape(project) + suffix
	r, err := http.NewRequestWithContext(ctx, method, u, bytes.NewReader(b))
	if err != nil {
		return out, err
	}
	r.Header.Set("Authorization", auth)
	r.Header.Set("Content-Type", "application/json")
	response, err := g.Client.Do(r)
	if err != nil {
		return out, status.Error(codes.Unavailable, "execution control plane unavailable")
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		code := codes.Unavailable
		switch response.StatusCode {
		case 400:
			code = codes.InvalidArgument
		case 401:
			code = codes.Unauthenticated
		case 403:
			code = codes.PermissionDenied
		case 404:
			code = codes.NotFound
		case 429:
			code = codes.ResourceExhausted
		}
		return out, status.Error(code, "execution request refused")
	}
	b, err = io.ReadAll(io.LimitReader(response.Body, 2*worker.MaxResponse+1))
	if err != nil || len(b) > 2*worker.MaxResponse {
		return out, status.Error(codes.ResourceExhausted, "control response too large")
	}
	if err = json.Unmarshal(b, &out); err != nil {
		return out, status.Error(codes.Internal, "invalid control response")
	}
	return out, nil
}

func (g *Gateway) GetCapabilities(ctx context.Context, r *re.GetCapabilitiesRequest) (*re.ServerCapabilities, error) {
	release, err := g.admit(ctx)
	if err != nil {
		return nil, err
	}
	defer release()
	account, auth, err := scope(ctx, r.InstanceName)
	if err != nil {
		return nil, err
	}
	op, err := g.call(ctx, http.MethodGet, account, r.InstanceName, capabilitiesSuffix, auth, nil)
	if err != nil {
		return nil, err
	}
	g.remember(account, r.InstanceName, op.CASEndpoint, op.Leases)
	g.setSized(account, r.InstanceName, op.SizedKeys)
	return &re.ServerCapabilities{LowApiVersion: &semver.SemVer{Major: 2}, HighApiVersion: &semver.SemVer{Major: 2, Minor: 3}, ExecutionCapabilities: &re.ExecutionCapabilities{ExecEnabled: true, DigestFunction: re.DigestFunction_SHA256, DigestFunctions: []re.DigestFunction_Value{re.DigestFunction_SHA256}}}, nil
}

// admit waits for one of the gateway's stream slots until the client gives
// up: a rejected Execute fails the Bazel build, while a waiting one only
// queues like an action the control plane has not started yet.
func (g *Gateway) admit(ctx context.Context) (func(), error) {
	select {
	case g.slots <- struct{}{}:
		g.metrics.streams.Inc()
		return func() { g.metrics.streams.Dec(); <-g.slots }, nil
	case <-ctx.Done():
		return nil, status.FromContextError(ctx.Err()).Err()
	}
}

func (g *Gateway) Execute(r *re.ExecuteRequest, s grpc.ServerStreamingServer[lro.Operation]) (err error) {
	release, err := g.admit(s.Context())
	if err != nil {
		return err
	}
	defer release()
	started, path, code := time.Now(), "server", codes.OK
	defer func() {
		if err != nil {
			code = status.Code(err)
		}
		g.metrics.executions.WithLabelValues(path, code.String()).Inc()
		g.metrics.duration.WithLabelValues(path).Observe(time.Since(started).Seconds())
	}()
	account, auth, err := scope(s.Context(), r.InstanceName)
	if err != nil {
		return err
	}
	if !worker.ValidDigest(r.ActionDigest) || (r.DigestFunction != re.DigestFunction_UNKNOWN && r.DigestFunction != re.DigestFunction_SHA256) {
		return status.Error(codes.InvalidArgument, "SHA-256 action digest required")
	}
	if r.ExecutionPolicy.GetPriority() != 0 || r.ResultsCachePolicy.GetPriority() != 0 {
		return status.Error(codes.InvalidArgument, "execution priorities are not supported")
	}
	if err = g.learnEndpoint(s.Context(), account, r.InstanceName, auth); err != nil {
		return err
	}
	inputs, action := g.prefetch(s.Context(), account, r.InstanceName, auth, r.ActionDigest)
	memory, explicit, err := g.memory(s.Context(), account, r.InstanceName, auth, r.ActionDigest, action)
	if err != nil {
		return err
	}
	record := newRecording(s.Context(), account, r.InstanceName, auth, r.ActionDigest, action, inputs, memory)
	// The server sizes the action from its earlier runs under this key.
	// Without the prefetched command there is none, and it runs at the size
	// it asks for.
	sizing := "auto"
	if action != nil {
		platform := action.Platform
		command := prefetchedCommand(inputs, action.CommandDigest)
		if platform == nil && command != nil {
			platform = command.Platform
		}
		if command != nil {
			record.sizeKey = worker.SizeKey(command, platform)
		}
		for _, p := range platform.GetProperties() {
			if p.Name == worker.SizingProperty {
				sizing = p.Value
			}
		}
	}
	// Leases hold VMs of the account's default size; take checks the action
	// fits one.
	if !g.isSized(account, r.InstanceName, record.sizeKey) {
		if op, ok := g.direct(s.Context(), account, r.InstanceName, auth, r, inputs, memory, explicit); ok {
			path, record.path = "lease", "lease"
			code, err = g.stream(s, account, r.InstanceName, auth, op, record)
			return err
		}
	}
	record.path = "scheduled"
	body := map[string]any{"hash": r.ActionDigest.Hash, "size": r.ActionDigest.SizeBytes, "skip_cache": r.SkipCacheLookup}
	if inputs != "" {
		body["inputs"] = inputs
	}
	// Always sent, so the size does not depend on the server's default
	// matching this gateway's while either is rolled out.
	body["memory_gb"] = memory
	// Without tuist-memory-gb the server picks the size, which task sizing
	// can take below memory_gb.
	body["memory_explicit"] = explicit
	if record.sizeKey != "" {
		body["size_key"] = record.sizeKey
	}
	if sizing == "off" {
		body["task_sizing"] = false
	}
	for key, value := range requestMetadata(s.Context()) {
		body[key] = value
	}
	op, err := g.call(s.Context(), http.MethodPost, account, r.InstanceName, "/operations", auth, body)
	if err != nil {
		return err
	}
	g.rememberAuthorization(auth, account, r.InstanceName)
	code, err = g.stream(s, account, r.InstanceName, auth, op, record)
	return err
}

func (g *Gateway) WaitExecution(r *re.WaitExecutionRequest, s grpc.ServerStreamingServer[lro.Operation]) error {
	release, err := g.admit(s.Context())
	if err != nil {
		return err
	}
	defer release()
	parts := strings.Split(r.Name, "/")
	if len(parts) != 6 || parts[0] != "accounts" || parts[2] != "projects" || parts[4] != "operations" || !uuid.MatchString(parts[5]) {
		return status.Error(codes.InvalidArgument, "invalid operation name")
	}
	account, auth, err := scope(s.Context(), parts[3])
	if err != nil {
		return err
	}
	if account != parts[1] {
		return status.Error(codes.PermissionDenied, "operation belongs to another account")
	}
	op, err := g.call(s.Context(), http.MethodGet, account, parts[3], "/operations/"+parts[5], auth, nil)
	if err != nil {
		return err
	}
	_, err = g.stream(s, account, parts[3], auth, op, nil)
	return err
}

// record observes the executed action's phases and sends its record; WaitExecution
// passes nil so a reconnecting client does not count the same action twice.
func (g *Gateway) stream(s grpc.ServerStreamingServer[lro.Operation], account, project, auth string, op operation, record *recording) (codes.Code, error) {
	if !uuid.MatchString(op.ID) {
		return codes.Unknown, status.Error(codes.Internal, "invalid operation id")
	}
	ctx, cancel := context.WithTimeout(s.Context(), 15*time.Minute)
	defer cancel()
	name := "accounts/" + account + "/projects/" + project + "/operations/" + op.ID
	last := ""
	legacyDelay := 100 * time.Millisecond
	var finished *re.ExecuteResponse
	for {
		stage := re.ExecutionStage_QUEUED
		if op.State == "executing" || op.State == "cleaning" {
			stage = re.ExecutionStage_EXECUTING
		}
		// A durable result can be delivered while deletion still holds the
		// account slot. Older servers omit Done and keep the original behavior.
		done := op.Done || op.State == "completed"
		if done {
			stage = re.ExecutionStage_COMPLETED
		}
		if op.State != last || done {
			meta, _ := anypb.New(&re.ExecuteOperationMetadata{Stage: stage})
			message := &lro.Operation{Name: name, Metadata: meta, Done: done}
			if done {
				response := &re.ExecuteResponse{Status: &rpc.Status{Code: op.Code, Message: op.Message}}
				if op.Response != "" {
					b, err := base64.StdEncoding.DecodeString(op.Response)
					if err != nil || len(b) > worker.MaxResponse {
						return codes.Unknown, status.Error(codes.Internal, "invalid execution result")
					}
					if err = proto.Unmarshal(b, response); err != nil {
						return codes.Unknown, status.Error(codes.Internal, "invalid execution protobuf")
					}
				}
				// Admission belongs to the durable operation, not this gateway's
				// stream lifetime or the guest's start time. Leave cached execution
				// metadata and older operations with unknown admission untouched.
				if op.QueuedAtUnixUS > 0 && !response.CachedResult && response.Result != nil {
					queued := timestamppb.New(time.UnixMicro(op.QueuedAtUnixUS))
					if queued.CheckValid() == nil {
						if response.Result.ExecutionMetadata == nil {
							response.Result.ExecutionMetadata = &re.ExecutedActionMetadata{}
						}
						response.Result.ExecutionMetadata.QueuedTimestamp = queued
					}
				}
				if record != nil && !response.CachedResult && response.Result != nil {
					g.metrics.observePhases(response.Result.ExecutionMetadata, op.QueueWaitsMS)
				}
				// Diagnostics only: neither the client nor the action cache keeps them.
				stripCASReads(response.GetResult().GetExecutionMetadata())
				// The usage sizes the action's next run; it goes to the server
				// with the action's record, never to the client.
				if usage, ok := worker.ReadUsage(response.GetResult().GetExecutionMetadata()); ok && record != nil {
					record.usage = &usage
					if usage.OOMKills > 0 && record.sizeKey != "" {
						g.markSized(account, project, record.sizeKey)
					}
				}
				worker.StripUsage(response.GetResult().GetExecutionMetadata())
				payload, _ := anypb.New(response)
				message.Result = &lro.Operation_Response{Response: payload}
				finished = response
			}
			if err := s.Send(message); err != nil {
				return codes.Unknown, err
			}
			last = op.State
			if done {
				g.publish(account, project, auth, op, message)
				g.record(record, op, finished)
				return codes.Code(op.Code), nil
			}
		}
		// The server subscribes before reading and waits for a durable state
		// change. Each bounded long poll reauthorizes the project credential;
		// reconnecting to another gateway never depends on local stream state.
		started := time.Now()
		next, err := g.call(ctx, http.MethodGet, account, project, "/operations/"+op.ID+"?after="+url.QueryEscape(op.State), auth, nil)
		if err != nil {
			return codes.Unknown, err
		}
		// During a rolling upgrade an older server may ignore the cursor.
		// Back off only for immediate unchanged responses, never completed work.
		if next.State == op.State && time.Since(started) < 50*time.Millisecond {
			select {
			case <-ctx.Done():
				return codes.Unknown, status.FromContextError(ctx.Err()).Err()
			case <-time.After(legacyDelay):
			}
			legacyDelay = min(2*legacyDelay, time.Second)
		} else {
			legacyDelay = 100 * time.Millisecond
		}
		op = next
	}
}

// publish stores a successful result in the action cache after the client
// already has it. A lost publication only costs a later cache miss, so it is
// bounded and best-effort: saturation and gateway shutdown drop it.
func (g *Gateway) publish(account, project, auth string, op operation, message *lro.Operation) {
	var response re.ExecuteResponse
	digest := &re.Digest{Hash: op.ActionHash, SizeBytes: op.ActionSize}
	if !op.Cacheable || !worker.ValidDigest(digest) || message.GetResponse().UnmarshalTo(&response) != nil {
		return
	}
	if response.Status.GetCode() != 0 || response.CachedResult || response.Result.GetExitCode() != 0 || response.Result == nil {
		return
	}
	select {
	case g.publications <- struct{}{}:
	default:
		g.metrics.publications.WithLabelValues("dropped").Inc()
		log.Printf("action cache publication dropped: too many pending")
		return
	}
	g.pending.Add(1)
	go func() {
		defer func() { <-g.publications; g.pending.Done() }()
		conn, err := g.conn(op.CASEndpoint)
		if err != nil {
			g.metrics.publications.WithLabelValues("failed").Inc()
			log.Printf("action cache publication failed: %v", status.Code(err))
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", auth, "x-tuist-account-handle", account))
		request := &re.UpdateActionResultRequest{InstanceName: project, ActionDigest: digest, ActionResult: response.Result, DigestFunction: re.DigestFunction_SHA256}
		if _, err = re.NewActionCacheClient(conn).UpdateActionResult(ctx, request); err != nil {
			g.metrics.publications.WithLabelValues("failed").Inc()
			log.Printf("action cache publication failed: %v", status.Code(err))
			return
		}
		g.metrics.publications.WithLabelValues("stored").Inc()
	}()
}

// The control plane configures a handful of CAS endpoints; connections to
// them are shared across actions.
func (g *Gateway) conn(endpoint string) (*grpc.ClientConn, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if conn, ok := g.conns[endpoint]; ok {
		return conn, nil
	}
	if len(g.conns) >= 64 {
		return nil, status.Error(codes.ResourceExhausted, "too many cache endpoints")
	}
	conn, err := g.Dial(endpoint)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, "invalid cache endpoint")
	}
	g.conns[endpoint] = conn
	return conn, nil
}

// Wait lets pending publications finish during shutdown, until ctx ends.
// It then sends the records of finished actions.
func (g *Gateway) Wait(ctx context.Context) {
	defer g.waitRecords(ctx)
	done := make(chan struct{})
	go func() { g.pending.Wait(); close(done) }()
	select {
	case <-done:
	case <-ctx.Done():
	}
}
