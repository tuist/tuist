package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"

	"github.com/tuist/tuist/infra/runner-cache"
)

func TestPublicationPreflightChecksumAndRetry(t *testing.T) {
	phase := "normal"
	puts, publishes := 0, 0
	object := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != "PUT" || r.Header.Get("x-amz-checksum-sha256") != "checksum" || r.Header.Get("Authorization") != "" {
			t.Error("unsafe object upload")
		}
		puts++
		w.WriteHeader(200)
	}))
	defer object.Close()
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("Authorization") != "Bearer trusted" {
			t.Error("missing node credential")
		}
		var body map[string]any
		json.NewDecoder(r.Body).Decode(&body)
		if body["node_name"] != "host" || body["id"] != "lease" {
			t.Error("lost allocation identity")
		}
		if phase == "stale" {
			w.WriteHeader(409)
			return
		}
		if phase == "retry" {
			json.NewEncoder(w).Encode(map[string]int{"generation": 2})
			return
		}
		if body["operation"] == "upload" {
			json.NewEncoder(w).Encode(map[string]string{"upload_url": object.URL, "checksum_sha256": "checksum"})
			return
		}
		publishes++
		json.NewEncoder(w).Encode(map[string]int{"generation": 2})
	}))
	defer upstream.Close()
	dir := t.TempDir()
	token := filepath.Join(dir, "token")
	os.WriteFile(token, []byte("trusted"), 0600)
	archive := filepath.Join(dir, "image.gz")
	os.WriteFile(archive, []byte("archive"), 0600)
	transfer := &imageTransfer{URL: upstream.URL, Node: "host", TokenPath: token, Client: upstream.Client()}
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{ID: "lease", BaseGeneration: 1}}
	if n, err := transfer.Publish(slot, archive, "digest", "content"); n != 2 || err != nil {
		t.Fatal(n, err)
	}
	if puts != 1 || publishes != 1 {
		t.Fatal(puts, publishes)
	}
	phase = "retry"
	if _, err := transfer.Publish(slot, archive, "digest", "content"); err != nil {
		t.Fatal(err)
	}
	phase = "stale"
	if _, err := transfer.Publish(slot, archive, "digest", "content"); err != cachevolumes.ErrConflict {
		t.Fatal(err)
	}
	if puts != 1 || publishes != 1 {
		t.Fatal("retried or doomed image uploaded", puts, publishes)
	}
}
