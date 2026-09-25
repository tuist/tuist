package podagent

import (
	"context"
	"encoding/json"
	"errors"
	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	authenticationv1 "k8s.io/api/authentication/v1"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	ktesting "k8s.io/client-go/testing"
)

func TestCustomVolumeWriterFence(t *testing.T) {
	for _, tc := range []struct {
		name                                       string
		pod, running, apiError, runtimeError, want bool
	}{
		{name: "terminal pod still exists", pod: true},
		{name: "API gone VM alive", running: true},
		{name: "API error", apiError: true},
		{name: "runtime error", runtimeError: true},
		{name: "both fences", want: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			kube := fake.NewSimpleClientset()
			if tc.pod {
				_, _ = kube.CoreV1().Pods("runners").Create(context.Background(), &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "job", Namespace: "runners", UID: "uid"}, Status: corev1.PodStatus{Phase: corev1.PodSucceeded}}, metav1.CreateOptions{})
			}
			if tc.apiError {
				kube.PrependReactor("get", "pods", func(ktesting.Action) (bool, runtime.Object, error) { return true, nil, errors.New("API unavailable") })
			}
			c := &CustomVolumes{Kube: kube, Namespace: "runners", Running: func(_ context.Context, vm string) (bool, error) {
				if vm != "runners-job" {
					t.Fatal(vm)
				}
				if tc.runtimeError {
					return false, errors.New("pgrep unavailable")
				}
				return tc.running, nil
			}}
			got, err := c.gone("job", "uid")
			if got != tc.want {
				t.Fatalf("gone=%t want %t", got, tc.want)
			}
			if (tc.apiError || tc.runtimeError) != (err != nil) {
				t.Fatal(err)
			}
		})
	}
}

func TestCustomVolumeMailboxUsesHostIdentity(t *testing.T) {
	root := t.TempDir()
	pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "host-pod", Namespace: "runners", UID: "host-uid"}}
	share := filepath.Join(root, "pods", string(pod.UID))
	if err := os.MkdirAll(share, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(share, "cache.request"), []byte(`{"key":"gradle","uid":501,"pod_name":"victim","node_name":"victim","platform":"linux"}`), 0600); err != nil {
		t.Fatal(err)
	}
	id := "11111111-1111-4111-8111-111111111111"
	scope := strings.Repeat("a", 64)
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/authorize" || r.Header.Get("Authorization") != "Bearer host-only" {
			t.Error("unexpected request")
		}
		var got map[string]any
		if err := json.NewDecoder(r.Body).Decode(&got); err != nil {
			t.Error(err)
		}
		if got["pod_name"] != "host-pod" || got["pod_uid"] != "host-uid" || got["node_name"] != "host-node" || got["architecture"] != "arm64" || got["uid"] != float64(501) || got["platform"] != nil {
			t.Errorf("untrusted identity: %v", got)
		}
		_ = json.NewEncoder(w).Encode(cachevolumes.Identity{ID: id, Scope: scope, Account: 1, UID: 501})
	}))
	defer server.Close()
	kube := fake.NewSimpleClientset()
	kube.PrependReactor("create", "serviceaccounts", func(action ktesting.Action) (bool, runtime.Object, error) {
		if action.GetSubresource() != "token" || action.GetNamespace() != "runners" {
			t.Error("unexpected token request")
		}
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{Token: "host-only"}}, nil
	})
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{Root: root, SizeGB: 20, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }}, Create: func(p string, _ int64) error { return os.WriteFile(p, nil, 0600) }}
	if err := backend.Init(); err != nil {
		t.Fatal(err)
	}
	store, err := cachevolumes.Open(root, backend)
	if err != nil {
		t.Fatal(err)
	}
	defer store.Close()
	c := &CustomVolumes{Root: root, URL: server.URL, HTTP: server.Client(), Node: "host-node", Namespace: "runners", ServiceAccount: "cache-agent", Kube: kube, Store: store}
	if err := c.requests(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(share, "cache.request.response"))
	if err != nil {
		t.Fatal(err)
	}
	var response map[string]any
	if err := json.Unmarshal(data, &response); err != nil {
		t.Fatal(err)
	}
	if response["id"] != id || response["directory"] != scope {
		t.Fatal(string(data))
	}
	// An exposed file is not proof that the guest successfully mounted it.
	action, err := c.report(cachevolumes.Slot{Identity: cachevolumes.Identity{ID: id, Scope: scope}, PodUID: "host-uid", State: "active"}, false)
	if err != nil || action != "hold" {
		t.Fatalf("unmounted report: %s %v", action, err)
	}
}

func TestCustomVolumeReusesAndRefreshesHostToken(t *testing.T) {
	kube := fake.NewSimpleClientset()
	requests := 0
	kube.PrependReactor("create", "serviceaccounts", func(ktesting.Action) (bool, runtime.Object, error) {
		requests++
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{Token: "host-only", ExpirationTimestamp: metav1.NewTime(time.Now().Add(time.Minute))}}, nil
	})
	c := &CustomVolumes{Kube: kube, Namespace: "runners", ServiceAccount: "cache-agent"}
	for range 2 {
		if token, err := c.token(context.Background()); err != nil || token != "host-only" {
			t.Fatal(token, err)
		}
	}
	if requests != 1 {
		t.Fatalf("minted %d tokens before expiry", requests)
	}
	if time.Until(c.tokenUntil) > 31*time.Second {
		t.Fatal("ignored API token expiration")
	}
	c.tokenUntil = time.Now().Add(-time.Second)
	if _, err := c.token(context.Background()); err != nil {
		t.Fatal(err)
	}
	if requests != 2 {
		t.Fatal("did not refresh expiring token")
	}
}
