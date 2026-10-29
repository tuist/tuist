package cachevolumes

import (
	"context"
	"crypto/md5"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"sort"
	"sync"
	"sync/atomic"
	"time"
)

const (
	// partBytes is the size of each part of a multipart upload. Archives of at
	// least two parts upload in parts, uploadParallelism of them at a time,
	// with links signed partLinkBatch parts at a time.
	partBytes         = 128 << 20
	partLinkBatch     = 16
	uploadParallelism = 8
)

type partLink struct {
	PartNumber int    `json:"part_number"`
	URL        string `json:"url"`
}

// publication is what one Publish call has stored so far, so a retried attempt
// resumes it instead of sending the archive again.
type publication struct {
	uploadID string
	etags    map[int]string
	stored   bool
}

func (p *publication) progress() int {
	if p.stored {
		return len(p.etags) + 1
	}
	return len(p.etags)
}

// Publish uploads the archive at path and fast-forwards the slot's lineage to
// it. A large archive is sent in parts, so a failed attempt resumes with the
// parts storage does not hold yet; a small one is one PUT, sent again. Every
// attempt asks for fresh links, which also tells this host when the lineage
// advanced meanwhile (ErrConflict). Once storage holds the whole archive only
// the fast-forward is retried. Attempts that store nothing are bounded by
// uploadAttempts; one that stores parts starts the count again.
func (t *HTTPTransfer) Publish(slot Slot, path, digest, content string) (int64, error) {
	state := &publication{etags: map[int]string{}}
	failures := 0
	for {
		started, before := time.Now(), state.progress()
		generation, sent, err := t.publish(slot, path, digest, content, state)
		if err == nil {
			return generation, nil
		}
		if state.progress() > before {
			failures = 0
		}
		failures++
		if failures >= uploadAttempts || !retryableUpload(err) {
			t.abandon(slot, digest, content, state)
			return 0, err
		}
		logger(t.Log).Warn("cache upload retry", "scope", slot.Scope, "use", slot.ID, "attempt", failures,
			"stored", state.stored, "parts_stored", len(state.etags), "sent_bytes", sent,
			"elapsed_ms", time.Since(started).Milliseconds(), "error", err.Error())
		time.Sleep(t.backoff() * time.Duration(failures))
	}
}

func (t *HTTPTransfer) publish(slot Slot, path, digest, content string, state *publication) (int64, int64, error) {
	ctx := context.Background()
	var sent int64
	if !state.stored {
		info, err := os.Stat(path)
		if err != nil {
			return 0, 0, err
		}
		if state.uploadID == "" {
			result, err := t.requestWith(ctx, slot, "upload", digest, content, map[string]any{"multipart": info.Size() >= t.multipartMin()})
			if err != nil {
				return 0, 0, err
			}
			if result.Generation > 0 {
				return result.Generation, 0, nil
			}
			if result.UploadID == "" {
				if sent, err = t.upload(result, path); err != nil {
					return 0, sent, err
				}
			}
			state.uploadID = result.UploadID
		}
		if state.uploadID != "" {
			if sent, err = t.uploadParts(slot, path, info.Size(), digest, content, state); err != nil {
				return 0, sent, err
			}
			if _, err = t.requestWith(ctx, slot, "complete", digest, content, map[string]any{"upload_id": state.uploadID, "parts": state.parts()}); err != nil {
				return 0, sent, err
			}
		}
		state.stored = true
	}
	result, err := t.request(ctx, slot, "publish", digest, content)
	if err == nil && result.Generation <= slot.BaseGeneration {
		return 0, sent, errors.New("invalid published generation")
	}
	return result.Generation, sent, err
}

// abandon discards the parts of a multipart upload this call gives up on. The
// server also aborts it once its links expire.
func (t *HTTPTransfer) abandon(slot Slot, digest, content string, state *publication) {
	if state.uploadID == "" || state.stored {
		return
	}
	_, _ = t.requestWith(context.Background(), slot, "abort", digest, content, map[string]any{"upload_id": state.uploadID})
}

func (p *publication) parts() []map[string]any {
	numbers := make([]int, 0, len(p.etags))
	for number := range p.etags {
		numbers = append(numbers, number)
	}
	sort.Ints(numbers)
	parts := make([]map[string]any, 0, len(numbers))
	for _, number := range numbers {
		parts = append(parts, map[string]any{"part_number": number, "etag": p.etags[number]})
	}
	return parts
}

// uploadParts sends the parts storage does not hold yet and returns how many
// bytes it sent. Each batch is hashed first: the server signs every part's
// Content-MD5 into its link, so storage refuses bytes other than the ones hashed.
func (t *HTTPTransfer) uploadParts(slot Slot, path string, size int64, digest, content string, state *publication) (int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()
	count := int((size + t.partSize() - 1) / t.partSize())
	var (
		sent atomic.Int64
		mu   sync.Mutex
	)
	for {
		var pending []int
		for number := 1; number <= count && len(pending) < partLinkBatch; number++ {
			if _, ok := state.etags[number]; !ok {
				pending = append(pending, number)
			}
		}
		if len(pending) == 0 {
			return sent.Load(), nil
		}
		sums := make(map[int]string, len(pending))
		err := t.eachPart(pending, func(number int) error {
			offset, length := t.partRange(number, size)
			sum, err := partMD5(file, offset, length)
			mu.Lock()
			sums[number] = sum
			mu.Unlock()
			return err
		})
		if err != nil {
			return sent.Load(), err
		}
		parts := make([]map[string]any, 0, len(pending))
		for _, number := range pending {
			parts = append(parts, map[string]any{"part_number": number, "content_md5": sums[number]})
		}
		result, err := t.requestWith(context.Background(), slot, "upload_parts", digest, content, map[string]any{"upload_id": state.uploadID, "parts": parts})
		if err != nil {
			return sent.Load(), err
		}
		links := make(map[int]string, len(result.Parts))
		for _, part := range result.Parts {
			links[part.PartNumber] = part.URL
		}
		for _, number := range pending {
			if links[number] == "" {
				return sent.Load(), errors.New("image upload is missing a part link")
			}
		}
		err = t.eachPart(pending, func(number int) error {
			offset, length := t.partRange(number, size)
			etag, n, err := t.uploadPart(file, offset, length, links[number], sums[number])
			sent.Add(n)
			if err == nil {
				mu.Lock()
				state.etags[number] = etag
				mu.Unlock()
			}
			return err
		})
		if err != nil {
			return sent.Load(), err
		}
	}
}

// eachPart runs do for every part, uploadParallelism at a time. Every part runs
// to its end, so one that fails does not cost the others; the error returned
// prefers one a retry cannot fix.
func (t *HTTPTransfer) eachPart(numbers []int, do func(int) error) error {
	var (
		mu        sync.Mutex
		failure   error
		workers   sync.WaitGroup
		semaphore = make(chan struct{}, t.parallelism())
	)
	for _, number := range numbers {
		semaphore <- struct{}{}
		workers.Go(func() {
			defer func() { <-semaphore }()
			err := do(number)
			mu.Lock()
			defer mu.Unlock()
			if err != nil && (failure == nil || (retryableUpload(failure) && !retryableUpload(err))) {
				failure = err
			}
		})
	}
	workers.Wait()
	return failure
}

func (t *HTTPTransfer) partRange(number int, size int64) (int64, int64) {
	offset := int64(number-1) * t.partSize()
	return offset, min(t.partSize(), size-offset)
}

func partMD5(file *os.File, offset, length int64) (string, error) {
	sum := md5.New()
	if _, err := io.Copy(sum, io.NewSectionReader(file, offset, length)); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(sum.Sum(nil)), nil
}

// uploadPart PUTs one part with the Content-MD5 its link was signed for, which
// storage verifies on receipt, and returns the part's ETag and how many bytes
// the request read.
func (t *HTTPTransfer) uploadPart(file *os.File, offset, length int64, url, sum string) (string, int64, error) {
	response, sent, err := t.put(url, io.NewSectionReader(file, offset, length), length, http.Header{"Content-Md5": {sum}})
	if err != nil {
		return "", sent, err
	}
	etag := response.Header.Get("ETag")
	if etag == "" {
		return "", sent, errors.New("image part upload returned no ETag")
	}
	return etag, sent, nil
}

// upload PUTs the whole archive and returns how many bytes the request read.
func (t *HTTPTransfer) upload(result transferResponse, path string) (int64, error) {
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()
	stat, err := file.Stat()
	if err != nil {
		return 0, err
	}
	header := http.Header{}
	if result.Checksum != "" {
		header.Set("x-amz-checksum-sha256", result.Checksum)
	}
	_, sent, err := t.put(result.UploadURL, file, stat.Size(), header)
	return sent, err
}

// put sends body to a presigned URL, abandoning the request once it sends
// nothing for the stall timeout, and returns the accepted response.
func (t *HTTPTransfer) put(url string, src io.Reader, length int64, header http.Header) (*http.Response, int64, error) {
	ctx, cancel := context.WithCancelCause(context.Background())
	defer cancel(nil)
	stall := t.stall()
	watchdog := time.AfterFunc(stall, func() { cancel(errUploadStalled) })
	defer watchdog.Stop()
	body := &progressReader{r: src, progress: func() { watchdog.Reset(stall) }}
	req, err := http.NewRequestWithContext(ctx, "PUT", url, body)
	if err != nil {
		return nil, 0, errors.New("invalid upload URL")
	}
	req.ContentLength = length
	for key, values := range header {
		req.Header[key] = values
	}
	response, err := t.objectClient().Do(req)
	if err != nil {
		if cause := context.Cause(ctx); errors.Is(cause, errUploadStalled) {
			return nil, body.n.Load(), cause
		}
		return nil, body.n.Load(), fmt.Errorf("image upload failed: %w", transferError(err))
	}
	defer response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return nil, body.n.Load(), remoteError("upload", response)
	}
	return response, body.n.Load(), nil
}

// retryableUpload reports a publication failure another attempt may not meet:
// a request that failed or stalled in transit, or a server error.
func retryableUpload(err error) bool {
	var remote *RemoteError
	if errors.As(err, &remote) {
		return remote.StatusCode >= 500 || remote.StatusCode == http.StatusTooManyRequests || remote.StatusCode == http.StatusRequestTimeout
	}
	return errors.Is(err, errTransport) || errors.Is(err, errUploadStalled) || errors.Is(err, context.DeadlineExceeded)
}

func (t *HTTPTransfer) partSize() int64 {
	if t.partBytes > 0 {
		return t.partBytes
	}
	return partBytes
}

func (t *HTTPTransfer) multipartMin() int64 {
	return 2 * t.partSize()
}

func (t *HTTPTransfer) parallelism() int {
	if t.uploadParallelism > 0 {
		return t.uploadParallelism
	}
	return uploadParallelism
}
