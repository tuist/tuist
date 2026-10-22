package main

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

// The agent lists its own node's HEADs as itself and restores, in the server's
// order, only the ones it lacks, counting what it installed by reason.
func TestListingRestoresTheListedMastersItLacksInOrder(t *testing.T) {
	token := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(token, []byte("agent-token\n"), 0600); err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet || r.URL.Path != "/masters" || r.URL.Query().Get("node_name") != "linux-01" || r.Header.Get("Authorization") != "Bearer agent-token" {
			http.Error(w, "unexpected request", http.StatusForbidden)
			return
		}
		_, _ = io.WriteString(w, `{"masters": [
			{"kind": "custom", "id": "held", "scope": "`+strings.Repeat("a", 64)+`", "generation": 3, "head_size_bytes": 1, "reason": "prewarm"},
			{"kind": "custom", "id": "idle", "scope": "`+strings.Repeat("b", 64)+`", "generation": 2, "head_size_bytes": 100, "reason": "prewarm"},
			{"kind": "custom", "id": "unsaved", "scope": "`+strings.Repeat("c", 64)+`", "generation": 0, "reason": "prewarm"},
			{"kind": "custom", "id": "full", "scope": "`+strings.Repeat("d", 64)+`", "generation": 4, "head_size_bytes": 1000, "reason": "recent"},
			{"kind": "custom", "id": "recent", "account_id": 7, "scope": "`+strings.Repeat("e", 64)+`", "generation": 5, "image_digest": "i", "content_digest": "c", "volume_bytes": 20000000000, "head_size_bytes": 20},
			{"kind": "builtin", "id": "other", "scope": "`+strings.Repeat("f", 64)+`", "generation": 1}
		]}`)
	}))
	defer server.Close()

	var restored []cachevolumes.Slot
	installed := map[string]int64{}
	l := &listing{
		url: server.URL + "/masters", node: "linux-01", tokenPath: token, client: server.Client(),
		local: func(identity cachevolumes.Identity) bool { return identity.ID == "held" },
		restore: func(ctx context.Context, slot cachevolumes.Slot) error {
			if _, ok := ctx.Deadline(); !ok {
				t.Error("restore without a deadline")
			}
			restored = append(restored, slot)
			if slot.ID == "full" {
				return cachevolumes.ErrCapacity
			}
			return nil
		},
		installed: func(reason string, bytes int64) { installed[reason] += bytes },
		logger:    slog.New(slog.NewTextHandler(io.Discard, nil)), budget: time.Minute,
	}
	l.once(context.Background())

	var ids []string
	for _, slot := range restored {
		ids = append(ids, slot.ID)
	}
	if strings.Join(ids, ",") != "idle,full,recent" {
		t.Fatal("restored", ids)
	}
	want := cachevolumes.Identity{ID: "recent", Account: 7, Scope: strings.Repeat("e", 64), BaseGeneration: 5, ImageDigest: "i", ContentDigest: "c", VolumeBytes: 20_000_000_000, HeadSizeBytes: 20}
	if restored[2].Identity != want {
		t.Fatalf("listed identity = %+v", restored[2].Identity)
	}
	if installed["prewarm"] != 100 || installed["recent"] != 20 || len(installed) != 2 {
		t.Fatal("installed bytes", installed)
	}
}

func TestListingRestoresNothingWhenTheServerRefuses(t *testing.T) {
	token := filepath.Join(t.TempDir(), "token")
	if err := os.WriteFile(token, []byte("agent-token"), 0600); err != nil {
		t.Fatal(err)
	}
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "", http.StatusForbidden)
	}))
	defer server.Close()
	l := &listing{
		url: server.URL + "/masters", node: "linux-01", tokenPath: token, client: server.Client(),
		local:     func(cachevolumes.Identity) bool { return false },
		restore:   func(context.Context, cachevolumes.Slot) error { return errors.New("restored") },
		installed: func(string, int64) { t.Error("counted a master") },
		logger:    slog.New(slog.NewTextHandler(io.Discard, nil)), budget: time.Minute,
	}
	if _, err := l.masters(context.Background()); err == nil {
		t.Fatal("accepted a refused listing")
	}
	l.once(context.Background())
}
