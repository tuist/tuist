package admin

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/sandbox"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

type fakeBackend struct {
	created []protocol.CreateArgs
	built   []string
}

func (f *fakeBackend) Create(ctx context.Context, args protocol.CreateArgs) (protocol.CreateResult, error) {
	f.created = append(f.created, args)
	return protocol.CreateResult{BootMs: 12}, nil
}
func (f *fakeBackend) Resume(ctx context.Context, id string) (protocol.ResumeResult, error) {
	if id == "missing" {
		return protocol.ResumeResult{}, sandbox.ErrNotFound
	}
	return protocol.ResumeResult{RestoreMs: 3}, nil
}
func (f *fakeBackend) Pause(ctx context.Context, id string) (protocol.PauseResult, error) {
	if id == "busy" {
		return protocol.PauseResult{}, sandbox.ErrBusy
	}
	return protocol.PauseResult{SnapshotMs: 4, MemBytes: 5}, nil
}
func (f *fakeBackend) Delete(ctx context.Context, id string) error { return nil }
func (f *fakeBackend) Exec(ctx context.Context, args protocol.ExecArgs, out vsock.OutputFunc) (protocol.ExecResult, error) {
	out("stdout", []byte("out\n"))
	out("stderr", []byte("err\n"))
	return protocol.ExecResult{ExitCode: 2, DurationMs: 9}, nil
}
func (f *fakeBackend) StartWorker(ctx context.Context, args protocol.StartWorkerArgs) (protocol.StartWorkerResult, error) {
	return protocol.StartWorkerResult{ExecID: "e1"}, nil
}
func (f *fakeBackend) StopWorker(ctx context.Context, id string) error { return errors.New("boom") }
func (f *fakeBackend) Status(ctx context.Context, id string) (protocol.SandboxInfo, error) {
	return protocol.SandboxInfo{ID: id, State: protocol.StateRunning}, nil
}
func (f *fakeBackend) List() []protocol.SandboxInfo {
	return []protocol.SandboxInfo{{ID: "a", State: protocol.StatePaused}}
}
func (f *fakeBackend) Templates() []protocol.TemplateInfo {
	return []protocol.TemplateInfo{{Name: "default", Tag: "t1", Ready: true, Shapes: []string{"2x4096"}}}
}
func (f *fakeBackend) BuildTemplate(ctx context.Context, name, tag string, shape template.Shape) error {
	f.built = append(f.built, name+"/"+tag+"/"+shape.String())
	return nil
}

func do(t *testing.T, srv *httptest.Server, method, path, body string) (int, map[string]any) {
	t.Helper()
	req, err := http.NewRequest(method, srv.URL+path, bytes.NewBufferString(body))
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, _ := io.ReadAll(resp.Body)
	var out map[string]any
	if len(data) > 0 {
		if err := json.Unmarshal(data, &out); err != nil {
			t.Fatalf("%s %s: bad json %q", method, path, data)
		}
	}
	return resp.StatusCode, out
}

func TestAdminAPI(t *testing.T) {
	backend := &fakeBackend{}
	srv := httptest.NewServer(NewHandler(backend, nil))
	defer srv.Close()

	status, out := do(t, srv, "POST", "/v1/sandboxes", `{"template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":10,"hostname":"h"}`)
	if status != http.StatusCreated || out["id"] == "" || out["boot_ms"] != float64(12) {
		t.Fatalf("create %d %v", status, out)
	}
	if len(backend.created) != 1 || backend.created[0].SandboxID != out["id"] || backend.created[0].VCPUs != 2 || backend.created[0].Hostname != "h" {
		t.Fatalf("create args %+v", backend.created)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes", `{"id":"custom","vcpus":2,"memory_mb":4096}`)
	if status != http.StatusCreated || out["id"] != "custom" {
		t.Fatalf("create with id %d %v", status, out)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes", `{bad json`)
	if status != http.StatusBadRequest {
		t.Fatalf("bad json %d %v", status, out)
	}

	status, out = do(t, srv, "GET", "/v1/sandboxes", "")
	if status != http.StatusOK || len(out["sandboxes"].([]any)) != 1 {
		t.Fatalf("list %d %v", status, out)
	}
	status, out = do(t, srv, "GET", "/v1/sandboxes/a", "")
	if status != http.StatusOK || out["state"] != "running" {
		t.Fatalf("status %d %v", status, out)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes/a/pause", "")
	if status != http.StatusOK || out["snapshot_ms"] != float64(4) || out["mem_bytes"] != float64(5) {
		t.Fatalf("pause %d %v", status, out)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes/busy/pause", "")
	if status != http.StatusConflict || !strings.Contains(out["error"].(string), "worker or exec") {
		t.Fatalf("busy pause %d %v", status, out)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes/missing/resume", "")
	if status != http.StatusNotFound {
		t.Fatalf("missing resume %d %v", status, out)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes/a/resume", "")
	if status != http.StatusOK || out["restore_ms"] != float64(3) {
		t.Fatalf("resume %d %v", status, out)
	}
	status, _ = do(t, srv, "POST", "/v1/sandboxes/a/delete", "")
	if status != http.StatusOK {
		t.Fatalf("delete %d", status)
	}
	status, _ = do(t, srv, "DELETE", "/v1/sandboxes/a", "")
	if status != http.StatusOK {
		t.Fatalf("DELETE %d", status)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes/a/exec", `{"cmd":["ls","-la"],"cwd":"/workspace","timeout_ms":1000}`)
	if status != http.StatusOK || out["stdout"] != "out\n" || out["stderr"] != "err\n" || out["exit_code"] != float64(2) || out["duration_ms"] != float64(9) {
		t.Fatalf("exec %d %v", status, out)
	}
	status, _ = do(t, srv, "POST", "/v1/sandboxes/a/exec", `{"cmd":[]}`)
	if status != http.StatusBadRequest {
		t.Fatalf("exec without cmd %d", status)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes/a/worker/start", `{"env":{"K":"V"}}`)
	if status != http.StatusOK || out["exec_id"] != "e1" {
		t.Fatalf("worker start %d %v", status, out)
	}
	status, out = do(t, srv, "POST", "/v1/sandboxes/a/worker/stop", "")
	if status != http.StatusInternalServerError || out["error"] != "boom" {
		t.Fatalf("worker stop %d %v", status, out)
	}
	status, out = do(t, srv, "GET", "/v1/templates", "")
	if status != http.StatusOK || len(out["templates"].([]any)) != 1 {
		t.Fatalf("templates %d %v", status, out)
	}
	status, out = do(t, srv, "POST", "/v1/templates/default/t1/build", `{"vcpus":4,"memory_mb":8192}`)
	if status != http.StatusOK || out["shape"] != "4x8192" {
		t.Fatalf("build %d %v", status, out)
	}
	if len(backend.built) != 1 || backend.built[0] != "default/t1/4x8192" {
		t.Fatalf("built %v", backend.built)
	}
	status, _ = do(t, srv, "POST", "/v1/templates/default/t1/build", `{"vcpus":0,"memory_mb":8192}`)
	if status != http.StatusBadRequest {
		t.Fatalf("bad shape %d", status)
	}
	status, _ = do(t, srv, "GET", "/healthz", "")
	if status != http.StatusOK {
		t.Fatalf("healthz %d", status)
	}
}
