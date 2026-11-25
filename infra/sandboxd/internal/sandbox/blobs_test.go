package sandbox

import (
	"testing"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

func TestExecutionScopeComesOnlyFromActionExecs(t *testing.T) {
	request := `{"endpoint":"grpc://kura.kura.svc:4000","account":"tuist","instance":"kura","hash":"h","size":1}`
	action := protocol.ExecArgs{Cmd: []string{executorPath}, Env: map[string]string{"SBX_EXECUTION_TOKEN": "t", "SBX_EXECUTION_REQUEST": request}}
	scope, ok := executionScope(action)
	if !ok || scope.Endpoint != "grpc://kura.kura.svc:4000" || scope.Account != "tuist" || scope.Instance != "kura" || scope.Token != "t" {
		t.Fatalf("action exec: %+v %v", scope, ok)
	}
	for name, args := range map[string]protocol.ExecArgs{
		"preparation": {Cmd: []string{executorPath, "--prepare-cas", "grpc://kura.kura.svc:4000"}, Env: action.Env},
		"no token":    {Cmd: action.Cmd, Env: map[string]string{"SBX_EXECUTION_REQUEST": request}},
		"other host":  {Cmd: action.Cmd, Env: map[string]string{"SBX_EXECUTION_TOKEN": "t", "SBX_EXECUTION_REQUEST": `{"endpoint":"http://169.254.169.254","instance":"kura"}`}},
		"shell":       {Cmd: []string{"/bin/sh", "-c", executorPath}, Env: action.Env},
	} {
		if _, ok := executionScope(args); ok {
			t.Errorf("%s: served blobs", name)
		}
	}
}

func TestClaimedExecScopeIsTheServersPin(t *testing.T) {
	pin := &protocol.ExecutionScope{Endpoint: "grpc://kura.kura.svc:4000", Account: "tuist", Instance: "kura"}
	claimed := func(request string, pin *protocol.ExecutionScope) protocol.ExecArgs {
		return protocol.ExecArgs{
			Cmd:   []string{executorPath},
			Env:   map[string]string{"SBX_EXECUTION_TOKEN": "t", "SBX_EXECUTION_REQUEST": request},
			Claim: &protocol.ClaimArgs{Env: "SBX_EXECUTION_REQUEST", Scope: pin},
		}
	}
	// Handles are case-insensitive; the cache keys on the server's spelling.
	scope, ok := executionScope(claimed(`{"endpoint":"grpc://kura.kura.svc:4000","account":"Tuist","instance":"KURA"}`, pin))
	if !ok || scope.Account != "tuist" || scope.Instance != "kura" || scope.Token != "t" {
		t.Fatalf("pinned scope: %+v %v", scope, ok)
	}
	for name, args := range map[string]protocol.ExecArgs{
		"other account":  claimed(`{"endpoint":"grpc://kura.kura.svc:4000","account":"victim","instance":"kura"}`, pin),
		"other instance": claimed(`{"endpoint":"grpc://kura.kura.svc:4000","account":"tuist","instance":"app"}`, pin),
		"other endpoint": claimed(`{"endpoint":"grpc://other:4000","account":"tuist","instance":"kura"}`, pin),
		"no pin":         claimed(`{"endpoint":"grpc://kura.kura.svc:4000","account":"tuist","instance":"kura"}`, nil),
	} {
		if scope, ok := executionScope(args); ok {
			t.Errorf("%s: node cache scope %+v", name, scope)
		}
	}
}
