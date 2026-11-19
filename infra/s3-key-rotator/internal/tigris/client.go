// Package tigris calls the Tigris IAM and S3 APIs the rotator needs: create a
// bucket-scoped key, list and delete keys, and check that a key can reach its
// buckets.
//
// Tigris serves AWS-shaped IAM actions plus its own on the IAM endpoint
// (https://iam.storageapi.dev, the default of Tigris's own IAM SDK), all signed with SigV4 as service "s3" in region
// "auto". CreateAccessKeyWithBucketsRole and `?Detailed` ListAccessKeys are
// Tigris extensions: they set a key's name, bucket roles and scope in one call
// and return names when listing, which the AWS actions cannot. The request
// shapes follow Tigris's own IAM SDK (github.com/tigrisdata/storage,
// packages/iam).
package tigris

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	v4 "github.com/aws/aws-sdk-go-v2/aws/signer/v4"
)

const (
	signingService = "s3"
	signingRegion  = "auto"
	// noDefaultAllow is the `no_default_allow` access key scope: the key can do
	// only what its bucket roles grant, not the operations every standard key
	// gets (CreateBucket, CreateAccessKey, CreatePolicy). Without it, a leaked
	// short-lived key could mint itself a long-lived one.
	noDefaultAllow = 1
)

// Credentials is an access key pair.
type Credentials struct {
	AccessKeyID     string
	SecretAccessKey string
}

// BucketRole grants a key a role (ReadOnly, ReadWrite or Editor) on a bucket.
type BucketRole struct {
	Bucket string `json:"bucket"`
	Role   string `json:"role"`
}

// Key is an access key as listed.
type Key struct {
	ID   string
	Name string
}

// Client calls Tigris with an organization admin's key.
type Client struct {
	IAMEndpoint string
	S3Endpoint  string
	Admin       Credentials
	HTTP        *http.Client
	Now         func() time.Time
}

// CreateKey creates a `no_default_allow` key named name with roles.
func (c *Client) CreateKey(ctx context.Context, name string, roles []BucketRole) (Credentials, error) {
	request, err := json.Marshal(map[string]any{
		"req_uuid":         newUUID(),
		"name":             name,
		"buckets_role":     roles,
		"access_key_scope": noDefaultAllow,
	})
	if err != nil {
		return Credentials{}, err
	}

	var response struct {
		CreateAccessKeyResult struct {
			AccessKey struct {
				AccessKeyID     string `json:"AccessKeyId"`
				SecretAccessKey string `json:"SecretAccessKey"`
			} `json:"AccessKey"`
		} `json:"CreateAccessKeyResult"`
	}
	form := url.Values{"Req": {string(request)}}
	if err := c.iam(ctx, "Action=CreateAccessKeyWithBucketsRole", form, &response); err != nil {
		return Credentials{}, fmt.Errorf("create access key %s: %w", name, err)
	}

	key := response.CreateAccessKeyResult.AccessKey
	if key.AccessKeyID == "" || key.SecretAccessKey == "" {
		return Credentials{}, fmt.Errorf("create access key %s: response has no key", name)
	}
	return Credentials{AccessKeyID: key.AccessKeyID, SecretAccessKey: key.SecretAccessKey}, nil
}

// ListKeys returns every key the admin key can see.
func (c *Client) ListKeys(ctx context.Context) ([]Key, error) {
	var keys []Key
	marker := ""
	for {
		form := url.Values{"Action": {"ListAccessKeys"}, "MaxItems": {"1000"}}
		if marker != "" {
			form.Set("Marker", marker)
		}

		var response struct {
			IsTruncated bool   `json:"IsTruncated"`
			Marker      string `json:"Marker"`
			Keys        []struct {
				ID   string `json:"access_key_id"`
				Name string `json:"username"`
			} `json:"Keys"`
		}
		if err := c.iam(ctx, "Detailed", form, &response); err != nil {
			return nil, fmt.Errorf("list access keys: %w", err)
		}
		for _, key := range response.Keys {
			keys = append(keys, Key{ID: key.ID, Name: key.Name})
		}
		if !response.IsTruncated {
			return keys, nil
		}
		// A truncated page without a new marker would end the list early, and
		// a partial list must not pass for the whole one.
		if response.Marker == "" || response.Marker == marker {
			return nil, errors.New("list access keys: truncated response without a new marker")
		}
		marker = response.Marker
	}
}

// DeleteKey deletes a key. A key that no longer exists counts as deleted.
func (c *Client) DeleteKey(ctx context.Context, id string) error {
	form := url.Values{"Action": {"DeleteAccessKey"}, "Version": {"2010-05-08"}, "AccessKeyId": {id}}
	err := c.iam(ctx, "Action=DeleteAccessKey", form, nil)
	var status *StatusError
	if errors.As(err, &status) && (status.Code == http.StatusNotFound || strings.Contains(status.Body, "NoSuchEntity")) {
		return nil
	}
	if err != nil {
		return fmt.Errorf("delete access key %s: %w", id, err)
	}
	return nil
}

// CanReach reports whether key can read bucket's metadata (HeadBucket), so a
// new key is known to work before anything uses it.
func (c *Client) CanReach(ctx context.Context, key Credentials, bucket string) error {
	endpoint := strings.TrimRight(c.S3Endpoint, "/") + "/" + url.PathEscape(bucket)
	request, err := http.NewRequestWithContext(ctx, http.MethodHead, endpoint, nil)
	if err != nil {
		return err
	}
	response, err := c.send(ctx, request, nil, key)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return &StatusError{Code: response.StatusCode}
	}
	return nil
}

// StatusError is a non-2xx answer.
type StatusError struct {
	Code int
	Body string
}

func (e *StatusError) Error() string {
	if e.Body == "" {
		return fmt.Sprintf("HTTP %d", e.Code)
	}
	return fmt.Sprintf("HTTP %d: %s", e.Code, e.Body)
}

func (c *Client) iam(ctx context.Context, query string, form url.Values, out any) error {
	body := []byte(form.Encode())
	endpoint := strings.TrimRight(c.IAMEndpoint, "/") + "/?" + query
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	request.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	request.Header.Set("Accept", "application/json")

	response, err := c.send(ctx, request, body, c.Admin)
	if err != nil {
		return err
	}
	defer response.Body.Close()

	payload, err := io.ReadAll(io.LimitReader(response.Body, 4<<20))
	if err != nil {
		return err
	}
	if response.StatusCode/100 != 2 {
		// Error bodies carry an error code and message, never key material.
		return &StatusError{Code: response.StatusCode, Body: truncate(string(payload), 500)}
	}
	if out == nil {
		return nil
	}
	if err := json.Unmarshal(payload, out); err != nil {
		return fmt.Errorf("decode response: %w", err)
	}
	return nil
}

func (c *Client) send(ctx context.Context, request *http.Request, body []byte, key Credentials) (*http.Response, error) {
	sum := sha256.Sum256(body)
	payloadHash := hex.EncodeToString(sum[:])
	request.Header.Set("X-Amz-Content-Sha256", payloadHash)

	now := time.Now
	if c.Now != nil {
		now = c.Now
	}
	credentials := aws.Credentials{AccessKeyID: key.AccessKeyID, SecretAccessKey: key.SecretAccessKey}
	signer := v4.NewSigner(func(options *v4.SignerOptions) { options.DisableURIPathEscaping = true })
	if err := signer.SignHTTP(ctx, credentials, request, payloadHash, signingService, signingRegion, now()); err != nil {
		return nil, err
	}

	client := c.HTTP
	if client == nil {
		client = &http.Client{Timeout: 30 * time.Second}
	}
	return client.Do(request)
}

func newUUID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = (b[6] & 0x0f) | 0x40
	b[8] = (b[8] & 0x3f) | 0x80
	h := hex.EncodeToString(b[:])
	return h[0:8] + "-" + h[8:12] + "-" + h[12:16] + "-" + h[16:20] + "-" + h[20:32]
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
