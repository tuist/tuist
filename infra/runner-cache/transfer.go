package cachevolumes

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

type HTTPTransfer struct {
	URL, Node, TokenPath string
	Client               *http.Client
	// DownloadClient fetches image archives. It must not bound the whole
	// transfer: a stall, not a deadline, ends an attempt. Nil uses Client.
	DownloadClient *http.Client
	MaxBytes       int64
	Token          func(context.Context) (string, error)

	// Zero values use the package defaults; injectable so tests don't wait real minutes.
	stallTimeout time.Duration
	retryBackoff time.Duration
}

const (
	// downloadStallTimeout abandons an attempt that receives nothing for this
	// long. downloadAttempts / downloadRetryBackoff bound the retries of one
	// call; each resumes where the last one stopped.
	downloadStallTimeout = 2 * time.Minute
	downloadAttempts     = 5
	downloadRetryBackoff = 10 * time.Second
)

var errDownloadStalled = errors.New("image download stalled")

// ErrDownloadIncomplete is a download its context ended while it was still
// receiving bytes. What it received is kept for the next call to resume.
var ErrDownloadIncomplete = errors.New("image download incomplete")
var errArchiveTooLarge = errors.New("cache image archive exceeds the image size limit")

type transferResponse struct {
	DownloadURL   string `json:"download_url"`
	UploadURL     string `json:"upload_url"`
	Checksum      string `json:"checksum_sha256"`
	Generation    int64  `json:"generation"`
	ImageDigest   string `json:"image_digest"`
	ContentDigest string `json:"content_digest"`
	Conflict      bool   `json:"conflict"`
}

func (t *HTTPTransfer) request(ctx context.Context, slot Slot, operation, digest, content string) (transferResponse, error) {
	fields := map[string]any{"id": slot.ID, "node_name": t.Node, "operation": operation, "image_digest": digest, "content_digest": content}
	// A download names its generation: a host may refresh a stale master to the
	// current HEAD of the lineage it already holds.
	if operation == "download" {
		fields["generation"] = slot.BaseGeneration
	}
	body, _ := json.Marshal(fields)
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "POST", t.URL, bytes.NewReader(body))
	if err != nil {
		return transferResponse{}, err
	}
	token, err := t.token(ctx)
	if err != nil {
		return transferResponse{}, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", "application/json")
	response, err := t.Client.Do(req)
	if err != nil {
		return transferResponse{}, fmt.Errorf("image metadata request failed: %w", transferError(err))
	}
	defer response.Body.Close()
	if response.StatusCode == 409 {
		return transferResponse{}, ErrConflict
	}
	if response.StatusCode != 200 {
		return transferResponse{}, &RemoteError{Operation: "metadata", StatusCode: response.StatusCode}
	}
	var result transferResponse
	if err = json.NewDecoder(io.LimitReader(response.Body, 16384)).Decode(&result); err != nil {
		return result, err
	}
	if result.Conflict {
		return result, ErrConflict
	}
	return result, nil
}

// Download restores the slot's image to path. The archive is kept at
// path+".part" until it is complete, so a later call with the same path resumes
// an interrupted transfer instead of starting over.
func (t *HTTPTransfer) Download(ctx context.Context, slot Slot, path string) error {
	archive := path + ".part"
	if err := t.fetchArchive(ctx, slot, archive); err != nil {
		return err
	}
	file, err := os.Open(archive)
	if err != nil {
		return err
	}
	defer file.Close()
	if err = RestoreImage(ctx, file, path, slot.ContentDigest, t.MaxBytes); err != nil {
		if ctx.Err() == nil {
			// A complete archive that does not restore cannot be resumed into one that does.
			_ = os.Remove(archive)
		}
		return err
	}
	return os.Remove(archive)
}

func (t *HTTPTransfer) fetchArchive(ctx context.Context, slot Slot, archive string) error {
	backoff := t.retryBackoff
	if backoff <= 0 {
		backoff = downloadRetryBackoff
	}
	for attempt := 1; ; attempt++ {
		// Every attempt asks for a fresh link: a presigned URL can expire mid-download.
		result, err := t.request(ctx, slot, "download", "", "")
		if err != nil {
			return err
		}
		if result.Generation != slot.BaseGeneration || result.DownloadURL == "" {
			return errors.New("cache master identity mismatch")
		}
		err = t.fetch(ctx, result.DownloadURL, archive)
		var remote *RemoteError
		if err == nil || ctx.Err() != nil || attempt >= downloadAttempts || errors.Is(err, errArchiveTooLarge) || (errors.As(err, &remote) && remote.StatusCode < 500) {
			return err
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(backoff):
		}
	}
}

// fetch appends the rest of the archive to what archive already holds.
func (t *HTTPTransfer) fetch(ctx context.Context, url, archive string) error {
	ctx, cancel := context.WithCancelCause(ctx)
	defer cancel(nil)
	var offset int64
	if info, err := os.Stat(archive); err == nil {
		offset = info.Size()
	}
	req, err := http.NewRequestWithContext(ctx, "GET", url, nil)
	if err != nil {
		return errors.New("invalid download URL")
	}
	if offset > 0 {
		req.Header.Set("Range", "bytes="+strconv.FormatInt(offset, 10)+"-")
	}
	client := t.DownloadClient
	if client == nil {
		client = t.Client
	}
	response, err := client.Do(req)
	if err != nil {
		if cause := context.Cause(ctx); errors.Is(cause, errDownloadStalled) {
			return cause
		}
		return fmt.Errorf("image download failed: %w", transferError(err))
	}
	defer response.Body.Close()
	total := int64(-1)
	switch {
	case response.StatusCode == http.StatusPartialContent && offset > 0:
		start, size, ok := parseContentRange(response.Header.Get("Content-Range"))
		if !ok || start != offset {
			_ = os.Remove(archive)
			return errors.New("image download resumed at the wrong offset")
		}
		total = size
	case response.StatusCode == http.StatusRequestedRangeNotSatisfiable && offset > 0:
		if _, size, ok := parseContentRange(response.Header.Get("Content-Range")); ok && size == offset {
			return nil
		}
		_ = os.Remove(archive)
		return errors.New("partial image download is not a prefix of the saved version")
	case response.StatusCode == http.StatusOK:
		offset, total = 0, response.ContentLength
	default:
		return &RemoteError{Operation: "download", StatusCode: response.StatusCode}
	}
	// Incompressible payloads can grow slightly when compressed (see RestoreImage).
	limit := t.MaxBytes + t.MaxBytes/100 + (1 << 20)
	if total > limit {
		_ = os.Remove(archive)
		return errArchiveTooLarge
	}
	file, err := os.OpenFile(archive, os.O_WRONLY|os.O_CREATE, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	if err = file.Truncate(offset); err != nil {
		return err
	}
	if _, err = file.Seek(offset, io.SeekStart); err != nil {
		return err
	}
	stall := t.stallTimeout
	if stall <= 0 {
		stall = downloadStallTimeout
	}
	watchdog := time.AfterFunc(stall, func() { cancel(errDownloadStalled) })
	defer watchdog.Stop()
	body := &progressReader{r: response.Body, progress: func() { watchdog.Reset(stall) }}
	written, err := io.Copy(file, io.LimitReader(body, limit+1-offset))
	if err != nil {
		cause := context.Cause(ctx)
		if errors.Is(cause, errDownloadStalled) {
			return cause
		}
		if cause != nil && written > 0 {
			// The caller ran out of time while bytes were still arriving.
			return fmt.Errorf("%w: %w", ErrDownloadIncomplete, transferError(cause))
		}
		return fmt.Errorf("image download failed: %w", transferError(err))
	}
	if total >= 0 && offset+written != total {
		return errors.New("image download ended early")
	}
	return file.Sync()
}

type progressReader struct {
	r        io.Reader
	progress func()
}

func (p *progressReader) Read(b []byte) (int, error) {
	n, err := p.r.Read(b)
	if n > 0 {
		p.progress()
	}
	return n, err
}

// parseContentRange parses "bytes start-end/size".
func parseContentRange(value string) (start, size int64, ok bool) {
	var end int64
	if n, err := fmt.Sscanf(value, "bytes %d-%d/%d", &start, &end, &size); err == nil && n == 3 {
		return start, size, start >= 0 && end >= start && size > end
	}
	if n, err := fmt.Sscanf(value, "bytes */%d", &size); err == nil && n == 1 {
		return 0, size, size >= 0
	}
	return 0, 0, false
}
func (t *HTTPTransfer) Publish(slot Slot, path, digest, content string) (int64, error) {
	result, err := t.request(context.Background(), slot, "upload", digest, content)
	if err != nil {
		return 0, err
	}
	if result.Generation > 0 {
		return result.Generation, nil
	}
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()
	stat, err := file.Stat()
	if err != nil {
		return 0, err
	}
	req, err := http.NewRequest("PUT", result.UploadURL, file)
	if err != nil {
		return 0, errors.New("invalid upload URL")
	}
	req.ContentLength = stat.Size()
	if result.Checksum != "" {
		req.Header.Set("x-amz-checksum-sha256", result.Checksum)
	}
	response, err := t.Client.Do(req)
	if err != nil {
		return 0, fmt.Errorf("image upload failed: %w", transferError(err))
	}
	response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return 0, &RemoteError{Operation: "upload", StatusCode: response.StatusCode}
	}
	result, err = t.request(context.Background(), slot, "publish", digest, content)
	if err == nil && result.Generation <= slot.BaseGeneration {
		return 0, errors.New("invalid published generation")
	}
	return result.Generation, err
}

func (t *HTTPTransfer) Head(slot Slot) (Identity, error) {
	result, err := t.request(context.Background(), slot, "retain", "", "")
	if err != nil {
		return Identity{}, err
	}
	return Identity{BaseGeneration: result.Generation, ImageDigest: result.ImageDigest, ContentDigest: result.ContentDigest}, nil
}

// Preserve cancellation for classification without logging credential-bearing URLs.
func transferError(err error) error {
	if errors.Is(err, context.DeadlineExceeded) {
		return context.DeadlineExceeded
	}
	if errors.Is(err, context.Canceled) {
		return context.Canceled
	}
	return errors.New("transport error")
}

func (t *HTTPTransfer) token(ctx context.Context) (string, error) {
	if t.Token != nil {
		return t.Token(ctx)
	}
	data, err := os.ReadFile(t.TokenPath)
	return string(data), err
}
