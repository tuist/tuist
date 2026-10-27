// Package runnerrelay provides the ordinary Linux cache path from nodes outside
// the OVH private network. Each relay Service belongs to one KuraInstance and
// forwards to that instance's existing primary Service.
package runnerrelay

import (
	"crypto/sha256"
	"fmt"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"regexp"
	"strings"

	corev1 "k8s.io/api/core/v1"
)

const Label = "tuist.dev/runner-cache-wan"
const BackendAnnotation = "tuist.dev/runner-cache-backend"
const App = "kura-runner-wan-relay"

var dnsLabel = regexp.MustCompile(`^[a-z0-9]([-a-z0-9]*[a-z0-9])?$`)

func ServiceName(backend string) string {
	return fmt.Sprintf("wan-%x", sha256.Sum256([]byte(backend)))[:36]
}

type ServiceLookup func(name string) (*corev1.Service, error)

// NewHandler never accepts an upstream from the request. Only an owner-bound,
// controller-created alias in the configured namespace can select a backend.
func NewHandler(namespace string, lookup ServiceLookup, transport http.RoundTripper) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		host := req.Host
		if strings.Contains(host, ":") {
			var err error
			host, _, err = net.SplitHostPort(host)
			if err != nil {
				http.Error(w, "invalid cache host", http.StatusBadRequest)
				return
			}
		}
		suffix := "." + namespace + ".svc.cluster.local"
		if !strings.HasSuffix(host, suffix) {
			http.Error(w, "unknown cache host", http.StatusNotFound)
			return
		}
		name := strings.TrimSuffix(host, suffix)
		service, err := lookup(name)
		if err != nil || service == nil {
			http.Error(w, "cache route unavailable", http.StatusServiceUnavailable)
			return
		}
		backend := service.Annotations[BackendAnnotation]
		owned := false
		for _, owner := range service.OwnerReferences {
			owned = owned || (owner.APIVersion == "kura.tuist.dev/v1alpha1" && owner.Kind == "KuraInstance" &&
				owner.Name == backend && owner.UID != "" && owner.Controller != nil && *owner.Controller)
		}
		if service.Namespace != namespace || service.Name != name || service.Labels[Label] != "true" ||
			!owned || len(backend) > 63 || !dnsLabel.MatchString(backend) || name != ServiceName(backend) {
			http.Error(w, "invalid cache route", http.StatusBadGateway)
			return
		}
		target := &url.URL{Scheme: "http", Host: backend + suffix + ":4000"}
		proxy := &httputil.ReverseProxy{
			Transport: transport,
			Rewrite: func(r *httputil.ProxyRequest) {
				r.SetURL(target)
				r.Out.Host = target.Host
				// A relay must not let an endpoint-rename redirect escape onto a
				// direct path whose host route could use the private network.
				r.Out.Header.Del("X-Tuist-Accept-Endpoint-Redirect")
			},
			ModifyResponse: func(response *http.Response) error {
				switch response.StatusCode {
				case 301, 302, 303, 307, 308:
					return fmt.Errorf("cache route returned a redirect")
				}
				response.Header.Del("Alt-Svc")
				return nil
			},
			ErrorHandler: func(w http.ResponseWriter, _ *http.Request, _ error) {
				// Neither credentials nor artifact paths belong in relay logs.
				http.Error(w, "cache route unavailable", http.StatusBadGateway)
			},
		}
		proxy.ServeHTTP(w, req)
	})
}
