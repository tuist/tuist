package podagent

import (
	"crypto/sha1"
	"encoding/hex"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"reflect"
	"strconv"
	"testing"
	"time"

	"github.com/prometheus/client_golang/prometheus/testutil"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/validation"
)

const (
	repoVolumeA = "repo-0123456789abcdef"
	repoVolumeB = "repo-fedcba9876543210"
)

func seedVolumeMaster(t *testing.T, m *VolumeManager, account, volume, content string, generation int) {
	t.Helper()
	if err := os.MkdirAll(m.volumeDir(account, volume), 0o755); err != nil {
		t.Fatalf("mkdir volume dir: %v", err)
	}
	if err := os.WriteFile(m.masterImage(account, volume), []byte(content), 0o644); err != nil {
		t.Fatalf("seed master image: %v", err)
	}
	if err := os.WriteFile(m.masterGenerationPath(account, volume), []byte(strconv.Itoa(generation)), 0o644); err != nil {
		t.Fatalf("seed master generation: %v", err)
	}
}

func volumeMasterContent(t *testing.T, m *VolumeManager, account, volume string) (string, bool) {
	t.Helper()
	b, err := os.ReadFile(m.masterImage(account, volume))
	if err != nil {
		return "", false
	}
	return string(b), true
}

func allocateForVolume(t *testing.T, m *VolumeManager, vm, volume string) VolumeAttachment {
	t.Helper()
	att := mustAllocate(t, m, vm)
	att.VolumeName = volume
	return att
}

func materializePod(account, volume string) *corev1.Pod {
	labels := map[string]string{runnerAccountLabel: account}
	if volume != "" {
		labels[runnerCacheVolumeLabel] = volume
	}
	return &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Namespace: "ns", Name: "pod", Labels: labels}}
}

func TestMaterializeClonesTheRepositoryVolumesMaster(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "42", repoVolumeA, "image-of-repo-a", 3)
	seedVolumeMaster(t, m, "42", repoVolumeB, "image-of-repo-b", 8)
	seedVolumeMaster(t, m, "42", ReservedTuistCacheVolume, "image-of-account", 5)

	att := allocateForVolume(t, m, "vm-b", repoVolumeB)
	source, base, err := m.Materialize(att, "42")
	if err != nil || source != MaterializedWarm || base != 8 {
		t.Fatalf("Materialize = %s, %d, %v; want warm from repo B's master at generation 8", source, base, err)
	}
	if got := branchImageContent(t, m, att); got != "image-of-repo-b" {
		t.Fatalf("branch image = %q; want repo B's master", got)
	}
}

func TestFinalizePromotesIntoTheMaterializedVolume(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "42", repoVolumeA, "image-of-repo-a", 3)
	seedVolumeMaster(t, m, "42", ReservedTuistCacheVolume, "image-of-account", 5)

	att := allocateForVolume(t, m, "vm-a", repoVolumeA)
	if _, _, err := m.Materialize(att, "42"); err != nil {
		t.Fatalf("Materialize: %v", err)
	}
	att.SourceAccount = "42"
	writeBranchCache(t, m, att, "repo-a-after-job")
	att.PromotedGeneration = 4

	if out, err := m.Finalize(att, "42", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}
	if got, _ := volumeMasterContent(t, m, "42", repoVolumeA); got != "repo-a-after-job" {
		t.Fatalf("repo A master = %q; want the promoted branch", got)
	}
	if got, _ := m.MasterGeneration("42", repoVolumeA); got != 4 {
		t.Fatalf("repo A generation = %d; want 4", got)
	}
	if got, _ := volumeMasterContent(t, m, "42", ReservedTuistCacheVolume); got != "image-of-account" {
		t.Fatalf("account master = %q; a repository promote must leave it untouched", got)
	}
}

func TestMaterializeSeedsARepositoryVolumeFromTheAccountMaster(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "42", ReservedTuistCacheVolume, "image-of-account", 57)
	legacyMtime := time.Now().Add(-time.Hour).Truncate(time.Second)
	setMtime(t, m.masterImage("42", ReservedTuistCacheVolume), legacyMtime)

	att := allocateForVolume(t, m, "vm-seed", repoVolumeA)
	source, base, err := m.Materialize(att, "42")
	if err != nil || source != MaterializedSeeded || base != 0 {
		t.Fatalf("Materialize = %s, %d, %v; want seeded at base 0", source, base, err)
	}
	if got := branchImageContent(t, m, att); got != "image-of-account" {
		t.Fatalf("branch image = %q; want a clone of the account master", got)
	}
	info, err := os.Stat(m.masterImage("42", ReservedTuistCacheVolume))
	if err != nil || !info.ModTime().Equal(legacyMtime) {
		t.Fatalf("seeding touched the account master's mtime (%v); it must age out under LRU", info.ModTime())
	}

	att.SourceAccount = "42"
	writeBranchCache(t, m, att, "repo-a-first-head")
	att.PromotedGeneration = 1
	if out, err := m.Finalize(att, "42", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}
	if got, _ := m.MasterGeneration("42", repoVolumeA); got != 1 {
		t.Fatalf("repo A generation = %d; want its first HEAD, 1", got)
	}
	if got, _ := m.MasterGeneration("42", ReservedTuistCacheVolume); got != 57 {
		t.Fatalf("account master generation = %d; want 57 untouched", got)
	}
}

func TestMaterializeNeverSeedsFromAnotherAccount(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "7", ReservedTuistCacheVolume, "image-of-7", 4)

	att := allocateForVolume(t, m, "vm-cold", repoVolumeA)
	source, base, err := m.Materialize(att, "42")
	if err != nil || source != MaterializedCold || base != 0 {
		t.Fatalf("Materialize = %s, %d, %v; want cold", source, base, err)
	}
	if branchHasWarmCache(m, att) {
		t.Fatalf("branch image = %q; account 42 must not see account 7's cache", branchImageContent(t, m, att))
	}
}

func TestMaterializeDoesNotSeedTheAccountVolume(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "42", repoVolumeA, "image-of-repo-a", 2)

	att := allocateForVolume(t, m, "vm-legacy", ReservedTuistCacheVolume)
	source, _, err := m.Materialize(att, "42")
	if err != nil || source != MaterializedCold {
		t.Fatalf("Materialize = %s, %v; a job with no repository must not borrow a repository's master", source, err)
	}
}

func TestAdmissionKeepsTheVolumeItMaterializes(t *testing.T) {
	m, _ := newTestManager(t, 2)
	seedVolumeMaster(t, m, "42", repoVolumeA, "image-of-repo-a", 1)
	setMtime(t, m.masterImage("42", repoVolumeA), time.Now().Add(-time.Hour))
	seedVolumeMaster(t, m, "42", repoVolumeB, "image-of-repo-b", 1)

	att := allocateForVolume(t, m, "vm-a", repoVolumeA)
	source, _, err := m.Materialize(att, "42")
	if err != nil || source != MaterializedWarm {
		t.Fatalf("Materialize = %s, %v; want a warm admission", source, err)
	}
	if _, ok := volumeMasterContent(t, m, "42", repoVolumeA); !ok {
		t.Fatal("admission evicted the volume it was materializing")
	}
	if _, ok := volumeMasterContent(t, m, "42", repoVolumeB); ok {
		t.Fatal("the same account's other repository master should have been evicted instead")
	}
}

func TestAdmissionKeepsTheAccountMasterItSeedsFrom(t *testing.T) {
	m, _ := newTestManager(t, 2)
	seedVolumeMaster(t, m, "42", ReservedTuistCacheVolume, "image-of-account", 9)
	setMtime(t, m.masterImage("42", ReservedTuistCacheVolume), time.Now().Add(-time.Hour))
	seedVolumeMaster(t, m, "7", ReservedTuistCacheVolume, "image-of-7", 1)

	att := allocateForVolume(t, m, "vm-seed", repoVolumeA)
	source, _, err := m.Materialize(att, "42")
	if err != nil || source != MaterializedSeeded {
		t.Fatalf("Materialize = %s, %v; want a seeded admission", source, err)
	}
	if got := branchImageContent(t, m, att); got != "image-of-account" {
		t.Fatalf("branch image = %q; admission evicted the master it was about to seed from", got)
	}
	if masterExists(m, "7") {
		t.Fatal("the other account's master should have been evicted instead")
	}
}

func TestCacheMasterNodeLabelsAdvertiseEveryVolume(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "42", ReservedTuistCacheVolume, "a", 1)
	seedVolumeMaster(t, m, "42", repoVolumeA, "b", 1)
	seedVolumeMaster(t, m, "9223372036854775807", repoVolumeB, "c", 1)
	seedVolumeMaster(t, m, "42", "not-a-volume", "d", 1)

	labels, err := m.CacheMasterNodeLabels()
	if err != nil {
		t.Fatalf("CacheMasterNodeLabels: %v", err)
	}
	want := map[string]string{
		"tuist.dev/cache-master-42":                                 "true",
		"tuist.dev/cache-master-42." + repoVolumeA:                  "true",
		"tuist.dev/cache-master-9223372036854775807." + repoVolumeB: "true",
		"tuist.dev/cache-volumes-per-repository":                    "true",
	}
	if !reflect.DeepEqual(labels, want) {
		t.Fatalf("labels = %v; want %v", labels, want)
	}
	for key := range labels {
		if errs := validation.IsQualifiedName(key); len(errs) > 0 {
			t.Fatalf("label key %q is not a valid Kubernetes label key: %v", key, errs)
		}
	}
}

func TestCacheMasterNodeLabelsAdvertiseRepositoryVolumesWithNoMasters(t *testing.T) {
	m, _ := newTestManager(t, 100)

	labels, err := m.CacheMasterNodeLabels()
	if err != nil {
		t.Fatalf("CacheMasterNodeLabels: %v", err)
	}
	if !reflect.DeepEqual(labels, map[string]string{"tuist.dev/cache-volumes-per-repository": "true"}) {
		t.Fatalf("labels = %v; a host with cache volumes on must advertise repository volumes before it holds a master", labels)
	}
}

func TestRunnerCacheVolumeFromPod(t *testing.T) {
	for _, tc := range []struct {
		name   string
		labels map[string]string
		want   string
		ok     bool
	}{
		{"absent reads as the account volume", map[string]string{}, ReservedTuistCacheVolume, true},
		{"repository volume", map[string]string{runnerCacheVolumeLabel: repoVolumeA}, repoVolumeA, true},
		{"account volume", map[string]string{runnerCacheVolumeLabel: ReservedTuistCacheVolume}, ReservedTuistCacheVolume, true},
		{"uppercase hex", map[string]string{runnerCacheVolumeLabel: "repo-0123456789ABCDEF"}, "", false},
		{"short hash", map[string]string{runnerCacheVolumeLabel: "repo-0123"}, "", false},
		{"traversal", map[string]string{runnerCacheVolumeLabel: ".."}, "", false},
		{"branches dir", map[string]string{runnerCacheVolumeLabel: "branches"}, "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Labels: tc.labels}}
			got, ok := RunnerCacheVolumeFromPod(pod)
			if got != tc.want || ok != tc.ok {
				t.Fatalf("RunnerCacheVolumeFromPod = %q, %v; want %q, %v", got, ok, tc.want, tc.ok)
			}
		})
	}
}

func TestMaybeMaterializeVolumeUsesThePodsVolume(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "42", repoVolumeA, "image-of-repo-a", 6)
	seedVolumeMaster(t, m, "42", ReservedTuistCacheVolume, "image-of-account", 5)
	statusDir := t.TempDir()
	att := mustAllocate(t, m, "vm-a")

	store := NewStore()
	store.Put("ns", "pod", &Entry{VMName: "vm-a", Volume: att, VolumeStatusDir: statusDir})
	r := &Reconciler{Store: store, Volumes: m, ConvergeHeadWaitInterval: time.Millisecond, ConvergeHeadWaitAttempts: 1}
	r.maybeMaterializeVolume(materializePod("42", repoVolumeA))

	entry := store.Get("ns", "pod")
	if entry.Volume.VolumeName != repoVolumeA || entry.Volume.SourceAccount != "42" {
		t.Fatalf("attachment = %+v; want account 42, volume %s", entry.Volume, repoVolumeA)
	}
	if got := branchImageContent(t, m, entry.Volume); got != "image-of-repo-a" {
		t.Fatalf("branch image = %q; want repo A's master", got)
	}
	if b, _ := os.ReadFile(filepath.Join(statusDir, baseGenerationFile)); string(b) != "6" {
		t.Fatalf("staged base generation = %q; want repo A's 6", b)
	}
}

func TestMaybeMaterializeVolumeCountsASeed(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "42", ReservedTuistCacheVolume, "image-of-account", 5)
	statusDir := t.TempDir()
	att := mustAllocate(t, m, "vm-seed")
	seededBefore := testutil.ToFloat64(cacheVolumeMaterializeTotal.WithLabelValues("seeded"))

	store := NewStore()
	store.Put("ns", "pod", &Entry{VMName: "vm-seed", Volume: att, VolumeStatusDir: statusDir})
	r := &Reconciler{Store: store, Volumes: m, ConvergeHeadWaitInterval: time.Millisecond, ConvergeHeadWaitAttempts: 1}
	r.maybeMaterializeVolume(materializePod("42", repoVolumeA))

	if got := testutil.ToFloat64(cacheVolumeMaterializeTotal.WithLabelValues("seeded")); got != seededBefore+1 {
		t.Fatalf("seeded materialize counter = %v; want %v", got, seededBefore+1)
	}
	if b, _ := os.ReadFile(filepath.Join(statusDir, baseGenerationFile)); string(b) != "0" {
		t.Fatalf("staged base generation = %q; a seed must promote from base 0", b)
	}
}

func TestMaybeMaterializeVolumeIsolatesAMalformedVolume(t *testing.T) {
	m, _ := newTestManager(t, 100)
	seedVolumeMaster(t, m, "42", ReservedTuistCacheVolume, "image-of-account", 5)
	statusDir := t.TempDir()
	att := mustAllocate(t, m, "vm-bad")

	store := NewStore()
	store.Put("ns", "pod", &Entry{VMName: "vm-bad", Volume: att, VolumeStatusDir: statusDir})
	r := &Reconciler{Store: store, Volumes: m, ConvergeHeadWaitInterval: time.Millisecond, ConvergeHeadWaitAttempts: 1}
	r.maybeMaterializeVolume(materializePod("42", "repo-NOT-HEX"))

	entry := store.Get("ns", "pod")
	if entry.Volume.SourceAccount != "" {
		t.Fatalf("SourceAccount = %q; a malformed volume must never promote", entry.Volume.SourceAccount)
	}
	if branchHasWarmCache(m, entry.Volume) {
		t.Fatalf("branch image = %q; a malformed volume must get an empty image", branchImageContent(t, m, entry.Volume))
	}
	if _, err := os.Stat(filepath.Join(statusDir, cacheReadyFile)); err != nil {
		t.Fatalf("cache-ready not written: %v", err)
	}
}

func TestMaybeMaterializeVolumeConvergesThePodsVolume(t *testing.T) {
	served := []byte("repo-a-head")
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write(served)
	}))
	defer srv.Close()
	digest := sha1.Sum(served)

	m, _ := newTestManager(t, 100)
	statusDir := t.TempDir()
	stageHead(t, statusDir, volumeHead{Generation: 4, Digest: hex.EncodeToString(digest[:]), DownloadURL: srv.URL})
	att := mustAllocate(t, m, "vm-a")

	store := NewStore()
	store.Put("ns", "pod", &Entry{VMName: "vm-a", Volume: att, VolumeStatusDir: statusDir})
	r := &Reconciler{Store: store, Volumes: m, ConvergeHeadWaitInterval: time.Millisecond, ConvergeHeadWaitAttempts: 1}
	r.maybeMaterializeVolume(materializePod("42", repoVolumeA))

	deadline := time.Now().Add(5 * time.Second)
	for {
		if gen, _ := m.MasterGeneration("42", repoVolumeA); gen == 4 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("convergence never installed the HEAD into the pod's repository volume")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if masterExists(m, "42") {
		t.Fatal("convergence installed a repository HEAD into the account volume")
	}
}

func TestReattachVolumeForPodRestoresTheVolume(t *testing.T) {
	m, _ := newTestManager(t, 100)
	att := mustAllocate(t, m, "vm-a")
	m.MarkMaterialized(att)
	writeBranchCache(t, m, att, "repo-a-in-flight")

	got, ok := ReattachVolumeForPod(m, materializePod("42", repoVolumeA), "vm-a")
	if !ok || got.VolumeName != repoVolumeA || got.SourceAccount != "42" {
		t.Fatalf("ReattachVolumeForPod = %+v, %v; want account 42 on %s", got, ok, repoVolumeA)
	}
	got.PromotedGeneration = 2
	if out, err := m.Finalize(got, "42", true, true); err != nil || out != VolumeOutcomePromoted {
		t.Fatalf("Finalize = %s, %v; want promoted", out, err)
	}
	if gen, _ := m.MasterGeneration("42", repoVolumeA); gen != 2 {
		t.Fatalf("repo A generation = %d; the recovered job must promote into its own volume", gen)
	}
	if masterExists(m, "42") {
		t.Fatal("the recovered job promoted into the account volume")
	}
}

func TestReattachVolumeForPodDefaultsToTheAccountVolume(t *testing.T) {
	m, _ := newTestManager(t, 100)
	mustAllocate(t, m, "vm-old")

	got, ok := ReattachVolumeForPod(m, materializePod("42", ""), "vm-old")
	if !ok || got.VolumeName != ReservedTuistCacheVolume || got.SourceAccount != "42" {
		t.Fatalf("ReattachVolumeForPod = %+v, %v; a pod from an older server keeps the account volume", got, ok)
	}
}

func TestReattachVolumeForPodIsolatesAMalformedVolume(t *testing.T) {
	m, _ := newTestManager(t, 100)
	mustAllocate(t, m, "vm-bad")

	got, ok := ReattachVolumeForPod(m, materializePod("42", "repo-NOT-HEX"), "vm-bad")
	if !ok || got.SourceAccount != "" {
		t.Fatalf("ReattachVolumeForPod = %+v, %v; a malformed volume must not promote after a restart", got, ok)
	}
	if out, _ := m.Finalize(got, "42", true, true); out != VolumeOutcomeDiscarded {
		t.Fatalf("Finalize = %s; want discarded", out)
	}
}
