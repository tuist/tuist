package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"time"
)

// A job's GitHub OIDC token, at most 16 KiB, with the pod it came from.
const executionRequestLimit = 20 << 10

type executionRequest struct {
	PodName string `json:"pod_name"`
	PodUID  string `json:"pod_uid"`
	Token   string `json:"token"`
}

// serveExecution forwards the GitHub OIDC token a job minted for itself, so the
// server binds the pod's session to that job without waiting for GitHub's
// report. Only the pod itself may present it, and the agent never reads it.
func (a *agent) serveExecution(w http.ResponseWriter, r *http.Request) {
	var input executionRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, executionRequestLimit)).Decode(&input); err != nil || input.Token == "" {
		http.Error(w, "invalid request", http.StatusBadRequest)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 10*time.Second)
	defer cancel()
	if !a.runnerPod(ctx, r, input.PodName, input.PodUID) {
		http.Error(w, "unavailable", http.StatusForbidden)
		return
	}
	body, _ := json.Marshal(map[string]any{"pod_name": input.PodName, "pod_uid": input.PodUID, "node_name": a.node, "token": input.Token})
	var ignored struct{}
	status, err := a.allocateOnce(ctx, a.serverURL("/execution"), body, &ignored)
	if err != nil || status != http.StatusOK {
		log.Printf("execution token for pod %s not accepted: status %d", input.PodName, status)
		http.Error(w, "unavailable", http.StatusForbidden)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	w.Write([]byte("{}"))
}
