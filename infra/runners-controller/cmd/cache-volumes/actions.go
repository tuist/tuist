package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

var errUnknownCaller = errors.New("not a runner pod on this node")

// runnerPods resolves a GitHub Actions cache request's source address to the
// live runner Pod on this node. Cache clients cannot add headers, so the
// address is the only proof; buildx and job containers egress as the Pod.
type runnerPods struct {
	kube            kubernetes.Interface
	namespace, node string
	mu              sync.Mutex
	byIP            map[string]cachevolumes.ActionsCaller
	listed          time.Time
}

func (p *runnerPods) caller(ctx context.Context, ip string) (cachevolumes.ActionsCaller, error) {
	p.mu.Lock()
	defer p.mu.Unlock()
	caller, ok := p.byIP[ip]
	// A Pod's address is reused only after its sandbox is gone, which takes far
	// longer than a listing lives.
	if ok && time.Since(p.listed) < 5*time.Second {
		return caller, nil
	}
	if time.Since(p.listed) < time.Second {
		if ok {
			return caller, nil
		}
		return cachevolumes.ActionsCaller{}, errUnknownCaller
	}
	pods, err := p.kube.CoreV1().Pods(p.namespace).List(ctx, metav1.ListOptions{
		LabelSelector: "tuist.dev/runner=true",
		FieldSelector: "spec.nodeName=" + p.node,
	})
	if err != nil {
		return cachevolumes.ActionsCaller{}, err
	}
	p.byIP = map[string]cachevolumes.ActionsCaller{}
	for _, pod := range pods.Items {
		if pod.Status.PodIP != "" && pod.Status.Phase == corev1.PodRunning && pod.DeletionTimestamp == nil && pod.Spec.NodeName == p.node {
			p.byIP[pod.Status.PodIP] = cachevolumes.ActionsCaller{PodName: pod.Name, PodUID: string(pod.UID)}
		}
	}
	p.listed = time.Now()
	if caller, ok = p.byIP[ip]; ok {
		return caller, nil
	}
	return cachevolumes.ActionsCaller{}, errUnknownCaller
}

// actionsIndex is the server's GitHub Actions cache index, which scopes every
// request by the job GitHub runs on the calling Pod. Every endpoint is
// idempotent, so requests go through DoServer.
type actionsIndex struct {
	url, node, tokenPath string
	client               *http.Client
	log                  *slog.Logger
}

func (i *actionsIndex) Lookup(ctx context.Context, caller cachevolumes.ActionsCaller, key string, restoreKeys []string, version string) (*cachevolumes.ActionsEntry, error) {
	var result struct {
		Entry *cachevolumes.ActionsEntry `json:"entry"`
	}
	if restoreKeys == nil {
		restoreKeys = []string{}
	}
	err := i.post(ctx, "lookup", map[string]any{"pod_name": caller.PodName, "pod_uid": caller.PodUID, "key": key, "restore_keys": restoreKeys, "version": version}, &result)
	return result.Entry, err
}

func (i *actionsIndex) Reserve(ctx context.Context, caller cachevolumes.ActionsCaller, id, key, version string) error {
	return i.post(ctx, "reserve", map[string]any{"pod_name": caller.PodName, "pod_uid": caller.PodUID, "id": id, "key": key, "version": version}, nil)
}

func (i *actionsIndex) Commit(ctx context.Context, id string, size int64, sha256 string) (cachevolumes.ActionsUpload, error) {
	var upload cachevolumes.ActionsUpload
	err := i.post(ctx, "commit", map[string]any{"id": id, "size_bytes": size, "sha256": sha256}, &upload)
	return upload, err
}

func (i *actionsIndex) Stored(ctx context.Context, id string) error {
	return i.post(ctx, "stored", map[string]any{"id": id}, nil)
}

// post asks the server and decodes its answer into result. A job GitHub has not
// reported yet (425) is asked again each second while ctx lasts.
func (i *actionsIndex) post(ctx context.Context, operation string, fields map[string]any, result any) error {
	fields["node_name"] = i.node
	body, _ := json.Marshal(fields)
	for {
		token, err := os.ReadFile(i.tokenPath)
		if err != nil {
			return err
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPost, i.url+"/"+operation, bytes.NewReader(body))
		if err != nil {
			return err
		}
		req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
		req.Header.Set("Content-Type", "application/json")
		resp, err := cachevolumes.DoServer(i.client, req, i.log)
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
			return cachevolumes.ErrConflict
		case status != http.StatusTooEarly:
			return fmt.Errorf("actions cache %s rejected: %d", operation, status)
		}
		select {
		case <-ctx.Done():
			return cachevolumes.ErrExecutionPending
		case <-time.After(time.Second):
		}
	}
}
