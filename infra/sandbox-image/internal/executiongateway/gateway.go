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

	lro "cloud.google.com/go/longrunning/autogen/longrunningpb"
	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"github.com/bazelbuild/remote-apis/build/bazel/semver"
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
	Dial  func(endpoint string) (*grpc.ClientConn, error)
	slots chan struct{}

	publications chan struct{}
	pending      sync.WaitGroup
	mu           sync.Mutex
	conns        map[string]*grpc.ClientConn
	// Each project's cache endpoint, learned from capability checks.
	endpoints map[string]endpoint
}

type endpoint struct {
	url     string
	expires time.Time
}

func New(serverURL string) *Gateway {
	return &Gateway{URL: strings.TrimRight(serverURL, "/"), Client: &http.Client{Timeout: 10 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, Dial: worker.Dial, slots: make(chan struct{}, 128), publications: make(chan struct{}, 256), conns: map[string]*grpc.ClientConn{}, endpoints: map[string]endpoint{}}
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

type operation struct {
	QueuedAtUnixUS int64  `json:"queued_at_unix_us"`
	ID             string `json:"id"`
	State          string `json:"state"`
	Response       string `json:"response"`
	Code           int32  `json:"code"`
	Message        string `json:"message"`
	Image          string `json:"image"`
	Done           bool   `json:"done"`
	// Set on successful results that the action cache should store.
	Cacheable   bool   `json:"cacheable"`
	ActionHash  string `json:"action_hash"`
	ActionSize  int64  `json:"action_size"`
	CASEndpoint string `json:"cas_endpoint"`
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
	release, err := g.admit()
	if err != nil {
		return nil, err
	}
	defer release()
	account, auth, err := scope(ctx, r.InstanceName)
	if err != nil {
		return nil, err
	}
	op, err := g.call(ctx, http.MethodGet, account, r.InstanceName, "/capabilities", auth, nil)
	if err != nil {
		return nil, err
	}
	g.remember(account, r.InstanceName, op.CASEndpoint)
	return &re.ServerCapabilities{LowApiVersion: &semver.SemVer{Major: 2}, HighApiVersion: &semver.SemVer{Major: 2, Minor: 3}, ExecutionCapabilities: &re.ExecutionCapabilities{ExecEnabled: true, DigestFunction: re.DigestFunction_SHA256, DigestFunctions: []re.DigestFunction_Value{re.DigestFunction_SHA256}}}, nil
}

func (g *Gateway) admit() (func(), error) {
	select {
	case g.slots <- struct{}{}:
		return func() { <-g.slots }, nil
	default:
		return nil, status.Error(codes.ResourceExhausted, "too many execution streams")
	}
}

func (g *Gateway) Execute(r *re.ExecuteRequest, s grpc.ServerStreamingServer[lro.Operation]) error {
	release, err := g.admit()
	if err != nil {
		return err
	}
	defer release()
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
	body := map[string]any{"hash": r.ActionDigest.Hash, "size": r.ActionDigest.SizeBytes, "skip_cache": r.SkipCacheLookup}
	if inputs := g.prefetch(s.Context(), account, r.InstanceName, auth, r.ActionDigest); inputs != "" {
		body["inputs"] = inputs
	}
	op, err := g.call(s.Context(), http.MethodPost, account, r.InstanceName, "/operations", auth, body)
	if err != nil {
		return err
	}
	return g.stream(s, account, r.InstanceName, auth, op)
}

func (g *Gateway) WaitExecution(r *re.WaitExecutionRequest, s grpc.ServerStreamingServer[lro.Operation]) error {
	release, err := g.admit()
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
	return g.stream(s, account, parts[3], auth, op)
}

func (g *Gateway) stream(s grpc.ServerStreamingServer[lro.Operation], account, project, auth string, op operation) error {
	if !uuid.MatchString(op.ID) {
		return status.Error(codes.Internal, "invalid operation id")
	}
	ctx, cancel := context.WithTimeout(s.Context(), 15*time.Minute)
	defer cancel()
	name := "accounts/" + account + "/projects/" + project + "/operations/" + op.ID
	last := ""
	legacyDelay := 100 * time.Millisecond
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
						return status.Error(codes.Internal, "invalid execution result")
					}
					if err = proto.Unmarshal(b, response); err != nil {
						return status.Error(codes.Internal, "invalid execution protobuf")
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
				payload, _ := anypb.New(response)
				message.Result = &lro.Operation_Response{Response: payload}
			}
			if err := s.Send(message); err != nil {
				return err
			}
			last = op.State
			if done {
				g.publish(account, project, auth, op, message)
				return nil
			}
		}
		// The server subscribes before reading and waits for a durable state
		// change. Each bounded long poll reauthorizes the project credential;
		// reconnecting to another gateway never depends on local stream state.
		started := time.Now()
		next, err := g.call(ctx, http.MethodGet, account, project, "/operations/"+op.ID+"?after="+url.QueryEscape(op.State), auth, nil)
		if err != nil {
			return err
		}
		// During a rolling upgrade an older server may ignore the cursor.
		// Back off only for immediate unchanged responses, never completed work.
		if next.State == op.State && time.Since(started) < 50*time.Millisecond {
			select {
			case <-ctx.Done():
				return status.FromContextError(ctx.Err()).Err()
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
		log.Printf("action cache publication dropped: too many pending")
		return
	}
	g.pending.Add(1)
	go func() {
		defer func() { <-g.publications; g.pending.Done() }()
		conn, err := g.conn(op.CASEndpoint)
		if err != nil {
			log.Printf("action cache publication failed: %v", status.Code(err))
			return
		}
		ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer cancel()
		ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", auth, "x-tuist-account-handle", account))
		request := &re.UpdateActionResultRequest{InstanceName: project, ActionDigest: digest, ActionResult: response.Result, DigestFunction: re.DigestFunction_SHA256}
		if _, err = re.NewActionCacheClient(conn).UpdateActionResult(ctx, request); err != nil {
			log.Printf("action cache publication failed: %v", status.Code(err))
		}
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
func (g *Gateway) Wait(ctx context.Context) {
	done := make(chan struct{})
	go func() { g.pending.Wait(); close(done) }()
	select {
	case <-done:
	case <-ctx.Done():
	}
}
