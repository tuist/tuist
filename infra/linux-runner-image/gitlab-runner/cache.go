package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"

	"gitlab.com/gitlab-org/gitlab-runner/cache"
	"gitlab.com/gitlab-org/gitlab-runner/cache/cacheconfig"
)

// The machine is discarded after one job, so GitLab's `cache:` keyword needs a
// remote store to outlive it. The Tuist server presigns object URLs for this
// job; storage credentials never enter the machine.
const cacheAdapterType = "tuist"

var errCacheRejected = errors.New("Tuist cache request rejected")

func cacheConfig() *cacheconfig.Config {
	// Shared drops the runner namespace, leaving `project/<id>/<key>`. The
	// server scopes that path to the job's account and ref protection.
	return &cacheconfig.Config{Type: cacheAdapterType, Shared: true}
}

func registerCacheAdapter(job assignment) error {
	return cache.Factories().Register(cacheAdapterType, func(_ *cacheconfig.Config, timeout time.Duration, objectName string) (cache.Adapter, error) {
		return &cacheAdapter{job: job, timeout: timeout, objectName: objectName}, nil
	})
}

type cacheAdapter struct {
	job        assignment
	timeout    time.Duration
	objectName string
	once       sync.Once
	download   string
}

// Without a URL, GitLab Runner skips the remote cache and continues the job.
func (a *cacheAdapter) GetDownloadURL(ctx context.Context) cache.PresignedURL {
	a.once.Do(func() {
		var response struct {
			URL string `json:"url"`
		}
		request := map[string]any{"object_name": a.objectName, "expires_in": int(a.timeout.Seconds())}
		if err := newCacheClient(a.job.ReportURL, a.job.ReportToken).post(ctx, "cache/download", request, &response); err == nil {
			a.download = response.URL
		}
	})
	return presigned(a.download)
}

// Uploads go through the multipart bucket in GetGoCloudURL, since a single
// presigned PUT is capped at 5 GB.
func (a *cacheAdapter) GetUploadURL(context.Context) cache.PresignedURL { return cache.PresignedURL{} }

func (a *cacheAdapter) GetHeadURL(context.Context) cache.PresignedURL { return cache.PresignedURL{} }

func (a *cacheAdapter) WithMetadata(map[string]string) {}

func (a *cacheAdapter) GetGoCloudURL(_ context.Context, upload bool) (cache.GoCloudURL, error) {
	if !upload {
		return cache.GoCloudURL{}, nil
	}
	// The archiver runs as a separate process and reads these from its env file.
	return cache.GoCloudURL{
		URL: &url.URL{Scheme: cacheURLScheme, Host: "cache", Path: "/" + a.objectName},
		Environment: map[string]string{
			cacheEndpointEnv: a.job.ReportURL,
			cacheTokenEnv:    a.job.ReportToken,
		},
	}, nil
}

func presigned(raw string) cache.PresignedURL {
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "https" && parsed.Scheme != "http") || parsed.Host == "" {
		return cache.PresignedURL{}
	}
	return cache.PresignedURL{URL: parsed}
}

type cacheClient struct {
	endpoint string
	token    string
	api      *http.Client
	storage  *http.Client
}

func newCacheClient(endpoint, token string) *cacheClient {
	noRedirects := func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	return &cacheClient{
		endpoint: strings.TrimRight(endpoint, "/"),
		token:    token,
		api:      &http.Client{Timeout: 20 * time.Second, CheckRedirect: noRedirects},
		// A part transfer is bounded by its context, not a fixed deadline.
		storage: &http.Client{CheckRedirect: noRedirects},
	}
}

func (c *cacheClient) post(ctx context.Context, path string, body, out any) error {
	encoded, err := json.Marshal(body)
	if err != nil {
		return err
	}
	return withRetries(ctx, func() (bool, error) {
		request, err := http.NewRequestWithContext(ctx, http.MethodPost, c.endpoint+"/"+path, bytes.NewReader(encoded))
		if err != nil {
			return false, err
		}
		request.Header.Set("Authorization", "Bearer "+c.token)
		request.Header.Set("Content-Type", "application/json")
		response, err := c.api.Do(request)
		if err != nil {
			return true, err
		}
		defer response.Body.Close()
		if response.StatusCode < 200 || response.StatusCode >= 300 {
			_, _ = io.Copy(io.Discard, response.Body)
			return retryable(response.StatusCode), errCacheRejected
		}
		if out == nil {
			_, _ = io.Copy(io.Discard, response.Body)
			return false, nil
		}
		return false, json.NewDecoder(io.LimitReader(response.Body, 64*1024)).Decode(out)
	})
}

func (c *cacheClient) putPart(ctx context.Context, partURL string, data []byte) (string, error) {
	var etag string
	err := withRetries(ctx, func() (bool, error) {
		request, err := http.NewRequestWithContext(ctx, http.MethodPut, partURL, bytes.NewReader(data))
		if err != nil {
			return false, err
		}
		request.ContentLength = int64(len(data))
		response, err := c.storage.Do(request)
		if err != nil {
			return true, err
		}
		defer response.Body.Close()
		_, _ = io.Copy(io.Discard, response.Body)
		if response.StatusCode < 200 || response.StatusCode >= 300 {
			return retryable(response.StatusCode), errors.New("cache part upload rejected")
		}
		if etag = response.Header.Get("ETag"); etag == "" {
			return false, errors.New("cache part upload returned no ETag")
		}
		return false, nil
	})
	return etag, err
}

func retryable(status int) bool {
	return status >= 500 || status == http.StatusTooManyRequests
}

func withRetries(ctx context.Context, attempt func() (bool, error)) error {
	const attempts = 3
	for i := 1; ; i++ {
		retry, err := attempt()
		if err == nil || !retry || i == attempts {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Duration(i) * time.Second):
		}
	}
}
