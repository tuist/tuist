package main

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

var dockerTestScope = digest("docker-scope")

func dockerVolumeDirectory(t *testing.T, id string) string {
	t.Helper()
	root := t.TempDir()
	dir := filepath.Join(root, dockerTestScope)
	if err := os.MkdirAll(dir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, ".tuist-volume"), []byte(id), 0644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, dockerImageName), []byte("image"), 0644); err != nil {
		t.Fatal(err)
	}
	return root
}

func readDockerState(t *testing.T, path string) dockerHookState {
	t.Helper()
	var state dockerHookState
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := json.Unmarshal(data, &state); err != nil {
		t.Fatal(err)
	}
	return state
}

func TestDockerJobSwitchesOntoTheGrantedImage(t *testing.T) {
	root := dockerVolumeDirectory(t, "use")
	statePath := filepath.Join(t.TempDir(), "state.json")
	var sent []dockerMessage
	result := dockerJob(context.Background(), root, statePath,
		func(context.Context) (macResponse, error) {
			return macResponse{Directory: dockerTestScope, ID: "use", Warm: true}, nil
		},
		func(message dockerMessage) (string, error) { sent = append(sent, message); return "ok", nil })
	if result != "reused" {
		t.Fatalf("result %q", result)
	}
	if len(sent) != 1 || sent[0] != (dockerMessage{Docker: "switch", Source: dockerTestScope + "/" + dockerImageName}) {
		t.Fatalf("sent %v", sent)
	}
	if !readDockerState(t, statePath).Mounted {
		t.Fatal("hook did not record the mounted data root")
	}
}

func TestDockerJobLeavesTheEphemeralRootWithoutAProvenGrant(t *testing.T) {
	for name, test := range map[string]struct {
		response macResponse
		err      error
		want     string
		reason   string
	}{
		"request failed":  {err: errors.New("down"), want: "unavailable (request)"},
		"unseen":          {response: macResponse{Error: "unavailable", Reason: "unseen"}, want: "unavailable (unseen)", reason: "unseen"},
		"invalid reason":  {response: macResponse{Error: "unavailable", Reason: "Not A Reason"}, want: "unavailable (error)", reason: "error"},
		"other directory": {response: macResponse{Directory: digest("other"), ID: "use"}, want: "unavailable (not exposed)"},
		"other lease":     {response: macResponse{Directory: dockerTestScope, ID: "someone-else"}, want: "unavailable (not exposed)"},
	} {
		t.Run(name, func(t *testing.T) {
			root := dockerVolumeDirectory(t, "use")
			statePath := filepath.Join(t.TempDir(), "state.json")
			result := dockerJob(context.Background(), root, statePath,
				func(context.Context) (macResponse, error) { return test.response, test.err },
				func(dockerMessage) (string, error) { t.Fatal("switched without a proven grant"); return "", nil })
			if result != test.want {
				t.Fatalf("result %q, want %q", result, test.want)
			}
			if test.reason != "" && readDockerState(t, statePath).Reason != test.reason {
				t.Fatalf("state %v", readDockerState(t, statePath))
			}
		})
	}
}

func TestDockerJobReportsAFailedSwitch(t *testing.T) {
	root := dockerVolumeDirectory(t, "use")
	statePath := filepath.Join(t.TempDir(), "state.json")
	result := dockerJob(context.Background(), root, statePath,
		func(context.Context) (macResponse, error) {
			return macResponse{Directory: dockerTestScope, ID: "use"}, nil
		},
		func(dockerMessage) (string, error) { return "", errors.New("mount failed") })
	if result != "unavailable (switch failed)" {
		t.Fatalf("result %q", result)
	}
	if _, err := os.Stat(statePath); !os.IsNotExist(err) {
		t.Fatal("a failed switch left a teardown to do")
	}
}

func TestDockerJobReportsADataRootStartedEmptyInsteadOfTheSavedOne(t *testing.T) {
	root := dockerVolumeDirectory(t, "use")
	statePath := filepath.Join(t.TempDir(), "state.json")
	result := dockerJob(context.Background(), root, statePath,
		func(context.Context) (macResponse, error) {
			return macResponse{Directory: dockerTestScope, ID: "use", Warm: true}, nil
		},
		func(dockerMessage) (string, error) { return dockerReset, nil })
	if result != "started empty (the saved data root could not be mounted)" {
		t.Fatalf("result %q", result)
	}
	if !readDockerState(t, statePath).Mounted {
		t.Fatal("hook did not record the mounted data root")
	}
}

func TestDockerTeardown(t *testing.T) {
	noImages := func() ([]string, error) { return nil, nil }
	someImages := func() ([]string, error) { return []string{"sha256:" + strings.Repeat("a", 64)}, nil }
	for name, test := range map[string]struct {
		state      *dockerHookState
		images     func() ([]string, error)
		want       string
		sent, seen bool
	}{
		"no hook state":                    {images: someImages, want: "skipped"},
		"mounted":                          {state: &dockerHookState{Mounted: true}, images: someImages, want: "saved for the host to verify", sent: true},
		"unseen repository using Docker":   {state: &dockerHookState{Reason: "unseen"}, images: someImages, want: "repository marked as using Docker", seen: true},
		"unseen repository without images": {state: &dockerHookState{Reason: "unseen"}, images: noImages, want: "skipped (no images)"},
		"denied":                           {state: &dockerHookState{Reason: "denied"}, images: someImages, want: "skipped"},
	} {
		t.Run(name, func(t *testing.T) {
			statePath := filepath.Join(t.TempDir(), "state.json")
			if test.state != nil {
				if err := writeDockerState(statePath, *test.state); err != nil {
					t.Fatal(err)
				}
			}
			sent, seen := false, false
			result := dockerTeardown(statePath,
				func(message dockerMessage) (string, error) { sent = message.Docker == "teardown"; return "ok", nil },
				func() dockerMergeOffer { return dockerMergeOffer{} },
				test.images,
				func() error { seen = true; return nil })
			if result != test.want || sent != test.sent || seen != test.seen {
				t.Fatalf("result %q, sent %t, seen %t", result, sent, seen)
			}
		})
	}
}

func dockerID(c string) string { return "sha256:" + strings.Repeat(c, 64) }

func TestPlanDockerTeardownKeepsContentAndDropsNames(t *testing.T) {
	now := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	pulled := dockerImage{ID: dockerID("a"), RepoTags: []string{"ghcr.io/org/build:jdk-21", dockerInternalReference(dockerID("a"))}, RepoDigests: []string{"ghcr.io/org/build@sha256:" + strings.Repeat("f", 64)}}
	ran := dockerImage{ID: dockerID("b"), RepoTags: []string{dockerInternalReference(dockerID("b"))}}
	recent := dockerImage{ID: dockerID("c"), RepoTags: []string{dockerInternalReference(dockerID("c"))}}
	old := dockerImage{ID: dockerID("d"), RepoTags: []string{dockerInternalReference(dockerID("d"))}}
	built := dockerImage{ID: dockerID("e"), RepoTags: []string{"app:latest"}}
	saved := dockerLedger{
		pulled.ID: {LastUsedAt: now.Add(-time.Hour), References: []string{"ghcr.io/org/build:jdk-20"}, Pulled: true},
		ran.ID:    {LastUsedAt: now.Add(-3 * 24 * time.Hour), References: []string{"postgres:16"}, Pulled: true},
		recent.ID: {LastUsedAt: now.Add(-13 * 24 * time.Hour), Pulled: true},
		old.ID:    {LastUsedAt: now.Add(-15 * 24 * time.Hour), Pulled: true},
	}
	plan := planDockerTeardown([]dockerImage{pulled, ran, recent, old, built}, map[string]bool{ran.ID: true}, saved, now)

	if strings.Join(plan.Remove, ",") != strings.Join([]string{old.ID, built.ID}, ",") {
		t.Fatalf("removed %v", plan.Remove)
	}
	if _, kept := plan.Keep[built.ID]; kept {
		t.Fatal("kept an image the job built")
	}
	if _, kept := plan.Keep[recent.ID]; !kept {
		t.Fatal("an image used within the retention was dropped")
	}
	if got := plan.Keep[pulled.ID].References; len(got) != 3 || got[0] != "ghcr.io/org/build:jdk-21" || got[2] != "ghcr.io/org/build:jdk-20" {
		t.Fatalf("references %v", got)
	}
	for _, id := range []string{pulled.ID, ran.ID} {
		if !plan.Keep[id].LastUsedAt.Equal(now) {
			t.Fatalf("%s used by the job kept %v", id, plan.Keep[id].LastUsedAt)
		}
	}
	if !plan.Keep[recent.ID].LastUsedAt.Equal(saved[recent.ID].LastUsedAt) {
		t.Fatal("an unused image's last use moved")
	}
	wantUntag := []string{"ghcr.io/org/build:jdk-21", "ghcr.io/org/build@sha256:" + strings.Repeat("f", 64)}
	if strings.Join(plan.Untag, ",") != strings.Join(wantUntag, ",") {
		t.Fatalf("untag %v", plan.Untag)
	}
	if len(plan.Tag) != 0 {
		t.Fatalf("tag %v", plan.Tag)
	}
	if !plan.Stale {
		t.Fatal("a used image saved three days ago did not refresh the ledger")
	}
}

func TestPlanDockerTeardownLeavesAFreshLedgerAlone(t *testing.T) {
	now := time.Now()
	image := dockerImage{ID: dockerID("a"), RepoTags: []string{"postgres:16", dockerInternalReference(dockerID("a"))}}
	plan := planDockerTeardown([]dockerImage{image}, nil, dockerLedger{image.ID: {LastUsedAt: now.Add(-time.Hour), Pulled: true}}, now)
	if plan.Stale || len(plan.Tag) != 0 {
		t.Fatalf("plan %+v", plan)
	}
}

func TestDockerSnapshotDiffers(t *testing.T) {
	base := dockerSnapshot{Images: []string{"a", "b"}, BuildCacheBytes: 10}
	if base.differs(dockerSnapshot{Images: []string{"b", "a"}, BuildCacheBytes: 10}) {
		t.Fatal("same images in another order differ")
	}
	if !base.differs(dockerSnapshot{Images: []string{"a"}, BuildCacheBytes: 10}) || !base.differs(dockerSnapshot{Images: []string{"a", "b"}, BuildCacheBytes: 10 + dockerBuildCacheChange}) {
		t.Fatal("a changed data root did not differ")
	}
	if base.differs(dockerSnapshot{Images: []string{"a", "b"}, BuildCacheBytes: 4096}) {
		t.Fatal("a build context record republished the data root")
	}
}

func TestParseHumanSize(t *testing.T) {
	for input, want := range map[string]int64{"0B": 0, "512B": 512, "1.5kB": 1500, "2.25GB": 2_250_000_000, "3MB": 3_000_000} {
		if got, ok := parseHumanSize(input); !ok || got != want {
			t.Fatalf("%q = %d, %t", input, got, ok)
		}
	}
	if _, ok := parseHumanSize("lots"); ok {
		t.Fatal("parsed a non-size")
	}
}

func TestReservedKeysAreRefused(t *testing.T) {
	for _, key := range []string{"docker", "checkout"} {
		if _, err := parseArguments([]string{"--key", key, "--path", "x"}, io.Discard); err == nil || !strings.Contains(err.Error(), "reserved") {
			t.Fatalf("%s: %v", key, err)
		}
	}
}

func TestRemainingReferencesIgnoreTheInternalReference(t *testing.T) {
	kept := dockerImage{ID: dockerID("a"), RepoTags: []string{dockerInternalReference(dockerID("a"))}, RepoDigests: []string{dockerInternalRepository + "@sha256:" + strings.Repeat("b", 64)}}
	if remaining := remainingReferences([]dockerImage{kept}); len(remaining) != 0 {
		t.Fatalf("remaining %v", remaining)
	}
	tagged := dockerImage{ID: dockerID("c"), RepoTags: []string{"alpine:3.20", dockerInternalReference(dockerID("c"))}}
	if remaining := remainingReferences([]dockerImage{kept, tagged}); len(remaining) != 1 || remaining[0] != "alpine:3.20" {
		t.Fatalf("remaining %v", remaining)
	}
}

func TestPlanDockerTeardownKeepsAPulledImageNewToTheLedger(t *testing.T) {
	now := time.Now()
	pulled := dockerImage{ID: dockerID("a"), RepoTags: []string{"postgres:16"}, RepoDigests: []string{"postgres@sha256:" + strings.Repeat("b", 64)}}
	loaded := dockerImage{ID: dockerID("c"), RepoTags: []string{"local:dev"}}
	plan := planDockerTeardown([]dockerImage{pulled, loaded}, nil, dockerLedger{}, now)
	if entry, kept := plan.Keep[pulled.ID]; !kept || !entry.Pulled || !entry.LastUsedAt.Equal(now) {
		t.Fatalf("pulled image %+v", plan.Keep)
	}
	if len(plan.Remove) != 1 || plan.Remove[0] != loaded.ID {
		t.Fatalf("removed %v", plan.Remove)
	}
}

func TestDockerTeardownHandsTheOfferedHeadToTheSupervisor(t *testing.T) {
	statePath := filepath.Join(t.TempDir(), "state.json")
	if err := writeDockerState(statePath, dockerHookState{Mounted: true}); err != nil {
		t.Fatal(err)
	}
	source := dockerTestScope + "/" + dockerMergeImageName
	for name, test := range map[string]struct {
		offer dockerMergeOffer
		want  dockerMessage
	}{
		"a head another job saved": {
			offer: dockerMergeOffer{Merge: true, Source: source, Generation: 4},
			want:  dockerMessage{Docker: "teardown", Merge: source, Generation: 4},
		},
		"no head to merge": {
			want: dockerMessage{Docker: "teardown"},
		},
		"a source outside the cache directory": {
			offer: dockerMergeOffer{Merge: true, Source: "../" + dockerMergeImageName, Generation: 4},
			want:  dockerMessage{Docker: "teardown"},
		},
	} {
		t.Run(name, func(t *testing.T) {
			var sent dockerMessage
			dockerTeardown(statePath,
				func(message dockerMessage) (string, error) { sent = message; return "ok", nil },
				func() dockerMergeOffer { return test.offer },
				func() ([]string, error) { return nil, nil },
				func() error { return nil })
			if sent != test.want {
				t.Fatalf("sent %+v", sent)
			}
		})
	}
}

func TestPlanDockerMergeMovesTheSmallerSide(t *testing.T) {
	flutter := dockerImage{ID: dockerID("a"), Size: 6_000_000_000}
	postgres := dockerImage{ID: dockerID("b"), Size: 450_000_000}
	alpine := dockerImage{ID: dockerID("c"), Size: 8_000_000}
	for name, test := range map[string]struct {
		branch, head []dockerImage
		want         dockerMergePlan
	}{
		"a small new image goes into the saved head": {
			branch: []dockerImage{postgres, alpine},
			head:   []dockerImage{postgres, flutter},
			want:   dockerMergePlan{Into: "head", Move: []string{alpine.ID}},
		},
		"the saved head's small images come into a large data root": {
			branch: []dockerImage{postgres, flutter},
			head:   []dockerImage{postgres, alpine},
			want:   dockerMergePlan{Into: "branch", Move: []string{alpine.ID}},
		},
		"nothing the head lacks": {
			branch: []dockerImage{postgres},
			head:   []dockerImage{postgres, flutter},
			want:   dockerMergePlan{},
		},
		"an empty head": {
			branch: []dockerImage{alpine},
			want:   dockerMergePlan{Into: "branch"},
		},
	} {
		t.Run(name, func(t *testing.T) {
			if got := planDockerMerge(test.branch, test.head); !reflect.DeepEqual(got, test.want) {
				t.Fatalf("plan %+v", got)
			}
		})
	}
}

func TestMergeDockerLedgersKeepsTheMovedImagesHistory(t *testing.T) {
	used := time.Date(2026, 10, 25, 12, 0, 0, 0, time.UTC)
	into := dockerLedger{dockerID("a"): {LastUsedAt: used, Pulled: true}}
	from := dockerLedger{dockerID("b"): {LastUsedAt: used.Add(time.Hour), Pulled: true}, dockerID("c"): {LastUsedAt: used}}
	merged := mergeDockerLedgers(into, from, []string{dockerID("b")})
	if len(merged) != 2 || !merged[dockerID("b")].Pulled || !merged[dockerID("a")].Pulled {
		t.Fatalf("merged %v", merged)
	}
	if _, ok := into[dockerID("b")]; ok {
		t.Fatal("merging changed the ledger it started from")
	}
}
