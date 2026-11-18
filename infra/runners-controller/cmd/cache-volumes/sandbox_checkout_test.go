package main

import (
	"archive/tar"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http/httptest"
	"os"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const sandboxNamespace = "tuist-sandboxes"

func sandboxdPodObject() *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: "sandboxd-x", Namespace: sandboxNamespace, Labels: map[string]string{"tuist.dev/sandboxd": "true"}},
		Spec:       corev1.PodSpec{NodeName: "node"},
		Status:     corev1.PodStatus{PodIP: "10.0.0.9", Phase: corev1.PodRunning},
	}
}

// sandboxAgent is checkoutAgent with this node's sandboxd Pod at 10.0.0.9.
func sandboxAgent(t *testing.T, grant map[string]any, ready bool) (*agent, *checkoutServer) {
	t.Helper()
	a, server := checkoutAgent(t, grant, ready)
	a.sandboxNamespace = sandboxNamespace
	if _, err := a.kube.CoreV1().Pods(sandboxNamespace).Create(context.Background(), sandboxdPodObject(), metav1.CreateOptions{}); err != nil {
		t.Fatal(err)
	}
	return a, server
}

func sandboxRequestBody(t *testing.T, pod string, grant map[string]any) []byte {
	t.Helper()
	withPath := map[string]any{"path": "/workspace/repo"}
	for key, value := range grant {
		withPath[key] = value
	}
	body, err := json.Marshal(map[string]any{"pod_name": pod, "grant": withPath})
	if err != nil {
		t.Fatal(err)
	}
	return body
}

func requestSandboxSeed(t *testing.T, a *agent, ip string, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest("POST", "/sandbox-checkout/seed", bytes.NewReader(body))
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	a.serve(w, req)
	return w
}

func requestSandboxExport(t *testing.T, a *agent, ip string, body []byte, archive []byte) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest("POST", "/sandbox-checkout/export", bytes.NewReader(append(append(body, '\n'), archive...)))
	req.RemoteAddr = ip + ":1234"
	w := httptest.NewRecorder()
	a.serve(w, req)
	return w
}

func answerError(w *httptest.ResponseRecorder) string {
	var answer struct {
		Error string `json:"error"`
	}
	_ = json.Unmarshal(w.Body.Bytes(), &answer)
	return answer.Error
}

func TestSandboxCheckoutAuthorizesOnlyThisNodesSandboxd(t *testing.T) {
	grant := checkoutGrantJSON(1)
	for name, tc := range map[string]struct {
		pod       func(*corev1.Pod)
		ip        string
		name      string
		namespace string
	}{
		"other address":  {ip: "10.0.0.10"},
		"runner pod":     {name: "runner", ip: "10.0.0.5"},
		"other node":     {pod: func(p *corev1.Pod) { p.Spec.NodeName = "elsewhere" }},
		"unlabelled":     {pod: func(p *corev1.Pod) { p.Labels = nil }},
		"not running":    {pod: func(p *corev1.Pod) { p.Status.Phase = corev1.PodPending }},
		"deleting":       {pod: func(p *corev1.Pod) { now := metav1.Now(); p.DeletionTimestamp = &now }},
		"not configured": {namespace: "-"},
	} {
		t.Run(name, func(t *testing.T) {
			a, server := checkoutAgent(t, grant, true)
			installMaster(t, a)
			a.sandboxNamespace = sandboxNamespace
			if tc.namespace == "-" {
				a.sandboxNamespace = ""
			}
			pod := sandboxdPodObject()
			if tc.pod != nil {
				tc.pod(pod)
			}
			if _, err := a.kube.CoreV1().Pods(sandboxNamespace).Create(context.Background(), pod, metav1.CreateOptions{}); err != nil {
				t.Fatal(err)
			}
			ip, podName := "10.0.0.9", "sandboxd-x"
			if tc.ip != "" {
				ip = tc.ip
			}
			if tc.name != "" {
				podName = tc.name
			}
			body := sandboxRequestBody(t, podName, grant)
			if w := requestSandboxSeed(t, a, ip, body); w.Code != 403 {
				t.Fatalf("seed: %d %s", w.Code, w.Body)
			}
			if w := requestSandboxExport(t, a, ip, body, checkoutArchive(t)); w.Code != 403 {
				t.Fatalf("export: %d %s", w.Code, w.Body)
			}
			if len(server.reports) != 0 || a.checkouts.Queued() != 0 {
				t.Fatalf("a refused caller reported %v or queued %d", server.reports, a.checkouts.Queued())
			}
		})
	}
}

func TestSandboxSeedColdReportsTheUseAndQueuesARestore(t *testing.T) {
	a, server := sandboxAgent(t, checkoutGrantJSON(3), true)
	w := requestSandboxSeed(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", checkoutGrantJSON(3)))
	if w.Code != 404 || answerError(w) != "cold" {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	if len(server.reports) != 1 || server.reports[0]["id"] != checkoutUse || server.reports[0]["state"] != "deleted" || server.reports[0]["warm"] != false {
		t.Fatalf("reports %v", server.reports)
	}
	task, ok := a.checkouts.Pending(checkoutScope)
	if !ok || task.Export != "" || task.BaseGeneration != 3 || task.Use != checkoutUse {
		t.Fatalf("restore %+v %v", task, ok)
	}
}

func TestSandboxSeedColdWithoutAHeadQueuesNothing(t *testing.T) {
	a, server := sandboxAgent(t, checkoutGrantJSON(0), true)
	w := requestSandboxSeed(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", checkoutGrantJSON(0)))
	if w.Code != 404 || answerError(w) != "cold" || len(server.reports) != 1 || a.checkouts.Queued() != 0 {
		t.Fatalf("%d %s %v %d", w.Code, w.Body, server.reports, a.checkouts.Queued())
	}
}

func TestSandboxSeedOnAHostWithoutCheckoutsEndsTheUse(t *testing.T) {
	a, server := sandboxAgent(t, checkoutGrantJSON(1), false)
	installMaster(t, a)
	w := requestSandboxSeed(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", checkoutGrantJSON(1)))
	if w.Code != 503 || len(server.reports) != 1 || server.reports[0]["warm"] != false {
		t.Fatalf("%d %s %v", w.Code, w.Body, server.reports)
	}
}

// imageCommands fakes losetup and mount: a clone attached at a mount point
// holds the repository a master would.
type imageCommands struct {
	mu    sync.Mutex
	calls [][]string
}

func (c *imageCommands) run(_ context.Context, _ string, _ []string, name string, args ...string) ([]byte, error) {
	c.mu.Lock()
	c.calls = append(c.calls, append([]string{name}, args...))
	c.mu.Unlock()
	switch {
	case name == "cp":
		return nil, os.WriteFile(args[len(args)-1], []byte("clone"), 0o600)
	case name == "losetup" && slices.Contains(args, "--find"):
		return []byte("/dev/loop7\n"), nil
	case name == "mount":
		repo := filepath.Join(args[len(args)-1], "checkout")
		if err := os.MkdirAll(filepath.Join(repo, ".git", "objects"), 0o755); err != nil {
			return nil, err
		}
		if err := os.WriteFile(filepath.Join(repo, ".git", "HEAD"), []byte("ref: refs/heads/main\n"), 0o644); err != nil {
			return nil, err
		}
		if err := os.WriteFile(filepath.Join(repo, "build.sh"), []byte("#!/bin/sh\n"), 0o755); err != nil {
			return nil, err
		}
		return nil, os.Symlink("/etc/passwd", filepath.Join(repo, "link"))
	}
	return nil, nil
}

func TestSandboxSeedStreamsAReadOnlyCloneOfTheMaster(t *testing.T) {
	a, server := sandboxAgent(t, checkoutGrantJSON(1), true)
	installMaster(t, a)
	commands := &imageCommands{}
	a.checkouts.Images = &cachevolumes.Ext4CheckoutImages{Run: commands.run}
	w := requestSandboxSeed(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", checkoutGrantJSON(1)))
	if w.Code != 200 || w.Header().Get("Content-Type") != "application/x-tar" {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	entries := map[string]*tar.Header{}
	archive := tar.NewReader(bytes.NewReader(w.Body.Bytes()))
	for {
		header, err := archive.Next()
		if errors.Is(err, io.EOF) {
			break
		}
		if err != nil {
			t.Fatal(err)
		}
		entries[header.Name] = header
	}
	if len(entries) != 5 || entries[".git/"].Typeflag != tar.TypeDir || entries[".git/HEAD"].Size != int64(len("ref: refs/heads/main\n")) ||
		entries["build.sh"].Mode != 0o755 || entries["link"].Typeflag != tar.TypeSymlink || entries["link"].Linkname != "/etc/passwd" ||
		entries["build.sh"].Uid != 0 || entries["build.sh"].Uname != "" {
		t.Fatalf("entries %v", entries)
	}
	var attached bool
	for _, call := range commands.calls {
		if call[0] == "losetup" && slices.Contains(call, "--find") {
			attached = slices.Contains(call, "--read-only")
		}
		if call[0] == "mount" && !strings.Contains(strings.Join(call, " "), ",ro") {
			t.Fatalf("mounted read-write: %v", call)
		}
	}
	if !attached {
		t.Fatalf("the clone was not attached read-only: %v", commands.calls)
	}
	if left, _ := filepath.Glob(filepath.Join(a.checkouts.Root, sandboxSeedsDir, "*")); len(left) != 0 {
		t.Fatalf("seed clone left behind: %v", left)
	}
	if len(server.reports) != 1 || server.reports[0]["id"] != checkoutUse || server.reports[0]["state"] != "deleted" || server.reports[0]["warm"] != true {
		t.Fatalf("reports %v", server.reports)
	}
}

func TestSandboxSeedsAreBounded(t *testing.T) {
	a, server := sandboxAgent(t, checkoutGrantJSON(1), true)
	installMaster(t, a)
	a.sandboxSeeds = make(chan struct{}, 1)
	a.sandboxSeeds <- struct{}{}
	w := requestSandboxSeed(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", checkoutGrantJSON(1)))
	if w.Code != 503 || answerError(w) != "busy" || len(server.reports) != 1 {
		t.Fatalf("%d %s %v", w.Code, w.Body, server.reports)
	}
}

func TestSandboxExportLandsInIncomingAndIsQueued(t *testing.T) {
	a, server := sandboxAgent(t, checkoutGrantJSON(1), true)
	w := requestSandboxExport(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", checkoutGrantJSON(1)), checkoutArchive(t))
	if w.Code != 202 {
		t.Fatalf("%d %s", w.Code, w.Body)
	}
	dst := a.checkouts.Incoming("sandbox-" + checkoutUse)
	if head, err := os.ReadFile(filepath.Join(dst, "head")); err != nil || string(head) != checkoutCommit+"\n" {
		t.Fatalf("export head %q %v", head, err)
	}
	task, ok := a.checkouts.Pending(checkoutScope)
	if !ok || task.Export != dst || task.Use != checkoutUse || task.Commit != checkoutCommit || !task.DefaultBranchJob || task.UID != 1000 {
		t.Fatalf("queued %+v %v", task, ok)
	}
	if len(server.reports) != 0 {
		t.Fatalf("an export reported the use: %v", server.reports)
	}
}

func TestSandboxExportRefusals(t *testing.T) {
	t.Run("invalid export", func(t *testing.T) {
		a, _ := sandboxAgent(t, checkoutGrantJSON(1), true)
		var buffer bytes.Buffer
		archive := tar.NewWriter(&buffer)
		_ = archive.WriteHeader(&tar.Header{Name: "../escape", Mode: 0o644, Size: 1, Typeflag: tar.TypeReg})
		_, _ = archive.Write([]byte("x"))
		_ = archive.Close()
		w := requestSandboxExport(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", checkoutGrantJSON(1)), buffer.Bytes())
		if w.Code != 400 || a.checkouts.Queued() != 0 {
			t.Fatalf("%d %s", w.Code, w.Body)
		}
		if _, err := os.Stat(a.checkouts.Incoming("sandbox-" + checkoutUse)); !os.IsNotExist(err) {
			t.Fatalf("a refused export was kept: %v", err)
		}
	})
	t.Run("invalid use", func(t *testing.T) {
		a, _ := sandboxAgent(t, checkoutGrantJSON(1), true)
		grant := checkoutGrantJSON(1)
		grant["id"] = "../../x"
		if w := requestSandboxExport(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", grant), checkoutArchive(t)); w.Code != 400 {
			t.Fatalf("%d %s", w.Code, w.Body)
		}
	})
	t.Run("busy", func(t *testing.T) {
		a, _ := sandboxAgent(t, checkoutGrantJSON(1), true)
		a.exports = make(chan struct{}, 1)
		a.exports <- struct{}{}
		if w := requestSandboxExport(t, a, "10.0.0.9", sandboxRequestBody(t, "sandboxd-x", checkoutGrantJSON(1)), checkoutArchive(t)); w.Code != 503 || answerError(w) != "busy" {
			t.Fatalf("%d %s", w.Code, w.Body)
		}
	})
}
