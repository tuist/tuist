// Command rotator runs one S3 key rotation pass for one Secret. It is meant to
// run as a CronJob; see internal/rotation for what a pass does.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/s3-key-rotator/internal/rotation"
	"github.com/tuist/tuist/infra/s3-key-rotator/internal/tigris"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

func main() {
	logger := slog.New(slog.NewJSONHandler(os.Stderr, nil))
	if err := run(logger); err != nil {
		logger.Error("rotation failed", "error", err)
		os.Exit(1)
	}
}

func run(logger *slog.Logger) error {
	var (
		namespace   = flag.String("namespace", os.Getenv("POD_NAMESPACE"), "namespace of the rotated Secret")
		secretName  = flag.String("secret", "", "name of the rotated Secret")
		prefix      = flag.String("key-prefix", "", "name prefix of the keys this Secret's rotation owns")
		roles       = flag.String("bucket-roles", "", `JSON list of bucket roles, such as [{"bucket":"b","role":"ReadWrite"}]`)
		interval    = flag.Duration("interval", 24*time.Hour, "age at which the current key is replaced")
		retention   = flag.Duration("retention", 13*time.Hour, "how long a replaced key keeps working")
		rotateNow   = flag.Bool("rotate-now", false, "replace the current key regardless of its age; the replaced key still works for the retention")
		adminDir    = flag.String("admin-credentials-dir", "/var/run/tigris-admin", "directory with the admin key's access_key_id and secret_access_key")
		iamEndpoint = flag.String("iam-endpoint", "https://iam.storageapi.dev", "Tigris IAM endpoint")
		s3Endpoint  = flag.String("s3-endpoint", "https://t3.storage.dev", "Tigris S3 endpoint")
	)
	flag.Parse()

	var bucketRoles []tigris.BucketRole
	if err := json.Unmarshal([]byte(*roles), &bucketRoles); err != nil {
		return fmt.Errorf("--bucket-roles: %w", err)
	}

	admin, err := readCredentials(*adminDir)
	if err != nil {
		return err
	}

	restConfig, err := rest.InClusterConfig()
	if err != nil {
		return err
	}
	clientset, err := kubernetes.NewForConfig(restConfig)
	if err != nil {
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Minute)
	defer cancel()

	rotator := &rotation.Rotator{
		Config: rotation.Config{
			Namespace:     *namespace,
			SecretName:    *secretName,
			Prefix:        *prefix,
			Roles:         bucketRoles,
			Interval:      *interval,
			Retention:     *retention,
			RotateNow:     *rotateNow,
			AdminKeyID:    admin.AccessKeyID,
			VerifyTimeout: 3 * time.Minute,
			VerifyBackoff: 10 * time.Second,
		},
		Tigris:     &tigris.Client{IAMEndpoint: *iamEndpoint, S3Endpoint: *s3Endpoint, Admin: admin},
		Kubernetes: clientset,
		Logger:     logger,
		Now:        time.Now,
		Sleep: func(ctx context.Context, d time.Duration) error {
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(d):
				return nil
			}
		},
	}
	return rotator.Run(ctx)
}

func readCredentials(dir string) (tigris.Credentials, error) {
	read := func(name string) (string, error) {
		content, err := os.ReadFile(filepath.Join(dir, name))
		if err != nil {
			return "", err
		}
		value := strings.TrimSpace(string(content))
		if value == "" {
			return "", fmt.Errorf("%s is empty", filepath.Join(dir, name))
		}
		return value, nil
	}
	id, err := read(rotation.AccessKeyIDField)
	if err != nil {
		return tigris.Credentials{}, err
	}
	secret, err := read(rotation.SecretAccessKeyField)
	if err != nil {
		return tigris.Credentials{}, err
	}
	return tigris.Credentials{AccessKeyID: id, SecretAccessKey: secret}, nil
}
