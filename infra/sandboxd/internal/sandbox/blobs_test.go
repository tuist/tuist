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
