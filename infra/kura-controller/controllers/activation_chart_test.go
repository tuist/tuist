package controllers

import (
	"os"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"sigs.k8s.io/yaml"
)

func TestActivationRoutesShareGRPCIngress(t *testing.T) {
	for _, env := range []string{"staging", "canary", "production"} {
		t.Run(env, func(t *testing.T) {
			values := []string{"values-managed-common.yaml", "values-managed-" + env + ".yaml"}
			templates := []string{"templates/kura-activation.yaml"}
			if docs := renderStableChartWithValues(t, "tuist", templates, values); len(docs) != 0 {
				t.Fatal("activation must remain disabled in managed overlays")
			}
			docs := renderStableChartWithValues(t, "tuist", templates, values, "kuraActivation.enabled=true", "kuraController.image.tag=test")
			ingresses := 0
			for _, doc := range docs {
				if doc["kind"] != "Ingress" {
					continue
				}
				ingresses++
				class, _, _ := unstructured.NestedString(doc, "spec", "ingressClassName")
				if class != "nginx-grpc" {
					t.Fatalf("HTTP and gRPC must use the same HTTP/2-safe ingress: %q", class)
				}
				annotations, _, _ := unstructured.NestedStringMap(doc, "metadata", "annotations")
				if annotations["nginx.ingress.kubernetes.io/configuration-snippet"] != "" {
					t.Fatal("must not require unsafe snippets")
				}
				if annotations["nginx.ingress.kubernetes.io/proxy-request-buffering"] != "off" {
					t.Fatal("uploads must stream")
				}
				name, _, _ := unstructured.NestedString(doc, "metadata", "name")
				if strings.HasSuffix(name, "-grpc") && annotations["nginx.ingress.kubernetes.io/backend-protocol"] != "GRPC" {
					t.Fatal("missing gRPC backend protocol")
				}
			}
			if ingresses != 2 {
				t.Fatalf("want two protocol routes, got %d", ingresses)
			}

			platformValues := "values-tuist-" + env + ".yaml"
			if env == "production" {
				platformValues = "values-tuist.yaml"
			}
			_, file, _, _ := runtime.Caller(0)
			platform := filepath.Join(filepath.Dir(file), "..", "..", "helm", "platform")
			readValues := func(name string) map[string]interface{} {
				t.Helper()
				data, err := os.ReadFile(filepath.Join(platform, name))
				if err != nil {
					t.Fatal(err)
				}
				var v map[string]interface{}
				if err := yaml.Unmarshal(data, &v); err != nil {
					t.Fatal(err)
				}
				return v
			}
			base, overlay := readValues("values.yaml"), readValues(platformValues)
			enabled, _, _ := unstructured.NestedBool(overlay, "grpc-ingress-nginx", "enabled")
			if !enabled {
				t.Fatal("managed environment has no dedicated gRPC ingress")
			}
			keepalive, _, _ := unstructured.NestedString(base, "grpc-ingress-nginx", "controller", "config", "upstream-keepalive-connections")
			if override, ok, _ := unstructured.NestedString(overlay, "grpc-ingress-nginx", "controller", "config", "upstream-keepalive-connections"); ok {
				keepalive = override
			}
			if keepalive == "" || keepalive == "0" {
				t.Fatal("gRPC ingress would send a forbidden Connection header")
			}

			writer := false
			for _, doc := range renderStableChartWithValues(t, "platform", []string{"templates/cache-dns.yaml"}, []string{platformValues}, "cacheDNS.activationIngressClass=nginx-grpc") {
				if doc["kind"] != "Deployment" {
					continue
				}
				writer = true
				containers, _, _ := unstructured.NestedSlice(doc, "spec", "template", "spec", "containers")
				args, _, _ := unstructured.NestedStringSlice(containers[0].(map[string]interface{}), "args")
				joined := strings.Join(args, " ")
				if !strings.Contains(joined, "--source=ingress") || !strings.Contains(joined, "--ingress-class=nginx-grpc") {
					t.Fatalf("wildcard must follow the same ingress: %s", joined)
				}
			}
			if !writer {
				t.Fatal("missing wildcard DNS writer")
			}
		})
	}
}
