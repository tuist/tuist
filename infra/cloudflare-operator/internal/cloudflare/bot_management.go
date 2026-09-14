package cloudflare

import (
	"context"
	"fmt"
	"net/http"
)

// BotManagement mirrors the zone-scoped bot_management configuration
// Cloudflare returns from GET /zones/{zoneId}/bot_management. Fields
// are pointers so the caller can distinguish "server did not return
// this field" (e.g. plan tier without the feature) from "server
// returned a zero value". The reconciler needs that distinction to
// compute drift correctly against a CR that only sets a subset.
type BotManagement struct {
	// Bot Fight Mode / JS-detection tier.
	EnableJS             *bool `json:"enable_js,omitempty"`
	SuppressSessionScore *bool `json:"suppress_session_score,omitempty"`
	UsingLatestModel     *bool `json:"using_latest_model,omitempty"`

	// Super Bot Fight Mode tier (Business+).
	SBFMDefinitelyAutomated      *string `json:"sbfm_definitely_automated,omitempty"`
	SBFMLikelyAutomated          *string `json:"sbfm_likely_automated,omitempty"`
	SBFMVerifiedBots             *string `json:"sbfm_verified_bots,omitempty"`
	SBFMStaticResourceProtection *bool   `json:"sbfm_static_resource_protection,omitempty"`
	OptimizeWordpress            *bool   `json:"optimize_wordpress,omitempty"`

	// AI Crawl Control fields the endpoint also returns. We do not
	// model these in the CRD (see cloudflarebotmanagement_types.go),
	// but we decode them so an operator PATCH does not accidentally
	// clobber them when the wire representation is round-tripped.
	// The reconciler never sends these on a PATCH — it only sends
	// fields the CR explicitly sets — so decoding them is defensive,
	// not required.
	AIBotsProtection         *string `json:"ai_bots_protection,omitempty"`
	ContentBotsProtection    *string `json:"content_bots_protection,omitempty"`
	CrawlerProtection        *string `json:"crawler_protection,omitempty"`
	AITraining               *string `json:"ai_training,omitempty"`
	AISearch                 *string `json:"ai_search,omitempty"`
	AIUser                   *string `json:"ai_user,omitempty"`
	IsRobotsTxtManaged       *bool   `json:"is_robots_txt_managed,omitempty"`
	BotPreferenceSyncEnabled *bool   `json:"bot_preference_sync_enabled,omitempty"`
	CFRobotsVariant          *string `json:"cf_robots_variant,omitempty"`
	AIBotsMigrationOptOut    *bool   `json:"ai_bots_migration_opt_out,omitempty"`
}

// GetBotManagement returns the zone's current bot_management state.
// Cloudflare responds with all fields the zone's plan tier exposes;
// fields not applicable to the plan come back omitted.
func (c *Client) GetBotManagement(ctx context.Context, zoneID string) (*BotManagement, error) {
	path := fmt.Sprintf("/zones/%s/bot_management", zoneID)
	var wrapper struct {
		Result BotManagement `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodGet, path, nil, &wrapper); err != nil {
		return nil, err
	}
	return &wrapper.Result, nil
}

// UpdateBotManagement PUTs the zone's bot_management configuration.
//
// Cloudflare rejects PATCH on this endpoint (HTTP 405), so this is a
// full-state PUT: callers MUST pass the complete desired state (the
// reconciler builds it by GETing live state and overlaying only the
// fields the CR explicitly sets). Passing a sparse struct would leave
// Cloudflare-side fields that the caller does not manage — AI Crawl
// Control settings, for instance — omitted from the wire body via
// omitempty, and the wire behavior of a PUT-with-missing-fields on
// this endpoint is not documented as merge, so a sparse call could
// silently wipe those fields.
func (c *Client) UpdateBotManagement(ctx context.Context, zoneID string, patch BotManagement) (*BotManagement, error) {
	path := fmt.Sprintf("/zones/%s/bot_management", zoneID)
	var wrapper struct {
		Result BotManagement `json:"result"`
	}
	if _, err := c.do(ctx, http.MethodPut, path, patch, &wrapper); err != nil {
		return nil, err
	}
	return &wrapper.Result, nil
}
