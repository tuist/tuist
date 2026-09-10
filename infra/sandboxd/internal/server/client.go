// Package server is the node's WebSocket client to the Tuist server: one
// long-lived connection carrying commands in and results, streams, events
// and reports out. See infra/sandboxd/AGENTS.md "Node to server".
package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/coder/websocket"

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
)

const (
	ConnectPath           = "/api/internal/sandboxes/nodes/connect"
	DefaultReportInterval = 30 * time.Second
	DefaultMinBackoff     = time.Second
	DefaultMaxBackoff     = 30 * time.Second
	writeTimeout          = 15 * time.Second
	readLimit             = 8 << 20
	eventQueueSize        = 1024
)

// Handler runs one command and returns its result; stream carries exec
// output frames.
type Handler func(ctx context.Context, cmd protocol.Command, stream func(protocol.Stream)) protocol.Result

type Config struct {
	URL       string
	NodeName  string
	TokenPath string
	Hello     func() protocol.Hello
	Report    func() protocol.Report
	Handler   Handler
	Log       *slog.Logger

	ReportInterval time.Duration
	MinBackoff     time.Duration
	MaxBackoff     time.Duration
	// HTTPClient overrides the dialer's client (tests).
	HTTPClient *http.Client
}

type Client struct {
	cfg    Config
	events chan protocol.Event

	mu        sync.Mutex
	conn      *websocket.Conn
	connected bool
}

func New(cfg Config) *Client {
	if cfg.ReportInterval == 0 {
		cfg.ReportInterval = DefaultReportInterval
	}
	if cfg.MinBackoff == 0 {
		cfg.MinBackoff = DefaultMinBackoff
	}
	if cfg.MaxBackoff == 0 {
		cfg.MaxBackoff = DefaultMaxBackoff
	}
	if cfg.Log == nil {
		cfg.Log = slog.Default()
	}
	return &Client{cfg: cfg, events: make(chan protocol.Event, eventQueueSize)}
}

// Emit queues an event for the server. Events survive a reconnect; when
// the queue is full the oldest is dropped.
func (c *Client) Emit(event protocol.Event) {
	if event.Type == "" {
		event.Type = protocol.FrameEvent
	}
	for {
		select {
		case c.events <- event:
			return
		default:
		}
		select {
		case dropped := <-c.events:
			c.cfg.Log.Warn("event queue full, dropping oldest", "event", dropped.Event, "sandbox", dropped.SandboxID)
		default:
		}
	}
}

func (c *Client) Connected() bool {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.connected
}

// Run keeps a session open until ctx ends, reconnecting with exponential
// backoff.
func (c *Client) Run(ctx context.Context) {
	backoff := c.cfg.MinBackoff
	for ctx.Err() == nil {
		started := time.Now()
		err := c.session(ctx)
		if ctx.Err() != nil {
			return
		}
		if time.Since(started) > time.Minute {
			backoff = c.cfg.MinBackoff
		}
		c.cfg.Log.Warn("server connection ended", "error", err, "retry_in", backoff)
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		backoff *= 2
		if backoff > c.cfg.MaxBackoff {
			backoff = c.cfg.MaxBackoff
		}
	}
}

func (c *Client) url() string {
	base := strings.TrimRight(c.cfg.URL, "/")
	if strings.HasSuffix(base, ConnectPath) {
		return base
	}
	return base + ConnectPath
}

func (c *Client) token() (string, error) {
	data, err := os.ReadFile(c.cfg.TokenPath)
	if err != nil {
		return "", fmt.Errorf("reading token: %w", err)
	}
	return strings.TrimSpace(string(data)), nil
}

func (c *Client) session(parent context.Context) error {
	ctx, cancel := context.WithCancel(parent)
	defer cancel()

	token, err := c.token()
	if err != nil {
		return err
	}
	headers := http.Header{}
	headers.Set("Authorization", "Bearer "+token)
	headers.Set("X-Tuist-Node-Name", c.cfg.NodeName)
	dialCtx, dialCancel := context.WithTimeout(ctx, 30*time.Second)
	conn, resp, err := websocket.Dial(dialCtx, c.url(), &websocket.DialOptions{HTTPHeader: headers, HTTPClient: c.cfg.HTTPClient})
	dialCancel()
	if err != nil {
		if resp != nil {
			return fmt.Errorf("dial %s: %w (status %d)", c.url(), err, resp.StatusCode)
		}
		return fmt.Errorf("dial %s: %w", c.url(), err)
	}
	conn.SetReadLimit(readLimit)
	defer conn.CloseNow()

	c.mu.Lock()
	c.conn = conn
	c.connected = true
	c.mu.Unlock()
	defer func() {
		c.mu.Lock()
		c.conn = nil
		c.connected = false
		c.mu.Unlock()
	}()

	hello := c.cfg.Hello()
	hello.Type = protocol.FrameHello
	hello.Node = c.cfg.NodeName
	if err := c.send(ctx, hello); err != nil {
		return fmt.Errorf("sending hello: %w", err)
	}
	c.cfg.Log.Info("connected to server", "url", c.url(), "sandboxes", len(hello.Sandboxes), "templates", len(hello.Templates))

	errCh := make(chan error, 3)
	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		errCh <- c.readLoop(ctx, conn)
	}()
	go func() {
		defer wg.Done()
		errCh <- c.pushLoop(ctx)
	}()
	err = <-errCh
	cancel()
	conn.CloseNow()
	wg.Wait()
	return err
}

// send serializes writes across the command goroutines.
func (c *Client) send(ctx context.Context, frame any) error {
	data, err := json.Marshal(frame)
	if err != nil {
		return err
	}
	c.mu.Lock()
	conn := c.conn
	c.mu.Unlock()
	if conn == nil {
		return errors.New("not connected")
	}
	writeCtx, cancel := context.WithTimeout(ctx, writeTimeout)
	defer cancel()
	return conn.Write(writeCtx, websocket.MessageText, data)
}

func (c *Client) readLoop(ctx context.Context, conn *websocket.Conn) error {
	var handlers sync.WaitGroup
	defer handlers.Wait()
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return fmt.Errorf("read: %w", err)
		}
		frame, err := protocol.Decode(data)
		if err != nil {
			c.cfg.Log.Warn("ignoring undecodable frame", "error", err)
			continue
		}
		cmd, ok := frame.(*protocol.Command)
		if !ok {
			c.cfg.Log.Warn("ignoring unexpected frame from server", "type", fmt.Sprintf("%T", frame))
			continue
		}
		handlers.Add(1)
		go func(cmd protocol.Command) {
			defer handlers.Done()
			c.handle(ctx, cmd)
		}(*cmd)
	}
}

func (c *Client) handle(ctx context.Context, cmd protocol.Command) {
	started := time.Now()
	stream := func(s protocol.Stream) {
		s.Type = protocol.FrameStream
		s.ID = cmd.ID
		if err := c.send(ctx, s); err != nil {
			c.cfg.Log.Debug("stream frame not delivered", "command", cmd.ID, "error", err)
		}
	}
	result := c.cfg.Handler(ctx, cmd, stream)
	result.Type = protocol.FrameResult
	result.ID = cmd.ID
	log := c.cfg.Log.With("command", cmd.ID, "op", cmd.Op, "elapsed", time.Since(started))
	if !result.OK {
		log.Warn("command failed", "error", result.Error)
	} else {
		log.Info("command done")
	}
	if err := c.send(ctx, result); err != nil {
		log.Warn("result not delivered", "error", err)
	}
}

// pushLoop sends queued events and periodic reports.
func (c *Client) pushLoop(ctx context.Context) error {
	ticker := time.NewTicker(c.cfg.ReportInterval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		case event := <-c.events:
			if err := c.send(ctx, event); err != nil {
				// Put it back so the next session delivers it.
				c.Emit(event)
				return fmt.Errorf("sending event: %w", err)
			}
		case <-ticker.C:
			if c.cfg.Report == nil {
				continue
			}
			report := c.cfg.Report()
			report.Type = protocol.FrameReport
			if err := c.send(ctx, report); err != nil {
				return fmt.Errorf("sending report: %w", err)
			}
		}
	}
}
