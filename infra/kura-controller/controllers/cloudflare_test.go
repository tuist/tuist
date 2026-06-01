package controllers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestDesiredCloudflareLoadBalancerUsesDNSOnlyProximitySteering(t *testing.T) {
	loadBalancer := desiredCloudflareLoadBalancer("tuist.kura.tuist.dev", "https", []string{"pool-eu", "pool-us"})

	if loadBalancer.Name != "tuist.kura.tuist.dev" {
		t.Fatalf("expected load balancer name to be the global host, got %q", loadBalancer.Name)
	}
	if loadBalancer.Proxied {
		t.Fatal("expected Cloudflare load balancer to be DNS-only")
	}
	if loadBalancer.TTL != 30 {
		t.Fatalf("expected DNS-only load balancer TTL 30, got %d", loadBalancer.TTL)
	}
	if loadBalancer.SteeringPolicy != "proximity" {
		t.Fatalf("expected proximity steering, got %q", loadBalancer.SteeringPolicy)
	}
	if loadBalancer.FallbackPool != "pool-eu" {
		t.Fatalf("expected first sorted pool as fallback, got %q", loadBalancer.FallbackPool)
	}
	if len(loadBalancer.DefaultPools) != 2 || loadBalancer.DefaultPools[0] != "pool-eu" || loadBalancer.DefaultPools[1] != "pool-us" {
		t.Fatalf("expected default pools to be preserved, got %v", loadBalancer.DefaultPools)
	}
}

func TestCloudflareLoadBalancingEnabledWithZoneName(t *testing.T) {
	config := CloudflareLoadBalancingConfig{
		ZoneName: "tuist.dev",
		APIToken: "token",
	}

	if !config.Enabled() {
		t.Fatal("expected Cloudflare load balancing to be enabled with zone name plus API token")
	}
}

func TestCloudflareClientResolvesZoneMetadataFromZoneName(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/zones" || r.URL.Query().Get("name") != "tuist.dev" {
			t.Fatalf("unexpected request path: %s?%s", r.URL.Path, r.URL.RawQuery)
		}
		if got := r.Header.Get("Authorization"); got != "Bearer token" {
			t.Fatalf("expected bearer token auth header, got %q", got)
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"success":true,"result":[{"id":"zone-123","name":"tuist.dev","account":{"id":"account-456"}}],"errors":[]}`))
	}))
	defer server.Close()

	client := newCloudflareClient(CloudflareLoadBalancingConfig{
		ZoneName: "tuist.dev",
		APIToken: "token",
	})
	client.baseURL = server.URL
	client.httpClient = server.Client()

	if err := client.ensureZoneResolved(context.Background()); err != nil {
		t.Fatalf("expected zone resolution to succeed, got %v", err)
	}
	if client.zoneID != "zone-123" {
		t.Fatalf("expected resolved zone ID, got %q", client.zoneID)
	}
	if client.accountID != "account-456" {
		t.Fatalf("expected resolved account ID, got %q", client.accountID)
	}
}

func TestCloudflareClientClassifiesOriginLimitErrors(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/accounts/account-123/load_balancers/pools" {
			t.Fatalf("unexpected request path: %s", r.URL.Path)
		}

		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"success":false,"errors":[{"code":1000,"message":"origin limit exceeded for pool"}]}`))
	}))
	defer server.Close()

	client := newCloudflareClient(CloudflareLoadBalancingConfig{
		AccountID: "account-123",
		ZoneID:    "zone-123",
		APIToken:  "token",
	})
	client.baseURL = server.URL
	client.httpClient = server.Client()

	_, err := client.createPool(context.Background(), cloudflarePool{Name: "pool"})
	if err == nil {
		t.Fatal("expected Cloudflare request to fail")
	}
	if !cloudflareOriginLimitExceeded(err) {
		t.Fatalf("expected origin limit error classification, got %v", err)
	}
}

func TestJoinStatusMessage(t *testing.T) {
	got := joinStatusMessage("3/3 replicas ready", "global endpoint reconciliation degraded: quota exceeded")

	want := "3/3 replicas ready; global endpoint reconciliation degraded: quota exceeded"
	if got != want {
		t.Fatalf("expected %q, got %q", want, got)
	}
}
