// Package admin is the unauthenticated bring-up HTTP API (ADMIN_ADDR). It
// exposes the same operations as the server WebSocket as plain JSON.
package admin

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/sandbox"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
)

type Backend interface {
	sandbox.Operations
	List() []protocol.SandboxInfo
	Templates() []protocol.TemplateInfo
	BuildTemplate(ctx context.Context, name, tag string, shape template.Shape) error
}

type createRequest struct {
	ID          string `json:"id"`
	Template    string `json:"template"`
	TemplateTag string `json:"template_tag"`
	VCPUs       int    `json:"vcpus"`
	MemoryMB    int    `json:"memory_mb"`
	WorkspaceGB int    `json:"workspace_gb"`
	Hostname    string `json:"hostname"`
}

type execRequest struct {
	Cmd       []string          `json:"cmd"`
	Env       map[string]string `json:"env"`
	Cwd       string            `json:"cwd"`
	TimeoutMs int64             `json:"timeout_ms"`
}

type execResponse struct {
	Stdout     string `json:"stdout"`
	Stderr     string `json:"stderr"`
	ExitCode   int    `json:"exit_code"`
	DurationMs int64  `json:"duration_ms"`
}

type buildRequest struct {
	VCPUs    int `json:"vcpus"`
	MemoryMB int `json:"memory_mb"`
}

func NewHandler(backend Backend, log *slog.Logger) http.Handler {
	if log == nil {
		log = slog.Default()
	}
	h := &handler{backend: backend, log: log}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusOK) })
	mux.HandleFunc("GET /v1/sandboxes", h.list)
	mux.HandleFunc("POST /v1/sandboxes", h.create)
	mux.HandleFunc("GET /v1/sandboxes/{id}", h.status)
	mux.HandleFunc("POST /v1/sandboxes/{id}/pause", h.pause)
	mux.HandleFunc("POST /v1/sandboxes/{id}/resume", h.resume)
	mux.HandleFunc("POST /v1/sandboxes/{id}/delete", h.delete)
	mux.HandleFunc("DELETE /v1/sandboxes/{id}", h.delete)
	mux.HandleFunc("POST /v1/sandboxes/{id}/exec", h.exec)
	mux.HandleFunc("POST /v1/sandboxes/{id}/worker/start", h.startWorker)
	mux.HandleFunc("POST /v1/sandboxes/{id}/worker/stop", h.stopWorker)
	mux.HandleFunc("GET /v1/templates", h.templates)
	mux.HandleFunc("POST /v1/templates/{name}/{tag}/build", h.build)
	return mux
}

type handler struct {
	backend Backend
	log     *slog.Logger
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, err error) {
	status := http.StatusInternalServerError
	switch {
	case errors.Is(err, sandbox.ErrNotFound):
		status = http.StatusNotFound
	case errors.Is(err, sandbox.ErrAlreadyExists), errors.Is(err, sandbox.ErrBusy), errors.Is(err, sandbox.ErrNotRunning),
		errors.Is(err, sandbox.ErrNotPaused), errors.Is(err, sandbox.ErrNoWorker), errors.Is(err, sandbox.ErrWorkerRunning):
		status = http.StatusConflict
	case errors.Is(err, errBadRequest):
		status = http.StatusBadRequest
	}
	writeJSON(w, status, map[string]string{"error": err.Error()})
}

var errBadRequest = errors.New("bad request")

func decode(r *http.Request, v any) error {
	if r.Body == nil {
		return nil
	}
	dec := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 4<<20))
	if err := dec.Decode(v); err != nil {
		if errors.Is(err, errEOF()) {
			return nil
		}
		return fmt.Errorf("%w: %v", errBadRequest, err)
	}
	return nil
}

func errEOF() error { return errEOFValue }

var errEOFValue = errors.New("EOF")

func (h *handler) list(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"sandboxes": h.backend.List()})
}

func (h *handler) create(w http.ResponseWriter, r *http.Request) {
	var req createRequest
	if err := decode(r, &req); err != nil {
		writeError(w, err)
		return
	}
	id := req.ID
	if id == "" {
		id = newID()
	}
	res, err := h.backend.Create(r.Context(), protocol.CreateArgs{
		SandboxID: id, Template: req.Template, TemplateTag: req.TemplateTag, VCPUs: req.VCPUs,
		MemoryMB: req.MemoryMB, WorkspaceGB: req.WorkspaceGB, Hostname: req.Hostname,
	})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"id": id, "boot_ms": res.BootMs})
}

func (h *handler) status(w http.ResponseWriter, r *http.Request) {
	info, err := h.backend.Status(r.Context(), r.PathValue("id"))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, info)
}

func (h *handler) pause(w http.ResponseWriter, r *http.Request) {
	res, err := h.backend.Pause(r.Context(), r.PathValue("id"))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (h *handler) resume(w http.ResponseWriter, r *http.Request) {
	res, err := h.backend.Resume(r.Context(), r.PathValue("id"))
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (h *handler) delete(w http.ResponseWriter, r *http.Request) {
	if err := h.backend.Delete(r.Context(), r.PathValue("id")); err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{})
}

func (h *handler) exec(w http.ResponseWriter, r *http.Request) {
	var req execRequest
	if err := decode(r, &req); err != nil {
		writeError(w, err)
		return
	}
	if len(req.Cmd) == 0 {
		writeError(w, fmt.Errorf("%w: cmd is required", errBadRequest))
		return
	}
	var mu sync.Mutex
	var stdout, stderr bytes.Buffer
	res, err := h.backend.Exec(r.Context(), protocol.ExecArgs{SandboxID: r.PathValue("id"), Cmd: req.Cmd, Env: req.Env, Cwd: req.Cwd, TimeoutMs: req.TimeoutMs},
		func(stream string, data []byte) {
			mu.Lock()
			defer mu.Unlock()
			if stream == "stderr" {
				stderr.Write(data)
			} else {
				stdout.Write(data)
			}
		})
	if err != nil {
		writeError(w, err)
		return
	}
	mu.Lock()
	defer mu.Unlock()
	writeJSON(w, http.StatusOK, execResponse{Stdout: stdout.String(), Stderr: stderr.String(), ExitCode: res.ExitCode, DurationMs: res.DurationMs})
}

func (h *handler) startWorker(w http.ResponseWriter, r *http.Request) {
	var req struct {
		Env map[string]string `json:"env"`
	}
	if err := decode(r, &req); err != nil {
		writeError(w, err)
		return
	}
	res, err := h.backend.StartWorker(r.Context(), protocol.StartWorkerArgs{SandboxID: r.PathValue("id"), Env: req.Env})
	if err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (h *handler) stopWorker(w http.ResponseWriter, r *http.Request) {
	if err := h.backend.StopWorker(r.Context(), r.PathValue("id")); err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{})
}

func (h *handler) templates(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"templates": h.backend.Templates()})
}

func (h *handler) build(w http.ResponseWriter, r *http.Request) {
	var req buildRequest
	if err := decode(r, &req); err != nil {
		writeError(w, err)
		return
	}
	shape := template.Shape{VCPUs: req.VCPUs, MemoryMB: req.MemoryMB}
	if err := shape.Validate(); err != nil {
		writeError(w, fmt.Errorf("%w: %v", errBadRequest, err))
		return
	}
	started := time.Now()
	if err := h.backend.BuildTemplate(r.Context(), r.PathValue("name"), r.PathValue("tag"), shape); err != nil {
		writeError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"shape": shape.String(), "build_ms": time.Since(started).Milliseconds()})
}
