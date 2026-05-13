package controllers

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strings"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const cloudflareAPIBaseURL = "https://api.cloudflare.com/client/v4"

type CloudflareLoadBalancingConfig struct {
	AccountID string
	ZoneID    string
	APIToken  string
}

func (c CloudflareLoadBalancingConfig) Enabled() bool {
	return c.AccountID != "" && c.ZoneID != "" && c.APIToken != ""
}

type cloudflareClient struct {
	baseURL    string
	accountID  string
	zoneID     string
	apiToken   string
	httpClient *http.Client
}

type cloudflarePool struct {
	ID             string             `json:"id,omitempty"`
	Name           string             `json:"name"`
	Description    string             `json:"description,omitempty"`
	Enabled        bool               `json:"enabled"`
	Latitude       *float64           `json:"latitude,omitempty"`
	Longitude      *float64           `json:"longitude,omitempty"`
	Origins        []cloudflareOrigin `json:"origins"`
	OriginSteering cloudflarePolicy   `json:"origin_steering"`
	MinimumOrigins int                `json:"minimum_origins"`
}

type cloudflareOrigin struct {
	Name    string              `json:"name"`
	Address string              `json:"address"`
	Enabled bool                `json:"enabled"`
	Weight  float64             `json:"weight"`
	Header  map[string][]string `json:"header,omitempty"`
}

type cloudflarePolicy struct {
	Policy string `json:"policy"`
}

type cloudflareLoadBalancer struct {
	ID             string   `json:"id,omitempty"`
	Name           string   `json:"name"`
	Description    string   `json:"description,omitempty"`
	Enabled        bool     `json:"enabled"`
	Proxied        bool     `json:"proxied"`
	TTL            int      `json:"ttl"`
	FallbackPool   string   `json:"fallback_pool"`
	DefaultPools   []string `json:"default_pools"`
	SteeringPolicy string   `json:"steering_policy"`
}

type cloudflareListResponse[T any] struct {
	Success bool              `json:"success"`
	Result  []T               `json:"result"`
	Errors  []cloudflareError `json:"errors"`
}

type cloudflareSingleResponse[T any] struct {
	Success bool              `json:"success"`
	Result  T                 `json:"result"`
	Errors  []cloudflareError `json:"errors"`
}

type cloudflareError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

func newCloudflareClient(config CloudflareLoadBalancingConfig) *cloudflareClient {
	return &cloudflareClient{
		baseURL:   cloudflareAPIBaseURL,
		accountID: config.AccountID,
		zoneID:    config.ZoneID,
		apiToken:  config.APIToken,
		httpClient: &http.Client{
			Timeout: 20 * time.Second,
		},
	}
}

func (c *cloudflareClient) reconcileKuraLoadBalancers(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	if instance.Spec.GlobalPublicHost != "" && instance.Spec.PublicHost != "" {
		if err := c.reconcileKuraLoadBalancer(ctx, instance, instance.Spec.GlobalPublicHost, instance.Spec.PublicHost, "https"); err != nil {
			return err
		}
	}
	if instance.Spec.GlobalGRPCPublicHost != "" && instance.Spec.GRPCPublicHost != "" {
		if err := c.reconcileKuraLoadBalancer(ctx, instance, instance.Spec.GlobalGRPCPublicHost, instance.Spec.GRPCPublicHost, "grpcs"); err != nil {
			return err
		}
	}
	return nil
}

func (c *cloudflareClient) deleteKuraLoadBalancers(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	if instance.Spec.GlobalPublicHost != "" {
		if err := c.removeKuraPool(ctx, instance, instance.Spec.GlobalPublicHost, "https"); err != nil {
			return err
		}
	}
	if instance.Spec.GlobalGRPCPublicHost != "" {
		if err := c.removeKuraPool(ctx, instance, instance.Spec.GlobalGRPCPublicHost, "grpcs"); err != nil {
			return err
		}
	}
	return nil
}

func (c *cloudflareClient) reconcileKuraLoadBalancer(ctx context.Context, instance *kurav1alpha1.KuraInstance, globalHost, originHost, protocol string) error {
	pool, err := c.upsertPool(ctx, desiredCloudflarePool(instance, globalHost, originHost, protocol))
	if err != nil {
		return err
	}

	pools, err := c.kuraPools(ctx, globalHost, protocol)
	if err != nil {
		return err
	}
	poolIDs := sortedPoolIDs(appendOrReplacePool(pools, pool))
	if len(poolIDs) == 0 {
		return nil
	}

	return c.upsertLoadBalancer(ctx, desiredCloudflareLoadBalancer(globalHost, protocol, poolIDs))
}

func desiredCloudflareLoadBalancer(globalHost, protocol string, poolIDs []string) cloudflareLoadBalancer {
	return cloudflareLoadBalancer{
		Name:           globalHost,
		Description:    fmt.Sprintf("Kura global DNS-routed %s endpoint for %s", protocol, globalHost),
		Enabled:        true,
		Proxied:        false,
		TTL:            30,
		FallbackPool:   poolIDs[0],
		DefaultPools:   poolIDs,
		SteeringPolicy: "proximity",
	}
}

func (c *cloudflareClient) removeKuraPool(ctx context.Context, instance *kurav1alpha1.KuraInstance, globalHost, protocol string) error {
	poolName := cloudflarePoolName(instance, globalHost, protocol)
	pools, err := c.kuraPools(ctx, globalHost, protocol)
	if err != nil {
		return err
	}

	remaining := make([]cloudflarePool, 0, len(pools))
	var poolID string
	for _, pool := range pools {
		if pool.Name == poolName {
			poolID = pool.ID
			continue
		}
		remaining = append(remaining, pool)
	}

	loadBalancer, err := c.loadBalancerByName(ctx, globalHost)
	if err != nil {
		return err
	}
	if loadBalancer != nil {
		poolIDs := sortedPoolIDs(remaining)
		if len(poolIDs) == 0 {
			if err := c.deleteLoadBalancer(ctx, loadBalancer.ID); err != nil {
				return err
			}
		} else {
			loadBalancer.DefaultPools = poolIDs
			loadBalancer.FallbackPool = poolIDs[0]
			loadBalancer.Proxied = false
			loadBalancer.TTL = 30
			loadBalancer.SteeringPolicy = "proximity"
			if err := c.updateLoadBalancer(ctx, *loadBalancer); err != nil {
				return err
			}
		}
	}

	if poolID != "" {
		return c.deletePool(ctx, poolID)
	}
	return nil
}

func desiredCloudflarePool(instance *kurav1alpha1.KuraInstance, globalHost, originHost, protocol string) cloudflarePool {
	return cloudflarePool{
		Name:           cloudflarePoolName(instance, globalHost, protocol),
		Description:    fmt.Sprintf("Kura %s regional endpoint for %s in %s", protocol, instance.Spec.AccountHandle, instance.Spec.Region),
		Enabled:        true,
		Latitude:       instance.Spec.CloudflarePoolLatitude,
		Longitude:      instance.Spec.CloudflarePoolLongitude,
		MinimumOrigins: 1,
		OriginSteering: cloudflarePolicy{Policy: "random"},
		Origins: []cloudflareOrigin{{
			Name:    instance.Spec.Region,
			Address: originHost,
			Enabled: true,
			Weight:  1,
			Header: map[string][]string{
				"Host": []string{originHost},
			},
		}},
	}
}

func cloudflarePoolName(instance *kurav1alpha1.KuraInstance, globalHost, protocol string) string {
	return strings.ToLower(fmt.Sprintf("tuist-kura-%s-%s-%s", protocol, globalHost, instance.Spec.Region))
}

func cloudflarePoolPrefix(globalHost, protocol string) string {
	return strings.ToLower(fmt.Sprintf("tuist-kura-%s-%s-", protocol, globalHost))
}

func appendOrReplacePool(pools []cloudflarePool, pool cloudflarePool) []cloudflarePool {
	replaced := false
	for index := range pools {
		if pools[index].Name == pool.Name {
			pools[index] = pool
			replaced = true
		}
	}
	if !replaced {
		pools = append(pools, pool)
	}
	return pools
}

func sortedPoolIDs(pools []cloudflarePool) []string {
	sort.Slice(pools, func(i, j int) bool {
		return pools[i].Name < pools[j].Name
	})
	ids := make([]string, 0, len(pools))
	for _, pool := range pools {
		if pool.ID != "" {
			ids = append(ids, pool.ID)
		}
	}
	return ids
}

func (c *cloudflareClient) upsertPool(ctx context.Context, pool cloudflarePool) (cloudflarePool, error) {
	existing, err := c.poolByName(ctx, pool.Name)
	if err != nil {
		return cloudflarePool{}, err
	}
	if existing == nil {
		return c.createPool(ctx, pool)
	}
	pool.ID = existing.ID
	return c.updatePool(ctx, pool)
}

func (c *cloudflareClient) upsertLoadBalancer(ctx context.Context, loadBalancer cloudflareLoadBalancer) error {
	existing, err := c.loadBalancerByName(ctx, loadBalancer.Name)
	if err != nil {
		return err
	}
	if existing == nil {
		_, err := c.createLoadBalancer(ctx, loadBalancer)
		return err
	}
	loadBalancer.ID = existing.ID
	return c.updateLoadBalancer(ctx, loadBalancer)
}

func (c *cloudflareClient) kuraPools(ctx context.Context, globalHost, protocol string) ([]cloudflarePool, error) {
	pools, err := c.listPools(ctx)
	if err != nil {
		return nil, err
	}
	prefix := cloudflarePoolPrefix(globalHost, protocol)
	result := []cloudflarePool{}
	for _, pool := range pools {
		if strings.HasPrefix(pool.Name, prefix) {
			result = append(result, pool)
		}
	}
	return result, nil
}

func (c *cloudflareClient) poolByName(ctx context.Context, name string) (*cloudflarePool, error) {
	pools, err := c.listPools(ctx)
	if err != nil {
		return nil, err
	}
	for _, pool := range pools {
		if pool.Name == name {
			return &pool, nil
		}
	}
	return nil, nil
}

func (c *cloudflareClient) loadBalancerByName(ctx context.Context, name string) (*cloudflareLoadBalancer, error) {
	loadBalancers, err := c.listLoadBalancers(ctx)
	if err != nil {
		return nil, err
	}
	for _, loadBalancer := range loadBalancers {
		if loadBalancer.Name == name {
			return &loadBalancer, nil
		}
	}
	return nil, nil
}

func (c *cloudflareClient) listPools(ctx context.Context) ([]cloudflarePool, error) {
	var response cloudflareListResponse[cloudflarePool]
	err := c.do(ctx, http.MethodGet, fmt.Sprintf("/accounts/%s/load_balancers/pools?per_page=1000", c.accountID), nil, &response)
	return response.Result, err
}

func (c *cloudflareClient) createPool(ctx context.Context, pool cloudflarePool) (cloudflarePool, error) {
	var response cloudflareSingleResponse[cloudflarePool]
	err := c.do(ctx, http.MethodPost, fmt.Sprintf("/accounts/%s/load_balancers/pools", c.accountID), pool, &response)
	return response.Result, err
}

func (c *cloudflareClient) updatePool(ctx context.Context, pool cloudflarePool) (cloudflarePool, error) {
	var response cloudflareSingleResponse[cloudflarePool]
	err := c.do(ctx, http.MethodPut, fmt.Sprintf("/accounts/%s/load_balancers/pools/%s", c.accountID, pool.ID), pool, &response)
	return response.Result, err
}

func (c *cloudflareClient) deletePool(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodDelete, fmt.Sprintf("/accounts/%s/load_balancers/pools/%s", c.accountID, id), nil, nil)
}

func (c *cloudflareClient) listLoadBalancers(ctx context.Context) ([]cloudflareLoadBalancer, error) {
	var response cloudflareListResponse[cloudflareLoadBalancer]
	err := c.do(ctx, http.MethodGet, fmt.Sprintf("/zones/%s/load_balancers?per_page=1000", c.zoneID), nil, &response)
	return response.Result, err
}

func (c *cloudflareClient) createLoadBalancer(ctx context.Context, loadBalancer cloudflareLoadBalancer) (cloudflareLoadBalancer, error) {
	var response cloudflareSingleResponse[cloudflareLoadBalancer]
	err := c.do(ctx, http.MethodPost, fmt.Sprintf("/zones/%s/load_balancers", c.zoneID), loadBalancer, &response)
	return response.Result, err
}

func (c *cloudflareClient) updateLoadBalancer(ctx context.Context, loadBalancer cloudflareLoadBalancer) error {
	var response cloudflareSingleResponse[cloudflareLoadBalancer]
	return c.do(ctx, http.MethodPut, fmt.Sprintf("/zones/%s/load_balancers/%s", c.zoneID, loadBalancer.ID), loadBalancer, &response)
}

func (c *cloudflareClient) deleteLoadBalancer(ctx context.Context, id string) error {
	return c.do(ctx, http.MethodDelete, fmt.Sprintf("/zones/%s/load_balancers/%s", c.zoneID, id), nil, nil)
}

func (c *cloudflareClient) do(ctx context.Context, method, path string, body any, response any) error {
	var reader io.Reader
	if body != nil {
		encoded, err := json.Marshal(body)
		if err != nil {
			return err
		}
		reader = bytes.NewReader(encoded)
	}

	endpoint := strings.TrimRight(c.baseURL, "/") + path
	request, err := http.NewRequestWithContext(ctx, method, endpoint, reader)
	if err != nil {
		return err
	}
	request.Header.Set("Authorization", "Bearer "+c.apiToken)
	request.Header.Set("Content-Type", "application/json")

	httpResponse, err := c.httpClient.Do(request)
	if err != nil {
		return err
	}
	defer httpResponse.Body.Close()

	responseBody, err := io.ReadAll(httpResponse.Body)
	if err != nil {
		return err
	}
	if httpResponse.StatusCode < 200 || httpResponse.StatusCode >= 300 {
		return fmt.Errorf("cloudflare %s %s failed with status %d: %s", method, path, httpResponse.StatusCode, string(responseBody))
	}
	if response == nil || len(responseBody) == 0 {
		return nil
	}
	if err := json.Unmarshal(responseBody, response); err != nil {
		return err
	}
	return cloudflareResponseError(response)
}

func cloudflareResponseError(response any) error {
	switch value := response.(type) {
	case *cloudflareListResponse[cloudflarePool]:
		if !value.Success {
			return fmt.Errorf("cloudflare API error: %v", value.Errors)
		}
	case *cloudflareListResponse[cloudflareLoadBalancer]:
		if !value.Success {
			return fmt.Errorf("cloudflare API error: %v", value.Errors)
		}
	case *cloudflareSingleResponse[cloudflarePool]:
		if !value.Success {
			return fmt.Errorf("cloudflare API error: %v", value.Errors)
		}
	case *cloudflareSingleResponse[cloudflareLoadBalancer]:
		if !value.Success {
			return fmt.Errorf("cloudflare API error: %v", value.Errors)
		}
	}
	return nil
}
