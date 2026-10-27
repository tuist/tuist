package cachevolumes

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
)

type HTTPTransfer struct {
	URL, Node, TokenPath string
	Client               *http.Client
	// ObjectClient downloads and uploads image archives. It must not bound the
	// whole transfer: a stall, not a deadline, ends an attempt. Nil uses Client
	// without its timeout.
	ObjectClient *http.Client
	MaxBytes     int64
	Token        func(context.Context) (string, error)
	// Log records retried server requests and uploads; nil is slog.Default.
	Log *slog.Logger

	// Zero values use the package defaults; injectable so tests don't wait real minutes.
	stallTimeout      time.Duration
	retryBackoff      time.Duration
	partBytes         int64
	uploadParallelism int
}

const (
	// transferStallTimeout abandons a download that receives nothing, or an
	// upload that sends nothing, for this long. downloadAttempts /
	// transferRetryBackoff bound the retries of one download; each resumes where the
	// last one stopped. uploadAttempts bounds the attempts of one publication;
	// each sends the whole archive again, waiting transferRetryBackoff times its number.
	transferStallTimeout = 2 * time.Minute
	downloadAttempts     = 5
	uploadAttempts       = 4
	transferRetryBackoff = 10 * time.Second
)

var errDownloadStalled = errors.New("image download stalled")
var errUploadStalled = errors.New("image upload stalled")

// errTransport is a request that failed before the remote end answered it.
var errTransport = errors.New("transport error")

// ErrDownloadIncomplete is a download its context ended while it was still
// receiving bytes. What it received is kept for the next call to resume.
var ErrDownloadIncomplete = errors.New("image download incomplete")
var errArchiveTooLarge = errors.New("cache image archive exceeds the image size limit")

type transferResponse struct {
	DownloadURL   string     `json:"download_url"`
	UploadURL     string     `json:"upload_url"`
	Checksum      string     `json:"checksum_sha256"`
	Generation    int64      `json:"generation"`
	ImageDigest   string     `json:"image_digest"`
	ContentDigest string     `json:"content_digest"`
	Conflict      bool       `json:"conflict"`
	UploadID      string     `json:"upload_id"`
	Parts         []partLink `json:"parts"`
}

func (t *HTTPTransfer) request(ctx context.Context, slot Slot, operation, digest, content string) (transferResponse, error) {
	return t.requestWith(ctx, slot, operation, digest, content, nil)
}

func (t *HTTPTransfer) requestWith(ctx context.Context, slot Slot, operation, digest, content string, extra map[string]any) (transferResponse, error) {
	fields := map[string]any{"id": slot.ID, "node_name": t.Node, "operation": operation, "image_digest": digest, "content_digest": content}
	for key, value := range extra {
		fields[key] = value
	}
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
	response, err := DoServer(t.Client, req, t.Log)
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
	if err = json.NewDecoder(io.LimitReader(response.Body, 1<<20)).Decode(&result); err != nil {
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
	if err = RestoreImage(ctx, file, path, slot.ContentDigest, t.maxBytes(slot)); err != nil {
		if ctx.Err() == nil {
			// A complete archive that does not restore cannot be resumed into one that does.
			_ = os.Remove(archive)
		}
		return err
	}
	return os.Remove(archive)
}

func (t *HTTPTransfer) fetchArchive(ctx context.Context, slot Slot, archive string) error {
	backoff := t.backoff()
	for attempt := 1; ; attempt++ {
		// Every attempt asks for a fresh link: a presigned URL can expire mid-download.
		result, err := t.request(ctx, slot, "download", "", "")
		if err != nil {
			return err
		}
		if result.Generation != slot.BaseGeneration || result.DownloadURL == "" {
			return errors.New("cache master identity mismatch")
		}
		err = t.fetch(ctx, result.DownloadURL, archive, t.maxBytes(slot))
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
func (t *HTTPTransfer) fetch(ctx context.Context, url, archive string, maxBytes int64) error {
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
	stall := t.stall()
	// The watchdog also covers a server that accepts the request but never answers.
	watchdog := time.AfterFunc(stall, func() { cancel(errDownloadStalled) })
	defer watchdog.Stop()
	response, err := t.objectClient().Do(req)
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
		return remoteError("download", response)
	}
	// Incompressible payloads can grow slightly when compressed (see RestoreImage).
	limit := maxBytes + maxBytes/100 + (1 << 20)
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
	watchdog.Reset(stall)
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
	// n counts what was read; net/http may read an upload's body after Do returns.
	n atomic.Int64
}

func (p *progressReader) Read(b []byte) (int, error) {
	n, err := p.r.Read(b)
	if n > 0 {
		p.n.Add(int64(n))
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

// remoteError names an object store's error code (S3's <Code>) when its
// response body carries one, so a 5xx says whether storage was overloaded,
// failed internally or never answered behind a proxy.
func remoteError(operation string, response *http.Response) *RemoteError {
	body, _ := io.ReadAll(io.LimitReader(response.Body, 4096))
	remote := &RemoteError{Operation: operation, StatusCode: response.StatusCode}
	if match := storageErrorCode.FindSubmatch(body); match != nil {
		remote.Code = string(match[1])
	}
	return remote
}

var storageErrorCode = regexp.MustCompile(`<Code>([A-Za-z]{1,64})</Code>`)

func (t *HTTPTransfer) objectClient() *http.Client {
	if t.ObjectClient != nil {
		return t.ObjectClient
	}
	client := *t.Client
	client.Timeout = 0
	return &client
}

func (t *HTTPTransfer) stall() time.Duration {
	if t.stallTimeout > 0 {
		return t.stallTimeout
	}
	return transferStallTimeout
}

func (t *HTTPTransfer) backoff() time.Duration {
	if t.retryBackoff > 0 {
		return t.retryBackoff
	}
	return transferRetryBackoff
}

func (t *HTTPTransfer) Head(slot Slot) (Identity, error) {
	result, err := t.request(context.Background(), slot, "retain", "", "")
	if err != nil {
		return Identity{}, err
	}
	return Identity{BaseGeneration: result.Generation, ImageDigest: result.ImageDigest, ContentDigest: result.ContentDigest}, nil
}

// transferError preserves cancellation for classification and keeps what the
// network reported (a reset, a broken pipe, an EOF, a TLS failure) without the
// credential-bearing URL net/http puts in front of it.
func transferError(err error) error {
	if errors.Is(err, context.DeadlineExceeded) {
		return context.DeadlineExceeded
	}
	if errors.Is(err, context.Canceled) {
		return context.Canceled
	}
	var request *url.Error
	if errors.As(err, &request) {
		err = request.Err
	}
	return fmt.Errorf("%w: %s", errTransport, signedURL.ReplaceAllString(err.Error(), "<url>"))
}

// signedURL matches a URL, which may carry a signature, in an error's text.
var signedURL = regexp.MustCompile(`https?://[^\s"']+`)

func (t *HTTPTransfer) token(ctx context.Context) (string, error) {
	if t.Token != nil {
		return t.Token(ctx)
	}
	data, err := os.ReadFile(t.TokenPath)
	return string(data), err
}

// maxBytes bounds the slot's restored image: a Docker data root is larger than
// the host's other volumes.
func (t *HTTPTransfer) maxBytes(slot Slot) int64 {
	if slot.Kind == KindDocker {
		return max(t.MaxBytes, DockerVolumeBytes)
	}
	return t.MaxBytes
}

// Rebase moves the slot's use to the lineage's head named by the slot's base,
// once its data root holds that head's content. The server refuses (ErrConflict)
// when the head moved again or the use may no longer publish.
func (t *HTTPTransfer) Rebase(slot Slot) error {
	_, err := t.requestWith(context.Background(), slot, "rebase", slot.ImageDigest, slot.ContentDigest, map[string]any{"generation": slot.BaseGeneration})
	return err
}
