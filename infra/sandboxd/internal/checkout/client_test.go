package checkout

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestClientSpeaksTheAgentsEndpoints(t *testing.T) {
	var cold bool
	agent := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		reader := bufio.NewReader(r.Body)
		line, _ := reader.ReadBytes('\n')
		var request agentRequest
		if err := json.Unmarshal(line, &request); err != nil || request.PodName != "sandboxd-x" || request.Grant != testGrant {
			t.Errorf("%s: request %q %v", r.URL.Path, line, err)
		}
		switch r.URL.Path {
		case "/sandbox-checkout/seed":
			if cold {
				w.WriteHeader(http.StatusNotFound)
				io.WriteString(w, `{"error":"cold"}`)
				return
			}
			io.WriteString(w, "tree")
		case "/sandbox-checkout/export":
			if rest, _ := io.ReadAll(reader); string(rest) != "archive" {
				t.Errorf("export body %q", rest)
			}
			w.WriteHeader(http.StatusAccepted)
		default:
			w.WriteHeader(http.StatusForbidden)
			io.WriteString(w, `{"error":"forbidden"}`)
		}
	}))
	defer agent.Close()
	client := &Client{URL: agent.URL + "/", PodName: "sandboxd-x", HTTP: agent.Client()}
	tree, err := client.Seed(context.Background(), testGrant)
	if err != nil {
		t.Fatal(err)
	}
	if data, _ := io.ReadAll(tree); string(data) != "tree" {
		t.Fatalf("seed %q", data)
	}
	tree.Close()
	cold = true
	if _, err := client.Seed(context.Background(), testGrant); !errors.Is(err, ErrCold) {
		t.Fatalf("cold seed: %v", err)
	}
	if err := client.Export(context.Background(), testGrant, strings.NewReader("archive")); err != nil {
		t.Fatal(err)
	}
	client.URL = agent.URL + "/elsewhere"
	if err := client.Export(context.Background(), testGrant, strings.NewReader("archive")); err == nil || !strings.Contains(err.Error(), "forbidden") {
		t.Fatalf("refused export: %v", err)
	}
}
