package main

import (
	"context"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// listingResponseMaxBytes bounds the server's list, a few dozen entries.
const listingResponseMaxBytes = 1 << 20

// listing asks the server which custom HEADs this node should hold
// (`/runners/cache-volumes/masters`) and restores the ones it lacks, one at a
// time and only into free space, in the server's order: volumes runs keep
// reusing and left idle first, so an account's next working day starts warm.
// No job waits on it.
type listing struct {
	url, node, tokenPath string
	client               *http.Client
	local                func(cachevolumes.Identity) bool
	restore              func(context.Context, cachevolumes.Slot) error
	observe              cachevolumes.Observer
	installed            func(reason string, bytes int64)
	logger               *slog.Logger
	interval, budget     time.Duration
}

type listedMaster struct {
	Kind          string `json:"kind"`
	ID            string `json:"id"`
	AccountID     int64  `json:"account_id"`
	Scope         string `json:"scope"`
	Generation    int64  `json:"generation"`
	ImageDigest   string `json:"image_digest"`
	ContentDigest string `json:"content_digest"`
	VolumeBytes   int64  `json:"volume_bytes"`
	HeadSizeBytes int64  `json:"head_size_bytes"`
	Reason        string `json:"reason"`
}

func (m listedMaster) identity() cachevolumes.Identity {
	return cachevolumes.Identity{
		ID: m.ID, Account: m.AccountID, Scope: m.Scope, BaseGeneration: m.Generation, ImageDigest: m.ImageDigest,
		ContentDigest: m.ContentDigest, VolumeBytes: m.VolumeBytes, HeadSizeBytes: m.HeadSizeBytes,
	}
}

// listingReason bounds the prefetched-bytes label to the reasons the server sends.
func listingReason(reason string) string {
	if reason == "prewarm" {
		return reason
	}
	return "recent"
}

func (l *listing) run(ctx context.Context) {
	for {
		l.once(ctx)
		select {
		case <-ctx.Done():
			return
		case <-time.After(l.interval):
		}
	}
}

func (l *listing) once(ctx context.Context) {
	masters, err := l.masters(ctx)
	if err != nil {
		l.logger.Warn("list the masters to prefetch", "error", signedURL.ReplaceAllString(err.Error(), "<url>"))
		return
	}
	for _, master := range masters {
		identity := master.identity()
		if master.Kind != "custom" || identity.BaseGeneration <= 0 || l.local(identity) {
			continue
		}
		if ctx.Err() != nil {
			return
		}
		attempt, cancel := context.WithTimeout(ctx, l.budget)
		slot := cachevolumes.Slot{Identity: identity}
		done := l.observe.For(slot).Start("prefetch", "remote")
		err := l.restore(attempt, slot)
		done(err)
		cancel()
		if err == nil {
			l.installed(listingReason(master.Reason), identity.HeadSizeBytes)
		}
	}
}

func (l *listing) masters(ctx context.Context) ([]listedMaster, error) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, l.url+"?"+url.Values{"node_name": {l.node}}.Encode(), nil)
	if err != nil {
		return nil, err
	}
	token, err := os.ReadFile(l.tokenPath)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	response, err := l.client.Do(req)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("listing rejected: %d", response.StatusCode)
	}
	var body struct {
		Masters []listedMaster `json:"masters"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, listingResponseMaxBytes)).Decode(&body); err != nil {
		return nil, err
	}
	return body.Masters, nil
}
