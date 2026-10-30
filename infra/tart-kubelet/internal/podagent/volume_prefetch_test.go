package podagent

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/client-go/kubernetes/fake"
	k8stesting "k8s.io/client-go/testing"
)

type stubPrefetch struct {
	masters []PrefetchMaster
	calls   atomic.Int32
}

func (s *stubPrefetch) CacheMasters(context.Context) ([]PrefetchMaster, error) {
	s.calls.Add(1)
	return s.masters, nil
}

type unavailableUntil struct {
	ready atomic.Bool
	calls atomic.Int32
}

func (s *unavailableUntil) CacheMasters(context.Context) ([]PrefetchMaster, error) {
	s.calls.Add(1)
	if !s.ready.Load() {
		return nil, errPrefetchUnavailable
	}
	return nil, nil
}

type recordingCustomPrefetch struct{ identities []cachevolumes.Identity }

func (r *recordingCustomPrefetch) PrefetchMaster(identity cachevolumes.Identity) bool {
	r.identities = append(r.identities, identity)
	return true
}

type recordingCheckoutPrefetch struct{ tasks []cachevolumes.CheckoutTask }

func (r *recordingCheckoutPrefetch) PrefetchCheckout(task cachevolumes.CheckoutTask) bool {
	r.tasks = append(r.tasks, task)
	return true
}

func TestServerPrefetchAuthenticatesAsTheHost(t *testing.T) {
	var gotAuth, gotPath string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth, gotPath = r.Header.Get("Authorization"), r.URL.Path
		_, _ = w.Write([]byte(`{"masters":[{"kind":"custom","account_id":42,"generation":4,"content_digest":"c"}]}`))
	}))
	defer srv.Close()

	client := fake.NewSimpleClientset()
	client.PrependReactor("create", "selfsubjectreviews", func(k8stesting.Action) (bool, runtime.Object, error) {
		return true, &authenticationv1.SelfSubjectReview{Status: authenticationv1.SelfSubjectReviewStatus{
			UserInfo: authenticationv1.UserInfo{Username: "system:serviceaccount:tuist:tart-kubelet-mac-01"},
		}}, nil
	})
	var mints atomic.Int32
	var mintedFor, audiences string
	client.PrependReactor("create", "serviceaccounts", func(action k8stesting.Action) (bool, runtime.Object, error) {
		if action.GetSubresource() != "token" {
			return false, nil, nil
		}
		mints.Add(1)
		create := action.(k8stesting.CreateActionImpl)
		mintedFor = action.GetNamespace() + "/" + create.Name
		audiences = strings.Join(create.Object.(*authenticationv1.TokenRequest).Spec.Audiences, ",")
		return true, &authenticationv1.TokenRequest{Status: authenticationv1.TokenRequestStatus{
			Token:               "host-token",
			ExpirationTimestamp: metav1.NewTime(time.Now().Add(10 * time.Minute)),
		}}, nil
	})

	s := &ServerPrefetch{Client: client}
	if _, err := s.CacheMasters(context.Background()); err != errPrefetchUnavailable {
		t.Fatalf("before any runner Pod: err = %v, want errPrefetchUnavailable", err)
	}

	pod := func(url string) *corev1.Pod {
		return &corev1.Pod{Spec: corev1.PodSpec{Containers: []corev1.Container{{
			Env: []corev1.EnvVar{{Name: runnerDispatchURLEnv, Value: url}},
		}}}}
	}
	s.ObservePod(pod("https://evil.example/somewhere-else"))
	if _, err := s.CacheMasters(context.Background()); err != errPrefetchUnavailable {
		t.Fatalf("a URL that is not the dispatch endpoint was adopted: err = %v", err)
	}
	s.ObservePod(pod(srv.URL + runnerDispatchPath))

	for i := 0; i < 2; i++ {
		masters, err := s.CacheMasters(context.Background())
		if err != nil {
			t.Fatalf("CacheMasters: %v", err)
		}
		if len(masters) != 1 || masters[0].AccountID != 42 || masters[0].Generation != 4 {
			t.Fatalf("masters = %+v", masters)
		}
	}
	if gotPath != cacheMastersPath || gotAuth != "Bearer host-token" {
		t.Fatalf("request = %s with %q", gotPath, gotAuth)
	}
	if mintedFor != "tuist/tart-kubelet-mac-01" || audiences != RunnerHostAudience {
		t.Fatalf("minted for %s with audiences %q", mintedFor, audiences)
	}
	if got := mints.Load(); got != 1 {
		t.Fatalf("minted %d tokens for two calls, want the first reused", got)
	}
}

// Every start polls before any runner Pod has said where the server is; that must not cost a whole interval.
func TestPrefetchPollsAsSoonAsTheServerIsKnown(t *testing.T) {
	source := &unavailableUntil{}
	p := &PrefetchPoller{Source: source, Custom: &recordingCustomPrefetch{}}

	p.refresh(context.Background())
	source.ready.Store(true)
	p.refresh(context.Background())
	p.refresh(context.Background())
	if got := source.calls.Load(); got != 2 {
		t.Fatalf("prefetch polls = %d; want one as soon as the server is known, then one per interval", got)
	}
}

func TestPrefetchHandsCustomHeadsToTheCustomAgent(t *testing.T) {
	scope := strings.Repeat("a", 64)
	source := &stubPrefetch{masters: []PrefetchMaster{
		{AccountID: 42, Generation: 4},
		{
			Kind: "custom", ID: "11111111-1111-4111-8111-111111111111", AccountID: 42, Scope: scope, Generation: 3,
			ImageDigest: strings.Repeat("b", 40), ContentDigest: strings.Repeat("c", 64), VolumeBytes: 50_000_000_000, HeadSizeBytes: 4_000_000_000,
		},
	}}
	custom := &recordingCustomPrefetch{}
	now := time.Now()
	p := &PrefetchPoller{Source: source, Custom: custom, now: func() time.Time { return now }}

	p.refresh(context.Background())
	want := cachevolumes.Identity{
		ID: "11111111-1111-4111-8111-111111111111", Account: 42, Scope: scope, BaseGeneration: 3,
		ImageDigest: strings.Repeat("b", 40), ContentDigest: strings.Repeat("c", 64), VolumeBytes: 50_000_000_000, HeadSizeBytes: 4_000_000_000,
	}
	if len(custom.identities) != 1 || custom.identities[0] != want {
		t.Fatalf("custom prefetches = %+v", custom.identities)
	}

	now = now.Add(prefetchRefreshInterval)
	p.refresh(context.Background())
	if got := source.calls.Load(); got != 2 {
		t.Fatalf("prefetch polls = %d after an interval, want 2", got)
	}
}

func TestPrefetchServerClientDropsIdleConnectionsBeforeTheServer(t *testing.T) {
	transport, ok := prefetchHTTPClient.Transport.(*http.Transport)
	if !ok || transport.IdleConnTimeout != cachevolumes.ServerIdleTimeout {
		t.Fatalf("prefetch client transport = %#v, want idle timeout %s", prefetchHTTPClient.Transport, cachevolumes.ServerIdleTimeout)
	}
}

func TestPrefetchHandsCheckoutHeadsToTheCheckouts(t *testing.T) {
	scope, key := strings.Repeat("a", 64), strings.Repeat("d", 64)
	var masters []PrefetchMaster
	body := `[{"kind":"checkout","id":"11111111-1111-4111-8111-111111111111","account_id":42,"scope":"` + scope + `","generation":3,` +
		`"image_digest":"` + strings.Repeat("b", 40) + `","content_digest":"` + strings.Repeat("c", 64) + `","volume_bytes":20000000000,` +
		`"checkout_generation":2,"clone_url":"https://github.com/org/repo","default_branch":"main","uid":502,"volume_key":"` + key + `"}]`
	if err := json.Unmarshal([]byte(body), &masters); err != nil {
		t.Fatal(err)
	}
	custom, checkouts := &recordingCustomPrefetch{}, &recordingCheckoutPrefetch{}
	p := &PrefetchPoller{Source: &stubPrefetch{masters: masters}, Custom: custom, Checkouts: checkouts}

	p.refresh(context.Background())
	want := cachevolumes.CheckoutTask{
		Scope: scope, Generation: 2, CloneURL: "https://github.com/org/repo", DefaultBranch: "main",
		Use: "11111111-1111-4111-8111-111111111111", BaseGeneration: 3, ImageDigest: strings.Repeat("b", 40), ContentDigest: strings.Repeat("c", 64),
		UID: 502, VolumeKey: key, Spare: true,
	}
	if len(checkouts.tasks) != 1 || checkouts.tasks[0] != want {
		t.Fatalf("checkout prefetches = %+v", checkouts.tasks)
	}
	if len(custom.identities) != 0 {
		t.Fatalf("a checkout HEAD went to the custom agent: %+v", custom.identities)
	}
}
