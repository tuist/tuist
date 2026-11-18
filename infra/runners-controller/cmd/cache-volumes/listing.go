package main

import (
	"context"
	"encoding/json"
	"errors"
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

// listing asks the server which custom and checkout HEADs this node should hold
// (`/runners/cache-volumes/masters`) and restores the ones it lacks, one at a
// time and only into free space, in the server's order: volumes runs keep
// reusing and left idle first, so an account's next working day starts warm.
// Checkout HEADs go to the checkout populator as spare restores.
// No job waits on it.
type listing struct {
	url, node, tokenPath string
	client               *http.Client
	local                func(cachevolumes.Identity) bool
	restore              func(context.Context, cachevolumes.Slot) error
	// checkout queues a spare restore of a listed checkout HEAD (prefetchCheckout).
	checkout         func(cachevolumes.CheckoutTask) bool
	observe          cachevolumes.Observer
	installed        func(reason string, bytes int64)
	logger           *slog.Logger
	interval, budget time.Duration
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

	CheckoutGeneration int64  `json:"checkout_generation"`
	CloneURL           string `json:"clone_url"`
	DefaultBranch      string `json:"default_branch"`
	UID                int    `json:"uid"`
	VolumeKey          string `json:"volume_key"`
}

func (m listedMaster) checkoutTask() cachevolumes.CheckoutTask {
	return cachevolumes.CheckoutTask{
		Scope: m.Scope, Generation: m.CheckoutGeneration, CloneURL: m.CloneURL, DefaultBranch: m.DefaultBranch,
		Use: m.ID, BaseGeneration: m.Generation, ImageDigest: m.ImageDigest, ContentDigest: m.ContentDigest,
		UID: m.UID, VolumeKey: m.VolumeKey, Spare: true,
	}
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
		if master.Kind == cachevolumes.KindCheckout {
			if l.checkout != nil {
				l.checkout(master.checkoutTask())
			}
			continue
		}
		identity := master.identity()
		if master.Kind != "custom" || identity.BaseGeneration <= 0 {
			continue
		}
		if l.local(identity) {
			l.decided(master, "held", nil)
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
		switch {
		case err == nil:
			l.installed(listingReason(master.Reason), identity.HeadSizeBytes)
			l.decided(master, "restored", nil)
		case errors.Is(err, cachevolumes.ErrCapacity):
			l.decided(master, "no_space", err)
		default:
			l.decided(master, "failed", err)
		}
	}
}

// decided logs what the host did with one listed custom master, so a cold
// attach can be traced to a host that held it, had no room for it, or failed
// to restore it.
func (l *listing) decided(master listedMaster, decision string, err error) {
	attrs := []any{"decision", decision, "scope", master.Scope, "generation", master.Generation, "reason", listingReason(master.Reason), "head_size_bytes", master.HeadSizeBytes}
	if err != nil {
		attrs = append(attrs, "error", signedURL.ReplaceAllString(err.Error(), "<url>"))
	}
	l.logger.Info("prefetch listed master", attrs...)
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
