package podagent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	ktesting "k8s.io/client-go/testing"
)

func executionVolumes(t *testing.T, status int) (*CustomVolumes, *corev1.Pod, string, *[]map[string]any) {
	t.Helper()
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := filepath.Join(root, "pods", string(pod.UID))
	if err := os.MkdirAll(share, 0755); err != nil {
		t.Fatal(err)
	}
	forwarded := &[]map[string]any{}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/execution" || r.Header.Get("Authorization") != "Bearer host-only" {
			t.Errorf("request %s with %q", r.URL.Path, r.Header.Get("Authorization"))
		}
		var got map[string]any
		_ = json.NewDecoder(r.Body).Decode(&got)
		*forwarded = append(*forwarded, got)
		w.WriteHeader(status)
		w.Write([]byte("{}"))
	}))
	t.Cleanup(server.Close)
	kube := fake.NewSimpleClientset()
	kube.PrependReactor("create", "serviceaccounts", func(ktesting.Action) (bool, runtime.Object, error) {
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{Token: "host-only"}}, nil
	})
	return &CustomVolumes{Root: root, URL: server.URL, HTTP: server.Client(), Node: "host-node", Namespace: "runners", ServiceAccount: "cache-agent", Kube: kube}, pod, share, forwarded
}

func readMailboxResponse(t *testing.T, path string) map[string]any {
	t.Helper()
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatal(err)
	}
	return response
}

func TestCustomMailboxForwardsTheJobsExecutionTokenWithTheHostIdentity(t *testing.T) {
	c, pod, share, forwarded := executionVolumes(t, http.StatusOK)
	token := strings.Repeat("t", 12_000)
	request, _ := json.Marshal(map[string]any{"execution_token": token, "pod_name": "victim", "node_name": "victim"})
	if err := os.WriteFile(filepath.Join(share, "token.request"), request, 0600); err != nil {
		t.Fatal(err)
	}
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if response := readMailboxResponse(t, filepath.Join(share, "token.request.response")); response["error"] != nil {
		t.Fatalf("response %v", response)
	}
	if len(*forwarded) != 1 {
		t.Fatalf("forwarded %d requests", len(*forwarded))
	}
	got := (*forwarded)[0]
	if got["token"] != token || got["pod_name"] != "host-pod" || got["pod_uid"] != "host-uid" || got["node_name"] != "host-node" {
		t.Fatalf("untrusted identity: pod %v node %v", got["pod_name"], got["node_name"])
	}
}

func TestCustomMailboxReportsARejectedExecutionToken(t *testing.T) {
	c, pod, share, _ := executionVolumes(t, http.StatusForbidden)
	if err := os.WriteFile(filepath.Join(share, "token.request"), []byte(`{"execution_token":"jwt"}`), 0600); err != nil {
		t.Fatal(err)
	}
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	if response := readMailboxResponse(t, filepath.Join(share, "token.request.response")); response["error"] != "unavailable" {
		t.Fatalf("response %v", response)
	}
}
