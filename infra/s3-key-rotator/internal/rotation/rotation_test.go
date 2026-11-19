package rotation

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"sort"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/s3-key-rotator/internal/tigris"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/client-go/kubernetes/fake"
	k8stesting "k8s.io/client-go/testing"
)

type fakeTigris struct {
	keys        map[string]string // id -> name
	created     int
	unreachable map[string]int // key id -> failures left before it works
	neverWorks  bool
	unlisted    map[string]bool // keys that exist but ListKeys omits
}

func (f *fakeTigris) CreateKey(_ context.Context, name string, _ []tigris.BucketRole) (tigris.Credentials, error) {
	f.created++
	id := fmt.Sprintf("tid_%d", f.created)
	f.keys[id] = name
	return tigris.Credentials{AccessKeyID: id, SecretAccessKey: "tsec_" + id}, nil
}

func (f *fakeTigris) ListKeys(context.Context) ([]tigris.Key, error) {
	var keys []tigris.Key
	for id, name := range f.keys {
		if !f.unlisted[id] {
			keys = append(keys, tigris.Key{ID: id, Name: name})
		}
	}
	return keys, nil
}

func (f *fakeTigris) DeleteKey(_ context.Context, id string) error {
	delete(f.keys, id)
	return nil
}

func (f *fakeTigris) CanReach(_ context.Context, key tigris.Credentials, _ string) error {
	if _, exists := f.keys[key.AccessKeyID]; !exists || f.neverWorks {
		return errors.New("HTTP 403")
	}
	if f.unreachable[key.AccessKeyID] > 0 {
		f.unreachable[key.AccessKeyID]--
		return errors.New("HTTP 403")
	}
	return nil
}

func (f *fakeTigris) ids() []string {
	var ids []string
	for id := range f.keys {
		ids = append(ids, id)
	}
	sort.Strings(ids)
	return ids
}

type harness struct {
	t      *testing.T
	now    time.Time
	tigris *fakeTigris
	kube   *fake.Clientset
	r      *Rotator
}

func newHarness(t *testing.T, objects ...runtime.Object) *harness {
	h := &harness{
		t:      t,
		now:    time.Date(2026, 11, 19, 12, 0, 0, 0, time.UTC),
		tigris: &fakeTigris{keys: map[string]string{"tid_admin": "admin", "tid_other": "someone-else"}, unreachable: map[string]int{}, unlisted: map[string]bool{}},
		kube:   fake.NewSimpleClientset(objects...),
	}
	h.r = &Rotator{
		Config: Config{
			Namespace:     "tuist-staging",
			SecretName:    "s3-rotated",
			Prefix:        "tuist-staging-platform-",
			Roles:         []tigris.BucketRole{{Bucket: "tuist-staging", Role: "ReadWrite"}},
			Interval:      24 * time.Hour,
			Retention:     13 * time.Hour,
			AdminKeyID:    "tid_admin",
			VerifyTimeout: time.Minute,
			VerifyBackoff: 5 * time.Second,
		},
		Tigris:     h.tigris,
		Kubernetes: h.kube,
		Logger:     slog.New(slog.NewTextHandler(io.Discard, nil)),
		Now:        func() time.Time { return h.now },
		Sleep: func(_ context.Context, d time.Duration) error {
			h.now = h.now.Add(d)
			return nil
		},
	}
	return h
}

func (h *harness) run() {
	h.t.Helper()
	if err := h.r.Run(context.Background()); err != nil {
		h.t.Fatalf("run: %v", err)
	}
}

func (h *harness) secret() *corev1.Secret {
	h.t.Helper()
	secret, err := h.kube.CoreV1().Secrets("tuist-staging").Get(context.Background(), "s3-rotated", metav1.GetOptions{})
	if err != nil {
		h.t.Fatalf("get secret: %v", err)
	}
	return secret
}

func assertKeys(t *testing.T, got []string, want ...string) {
	t.Helper()
	sort.Strings(want)
	if fmt.Sprint(got) != fmt.Sprint(want) {
		t.Fatalf("keys = %v, want %v", got, want)
	}
}

func TestRotationKeepsThePreviousKeyForTheRetentionThenDeletesIt(t *testing.T) {
	h := newHarness(t)

	h.run()
	secret := h.secret()
	if string(secret.Data[AccessKeyIDField]) != "tid_1" || string(secret.Data[SecretAccessKeyField]) != "tsec_tid_1" {
		t.Fatalf("first run stored %q", secret.Data)
	}
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_1")

	// Before the interval nothing changes.
	h.now = h.now.Add(23 * time.Hour)
	h.run()
	if h.tigris.created != 1 {
		t.Fatalf("rotated before the interval")
	}

	// At the interval a new key replaces it; the old one is still retained.
	h.now = h.now.Add(time.Hour)
	rotatedAt := h.now
	h.run()
	secret = h.secret()
	if string(secret.Data[AccessKeyIDField]) != "tid_2" {
		t.Fatalf("second rotation stored %q", secret.Data[AccessKeyIDField])
	}
	if secret.Annotations[previousKeyAnnotation] != "tid_1" {
		t.Fatalf("previous key annotation = %q", secret.Annotations[previousKeyAnnotation])
	}
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_1", "tid_2")

	// One second before retention ends the old key survives; after, it is gone.
	h.now = rotatedAt.Add(13*time.Hour - time.Second)
	h.run()
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_1", "tid_2")

	h.now = rotatedAt.Add(13 * time.Hour)
	h.run()
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_2")
}

func minted(at time.Time) string { return "tuist-staging-platform-" + at.Format(keyNameTimeLayout) }

func TestDeletesKeysAFailedRunMintedOnceTheyAreOlderThanIntervalPlusRetention(t *testing.T) {
	h := newHarness(t)
	h.run()
	h.now = h.now.Add(13 * time.Hour)
	h.tigris.keys["tid_orphan_old"] = minted(h.now.Add(-37 * time.Hour))
	h.tigris.keys["tid_orphan_recent"] = minted(h.now.Add(-37*time.Hour + time.Second))
	// Not Prefix+timestamp: a longer prefix sharing ours, and a malformed name.
	h.tigris.keys["tid_nested"] = "tuist-staging-platform-eu-" + h.now.Add(-100*time.Hour).Format(keyNameTimeLayout)
	h.tigris.keys["tid_malformed"] = "tuist-staging-platform-old"

	h.run()

	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_1", "tid_orphan_recent", "tid_nested", "tid_malformed")
}

func TestNeverDeletesAKeyAConcurrentRunJustMinted(t *testing.T) {
	h := newHarness(t)
	h.run()
	// Another run minted this a minute ago and is still verifying it.
	h.tigris.keys["tid_concurrent"] = minted(h.now.Add(-time.Minute))

	h.run()

	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_1", "tid_concurrent")
}

func TestKeepsTheKeyPodsStillReadAfterTheSecretWasDeleted(t *testing.T) {
	h := newHarness(t)
	start := h.now
	h.tigris.keys["tid_live"] = minted(start.Add(-2 * time.Hour))

	h.run()
	if got := string(h.secret().Data[AccessKeyIDField]); got != "tid_1" {
		t.Fatalf("stored %q", got)
	}

	// Hourly runs: tid_1 is rotated on schedule at 24h, and tid_live may go
	// only once 13h have passed since that rotation (37h).
	for hour := 1; hour <= 37; hour++ {
		h.now = start.Add(time.Duration(hour) * time.Hour)
		h.run()
		_, present := h.tigris.keys["tid_live"]
		if hour < 37 && !present {
			t.Fatalf("tid_live deleted at %dh", hour)
		}
		if hour == 37 && present {
			t.Fatal("tid_live kept at 37h")
		}
	}
}

func TestKeepsAKeyThatStayedCurrentPastTheIntervalWhenTheSecretIsDeleted(t *testing.T) {
	h := newHarness(t)
	// Rotations stalled, so pods still read tid_stalled from their files.
	h.tigris.keys["tid_stalled"] = minted(h.now.Add(-38 * time.Hour))

	h.run()

	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_stalled", "tid_1")
}

func TestARotationRightAfterAStallKeepsTheReplacedKey(t *testing.T) {
	h0 := newHarness(t)
	now := h0.now
	// tid_c stayed current for 36h50m because runs stalled, was replaced 30
	// minutes ago, and the rotation time was lost since.
	existing := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name: "s3-rotated", Namespace: "tuist-staging",
			Annotations: map[string]string{
				previousKeyAnnotation:      "tid_c",
				previousRetireAtAnnotation: now.Add(12*time.Hour + 30*time.Minute).Format(time.RFC3339),
			},
		},
		Data: map[string][]byte{AccessKeyIDField: []byte("tid_new"), SecretAccessKeyField: []byte("s")},
	}
	h := newHarness(t, existing)
	h.tigris.keys["tid_c"] = minted(now.Add(-37*time.Hour - 20*time.Minute))
	h.tigris.keys["tid_new"] = minted(now.Add(-30 * time.Minute))

	h.run()

	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_c", "tid_new", "tid_1")
}

func TestAnEarlyRotationKeepsTheRetainedPreviousKey(t *testing.T) {
	h0 := newHarness(t)
	now := h0.now
	// The rotation annotation was lost, so this run rotates early and
	// overwrites the record of tid_prev, which was replaced an hour ago.
	existing := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name: "s3-rotated", Namespace: "tuist-staging",
			Annotations: map[string]string{
				previousKeyAnnotation:      "tid_prev",
				previousRetireAtAnnotation: now.Add(12 * time.Hour).Format(time.RFC3339),
			},
		},
		Data: map[string][]byte{AccessKeyIDField: []byte("tid_cur"), SecretAccessKeyField: []byte("s")},
	}
	h := newHarness(t, existing)
	h.tigris.keys["tid_prev"] = minted(now.Add(-25 * time.Hour))
	h.tigris.keys["tid_cur"] = minted(now.Add(-time.Hour))

	h.run()

	if got := string(h.secret().Data[AccessKeyIDField]); got != "tid_1" {
		t.Fatalf("stored %q", got)
	}
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_prev", "tid_cur", "tid_1")
}

func TestRotatesWhenTheCurrentKeyNoLongerExists(t *testing.T) {
	h0 := newHarness(t)
	existing := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name: "s3-rotated", Namespace: "tuist-staging",
			Annotations: map[string]string{rotatedAtAnnotation: h0.now.Add(-time.Hour).Format(time.RFC3339)},
		},
		Data: map[string][]byte{AccessKeyIDField: []byte("tid_deleted"), SecretAccessKeyField: []byte("s")},
	}
	h := newHarness(t, existing)

	h.run()

	if got := string(h.secret().Data[AccessKeyIDField]); got != "tid_1" {
		t.Fatalf("stored %q", got)
	}
}

func TestDoesNotRotateWhenTheCurrentKeyIsOnlyMissingFromTheList(t *testing.T) {
	h := newHarness(t)
	h.run()
	h.tigris.unlisted["tid_1"] = true

	h.now = h.now.Add(time.Hour)
	h.run()

	if h.tigris.created != 1 {
		t.Fatalf("rotated %d times", h.tigris.created-1)
	}
}

func oldSecret() *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name: "s3-rotated", Namespace: "tuist-staging",
			Annotations: map[string]string{rotatedAtAnnotation: "2026-11-01T00:00:00Z"},
		},
		Data: map[string][]byte{AccessKeyIDField: []byte("tid_old"), SecretAccessKeyField: []byte("tsec_old")},
	}
}

func TestKeepsANewKeyTheSecretStoredDespiteAWriteError(t *testing.T) {
	h := newHarness(t, oldSecret())
	h.tigris.keys["tid_old"] = minted(time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC))
	// The write lands, then the connection drops before the answer.
	h.kube.PrependReactor("update", "secrets", func(action k8stesting.Action) (bool, runtime.Object, error) {
		update := action.(k8stesting.UpdateAction)
		if err := h.kube.Tracker().Update(update.GetResource(), update.GetObject(), update.GetNamespace()); err != nil {
			t.Fatal(err)
		}
		return true, nil, errors.New("connection reset by peer")
	})

	h.run()

	if got := string(h.secret().Data[AccessKeyIDField]); got != "tid_1" {
		t.Fatalf("secret holds %q", got)
	}
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_old", "tid_1")
}

func TestDeletesANewKeyAFailedWriteDidNotStore(t *testing.T) {
	h := newHarness(t, oldSecret())
	h.tigris.keys["tid_old"] = minted(time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC))
	h.kube.PrependReactor("update", "secrets", func(k8stesting.Action) (bool, runtime.Object, error) {
		return true, nil, errors.New("connection reset by peer")
	})

	if err := h.r.Run(context.Background()); err == nil {
		t.Fatal("expected an error")
	}
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_old")
}

func TestANewKeyLosingAnUpdateConflictIsDeleted(t *testing.T) {
	existing := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name: "s3-rotated", Namespace: "tuist-staging",
			Annotations: map[string]string{rotatedAtAnnotation: "2026-11-01T00:00:00Z"},
		},
		Data: map[string][]byte{AccessKeyIDField: []byte("tid_old"), SecretAccessKeyField: []byte("tsec_old")},
	}
	h := newHarness(t, existing)
	h.tigris.keys["tid_old"] = minted(time.Date(2026, 11, 1, 0, 0, 0, 0, time.UTC))
	h.kube.PrependReactor("update", "secrets", func(k8stesting.Action) (bool, runtime.Object, error) {
		return true, nil, apierrors.NewConflict(schema.GroupResource{Resource: "secrets"}, "s3-rotated", errors.New("changed"))
	})

	if err := h.r.Run(context.Background()); err == nil {
		t.Fatal("expected an error")
	}
	if got := string(h.secret().Data[AccessKeyIDField]); got != "tid_old" {
		t.Fatalf("secret now holds %q", got)
	}
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_old")
}

func TestWaitsForANewKeyToPropagateBeforeStoringIt(t *testing.T) {
	h := newHarness(t)
	h.tigris.unreachable["tid_1"] = 3

	h.run()

	if got := string(h.secret().Data[AccessKeyIDField]); got != "tid_1" {
		t.Fatalf("stored %q", got)
	}
}

func TestANewKeyThatNeverWorksIsDeletedAndTheSecretKept(t *testing.T) {
	existing := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Name: "s3-rotated", Namespace: "tuist-staging",
			Annotations: map[string]string{rotatedAtAnnotation: "2026-11-01T00:00:00Z"},
		},
		Data: map[string][]byte{AccessKeyIDField: []byte("tid_old"), SecretAccessKeyField: []byte("tsec_old")},
	}
	h := newHarness(t, existing)
	h.tigris.keys["tid_old"] = "tuist-staging-platform-20261101T000000Z"
	h.tigris.neverWorks = true

	if err := h.r.Run(context.Background()); err == nil {
		t.Fatal("expected an error")
	}

	if got := string(h.secret().Data[AccessKeyIDField]); got != "tid_old" {
		t.Fatalf("secret now holds %q", got)
	}
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other", "tid_old")
}

func TestANewKeyThatCannotBeStoredIsDeleted(t *testing.T) {
	h := newHarness(t)
	h.kube.PrependReactor("create", "secrets", func(k8stesting.Action) (bool, runtime.Object, error) {
		return true, nil, errors.New("forbidden")
	})

	if err := h.r.Run(context.Background()); err == nil {
		t.Fatal("expected an error")
	}
	assertKeys(t, h.tigris.ids(), "tid_admin", "tid_other")
}

func TestRejectsConfigurationsThatCouldDeleteAKeyInUse(t *testing.T) {
	valid := newHarness(t).r.Config
	cases := map[string]func(*Config){
		"interval within retention":   func(c *Config) { c.Interval = 13 * time.Hour },
		"short retention":             func(c *Config) { c.Retention = time.Hour },
		"shorter than presigned URLs": func(c *Config) { c.Retention = 12 * time.Hour },
		"short prefix":                func(c *Config) { c.Prefix = "tuist-" },
		"prefix without separator":    func(c *Config) { c.Prefix = "tuist-staging" },
		"wildcard bucket":             func(c *Config) { c.Roles = []tigris.BucketRole{{Bucket: "*", Role: "ReadWrite"}} },
		"admin role":                  func(c *Config) { c.Roles = []tigris.BucketRole{{Bucket: "b", Role: "Admin"}} },
	}
	if err := valid.Validate(); err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
	for name, mutate := range cases {
		config := valid
		mutate(&config)
		if config.Validate() == nil {
			t.Errorf("%s: accepted", name)
		}
	}
}
