// Command tuist-log-shipper streams a runner job's stdout to the
// Tuist server's log ingest endpoint while the GitHub Actions runner
// is executing the job.
//
// It's wired into both runner images' dispatch-poll scripts as a pipe:
//
//	./run.sh --jitconfig <jit> ... 2>&1 | tuist-log-shipper --url <logs_url> --token <log_token>
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
// header. If either flag is empty the shipper degrades to a plain
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
	flag.IntVar(&cfg.bufferLines, "buffer-lines", 100_000, "max lines buffered for shipping before dropping")
	flag.IntVar(&cfg.maxLineBytes, "max-line-bytes", 1<<20, "longest line stored per message")
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
	s := newShipper(cfg)
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

		raw, err := reader.ReadString('\n')
		if line, ok := trimLine(raw); ok || err == nil {
			fmt.Fprintln(out, line)
			n++
			s.enqueue(logLine{N: n, TS: nowTS(), Msg: truncate(line, cfg.maxLineBytes)})
		}
		if err != nil {
			// EOF (run.sh exited) or a read error — the stream is over;
			// flush what's left and send the clean-close marker.
			s.finalize(false)
			return
		}
	}
}

// trimLine strips the trailing line ending (CRLF or LF). The bool
// reports whether there was any content — a bare "\n" yields ("", true)
// so blank lines are preserved, while the empty tail after EOF with a
// trailing newline yields ("", false) and is skipped.
func trimLine(raw string) (string, bool) {
	if raw == "" {
		return "", false
	}
	had := strings.HasSuffix(raw, "\n")
	line := strings.TrimSuffix(raw, "\n")
	line = strings.TrimSuffix(line, "\r")
	return line, had || line != ""
}

func truncate(s string, max int) string {
	if len(s) > max {
		return s[:max]
	}
	return s
}

type shipper struct {
	cfg    config
	client *http.Client
	in     chan logLine
	closed chan struct{}
}

func newShipper(cfg config) *shipper {
	return &shipper{
		cfg:    cfg,
		client: &http.Client{Timeout: cfg.httpTimeout},
		in:     make(chan logLine, cfg.bufferLines),
		closed: make(chan struct{}),
	}
}

// enqueue hands a line to the shipping loop without ever blocking the
// reader: if the buffer is full the line is dropped from shipping (it
// was already echoed to stdout).
func (s *shipper) enqueue(l logLine) {
	select {
	case s.in <- l:
	default:
	}
}

func (s *shipper) loop() {
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
func (s *shipper) finalize(partial bool) {
	close(s.in)
	<-s.closed
	s.post(batch{Done: true, Partial: partial})
}

func (s *shipper) post(b batch) {
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

func (s *shipper) postOnce(body []byte) bool {
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
