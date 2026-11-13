package archive

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"hash"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

const (
	putAttempts = 3
	maxPartSize = 512 << 20
)

// putRetryBackoff is a variable so tests do not wait it out.
var putRetryBackoff = 2 * time.Second

// ErrTooLarge means the archive outgrew the parts the server presigned.
var ErrTooLarge = errors.New("archive is larger than the presigned parts")

// Part is one uploaded part of a multipart upload, as the server completes
// it.
type Part struct {
	PartNumber int    `json:"part_number"`
	ETag       string `json:"etag"`
}

// Uploader is an io.Writer that cuts what it is given into parts of
// partSize and PUTs each one to the next presigned part URL. One part
// uploads while the next fills, so at most two parts are held in memory.
type Uploader struct {
	ctx      context.Context
	client   *http.Client
	urls     []string
	partSize int

	cur   []byte
	free  chan []byte
	queue chan pendingPart
	done  chan struct{}
	// failed closes when a part fails, so the writer stops reading disks.
	failed chan struct{}
	parts  []Part
	err    error
	sent   int
	hash   hash.Hash
	bytes  int64
	closed bool
}

type pendingPart struct {
	number int
	data   []byte
}

func NewUploader(ctx context.Context, client *http.Client, urls []string, partSize int64) (*Uploader, error) {
	if partSize <= 0 || partSize > maxPartSize {
		return nil, fmt.Errorf("part size %d", partSize)
	}
	if len(urls) == 0 {
		return nil, errors.New("no part URLs")
	}
	u := &Uploader{
		ctx: ctx, client: client, urls: urls, partSize: int(partSize),
		free: make(chan []byte, 2), queue: make(chan pendingPart, 1), done: make(chan struct{}), failed: make(chan struct{}),
		hash: sha256.New(),
	}
	u.free <- make([]byte, 0, partSize)
	u.free <- make([]byte, 0, partSize)
	go u.run()
	return u, nil
}

func (u *Uploader) run() {
	defer close(u.done)
	for part := range u.queue {
		if u.err == nil {
			etag, err := put(u.ctx, u.client, u.urls[part.number-1], part.data, part.number)
			if err != nil {
				u.err = err
				close(u.failed)
			} else {
				u.parts = append(u.parts, Part{PartNumber: part.number, ETag: etag})
			}
		}
		u.free <- part.data[:0]
	}
}

func (u *Uploader) Write(p []byte) (int, error) {
	written := 0
	for len(p) > 0 {
		if u.cur == nil {
			select {
			case buf := <-u.free:
				u.cur = buf
			case <-u.failed:
				return written, u.err
			case <-u.ctx.Done():
				return written, u.ctx.Err()
			}
		}
		n := min(len(p), u.partSize-len(u.cur))
		u.cur = append(u.cur, p[:n]...)
		u.hash.Write(p[:n])
		u.bytes += int64(n)
		p = p[n:]
		written += n
		if len(u.cur) == u.partSize {
			if err := u.send(); err != nil {
				return written, err
			}
		}
	}
	return written, nil
}

func (u *Uploader) send() error {
	if u.sent == len(u.urls) {
		return ErrTooLarge
	}
	u.sent++
	select {
	case u.queue <- pendingPart{number: u.sent, data: u.cur}:
		u.cur = nil
		return nil
	case <-u.failed:
		return u.err
	case <-u.ctx.Done():
		return u.ctx.Err()
	}
}

// Close uploads the last part and waits for every upload to finish.
func (u *Uploader) Close() error {
	if u.closed {
		return u.err
	}
	u.closed = true
	var err error
	if len(u.cur) > 0 {
		err = u.send()
	}
	close(u.queue)
	<-u.done
	if u.err != nil {
		return u.err
	}
	return err
}

func (u *Uploader) Parts() []Part { return u.parts }
func (u *Uploader) Bytes() int64  { return u.bytes }
func (u *Uploader) SHA256() string {
	return hex.EncodeToString(u.hash.Sum(nil))
}

func put(ctx context.Context, client *http.Client, target string, data []byte, number int) (string, error) {
	var last error
	for attempt := 1; attempt <= putAttempts; attempt++ {
		if attempt > 1 {
			select {
			case <-time.After(time.Duration(attempt-1) * putRetryBackoff):
			case <-ctx.Done():
				return "", ctx.Err()
			}
		}
		req, err := http.NewRequestWithContext(ctx, http.MethodPut, target, bytes.NewReader(data))
		if err != nil {
			return "", fmt.Errorf("part %d: %w", number, redact(err))
		}
		req.ContentLength = int64(len(data))
		resp, err := client.Do(req)
		if err != nil {
			last = fmt.Errorf("part %d: %w", number, redact(err))
			continue
		}
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 64<<10))
		resp.Body.Close()
		etag := resp.Header.Get("ETag")
		switch {
		case resp.StatusCode == http.StatusOK && etag != "":
			return etag, nil
		case resp.StatusCode == http.StatusOK:
			return "", fmt.Errorf("part %d: no ETag in the answer", number)
		case resp.StatusCode >= 500 || resp.StatusCode == http.StatusTooManyRequests:
			last = fmt.Errorf("part %d: object storage answered %d", number, resp.StatusCode)
		default:
			return "", fmt.Errorf("part %d: object storage answered %d", number, resp.StatusCode)
		}
	}
	return "", last
}

// Download GETs the archive and hands its body to consume, then checks that
// the object had exactly the expected size and SHA-256. consume may have
// written the content out by then; the caller discards it on error.
func Download(ctx context.Context, client *http.Client, target string, size int64, sum string, consume func(io.Reader) error) error {
	return DownloadRange(ctx, client, target, 0, size, sum, consume)
}

// DownloadRange is Download of the size bytes from offset on, such as the
// disk stream of an archive that holds a memory image ahead of it.
//
// A range longer than one segment is fetched as downloadStreams ranged GETs
// at a time and handed to consume in order, so a restore is not held to one
// connection's throughput while the hash and the extraction still read one
// sequential stream. A segment that fails is fetched again on its own.
func DownloadRange(ctx context.Context, client *http.Client, target string, offset, size int64, sum string, consume func(io.Reader) error) error {
	var body io.Reader
	if size > downloadSegment {
		segmented := newSegmentedBody(ctx, client, target, offset, size)
		defer segmented.close()
		body = segmented
	} else {
		resp, err := get(ctx, client, target, offset, size, offset > 0)
		if err != nil {
			return err
		}
		defer resp.Body.Close()
		body = resp.Body
	}
	hasher := sha256.New()
	counted := &countingReader{r: io.TeeReader(io.LimitReader(body, size+1), hasher)}
	if err := consume(counted); err != nil {
		return redact(err)
	}
	if _, err := io.Copy(io.Discard, counted); err != nil {
		return redact(err)
	}
	if counted.n != size {
		return fmt.Errorf("archive is %d bytes, expected %d", counted.n, size)
	}
	if got := hex.EncodeToString(hasher.Sum(nil)); !strings.EqualFold(got, sum) {
		return fmt.Errorf("archive checksum %s does not match %s", got, sum)
	}
	return nil
}

// Segmented downloads hold at most downloadStreams segments in memory: the
// ones in flight and the ones waiting for consume.
var (
	downloadSegment int64 = 8 << 20
	downloadStreams       = 8
	// getRetryBackoff is a variable so tests do not wait it out.
	getRetryBackoff = time.Second
)

const segmentAttempts = 3

// get GETs size bytes from offset, with a Range header when ranged, and
// checks the status and the announced length.
func get(ctx context.Context, client *http.Client, target string, offset, size int64, ranged bool) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, redact(err)
	}
	status := http.StatusOK
	if ranged {
		req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", offset, offset+size-1))
		status = http.StatusPartialContent
	}
	resp, err := client.Do(req)
	if err != nil {
		return nil, redact(err)
	}
	if resp.StatusCode != status {
		resp.Body.Close()
		return nil, &statusError{code: resp.StatusCode}
	}
	if resp.ContentLength >= 0 && resp.ContentLength != size {
		resp.Body.Close()
		return nil, fmt.Errorf("archive is %d bytes, expected %d", resp.ContentLength, size)
	}
	return resp, nil
}

type statusError struct{ code int }

func (e *statusError) Error() string { return fmt.Sprintf("object storage answered %d", e.code) }

// segmentedBody reads a range as consecutive segments that downloadStreams
// workers fetch ahead of the reader. A worker takes a buffer from free, and
// the reader returns it once it has read past that segment, so the buffers
// bound both the requests in flight and the memory held.
type segmentedBody struct {
	ctx     context.Context
	cancel  context.CancelFunc
	results []chan segment
	free    chan []byte
	next    int
	cur     []byte
	buf     []byte
}

type segment struct {
	data []byte
	err  error
}

func newSegmentedBody(ctx context.Context, client *http.Client, target string, offset, size int64) *segmentedBody {
	ctx, cancel := context.WithCancel(ctx)
	count := int((size + downloadSegment - 1) / downloadSegment)
	b := &segmentedBody{ctx: ctx, cancel: cancel, results: make([]chan segment, count), free: make(chan []byte, downloadStreams)}
	for i := range b.results {
		b.results[i] = make(chan segment, 1)
	}
	for range downloadStreams {
		b.free <- nil
	}
	go func() {
		for i := range count {
			var buf []byte
			select {
			case buf = <-b.free:
			case <-ctx.Done():
				return
			}
			start := int64(i) * downloadSegment
			length := min(downloadSegment, size-start)
			if buf == nil {
				buf = make([]byte, downloadSegment)
			}
			go func() {
				data, err := fetchSegment(ctx, client, target, offset+start, buf[:length])
				b.results[i] <- segment{data: data, err: err}
			}()
		}
	}()
	return b
}

func (b *segmentedBody) Read(p []byte) (int, error) {
	for len(b.cur) == 0 {
		if b.buf != nil {
			b.free <- b.buf
			b.buf = nil
		}
		if b.next == len(b.results) {
			return 0, io.EOF
		}
		select {
		case s := <-b.results[b.next]:
			if s.err != nil {
				return 0, s.err
			}
			b.buf, b.cur = s.data[:cap(s.data)], s.data
			b.next++
		case <-b.ctx.Done():
			return 0, b.ctx.Err()
		}
	}
	n := copy(p, b.cur)
	b.cur = b.cur[n:]
	return n, nil
}

// close stops the workers; requests in flight end with the context.
func (b *segmentedBody) close() { b.cancel() }

// fetchSegment fills buf from offset, trying segmentAttempts times when the
// transfer fails or storage answers 5xx or 429.
func fetchSegment(ctx context.Context, client *http.Client, target string, offset int64, buf []byte) ([]byte, error) {
	var last error
	for attempt := 1; attempt <= segmentAttempts; attempt++ {
		if attempt > 1 {
			select {
			case <-time.After(time.Duration(attempt-1) * getRetryBackoff):
			case <-ctx.Done():
				return nil, ctx.Err()
			}
		}
		resp, err := get(ctx, client, target, offset, int64(len(buf)), true)
		if err != nil {
			var status *statusError
			if errors.As(err, &status) && status.code < 500 && status.code != http.StatusTooManyRequests {
				return nil, err
			}
			last = err
			continue
		}
		_, err = io.ReadFull(resp.Body, buf)
		resp.Body.Close()
		if err == nil {
			return buf, nil
		}
		last = redact(err)
	}
	return nil, fmt.Errorf("archive bytes %d-%d: %w", offset, offset+int64(len(buf))-1, last)
}

type countingReader struct {
	r io.Reader
	n int64
}

func (c *countingReader) Read(p []byte) (int, error) {
	n, err := c.r.Read(p)
	c.n += int64(n)
	return n, err
}

// redact drops the URL from transport errors: presigned URLs carry their
// signature, and errors travel to the server and its logs.
func redact(err error) error {
	var urlErr *url.Error
	if errors.As(err, &urlErr) {
		return fmt.Errorf("%s: %w", urlErr.Op, urlErr.Err)
	}
	return err
}
