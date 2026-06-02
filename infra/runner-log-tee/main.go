// Command tuist-log-tee streams a runner job's stdout to the
// Tuist server's log ingest endpoint while the GitHub Actions runner
// is executing the job.
//
// It's wired into both runner images' dispatch-poll scripts as a pipe:
//
//	./run.sh --jitconfig <jit> ... 2>&1 | tuist-log-tee --url <logs_url> --token <log_token>
//
// Every line read from stdin is echoed straight back to stdout (so the
// VM/Pod's own log — poll.log on macOS, the container stream on Linux —
// still captures everything for debugging) and, in parallel, batched
// and POSTed to the ingest endpoint tagged with a monotonic line
// number and a read-time timestamp.
//
// Design constraints, in priority order:
//
//  1. Never block the build. The passthrough write happens first; if
//     the in-flight buffer is full (server slow/unreachable), lines are
//     dropped from shipping rather than stalling run.sh. A bounded
//     buffer caps memory.
//  2. Bounded teardown. On macOS the EXIT trap halts the VM the moment
//     this pipeline returns, so the closing flush must finish quickly —
//     every POST has a short timeout and a small retry budget.
//  3. Best-effort, not exactly-once. The server dedups on
//     (workflow_job_id, line_number), so retried batches are harmless;
//     dropped batches just leave gaps, which is acceptable for logs.
//
// Auth is the per-job `log_token` from dispatch, sent as a Bearer
// header. If either flag is empty the tee degrades to a plain
// stdin→stdout copy so a runner image paired with an older server (one
// that doesn't issue tokens) still works.
package main

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"sync/atomic"
	"syscall"
	"time"
)

type logLine struct {
	N   uint32 `json:"n"`
	TS  string `json:"ts"`
	Msg string `json:"message"`
}

type batch struct {
	Lines   []logLine `json:"lines"`
	Done    bool      `json:"done,omitempty"`
	Partial bool      `json:"partial,omitempty"`
}

type config struct {
	url          string
	token        string
	batchLines   int
	flushEvery   time.Duration
	httpTimeout  time.Duration
	maxRetries   int
	bufferLines  int
	bufferBytes  int
	maxLineBytes int
}

func main() {
	cfg := config{}
	flag.StringVar(&cfg.url, "url", "", "log ingest URL (required)")
	flag.StringVar(&cfg.token, "token", "", "per-job log token (required)")
	flag.IntVar(&cfg.batchLines, "batch-lines", 256, "flush after this many buffered lines")
	flag.DurationVar(&cfg.flushEvery, "flush-interval", 250*time.Millisecond, "flush at least this often")
	flag.DurationVar(&cfg.httpTimeout, "http-timeout", 5*time.Second, "per-request timeout")
	flag.IntVar(&cfg.maxRetries, "max-retries", 3, "POST attempts before dropping a batch")
	// Two ceilings on the in-flight queue. `buffer-lines` caps the
	// channel slot count (it's pre-allocated, so a giant value would
	// waste memory even when empty); `buffer-bytes` caps the actual
	// payload bytes. Whichever fills first triggers a drop, so a flood
	// of long lines and a flood of short ones both stay bounded.
	flag.IntVar(&cfg.bufferLines, "buffer-lines", 8192, "max in-flight lines before dropping")
	flag.IntVar(&cfg.bufferBytes, "buffer-bytes", 16<<20, "max in-flight payload bytes before dropping")
	// 64 KiB is comfortably above realistic log lines (verbose stack
	// traces, JSON object dumps) without giving a pathological line
	// room to dominate the byte budget.
	flag.IntVar(&cfg.maxLineBytes, "max-line-bytes", 64<<10, "longest line stored per message")
	flag.Parse()

	// Degrade to a plain passthrough when we have nothing to ship to —
	// keeps an image working against a server that predates log tokens.
	if cfg.url == "" || cfg.token == "" {
		_, _ = io.Copy(os.Stdout, os.Stdin)
		return
	}

	run(cfg, os.Stdin, os.Stdout)
}

func run(cfg config, in io.Reader, out io.Writer) {
	s := newTee(cfg)
	go s.loop()

	// SIGTERM/SIGINT (VM/Pod teardown) means the run was cut short —
	// finalize as partial. Normal completion is stdin EOF below.
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()

	reader := bufio.NewReaderSize(in, 64*1024)
	var n uint32

	for {
		select {
		case <-ctx.Done():
			s.finalize(true)
			return
		default:
		}

		line, hadLine, err := readBoundedLine(reader, cfg.maxLineBytes)
		if hadLine {
			fmt.Fprintln(out, line)
			n++
			s.enqueue(logLine{N: n, TS: nowTS(), Msg: line})
		}
		if err != nil {
			// EOF (run.sh exited) or a read error — the stream is over;
			// flush what's left and send the clean-close marker.
			s.finalize(false)
			return
		}
	}
}

// readBoundedLine reads from r up to the next newline, capping the
// returned line at maxBytes. Any bytes past the cap on the same line
// are discarded so a pathological producer (a single line containing
// the whole megabyte of JSON output a step decided to dump) can't grow
// the in-process buffer past maxBytes. Returns the trimmed line
// content (without trailing \r\n), whether a line was observed, and
// the terminating error (nil on a complete line, io.EOF if the stream
// ended on a partial last line).
func readBoundedLine(r *bufio.Reader, maxBytes int) (string, bool, error) {
	var b strings.Builder

	for {
		chunk, err := r.ReadSlice('\n')

		// Strip the trailing newline from the chunk before copying so
		// the builder only ever holds the line's content. ReadSlice
		// returns ErrBufferFull mid-line (no newline yet); in that case
		// `end == len(chunk)` and we keep going.
		end := len(chunk)
		if err == nil && end > 0 && chunk[end-1] == '\n' {
			end--
		}

		if end > 0 {
			remaining := maxBytes - b.Len()
			switch {
			case remaining <= 0:
				// already at the cap; discard
			case end > remaining:
				b.Write(chunk[:remaining])
			default:
				b.Write(chunk[:end])
			}
		}

		switch err {
		case nil:
			line := strings.TrimSuffix(b.String(), "\r")
			return line, true, nil
		case bufio.ErrBufferFull:
			// Underlying buffer ran out before a newline; keep reading
			// the remainder of this line so the next call starts at the
			// next one.
			continue
		default:
			line := strings.TrimSuffix(b.String(), "\r")
			return line, b.Len() > 0, err
		}
	}
}

type tee struct {
	cfg       config
	client    *http.Client
	in        chan logLine
	closed    chan struct{}
	bytesUsed atomic.Int64
}

// Rough per-line accounting overhead on top of the message payload
// (logLine struct + small map keys after JSON encoding). Tuning this
// up or down doesn't matter for correctness; it just shifts how many
// short lines fit under the byte cap.
const lineOverhead = 64

func newTee(cfg config) *tee {
	return &tee{
		cfg:    cfg,
		client: &http.Client{Timeout: cfg.httpTimeout},
		in:     make(chan logLine, cfg.bufferLines),
		closed: make(chan struct{}),
	}
}

// enqueue hands a line to the shipping loop without ever blocking the
// reader: if either the slot count or the byte budget is exhausted the
// line is dropped from shipping. It was already echoed to stdout, so
// the canonical log is intact.
func (s *tee) enqueue(l logLine) {
	cost := int64(len(l.Msg)) + lineOverhead

	for {
		used := s.bytesUsed.Load()
		if used+cost > int64(s.cfg.bufferBytes) {
			return
		}
		if s.bytesUsed.CompareAndSwap(used, used+cost) {
			break
		}
	}

	select {
	case s.in <- l:
	default:
		// Channel slot count saturated. Refund the byte reservation so
		// the budget reflects what's actually queued.
		s.bytesUsed.Add(-cost)
	}
}

func (s *tee) loop() {
	defer close(s.closed)

	buf := make([]logLine, 0, s.cfg.batchLines)
	ticker := time.NewTicker(s.cfg.flushEvery)
	defer ticker.Stop()

	flush := func() {
		if len(buf) == 0 {
			return
		}
		s.post(batch{Lines: buf})
		buf = buf[:0]
	}

	for {
		select {
		case l, ok := <-s.in:
			if !ok {
				flush()
				return
			}
			s.bytesUsed.Add(-(int64(len(l.Msg)) + lineOverhead))
			buf = append(buf, l)
			if len(buf) >= s.cfg.batchLines {
				flush()
			}
		case <-ticker.C:
			flush()
		}
	}
}

// finalize is called once, from the reader goroutine, after the last
// enqueue — so closing the channel can't race a send. It drains the
// shipping loop, then sends the closing marker the server uses to set
// the job's final log_state + line count.
func (s *tee) finalize(partial bool) {
	close(s.in)
	<-s.closed
	// Send an explicit empty list rather than relying on the struct's
	// zero value. A nil `[]logLine` serialises to `"lines": null`,
	// which the server's payload validator rejects as a 400; an
	// initialised empty slice serialises to `"lines": []`.
	s.post(batch{Lines: []logLine{}, Done: true, Partial: partial})
}

func (s *tee) post(b batch) {
	body, err := json.Marshal(b)
	if err != nil {
		return
	}

	for attempt := 0; attempt < s.cfg.maxRetries; attempt++ {
		if attempt > 0 {
			time.Sleep(backoff(attempt))
		}
		if s.postOnce(body) {
			return
		}
	}
}

func (s *tee) postOnce(body []byte) bool {
	req, err := http.NewRequest(http.MethodPost, s.cfg.url, bytes.NewReader(body))
	if err != nil {
		return false
	}
	req.Header.Set("Authorization", "Bearer "+s.cfg.token)
	req.Header.Set("Content-Type", "application/json")

	resp, err := s.client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)

	// 5xx is worth a retry; 2xx is success and 4xx won't fix itself
	// (bad/expired token, malformed body) so don't burn the budget.
	return resp.StatusCode < 500
}

func backoff(attempt int) time.Duration {
	return time.Duration(1<<uint(attempt-1)) * 200 * time.Millisecond
}

func nowTS() string {
	return time.Now().UTC().Format("2006-01-02T15:04:05.000000Z")
}
