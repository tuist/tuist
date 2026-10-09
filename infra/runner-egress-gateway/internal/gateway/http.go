package gateway

import (
	"net/http"
	"time"
)

// TunnelHealthHandler serves /healthz, which Mac hosts probe through the
// tunnel.
func TunnelHealthHandler(r *Reconciler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		writeResult(w, r.Status().Ready(), "not ready")
	})
	return mux
}

// ProbeHandler serves /readyz and /livez for the kubelet. Liveness fails when
// no reconcile pass finished within staleAfter, which means the loop is stuck.
func ProbeHandler(r *Reconciler, started time.Time, staleAfter time.Duration, now func() time.Time) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		writeResult(w, r.Status().Ready(), "not ready")
	})
	mux.HandleFunc("GET /livez", func(w http.ResponseWriter, _ *http.Request) {
		last := r.LastPass()
		if last.IsZero() {
			last = started
		}
		writeResult(w, now().Sub(last) <= staleAfter, "stale")
	})
	return mux
}

func writeResult(w http.ResponseWriter, ok bool, failure string) {
	w.Header().Set("Content-Type", "text/plain; charset=utf-8")
	if ok {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok"))
		return
	}
	w.WriteHeader(http.StatusServiceUnavailable)
	_, _ = w.Write([]byte(failure))
}
