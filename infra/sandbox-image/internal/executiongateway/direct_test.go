package executiongateway

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/proto"
)

func jwt(exp time.Time) string {
	payload := base64.RawURLEncoding.EncodeToString(fmt.Appendf(nil, `{"exp":%d}`, exp.Unix()))
	return "Bearer e30." + payload + ".signature"
}

type directLab struct {
	t          *testing.T
	gateway    *Gateway
	client     re.ExecutionClient
	operations atomic.Int32
	claims     chan map[string]any
	claimCode  int
}

func newDirectLab(t *testing.T, claimCode int) *directLab {
	lab := &directLab{t: t, claims: make(chan map[string]any, 4), claimCode: claimCode}
	g := New("https://control.example")
	g.Dial = func(string) (*grpc.ClientConn, error) { return nil, errors.New("no cache in this test") }
	var leased atomic.Bool
	g.Direct.Transport = transport(func(r *http.Request) (*http.Response, error) {
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		lab.claims <- body
		if r.URL.String() != "http://node.test/v1/claims" || lab.claimCode != http.StatusOK {
			return response(http.StatusNotFound, "no such claim"), nil
		}
		b, _ := proto.Marshal(&re.ExecuteResponse{Result: &re.ActionResult{ExitCode: 7}})
		stdout, _ := json.Marshal(map[string]any{"response": base64.StdEncoding.EncodeToString(b), "cacheable": false})
		out, _ := json.Marshal(map[string]any{"exit_code": 0, "stdout": stdout})
		return response(http.StatusOK, string(out)), nil
	})
	lab.gateway = g
	lab.client, _ = gatewayWith(t, g, func(r *http.Request) (*http.Response, error) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/capabilities"):
			return response(200, `{"cas_endpoint":"grpcs://cache.example","leases":true}`), nil
		case strings.HasSuffix(r.URL.Path, "/leases"):
			if leased.Swap(true) {
				time.Sleep(50 * time.Millisecond)
				return response(http.StatusNoContent, ""), nil
			}
			nonce := base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{9}, 32))
			return response(200, `{"sandbox_id":"vm-1","endpoint":"http://node.test","nonce":"`+nonce+`","image":"sha-x","cas_endpoint":"grpcs://cache.example","expires_in_ms":25000}`), nil
		default:
			lab.operations.Add(1)
			b, _ := proto.Marshal(&re.ExecuteResponse{Result: &re.ActionResult{ExitCode: 3}})
			return response(202, `{"id":"`+id+`","state":"completed","done":true,"response":"`+base64.StdEncoding.EncodeToString(b)+`"}`), nil
		}
	})
	return lab
}

func (lab *directLab) execute(auth string) int32 {
	lab.t.Helper()
	ctx := metadata.NewOutgoingContext(context.Background(), metadata.Pairs("authorization", auth, "x-tuist-account-handle", "tuist"))
	stream, err := lab.client.Execute(ctx, &re.ExecuteRequest{InstanceName: "app", ActionDigest: &re.Digest{Hash: strings.Repeat("a", 64), SizeBytes: 5}})
	if err != nil {
		lab.t.Fatal(err)
	}
	op, err := stream.Recv()
	var result re.ExecuteResponse
	if err != nil || !op.Done || op.GetResponse().UnmarshalTo(&result) != nil {
		lab.t.Fatalf("result: %v %v", op, err)
	}
	return result.Result.GetExitCode()
}

func (lab *directLab) awaitLease() {
	lab.t.Helper()
	for range 200 {
		lab.gateway.mu.Lock()
		p := lab.gateway.projects["tuist/app"]
		held := p != nil && p.lease != nil
		lab.gateway.mu.Unlock()
		if held {
			return
		}
		time.Sleep(5 * time.Millisecond)
	}
	lab.t.Fatal("no lease")
}

func (lab *directLab) capabilities(auth string) {
	lab.t.Helper()
	_, capabilities := gatewayWith(lab.t, lab.gateway, lab.gateway.Client.Transport.(transport))
	ctx := metadata.NewOutgoingContext(context.Background(), metadata.Pairs("authorization", auth, "x-tuist-account-handle", "tuist"))
	if _, err := capabilities.GetCapabilities(ctx, &re.GetCapabilitiesRequest{InstanceName: "app"}); err != nil {
		lab.t.Fatal(err)
	}
}

func TestLeasedVMRunsTheNextActionDirectly(t *testing.T) {
	lab := newDirectLab(t, http.StatusOK)
	auth := jwt(time.Now().Add(time.Hour))
	lab.capabilities(auth)

	if code := lab.execute(auth); code != 3 || lab.operations.Load() != 1 {
		t.Fatalf("the first action authorizes through the control plane: exit %d, operations %d", code, lab.operations.Load())
	}
	lab.awaitLease()
	if code := lab.execute(auth); code != 7 || lab.operations.Load() != 1 {
		t.Fatalf("the leased VM did not run the action: exit %d, operations %d", code, lab.operations.Load())
	}
	claim := <-lab.claims
	nonce, _ := base64.StdEncoding.DecodeString(claim["nonce"].(string))
	if claim["sandbox_id"] != "vm-1" || !bytes.Equal(nonce, bytes.Repeat([]byte{9}, 32)) {
		t.Fatalf("claim %v", claim)
	}
	var request map[string]any
	_ = json.Unmarshal([]byte(claim["value"].(string)), &request)
	if request["hash"] != strings.Repeat("a", 64) || request["size"] != float64(5) || request["account"] != "tuist" || request["instance"] != "app" ||
		request["image"] != "sha-x" || request["endpoint"] != "grpcs://cache.example" {
		t.Fatalf("request %v", request)
	}
}

func TestRefusedClaimFallsBackToTheControlPlane(t *testing.T) {
	lab := newDirectLab(t, http.StatusNotFound)
	auth := jwt(time.Now().Add(time.Hour))
	lab.capabilities(auth)
	lab.execute(auth)
	lab.awaitLease()

	if code := lab.execute(auth); code != 3 || lab.operations.Load() != 2 || len(lab.claims) != 1 {
		t.Fatalf("exit %d, operations %d, claims %d", code, lab.operations.Load(), len(lab.claims))
	}
}

func TestOnlyCredentialsTheControlPlaneAcceptedUseLeases(t *testing.T) {
	lab := newDirectLab(t, http.StatusOK)
	auth := jwt(time.Now().Add(time.Hour))
	lab.capabilities(auth)
	lab.execute(auth)
	lab.awaitLease()

	for _, other := range []string{jwt(time.Now().Add(2 * time.Hour)), "Bearer opaque", jwt(time.Now().Add(-time.Minute))} {
		if code := lab.execute(other); code != 3 {
			t.Fatalf("%s used a lease: exit %d", other, code)
		}
	}
	if len(lab.claims) != 0 || lab.operations.Load() != 4 {
		t.Fatalf("claims %d, operations %d", len(lab.claims), lab.operations.Load())
	}
}
