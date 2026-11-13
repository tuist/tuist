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
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return redact(err)
	}
	resp, err := client.Do(req)
	if err != nil {
		return redact(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("object storage answered %d", resp.StatusCode)
	}
	if resp.ContentLength >= 0 && resp.ContentLength != size {
		return fmt.Errorf("archive is %d bytes, expected %d", resp.ContentLength, size)
	}
	hasher := sha256.New()
	counted := &countingReader{r: io.TeeReader(io.LimitReader(resp.Body, size+1), hasher)}
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
