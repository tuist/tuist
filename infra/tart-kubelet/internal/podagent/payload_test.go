package podagent

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/envresolver"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/payload"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

const testPayloadDigest = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func payloadReconciler(t *testing.T, fetcher *payload.Fetcher) (*Reconciler, string) {
	t.Helper()
	dir := t.TempDir()
	calls := filepath.Join(dir, "calls")
	bin := filepath.Join(dir, "tart")
	script := `#!/bin/sh
echo "$@" >> ` + calls + `
case "$1" in
  get)
    case "$2" in
      tuist-golden-*) echo '{}' ;;
      *) echo "VM does not exist" >&2; exit 1 ;;
    esac ;;
  run) exit 1 ;;
esac
exit 0
`
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return &Reconciler{
		Tart:     &tart.Client{Binary: bin, UserDataDir: filepath.Join(dir, "userdata"), LogDir: filepath.Join(dir, "logs")},
		Resolver: &envresolver.Resolver{},
		Store:    NewStore(),
		Payloads: fetcher,
		NodeName: "mini-1",
	}, calls
}

func payloadPod(ref string) *corev1.Pod {
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "runner-0", UID: "runner-uid"},
		Spec:       corev1.PodSpec{Containers: []corev1.Container{{Name: "runner", Image: "ghcr.io/tuist/tuist-runner:macos-26-5-1.0.0"}}},
	}
	if ref != "" {
		pod.Annotations = map[string]string{payload.Annotation: ref}
	}
	return pod
}

func tartRuns(t *testing.T, calls string) []string {
	t.Helper()
	raw, err := os.ReadFile(calls)
	if err != nil && !os.IsNotExist(err) {
		t.Fatal(err)
	}
	var runs []string
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(line, "run ") {
			runs = append(runs, line)
		}
	}
	return runs
}

func TestCreatePodSharesPinnedPayloadReadOnly(t *testing.T) {
	root := t.TempDir()
	dir := filepath.Join(root, testPayloadDigest)
	if err := os.Mkdir(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	r, calls := payloadReconciler(t, &payload.Fetcher{Root: root})

	_ = r.createPod(context.Background(), payloadPod("ghcr.io/tuist/tuist-runner-payload@sha256:"+testPayloadDigest))

	runs := tartRuns(t, calls)
	if len(runs) != 1 || !strings.Contains(runs[0], "--dir payload:"+dir+":ro") {
		t.Fatalf("tart run = %q, want a read-only payload share of %s", runs, dir)
	}
}

func TestCreatePodNeverBootsWithoutPinnedPayload(t *testing.T) {
	r, calls := payloadReconciler(t, &payload.Fetcher{Root: t.TempDir(), Scheme: "http"})

	err := r.createPod(context.Background(), payloadPod("127.0.0.1:1/tuist/tuist-runner-payload@sha256:"+testPayloadDigest))

	if err == nil || !strings.Contains(err.Error(), "runner payload") {
		t.Fatalf("createPod error = %v, want a runner payload failure", err)
	}
	if runs := tartRuns(t, calls); len(runs) != 0 {
		t.Fatalf("booted a VM without its payload: %q", runs)
	}
	if r.Store.Get("tuist-runners", "runner-0") != nil {
		t.Fatal("recorded a Store entry for a VM that never booted")
	}
}

func TestCreatePodRejectsPayloadWithoutFetcher(t *testing.T) {
	r, calls := payloadReconciler(t, nil)

	err := r.createPod(context.Background(), payloadPod("ghcr.io/tuist/tuist-runner-payload@sha256:"+testPayloadDigest))

	if err == nil {
		t.Fatal("createPod booted a payload Pod with no fetcher")
	}
	if runs := tartRuns(t, calls); len(runs) != 0 {
		t.Fatalf("booted a VM without its payload: %q", runs)
	}
}

func TestCreatePodWithoutPayloadAddsNoShare(t *testing.T) {
	r, calls := payloadReconciler(t, &payload.Fetcher{Root: t.TempDir()})

	_ = r.createPod(context.Background(), payloadPod(""))

	runs := tartRuns(t, calls)
	if len(runs) != 1 || strings.Contains(runs[0], "payload:") {
		t.Fatalf("tart run = %q, want one run without a payload share", runs)
	}
}
