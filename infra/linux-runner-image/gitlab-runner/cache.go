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

type cacheURLs struct {
	Download string `json:"download_url"`
	Upload   string `json:"upload_url"`
}

type cacheAdapter struct {
	job        assignment
	timeout    time.Duration
	objectName string
	once       sync.Once
	urls       cacheURLs
}

// Without URLs, GitLab Runner skips the remote cache and continues the job.
func (a *cacheAdapter) GetDownloadURL(ctx context.Context) cache.PresignedURL {
	a.resolve(ctx)
	return presigned(a.urls.Download)
}

func (a *cacheAdapter) GetUploadURL(ctx context.Context) cache.PresignedURL {
	a.resolve(ctx)
	return presigned(a.urls.Upload)
}

func (a *cacheAdapter) GetHeadURL(context.Context) cache.PresignedURL { return cache.PresignedURL{} }

// Metadata would travel as signed headers the presigned URL does not cover.
func (a *cacheAdapter) WithMetadata(map[string]string) {}

func (a *cacheAdapter) GetGoCloudURL(context.Context, bool) (cache.GoCloudURL, error) {
	return cache.GoCloudURL{}, nil
}

func (a *cacheAdapter) resolve(ctx context.Context) {
	a.once.Do(func() {
		body, err := json.Marshal(map[string]any{"object_name": a.objectName, "expires_in": int(a.timeout.Seconds())})
		if err != nil {
			return
		}
		client := &http.Client{Timeout: 20 * time.Second, CheckRedirect: func(*http.Request, []*http.Request) error {
			return http.ErrUseLastResponse
		}}
		for attempt := 0; attempt < 3; attempt++ {
			retry, err := a.request(ctx, client, body)
			if err == nil || !retry {
				return
			}
			select {
			case <-ctx.Done():
				return
			case <-time.After(time.Duration(attempt+1) * time.Second):
			}
		}
	})
}

func (a *cacheAdapter) request(ctx context.Context, client *http.Client, body []byte) (bool, error) {
	request, err := http.NewRequestWithContext(ctx, http.MethodPost, strings.TrimRight(a.job.ReportURL, "/")+"/cache", bytes.NewReader(body))
	if err != nil {
		return false, err
	}
	request.Header.Set("Authorization", "Bearer "+a.job.ReportToken)
	request.Header.Set("Content-Type", "application/json")
	response, err := client.Do(request)
	if err != nil {
		return true, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		_, _ = io.Copy(io.Discard, response.Body)
		retry := response.StatusCode >= 500 || response.StatusCode == http.StatusTooManyRequests
		return retry, errors.New("cache URLs unavailable")
	}
	var urls cacheURLs
	if err := json.NewDecoder(io.LimitReader(response.Body, 64*1024)).Decode(&urls); err != nil {
		return false, err
	}
	a.urls = urls
	return false, nil
}

func presigned(raw string) cache.PresignedURL {
	parsed, err := url.Parse(raw)
	if err != nil || (parsed.Scheme != "https" && parsed.Scheme != "http") || parsed.Host == "" {
		return cache.PresignedURL{}
	}
	return cache.PresignedURL{URL: parsed}
}
