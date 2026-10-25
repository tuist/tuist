package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"sort"
	"strconv"
	"strings"
	"time"
)

// The job's Docker data root is a repository cache volume the host exposes as
// an unmounted ext4 image in the pod's cache directory. The job-start hook asks
// the sidecar's supervisor to move dockerd onto it; after the job the supervisor
// keeps only images and build cache, removes every tag, unmounts it and reports
// what it kept. Any failure leaves dockerd on the job's ephemeral data root.
const (
	dockerStatePath = "/home/runner/.tuist-docker.json"
	dockerImageName = "docker.img"
	dockerReport    = "docker.json"
	// dockerInternalRepository names the internal reference that keeps an image's
	// content once its registry tags are removed.
	dockerInternalRepository = "tuist-docker-cache"
	// dockerImageRetention drops images no job pulled, ran or built for this long.
	dockerImageRetention = 14 * 24 * time.Hour
	// dockerLedgerRefresh republishes an unchanged data root whose saved
	// last-use times are this stale, so retention reads current times.
	dockerLedgerRefresh = 24 * time.Hour
	// dockerBuildCacheBudget is what the build cache keeps.
	dockerBuildCacheBudget = "10gb"
	dockerReferenceLimit   = 16
)

var dockerImageID = regexp.MustCompile(`^sha256:[a-f0-9]{64}$`)
var dockerReferencePattern = regexp.MustCompile(`^[a-zA-Z0-9][a-zA-Z0-9._/:@-]{0,254}$`)

// dockerMessage is a request to the sidecar's supervisor over the mount socket.
type dockerMessage struct {
	Docker string `json:"docker"`
	Source string `json:"source,omitempty"`
}

// dockerHookState is what the job-start hook leaves for the teardown.
type dockerHookState struct {
	Mounted bool   `json:"mounted"`
	Reason  string `json:"reason,omitempty"`
}

// dockerJob asks the host for the job's data root and moves dockerd onto it. It
// never fails the job; the result is the line the hook prints.
func dockerJob(ctx context.Context, root, statePath string, request func(context.Context) (macResponse, error), send func(dockerMessage) error) string {
	response, err := request(ctx)
	if err != nil {
		return "unavailable (request)"
	}
	if response.Error != "" || !directoryPattern.MatchString(response.Directory) || response.ID == "" {
		reason := response.Reason
		if !reasonPattern.MatchString(reason) {
			reason = "error"
		}
		_ = writeDockerState(statePath, dockerHookState{Reason: reason})
		return "unavailable (" + reason + ")"
	}
	base := filepath.Join(root, response.Directory)
	if proof, err := os.ReadFile(filepath.Join(base, ".tuist-volume")); err != nil || string(proof) != response.ID {
		return "unavailable (not exposed)"
	}
	if info, err := os.Lstat(filepath.Join(base, dockerImageName)); err != nil || !info.Mode().IsRegular() {
		return "unavailable (no image)"
	}
	if err := send(dockerMessage{Docker: "switch", Source: response.Directory + "/" + dockerImageName}); err != nil {
		fmt.Fprintf(os.Stderr, "Tuist Docker cache: %v\n", err)
		return "unavailable (switch failed)"
	}
	_ = writeDockerState(statePath, dockerHookState{Mounted: true})
	if response.Warm {
		return "reused"
	}
	return "started empty"
}

// dockerTeardown runs after the job. A mounted data root is cleaned and
// unmounted by the supervisor; a job that had none reports whether it used
// Docker, so the repository's next jobs get one.
func dockerTeardown(statePath string, send func(dockerMessage) error, images func() ([]string, error), seen func() error) string {
	data, err := os.ReadFile(statePath)
	if err != nil {
		return "skipped"
	}
	var state dockerHookState
	if err := json.Unmarshal(data, &state); err != nil {
		return "skipped"
	}
	if state.Mounted {
		if err := send(dockerMessage{Docker: "teardown"}); err != nil {
			return "failed (" + err.Error() + ")"
		}
		return "saved for the host to verify"
	}
	if state.Reason != "unseen" {
		return "skipped"
	}
	ids, err := images()
	if err != nil || len(ids) == 0 {
		return "skipped (no images)"
	}
	if err := seen(); err != nil {
		return "failed (" + err.Error() + ")"
	}
	return "repository marked as using Docker"
}

func writeDockerState(path string, state dockerHookState) error {
	data, err := json.Marshal(state)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0644)
}

type dockerHTTPClient struct {
	endpoint, pod, uid string
	http               *http.Client
}

func newDockerHTTPClient(timeout time.Duration) *dockerHTTPClient {
	return &dockerHTTPClient{
		endpoint: os.Getenv("TUIST_CACHE_VOLUME_URL"), pod: os.Getenv("TUIST_CACHE_VOLUME_POD"), uid: os.Getenv("TUIST_CACHE_VOLUME_UID"),
		http: &http.Client{Timeout: timeout, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }},
	}
}

func (c *dockerHTTPClient) newRequest(ctx context.Context, path string) (*http.Request, error) {
	if c.endpoint == "" {
		return nil, errors.New("cache volumes disabled")
	}
	body, _ := json.Marshal(map[string]any{"pod_name": c.pod, "pod_uid": c.uid})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint+path, bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	return req, nil
}

func (c *dockerHTTPClient) request(ctx context.Context) (macResponse, error) {
	var response macResponse
	req, err := c.newRequest(ctx, "/docker")
	if err != nil {
		return response, err
	}
	err = requestJSON(c.http, req, &response)
	return response, err
}

func (c *dockerHTTPClient) seen(ctx context.Context) error {
	req, err := c.newRequest(ctx, "/docker-seen")
	if err != nil {
		return err
	}
	response, err := c.http.Do(req)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusNoContent {
		return fmt.Errorf("host returned %d", response.StatusCode)
	}
	return nil
}

// dockerImageIDs lists the images of the daemon the job used.
func dockerImageIDs() ([]string, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "docker", "image", "ls", "-aq", "--no-trunc").Output()
	if err != nil {
		return nil, err
	}
	return strings.Fields(string(out)), nil
}

// dockerLedger records when a job last pulled, ran or built each image the data
// root keeps, and the references jobs used for it. It lives in the data root.
type dockerLedger map[string]dockerLedgerEntry

type dockerLedgerEntry struct {
	LastUsedAt time.Time `json:"last_used_at"`
	References []string  `json:"references"`
}

// dockerImage is an image as `docker image inspect` reports it.
type dockerImage struct {
	ID          string   `json:"Id"`
	RepoTags    []string `json:"RepoTags"`
	RepoDigests []string `json:"RepoDigests"`
	Size        int64    `json:"Size"`
}

// externalReferences are the image's registry references, every one but the
// internal reference teardown keeps it under.
func (i dockerImage) externalReferences() []string {
	var references []string
	for _, reference := range append(append([]string{}, i.RepoTags...), i.RepoDigests...) {
		if !strings.HasPrefix(reference, dockerInternalRepository+":") && !strings.HasPrefix(reference, dockerInternalRepository+"@") && reference != "<none>:<none>" && reference != "<none>@<none>" {
			references = append(references, reference)
		}
	}
	return references
}

func dockerInternalReference(id string) string {
	return dockerInternalRepository + ":" + strings.TrimPrefix(id, "sha256:")
}

// dockerPlan is what teardown does to the data root's images.
type dockerPlan struct {
	// Keep are the images that stay, with their ledger entries.
	Keep dockerLedger
	// Remove are the images no job used within the retention.
	Remove []string
	// Untag are the registry references to remove from kept images.
	Untag []string
	// Tag are the kept images that still need their internal reference.
	Tag []string
	// Stale reports a kept image whose saved last use is older than the refresh.
	Stale bool
}

// planDockerTeardown decides what survives. A job used an image when one of
// its containers ran it, or when it has a registry reference: teardown removes
// every registry reference, so one present now was pulled, tagged or built by
// this job.
func planDockerTeardown(images []dockerImage, containerImages map[string]bool, saved dockerLedger, now time.Time) dockerPlan {
	plan := dockerPlan{Keep: dockerLedger{}}
	for _, image := range images {
		if !dockerImageID.MatchString(image.ID) {
			continue
		}
		external := image.externalReferences()
		entry, known := saved[image.ID]
		used := containerImages[image.ID] || len(external) > 0 || !known
		if used {
			entry.LastUsedAt = now
			entry.References = mergeReferences(external, entry.References)
		} else if now.Sub(entry.LastUsedAt) > dockerImageRetention {
			plan.Remove = append(plan.Remove, image.ID)
			continue
		}
		if known && now.Sub(saved[image.ID].LastUsedAt) > dockerLedgerRefresh && used {
			plan.Stale = true
		}
		plan.Keep[image.ID] = entry
		plan.Untag = append(plan.Untag, external...)
		if !slices.Contains(image.RepoTags, dockerInternalReference(image.ID)) {
			plan.Tag = append(plan.Tag, image.ID)
		}
	}
	sort.Strings(plan.Remove)
	sort.Strings(plan.Untag)
	sort.Strings(plan.Tag)
	return plan
}

// mergeReferences keeps the most recent references first, valid and bounded.
func mergeReferences(recent, older []string) []string {
	var merged []string
	for _, reference := range append(append([]string{}, recent...), older...) {
		if dockerReferencePattern.MatchString(reference) && !slices.Contains(merged, reference) && len(merged) < dockerReferenceLimit {
			merged = append(merged, reference)
		}
	}
	return merged
}

// dockerTeardownReport is the report the host reads beside the image.
type dockerTeardownReport struct {
	Clean           bool                  `json:"clean"`
	Changed         bool                  `json:"changed"`
	Images          []dockerReportedImage `json:"images"`
	BuildCacheBytes int64                 `json:"build_cache_bytes"`
}

type dockerReportedImage struct {
	ID         string    `json:"id"`
	References []string  `json:"references"`
	SizeBytes  int64     `json:"size_bytes"`
	LastUsedAt time.Time `json:"last_used_at"`
}

// dockerSnapshot is what decides whether a data root changed: its images and
// the bytes its build cache holds.
type dockerSnapshot struct {
	Images          []string
	BuildCacheBytes int64
}

func (s dockerSnapshot) differs(other dockerSnapshot) bool {
	a, b := slices.Clone(s.Images), slices.Clone(other.Images)
	sort.Strings(a)
	sort.Strings(b)
	return !slices.Equal(a, b) || s.BuildCacheBytes != other.BuildCacheBytes
}

func dockerReportImages(images []dockerImage, keep dockerLedger) []dockerReportedImage {
	var reported []dockerReportedImage
	for _, image := range images {
		entry, ok := keep[image.ID]
		if !ok {
			continue
		}
		references := entry.References
		if references == nil {
			references = []string{}
		}
		reported = append(reported, dockerReportedImage{ID: image.ID, References: references, SizeBytes: image.Size, LastUsedAt: entry.LastUsedAt.UTC().Truncate(time.Second)})
	}
	sort.Slice(reported, func(i, j int) bool { return reported[i].LastUsedAt.After(reported[j].LastUsedAt) })
	return reported
}

var humanSize = regexp.MustCompile(`^([0-9]+(?:\.[0-9]+)?)\s*([kKMGTP]?B)$`)

// parseHumanSize reads a size as `docker system df` prints it, such as 1.2GB.
func parseHumanSize(value string) (int64, bool) {
	match := humanSize.FindStringSubmatch(strings.TrimSpace(value))
	if match == nil {
		return 0, false
	}
	number, err := strconv.ParseFloat(match[1], 64)
	if err != nil {
		return 0, false
	}
	multiplier := map[string]float64{"B": 1, "kB": 1e3, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12, "PB": 1e15}[match[2]]
	return int64(number * multiplier), true
}

func dockerSocket() string {
	return filepath.Join(filepath.Dir(linuxCacheRoot), ".tuist-cache-mount.sock")
}

// dockerLinux runs in the job-start hook, beside the cached checkout, within the
// same window.
func dockerLinux() string {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	client := newDockerHTTPClient(20 * time.Second)
	return dockerJob(ctx, linuxCacheRoot, dockerStatePath, client.request, func(message dockerMessage) error {
		return sendDocker(dockerSocket(), message)
	})
}

// dockerTeardownLinux runs after the runner exits, outside the job's time.
func dockerTeardownLinux() string {
	client := newDockerHTTPClient(15 * time.Second)
	return dockerTeardown(dockerStatePath, func(message dockerMessage) error {
		return sendDocker(dockerSocket(), message)
	}, dockerImageIDs, func() error {
		ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		return client.seen(ctx)
	})
}

// remainingReferences are the registry references teardown failed to remove.
func remainingReferences(images []dockerImage) []string {
	var remaining []string
	for _, image := range images {
		remaining = append(remaining, image.externalReferences()...)
	}
	sort.Strings(remaining)
	return remaining
}
