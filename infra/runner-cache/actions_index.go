package cachevolumes

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"time"
)

// ActionsServer is the server's GitHub Actions cache index, which scopes every
// request by the job GitHub runs on the calling Pod. Both hosts use it: the
// Linux agent and tart-kubelet. Every endpoint is idempotent, so requests go
// through DoServer.
type ActionsServer struct {
	// URL is the server's .../runners/cache-volumes/actions-cache.
	URL, Node string
	// Token returns the host's credential for the server.
	Token  func(context.Context) (string, error)
	Client *http.Client
	Log    *slog.Logger
}

func (s *ActionsServer) Lookup(ctx context.Context, caller ActionsCaller, key string, restoreKeys []string, version string) (*ActionsEntry, error) {
	var result struct {
		Entry *ActionsEntry `json:"entry"`
	}
	if restoreKeys == nil {
		restoreKeys = []string{}
	}
	err := s.post(ctx, "lookup", map[string]any{"pod_name": caller.PodName, "pod_uid": caller.PodUID, "key": key, "restore_keys": restoreKeys, "version": version}, &result)
	return result.Entry, err
}

func (s *ActionsServer) Enabled(ctx context.Context, caller ActionsCaller) (bool, error) {
	var result struct {
		Enabled bool `json:"enabled"`
	}
	err := s.post(ctx, "enabled", map[string]any{"pod_name": caller.PodName, "pod_uid": caller.PodUID}, &result)
	return result.Enabled && err == nil, err
}

func (s *ActionsServer) Reserve(ctx context.Context, caller ActionsCaller, id, key, version string) error {
	return s.post(ctx, "reserve", map[string]any{"pod_name": caller.PodName, "pod_uid": caller.PodUID, "id": id, "key": key, "version": version}, nil)
}

func (s *ActionsServer) Upload(ctx context.Context, id string, size int64, sha256 string) (ActionsUpload, error) {
	var upload ActionsUpload
	err := s.post(ctx, "upload", map[string]any{"id": id, "size_bytes": size, "sha256": sha256}, &upload)
	return upload, err
}

func (s *ActionsServer) Commit(ctx context.Context, id string) error {
	return s.post(ctx, "commit", map[string]any{"id": id}, nil)
}

// post asks the server and decodes its answer into result. A job GitHub has not
// reported yet (425) is asked again each second while ctx lasts.
func (s *ActionsServer) post(ctx context.Context, operation string, fields map[string]any, result any) error {
	fields["node_name"] = s.Node
	body, _ := json.Marshal(fields)
	for {
		token, err := s.Token(ctx)
		if err != nil {
			return err
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, s.URL+"/"+operation, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		resp, err := DoServer(s.Client, req, s.Log)
		if err != nil {
			return err
		}
		status := resp.StatusCode
		if status == http.StatusOK && result != nil {
			err = json.NewDecoder(io.LimitReader(resp.Body, 64<<10)).Decode(result)
		}
		resp.Body.Close()
		switch {
		case status == http.StatusOK || status == http.StatusNoContent:
			return err
		case status == http.StatusConflict:
			return ErrConflict
		case status != http.StatusTooEarly:
			return fmt.Errorf("actions cache %s rejected: %d", operation, status)
		}
		select {
		case <-ctx.Done():
			return ErrExecutionPending
		case <-time.After(time.Second):
		}
	}
}
