package controllers

import "testing"

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
