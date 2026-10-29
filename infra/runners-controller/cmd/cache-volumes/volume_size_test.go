package main

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
)

// sizedAgent answers authorization with status and records each body it sent.
func sizedAgent(t *testing.T, status int) (*agent, *[]map[string]any) {
	t.Helper()
	root := t.TempDir()
	s, err := cachevolumes.Open(root, testBackend{})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "runner", Namespace: "runners", UID: types.UID("uid"), Labels: map[string]string{"tuist.dev/runner": "true"}}, Spec: corev1.PodSpec{NodeName: "node"}, Status: corev1.PodStatus{PodIP: "10.0.0.5", Phase: corev1.PodRunning}}
	bodies := &[]map[string]any{}
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		*bodies = append(*bodies, body)
		w.WriteHeader(status)
		if status == http.StatusOK {
			json.NewEncoder(w).Encode(map[string]any{"id": "00000000-0000-0000-0000-000000000001", "account_id": 1, "scope": strings.Repeat("a", 64), "volume_bytes": 50_000_000_000, "head_size_bytes": 4_000_000_000})
		}
	}))
	t.Cleanup(upstream.Close)
	tokenPath := filepath.Join(root, "token")
	if err := os.WriteFile(tokenPath, []byte("agent-token"), 0600); err != nil {
		t.Fatal(err)
	}
	s.MaxVolumeBytes = 100_000_000_000
	return &agent{maxVolumeBytes: 100_000_000_000, tokenPath: tokenPath, store: s, kube: fake.NewSimpleClientset(pod), namespace: "runners", node: "node", authorizeURL: upstream.URL, http: upstream.Client()}, bodies
}

func acquireSized(a *agent, requested int64) int {
	body, _ := json.Marshal(request{PodName: "runner", PodUID: "uid", Key: "gradle", RequestedVolumeBytes: cachevolumes.RequestedSize(requested)})
	req := httptest.NewRequest("POST", "/acquire", bytes.NewReader(body))
	req.RemoteAddr = "10.0.0.5:1234"
	w := httptest.NewRecorder()
	a.serve(w, req)
	return w.Code
}

func TestAcquireForwardsTheRequestedSizeAndTheHostMaximum(t *testing.T) {
	a, bodies := sizedAgent(t, http.StatusOK)

	if got := acquireSized(a, 50_000_000_000); got != http.StatusOK {
		t.Fatal("acquisition failed", got)
	}

	body := (*bodies)[0]
	if body["requested_volume_bytes"] != float64(50_000_000_000) || body["max_volume_bytes"] != float64(100_000_000_000) {
		t.Fatalf("authorized with %v", body)
	}
}

func TestAcquireDropsAnInvalidRequestedSize(t *testing.T) {
	for _, requested := range []int64{0, -1, 2_500_000_000, 101_000_000_000} {
		a, bodies := sizedAgent(t, http.StatusOK)

		if got := acquireSized(a, requested); got != http.StatusOK {
			t.Fatalf("an invalid size %d failed the acquisition: %d", requested, got)
		}

		body := (*bodies)[0]
		if _, ok := body["requested_volume_bytes"]; ok || body["max_volume_bytes"] != float64(100_000_000_000) {
			t.Fatalf("size %d authorized with %v", requested, body)
		}
	}
}

func TestAcquireReportsAVolumeLargerThanTheHostAsCapacity(t *testing.T) {
	a, bodies := sizedAgent(t, http.StatusInsufficientStorage)

	if got := acquireSized(a, 100_000_000_000); got != http.StatusServiceUnavailable {
		t.Fatal("a volume larger than the host was not unavailable", got)
	}
	if len(*bodies) != 1 {
		t.Fatalf("retried a capacity refusal %d times", len(*bodies)-1)
	}
}

func TestAcquireIgnoresAMalformedRequestedSize(t *testing.T) {
	a, bodies := sizedAgent(t, http.StatusOK)
	req := httptest.NewRequest("POST", "/acquire", strings.NewReader(`{"pod_name":"runner","pod_uid":"uid","key":"gradle","requested_volume_bytes":"50gb"}`))
	req.RemoteAddr = "10.0.0.5:1234"
	w := httptest.NewRecorder()

	a.serve(w, req)

	if w.Code != http.StatusOK {
		t.Fatal("a malformed size failed the acquisition", w.Code)
	}
	if _, ok := (*bodies)[0]["requested_volume_bytes"]; ok {
		t.Fatalf("authorized with %v", (*bodies)[0])
	}
}
