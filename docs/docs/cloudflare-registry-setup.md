# Cloudflare Registry Load Balancer Setup

This guide documents how to configure Cloudflare Load Balancing with geo-steering for the Swift Package Registry at `registry.tuist.dev`.

## Overview

The registry is served by 4 cache nodes distributed globally. Cloudflare Load Balancing routes users to the nearest healthy cache node using geo-steering.

### Cache Node Hostnames

| Region | Hostname |
|--------|----------|
| EU Central | `cache-eu-central.tuist.dev` |
| US East | `cache-us-east.tuist.dev` |
| US West | `cache-us-west.tuist.dev` |
| AP Southeast | `cache-ap-southeast.tuist.dev` |

## Step-by-Step Configuration

### 1. Create DNS Record

1. Navigate to **DNS** → **Records** in the Cloudflare dashboard
2. Create a new record:
   - **Type**: CNAME (will be converted to A by Load Balancer)
   - **Name**: `registry`
   - **Target**: Will be managed by Load Balancer
   - **Proxy status**: Proxied (orange cloud)

### 2. Create Origin Pools

Create 4 origin pools, one for each region:

#### Pool: EU Central
- **Name**: `registry-eu-central`
- **Origins**:
  - **Address**: `cache-eu-central.tuist.dev`
  - **Weight**: 1
- **Health Check**: See Step 3

#### Pool: US East
- **Name**: `registry-us-east`
- **Origins**:
  - **Address**: `cache-us-east.tuist.dev`
  - **Weight**: 1
- **Health Check**: See Step 3

#### Pool: US West
- **Name**: `registry-us-west`
- **Origins**:
  - **Address**: `cache-us-west.tuist.dev`
  - **Weight**: 1
- **Health Check**: See Step 3

#### Pool: AP Southeast
- **Name**: `registry-ap-southeast`
- **Origins**:
  - **Address**: `cache-ap-southeast.tuist.dev`
  - **Weight**: 1
- **Health Check**: See Step 3

### 3. Configure Health Checks

Create a health check monitor and attach it to all pools:

- **Name**: `registry-health`
- **Type**: HTTP
- **Path**: `/up`
- **Method**: GET
- **Expected Codes**: 200
- **Interval**: 60 seconds
- **Timeout**: 5 seconds
- **Retries**: 2
- **Follow Redirects**: No

### 4. Create Load Balancer

1. Navigate to **Traffic** → **Load Balancing**
2. Create a new Load Balancer:
   - **Hostname**: `registry.tuist.dev`
   - **Session Affinity**: None (stateless API)
   - **Proxy**: Enabled

### 5. Configure Geo-Steering

Set the traffic steering policy to **Geo Steering** and configure region mappings:

| Cloudflare Region Code | Region Name | Primary Pool | Fallback Order |
|------------------------|-------------|--------------|----------------|
| `WEU` | Western Europe | `registry-eu-central` | US East → US West → AP Southeast |
| `EEU` | Eastern Europe | `registry-eu-central` | US East → US West → AP Southeast |
| `ENAM` | Eastern North America | `registry-us-east` | US West → EU Central → AP Southeast |
| `WNAM` | Western North America | `registry-us-west` | US East → EU Central → AP Southeast |
| `SEAS` | Southeast Asia | `registry-ap-southeast` | US West → EU Central → US East |
| `NEAS` | Northeast Asia | `registry-ap-southeast` | US West → EU Central → US East |
| `OC` | Oceania | `registry-ap-southeast` | US West → EU Central → US East |
| `ME` | Middle East | `registry-eu-central` | AP Southeast → US East → US West |
| `AF` | Africa | `registry-eu-central` | US East → AP Southeast → US West |
| `SAS` | South Asia | `registry-ap-southeast` | EU Central → US West → US East |
| `SAM` | South America | `registry-us-east` | US West → EU Central → AP Southeast |
| `CAM` | Central America | `registry-us-east` | US West → EU Central → AP Southeast |

### 6. Configure Fallback Behavior

Set the default fallback pool order for regions not explicitly mapped:

1. `registry-us-east` (primary fallback)
2. `registry-eu-central`
3. `registry-us-west`
4. `registry-ap-southeast`

### 7. Enable the Load Balancer

1. Review all settings
2. Click **Save and Deploy**
3. Wait for DNS propagation (typically 1-5 minutes)

## Verification

### Test Health Checks

Verify all pools show as healthy in the Cloudflare dashboard:

1. Navigate to **Traffic** → **Load Balancing** → **Pools**
2. Each pool should show a green "Healthy" status

### Test Geo-Steering

From different geographic locations, verify routing:

```bash
# Check which cache node responds
curl -sI https://registry.tuist.dev/up | grep -i "x-served-by"

# Verify registry availability
curl -s https://registry.tuist.dev/api/registry/swift
# Expected: HTTP 200 OK
```

### Test Failover

1. Temporarily disable one origin pool
2. Verify traffic fails over to the next pool in the fallback order
3. Re-enable the pool and verify it receives traffic again

## Troubleshooting

### Pool Shows Unhealthy

1. Verify the cache node is running: `curl -I https://cache-{region}.tuist.dev/up`
2. Check health check configuration matches the endpoint
3. Review Cloudflare health check logs for error details

### Unexpected Routing

1. Verify geo-steering is enabled (not random or round-robin)
2. Check region mappings are correctly configured
3. Use Cloudflare's "Test" feature to simulate requests from different regions

## References

- [Cloudflare Load Balancing](https://developers.cloudflare.com/load-balancing/)
- [Geo Steering](https://developers.cloudflare.com/load-balancing/understand-basics/traffic-steering/steering-policies/geo-steering/)
- [Health Checks](https://developers.cloudflare.com/load-balancing/monitors/)
- [Region Codes](https://developers.cloudflare.com/load-balancing/reference/region-mapping-api/#list-of-load-balancer-regions)
