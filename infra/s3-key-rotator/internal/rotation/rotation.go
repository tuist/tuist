// Package rotation replaces the S3 key in a Kubernetes Secret with a freshly
// minted Tigris key on a schedule, and deletes old keys once nothing can still
// be using them.
//
// One run, meant to be a CronJob with concurrencyPolicy Forbid:
//
//  1. When the Secret is missing or its key is older than Interval, mint a new
//     key named Prefix+timestamp with the configured bucket roles, wait until
//     it can reach every bucket, then write it to the Secret. The previous key
//     is recorded in the Secret's annotations with the time it may be deleted
//     (now + Retention).
//  2. Delete the keys this rotation minted that nothing can still be using:
//     not the Secret's current key, not the previous key inside its
//     retention, minted (per the timestamp in its name) more than
//     Interval+Retention ago, and only once Retention has passed since the
//     Secret's last rotation.
//
// Workloads mount the Secret as files (TuistCommon.AWS.CredentialFiles), so
// they switch to the new key within about two minutes without restarting:
// kubelet updates the files, and the adapter re-reads them every 30 seconds.
// Retention must outlast that switch, the longest operation started on the
// old key, and the longest presigned URL it signed (12 hours for GitLab cache
// downloads), which is why it defaults to 13 hours.
//
// Step 2 has two time gates because the annotations alone are not enough.
// Every key other than the current one was replaced at or before the Secret's
// last rotation, so once Retention has passed since then, none of them can be
// in use; a run that had to recreate the Secret, or rotated early because its
// annotations were lost, therefore deletes nothing for Retention. This holds
// however long a key stayed current, such as after rotations stalled. The
// minting-time gate protects keys a concurrent run minted but has not stored
// yet (a manual `kubectl create job` ignores concurrencyPolicy), and deletes
// keys a crashed run minted but never stored. Only names that are exactly
// Prefix plus a timestamp count, so a longer prefix sharing this one's start
// is never matched.
package rotation

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/s3-key-rotator/internal/tigris"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
)

const (
	AccessKeyIDField     = "access_key_id"
	SecretAccessKeyField = "secret_access_key"

	rotatedAtAnnotation        = "tuist.dev/s3-key-rotated-at"
	previousKeyAnnotation      = "tuist.dev/s3-key-previous-id"
	previousRetireAtAnnotation = "tuist.dev/s3-key-previous-retire-at"

	keyNameTimeLayout = "20060102T150405Z"
	// minRetention covers the longest presigned URL (12 hours) plus the
	// time workloads take to switch to a new key.
	minRetention = 12*time.Hour + 15*time.Minute
)

// Tigris is the part of the Tigris API a run uses.
type Tigris interface {
	CreateKey(ctx context.Context, name string, roles []tigris.BucketRole) (tigris.Credentials, error)
	ListKeys(ctx context.Context) ([]tigris.Key, error)
	DeleteKey(ctx context.Context, id string) error
	CanReach(ctx context.Context, key tigris.Credentials, bucket string) error
}

// Config describes one rotated Secret.
type Config struct {
	Namespace  string
	SecretName string
	// Prefix names every key this Secret's rotation mints, such as
	// "tuist-staging-platform-". It must not be shared with anything else.
	Prefix string
	Roles  []tigris.BucketRole
	// Interval is how old the current key gets before it is replaced.
	Interval time.Duration
	// Retention is how long a replaced key keeps working.
	Retention time.Duration
	// RotateNow replaces the current key regardless of its age, such as after
	// it leaked. Cleanup keeps its time gates, so the replaced key still works
	// for Retention.
	RotateNow bool
	// AdminKeyID is the key the rotator itself uses, never deleted.
	AdminKeyID string
	// VerifyTimeout bounds the wait for a new key to reach its buckets.
	VerifyTimeout time.Duration
	VerifyBackoff time.Duration
}

// Validate rejects configurations that could delete a key still in use.
func (c Config) Validate() error {
	switch {
	case c.Namespace == "" || c.SecretName == "":
		return errors.New("namespace and secret name are required")
	case len(c.Prefix) < 8 || !strings.HasSuffix(c.Prefix, "-"):
		return fmt.Errorf("prefix %q must be at least 8 characters and end with '-'", c.Prefix)
	case len(c.Roles) == 0:
		return errors.New("at least one bucket role is required")
	case c.Retention < minRetention:
		return fmt.Errorf("retention %s is shorter than %s, the longest presigned URL plus the switch", c.Retention, minRetention)
	case c.Interval <= c.Retention:
		// Otherwise a rotation would replace the previous key while it is
		// still retained, and it would be deleted early.
		return fmt.Errorf("interval %s must be longer than retention %s", c.Interval, c.Retention)
	}
	for _, role := range c.Roles {
		if role.Bucket == "" || role.Bucket == "*" {
			return fmt.Errorf("bucket role %+v must name a bucket", role)
		}
		if role.Role != "ReadOnly" && role.Role != "ReadWrite" && role.Role != "Editor" {
			return fmt.Errorf("bucket role %+v must be ReadOnly, ReadWrite or Editor", role)
		}
	}
	return nil
}

// Rotator runs rotations.
type Rotator struct {
	Config     Config
	Tigris     Tigris
	Kubernetes kubernetes.Interface
	Logger     *slog.Logger
	Now        func() time.Time
	Sleep      func(context.Context, time.Duration) error
}

// Run performs one rotation pass.
func (r *Rotator) Run(ctx context.Context) error {
	if err := r.Config.Validate(); err != nil {
		return err
	}
	now := r.Now().UTC()

	secrets := r.Kubernetes.CoreV1().Secrets(r.Config.Namespace)
	secret, err := secrets.Get(ctx, r.Config.SecretName, metav1.GetOptions{})
	if apierrors.IsNotFound(err) {
		secret = nil
	} else if err != nil {
		return fmt.Errorf("read secret %s/%s: %w", r.Config.Namespace, r.Config.SecretName, err)
	}

	keys, err := r.Tigris.ListKeys(ctx)
	if err != nil {
		return err
	}

	if due, reason := r.rotationDue(ctx, secret, keys, now); due {
		r.Logger.Info("rotating S3 key", "secret", r.Config.SecretName, "reason", reason)
		if secret, err = r.rotate(ctx, secret, now); err != nil {
			return err
		}
	}

	return r.cleanup(ctx, secret, keys, now)
}

func (r *Rotator) rotationDue(ctx context.Context, secret *corev1.Secret, keys []tigris.Key, now time.Time) (bool, string) {
	if secret == nil {
		return true, "secret does not exist"
	}
	if len(secret.Data[AccessKeyIDField]) == 0 || len(secret.Data[SecretAccessKeyField]) == 0 {
		return true, "secret has no key"
	}
	rotatedAt, err := time.Parse(time.RFC3339, secret.Annotations[rotatedAtAnnotation])
	if err != nil {
		return true, "secret has no rotation time"
	}
	if now.Sub(rotatedAt) >= r.Config.Interval {
		return true, "key is older than the interval"
	}
	if r.Config.RotateNow {
		return true, "rotation requested"
	}
	current := string(secret.Data[AccessKeyIDField])
	for _, key := range keys {
		if key.ID == current {
			return false, ""
		}
	}
	// Not listed. Rotate only if the key really stopped working: a list that
	// came back incomplete must not rotate on every run.
	stored := tigris.Credentials{AccessKeyID: current, SecretAccessKey: string(secret.Data[SecretAccessKeyField])}
	if err := r.Tigris.CanReach(ctx, stored, r.Config.Roles[0].Bucket); err == nil {
		r.Logger.Warn("current S3 key is not listed but still works; not rotating", "key", current)
		return false, ""
	}
	return true, "current key no longer exists in Tigris"
}

func (r *Rotator) rotate(ctx context.Context, secret *corev1.Secret, now time.Time) (*corev1.Secret, error) {
	name := r.Config.Prefix + now.Format(keyNameTimeLayout)
	key, err := r.Tigris.CreateKey(ctx, name, r.Config.Roles)
	if err != nil {
		return nil, err
	}

	// Anything that fails from here on must not leave the new key behind.
	discard := func(cause error) error {
		if err := r.Tigris.DeleteKey(context.WithoutCancel(ctx), key.AccessKeyID); err != nil {
			r.Logger.Error("could not delete unused key; the next run deletes it", "key", key.AccessKeyID, "error", err)
		}
		return cause
	}

	if err := r.verify(ctx, key); err != nil {
		return nil, discard(fmt.Errorf("new key %s cannot reach its buckets: %w", key.AccessKeyID, err))
	}

	annotations := map[string]string{rotatedAtAnnotation: now.Format(time.RFC3339)}
	if secret != nil {
		if previous := string(secret.Data[AccessKeyIDField]); previous != "" {
			annotations[previousKeyAnnotation] = previous
			annotations[previousRetireAtAnnotation] = now.Add(r.Config.Retention).Format(time.RFC3339)
		}
	}
	data := map[string][]byte{
		AccessKeyIDField:     []byte(key.AccessKeyID),
		SecretAccessKeyField: []byte(key.SecretAccessKey),
	}

	secrets := r.Kubernetes.CoreV1().Secrets(r.Config.Namespace)
	var stored *corev1.Secret
	if secret == nil {
		stored, err = secrets.Create(ctx, &corev1.Secret{
			ObjectMeta: metav1.ObjectMeta{
				Name:        r.Config.SecretName,
				Namespace:   r.Config.Namespace,
				Annotations: annotations,
				Labels:      map[string]string{"app.kubernetes.io/managed-by": "s3-key-rotator"},
			},
			Type: corev1.SecretTypeOpaque,
			Data: data,
		}, metav1.CreateOptions{})
	} else {
		updated := secret.DeepCopy()
		if updated.Annotations == nil {
			updated.Annotations = map[string]string{}
		}
		delete(updated.Annotations, previousKeyAnnotation)
		delete(updated.Annotations, previousRetireAtAnnotation)
		for k, v := range annotations {
			updated.Annotations[k] = v
		}
		updated.Data = data
		// The resourceVersion from the read makes this fail rather than
		// overwrite a concurrent change.
		stored, err = secrets.Update(ctx, updated, metav1.UpdateOptions{})
	}
	if err != nil {
		cause := fmt.Errorf("store new key in secret %s: %w", r.Config.SecretName, err)
		if rejected(err) {
			return nil, discard(cause)
		}
		// A timeout or dropped connection can come after the API server
		// stored the write; deleting the key then would hand workloads a dead
		// key. Read back what is there instead.
		readCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), 30*time.Second)
		defer cancel()
		current, getErr := secrets.Get(readCtx, r.Config.SecretName, metav1.GetOptions{})
		switch {
		case getErr == nil && string(current.Data[AccessKeyIDField]) == key.AccessKeyID:
			stored = current
		case getErr == nil || apierrors.IsNotFound(getErr):
			return nil, discard(cause)
		default:
			// Unknown outcome: keep the key; cleanup deletes it after
			// Interval+Retention if it was never stored.
			r.Logger.Error("could not tell whether the new key was stored; keeping it", "key", key.AccessKeyID, "error", getErr)
			return nil, cause
		}
	}

	r.Logger.Info("stored new S3 key", "secret", r.Config.SecretName, "key", key.AccessKeyID,
		"previous", annotations[previousKeyAnnotation], "previous_retire_at", annotations[previousRetireAtAnnotation])
	return stored, nil
}

// verify waits until the key reaches every bucket: a new Tigris key can take a
// moment to propagate, and a key that never works must not reach workloads.
func (r *Rotator) verify(ctx context.Context, key tigris.Credentials) error {
	deadline := r.Now().Add(r.Config.VerifyTimeout)
	for _, role := range r.Config.Roles {
		for {
			err := r.Tigris.CanReach(ctx, key, role.Bucket)
			if err == nil {
				break
			}
			if !r.Now().Before(deadline) {
				return fmt.Errorf("bucket %s: %w", role.Bucket, err)
			}
			if err := r.Sleep(ctx, r.Config.VerifyBackoff); err != nil {
				return err
			}
		}
	}
	return nil
}

func (r *Rotator) cleanup(ctx context.Context, secret *corev1.Secret, keys []tigris.Key, now time.Time) error {
	// A missing Secret or rotation time means this run could not store one;
	// any key may still be in use (pods keep reading their files).
	if secret == nil {
		return nil
	}
	rotatedAt, err := time.Parse(time.RFC3339, secret.Annotations[rotatedAtAnnotation])
	if err != nil || now.Before(rotatedAt.Add(r.Config.Retention)) {
		return nil
	}

	keep := map[string]bool{r.Config.AdminKeyID: true, string(secret.Data[AccessKeyIDField]): true}
	if retireAt, err := time.Parse(time.RFC3339, secret.Annotations[previousRetireAtAnnotation]); err == nil && now.Before(retireAt) {
		keep[secret.Annotations[previousKeyAnnotation]] = true
	}

	var errs []error
	for _, key := range keys {
		if keep[key.ID] {
			continue
		}
		mintedAt, ok := r.mintedAt(key.Name)
		if !ok || now.Sub(mintedAt) < r.Config.Interval+r.Config.Retention {
			continue
		}
		if err := r.Tigris.DeleteKey(ctx, key.ID); err != nil {
			errs = append(errs, err)
			continue
		}
		r.Logger.Info("deleted retired S3 key", "key", key.ID, "name", key.Name)
	}
	return errors.Join(errs...)
}

// mintedAt is when the rotation minted a key named Prefix+timestamp; ok is
// false for any other name.
func (r *Rotator) mintedAt(name string) (time.Time, bool) {
	suffix, found := strings.CutPrefix(name, r.Config.Prefix)
	if !found {
		return time.Time{}, false
	}
	mintedAt, err := time.Parse(keyNameTimeLayout, suffix)
	return mintedAt, err == nil
}

// rejected reports whether the API server definitely refused a write, so the
// key it carried was not stored.
func rejected(err error) bool {
	return apierrors.IsConflict(err) || apierrors.IsAlreadyExists(err) || apierrors.IsInvalid(err) ||
		apierrors.IsForbidden(err) || apierrors.IsNotFound(err) || apierrors.IsBadRequest(err) ||
		apierrors.IsUnauthorized(err) || apierrors.IsRequestEntityTooLargeError(err)
}
