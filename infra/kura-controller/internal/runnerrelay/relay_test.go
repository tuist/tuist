package runnerrelay

import (
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func route(backend string) *corev1.Service {
	controller := true
	return &corev1.Service{ObjectMeta: metav1.ObjectMeta{
		Name: ServiceName(backend), Namespace: "kura", Labels: map[string]string{Label: "true"},
		Annotations: map[string]string{BackendAnnotation: backend},
		OwnerReferences: []metav1.OwnerReference{{APIVersion: "kura.tuist.dev/v1alpha1", Kind: "KuraInstance",
			Name: backend, UID: "instance-uid", Controller: &controller}},
	}}
}

func TestRelayPreservesArtifactRequestAndAuthorization(t *testing.T) {
	service := route("kura-tuist-ca-east-1-m")
	payload := strings.Repeat("artifact", 1024*1024)
	for _, method := range []string{"PUT", "GET", "HEAD"} {
		t.Run(method, func(t *testing.T) {
			called := false
			handler := NewHandler("kura", func(string) (*corev1.Service, error) { return service, nil }, roundTripFunc(func(r *http.Request) (*http.Response, error) {
				called = true
				if r.URL.Host != "kura-tuist-ca-east-1-m.kura.svc.cluster.local:4000" ||
					r.URL.EscapedPath() != "/api/cache/key%2Fpart" || r.URL.RawQuery != "namespace=gradle" ||
					r.Method != method || r.Header.Get("Authorization") != "Bearer test-only" {
					t.Fatalf("request did not retain its backend/path/method/authentication")
				}
				if r.Header.Get("X-Tuist-Accept-Endpoint-Redirect") != "" || r.Header.Get("X-Forwarded-Host") != "" {
					t.Fatal("unsafe forwarding headers retained")
				}
				body, _ := io.ReadAll(r.Body)
				if string(body) != payload {
					t.Fatal("artifact changed")
				}
				return &http.Response{StatusCode: 403, Header: http.Header{"X-Test": {"preserved"}}, Body: io.NopCloser(strings.NewReader("denied"))}, nil
			}))
			request := httptest.NewRequest(method, "http://"+service.Name+".kura.svc.cluster.local:4000/api/cache/key%2Fpart?namespace=gradle", strings.NewReader(payload))
			request.Header.Set("Authorization", "Bearer test-only")
			request.Header.Set("X-Tuist-Accept-Endpoint-Redirect", "true")
			request.Header.Set("X-Forwarded-Host", "attacker.invalid")
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, request)
			if !called || response.Code != 403 || response.Header().Get("X-Test") != "preserved" {
				t.Fatal("upstream authorization response was not preserved")
			}
		})
	}
}

func TestRelayRefusesUntrustedRoutesAndNeverFallsBack(t *testing.T) {
	for _, mutation := range []string{"lookup", "label", "owner", "namespace", "backend", "alias"} {
		t.Run(mutation, func(t *testing.T) {
			service := route("kura-tuist-ca-east-1")
			name := service.Name
			var lookupErr error
			switch mutation {
			case "lookup":
				lookupErr = errors.New("unavailable")
			case "label":
				service.Labels = nil
			case "owner":
				service.OwnerReferences = nil
			case "namespace":
				service.Namespace = "kube-system"
			case "backend":
				service.Annotations[BackendAnnotation] = "169.254.169.254/path"
			case "alias":
				name = "arbitrary"
			}
			handler := NewHandler("kura", func(string) (*corev1.Service, error) { return service, lookupErr }, roundTripFunc(func(*http.Request) (*http.Response, error) {
				t.Fatal("untrusted route reached the network")
				return nil, nil
			}))
			response := httptest.NewRecorder()
			handler.ServeHTTP(response, httptest.NewRequest("GET", "http://"+name+".kura.svc.cluster.local:4000/up", nil))
			if response.Code < 400 {
				t.Fatal("invalid route accepted")
			}
		})
	}
}

func TestRelayBlocksRedirectEscape(t *testing.T) {
	service := route("kura-tuist-ca-east-1")
	for _, status := range []int{301, 302, 303, 307, 308} {
		handler := NewHandler("kura", func(string) (*corev1.Service, error) { return service, nil }, roundTripFunc(func(*http.Request) (*http.Response, error) {
			return &http.Response{StatusCode: status, Header: http.Header{"Location": {"http://direct-cache.invalid"}}, Body: io.NopCloser(strings.NewReader(""))}, nil
		}))
		response := httptest.NewRecorder()
		handler.ServeHTTP(response, httptest.NewRequest("GET", "http://"+service.Name+".kura.svc.cluster.local:4000/up", nil))
		if response.Code != 502 || response.Header().Get("Location") != "" {
			t.Fatal("redirect escaped relay")
		}
	}
}

func TestServiceNameSupportsMovedAndLongInstances(t *testing.T) {
	if ServiceName("kura-tuist-ca-east-1") != "wan-209b81c1dc71dade7a30ee4287f72145" {
		t.Fatal("service naming contract changed")
	}
	if ServiceName("kura-tuist-ca-east-1") == ServiceName("kura-tuist-ca-east-1-m") {
		t.Fatal("move aliases collide")
	}
	if len(ServiceName(strings.Repeat("x", 63))) > 63 {
		t.Fatal("invalid Kubernetes service name")
	}
}
