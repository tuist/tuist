package executiongateway

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"sync"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

// Log copies: a record keeps the start of each output stream. When a stream
// is longer, the server answers the record with a presigned upload for the
// whole stream, or its end when it is very long, and the gateway copies those
// bytes from the cache to the server's object storage, so the dashboard can
// show the whole log.
//
// Copies must never slow remote execution down, so they share nothing with
// the client's path: they start only after the client has its result and the
// record was sent, read the cache over their own connections, upload with
// their own HTTP client, run two at a time through a bounded queue that drops
// rather than waits, and stream at most logCopyRate bytes per second through
// a pipe, holding one chunk at a time. A dropped or failed copy leaves the
// record's preview, which only the metrics count.

const (
	// The worker fails an action whose log passes 64 MiB, so this lets the
	// server ask for any whole stream; it asks for at most 16 MiB today.
	maxLogCopy          = 64 << 20
	maxLogUploadsAnswer = 1 << 20
	logCopyQueue        = 256
	logCopiers          = 2
	logCopyRate         = 8 << 20
	logCopyTimeout      = 2 * time.Minute
)

var sha256Hex = regexp.MustCompile(`^[0-9a-f]{64}$`)

// logUpload is the server's request for bytes [offset, offset+length) of the
// blob hash, whose size is size.
type logUpload struct {
	Hash   string `json:"hash"`
	Size   int64  `json:"size"`
	Offset int64  `json:"offset"`
	Length int64  `json:"length"`
	URL    string `json:"url"`
}

type logCopy struct {
	recordScope
	logUpload
}

type logCopier struct {
	queue chan logCopy
	start sync.Once
	mu    sync.Mutex
	conns map[string]*grpc.ClientConn
	rate  byteRate
}

func newLogCopier() *logCopier {
	return &logCopier{queue: make(chan logCopy, logCopyQueue), conns: map[string]*grpc.ClientConn{}, rate: byteRate{perSecond: logCopyRate}}
}

// longLog returns the hash of a stream the record cannot keep whole.
func longLog(d *re.Digest) string {
	if worker.ValidDigest(d) && d.SizeBytes > maxRecordLog {
		return d.Hash
	}
	return ""
}

// copyLog queues a copy, never blocking the record sender.
func (g *Gateway) copyLog(scope recordScope, u logUpload) {
	target, err := url.Parse(u.URL)
	if !sha256Hex.MatchString(u.Hash) || u.Offset < 0 || u.Length <= 0 || u.Length > maxLogCopy || u.Offset+u.Length > u.Size || err != nil || target.Scheme != "https" {
		g.metrics.logCopies.WithLabelValues("refused").Inc()
		return
	}
	c := g.logs
	c.start.Do(func() {
		for range logCopiers {
			go func() {
				for job := range c.queue {
					result := "copied"
					if err := g.uploadLog(job); err != nil {
						result = "failed"
					}
					g.metrics.logCopies.WithLabelValues(result).Inc()
				}
			}()
		}
	})
	select {
	case c.queue <- logCopy{scope, u}:
	default:
		g.metrics.logCopies.WithLabelValues("dropped").Inc()
	}
}

// uploadLog streams the requested bytes from the cache into the upload. The
// pipe holds no buffer: each chunk waits for its rate and for the upload to
// take it before the next is read. A short read fails the upload instead of
// storing part of the range.
func (g *Gateway) uploadLog(job logCopy) error {
	endpoint := g.endpoint(job.account, job.project)
	if endpoint == "" {
		return fmt.Errorf("no cache endpoint")
	}
	conn, err := g.logConn(endpoint)
	if err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), logCopyTimeout)
	defer cancel()
	readCtx := metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", job.auth, "x-tuist-account-handle", job.account))
	reader, err := bs.NewByteStreamClient(conn).Read(readCtx, &bs.ReadRequest{
		ResourceName: fmt.Sprintf("%s/blobs/%s/%d", job.project, job.Hash, job.Size),
		ReadOffset:   job.Offset,
		ReadLimit:    job.Length,
	})
	if err != nil {
		return err
	}
	body, pipe := io.Pipe()
	defer body.Close()
	go func() {
		var sent int64
		for sent < job.Length {
			chunk, err := reader.Recv()
			if err == io.EOF {
				break
			}
			if err != nil {
				pipe.CloseWithError(err)
				return
			}
			data := chunk.Data[:min(int64(len(chunk.Data)), job.Length-sent)]
			if err := g.logs.rate.wait(ctx, len(data)); err != nil {
				pipe.CloseWithError(err)
				return
			}
			if _, err := pipe.Write(data); err != nil {
				return
			}
			sent += int64(len(data))
			g.metrics.logBytes.Add(float64(len(data)))
		}
		if sent < job.Length {
			pipe.CloseWithError(io.ErrUnexpectedEOF)
			return
		}
		pipe.Close()
	}()
	request, err := http.NewRequestWithContext(ctx, http.MethodPut, job.URL, body)
	if err != nil {
		return err
	}
	request.ContentLength = job.Length
	request.Header.Set("Content-Type", "text/plain; charset=utf-8")
	response, err := g.LogUploads.Do(request)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(response.Body, 4096))
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return fmt.Errorf("upload answered %d", response.StatusCode)
	}
	return nil
}

// logConn is a cache connection for copies only, so their large reads never
// share flow control with the prefetches on the client's path.
func (g *Gateway) logConn(endpoint string) (*grpc.ClientConn, error) {
	c := g.logs
	c.mu.Lock()
	defer c.mu.Unlock()
	if conn, ok := c.conns[endpoint]; ok {
		return conn, nil
	}
	if len(c.conns) >= 64 {
		return nil, fmt.Errorf("too many cache endpoints")
	}
	conn, err := g.Dial(endpoint)
	if err != nil {
		return nil, err
	}
	c.conns[endpoint] = conn
	return conn, nil
}

// byteRate spaces writes so all copies together send at most perSecond bytes
// a second, without bursts after idle time.
type byteRate struct {
	mu        sync.Mutex
	next      time.Time
	perSecond int64
}

func (r *byteRate) wait(ctx context.Context, n int) error {
	r.mu.Lock()
	now := time.Now()
	start := r.next
	if start.Before(now) {
		start = now
	}
	r.next = start.Add(time.Duration(int64(n) * int64(time.Second) / r.perSecond))
	r.mu.Unlock()
	if delay := start.Sub(now); delay > 0 {
		timer := time.NewTimer(delay)
		defer timer.Stop()
		select {
		case <-timer.C:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return nil
}
