package executiongateway

import (
	"net/http"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
)

func TestExecutionsAreCountedByPathAndStatus(t *testing.T) {
	lab := newDirectLab(t, http.StatusOK)
	auth := jwt(time.Now().Add(time.Hour))
	lab.capabilities(auth)
	lab.execute(auth)
	lab.awaitLease()
	lab.execute(auth)

	m := lab.gateway.metrics
	if server, leased := testutil.ToFloat64(m.executions.WithLabelValues("server", "OK")), testutil.ToFloat64(m.executions.WithLabelValues("lease", "OK")); server != 1 || leased != 1 {
		t.Fatalf("server executions %v, leased executions %v; want one each", server, leased)
	}
	if n := testutil.CollectAndCount(m.duration); n != 2 {
		t.Fatalf("%d duration series; want one per path", n)
	}
	if streams := testutil.ToFloat64(m.streams); streams != 0 {
		t.Fatalf("%v streams still counted after both finished", streams)
	}
}

func TestPrefetchesAreCountedByHowTheInputsWereRead(t *testing.T) {
	for _, test := range []struct {
		name  string
		store *blobStore
	}{
		{"inputs", &blobStore{blobs: map[string][]byte{}, tree: true, inputs: true}},
		{"tree", &blobStore{blobs: map[string][]byte{}, tree: true}},
		{"walk", &blobStore{blobs: map[string][]byte{}}},
	} {
		t.Run(test.name, func(t *testing.T) {
			prefetch, _, g := prefetchLab(t, test.store)
			prefetch()
			if n := testutil.ToFloat64(g.metrics.prefetches.WithLabelValues(test.name)); n != 1 {
				t.Fatalf("%v prefetches counted as %s", n, test.name)
			}
		})
	}
}
