// Package checkout serves a worker's guest the node's master of its
// repository's checkout volume and takes the guest's export back, both
// through the node's runner-cache agent. The grant comes from the server's
// start_worker; nothing the guest sends decides what it is served or where its
// export goes.
package checkout

import (
	"archive/tar"
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net"
	"sync"
	"sync/atomic"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// GuestPort is the vsock port a guest connects to on the host (CID 2).
// Firecracker forwards it to the Unix socket "<vsock uds>_<port>".
const GuestPort = protocol.CheckoutVsockPort

// Agent is the node's runner-cache agent.
type Agent interface {
	// Seed returns a tar stream of the master's repository directory, or
	// ErrCold when the node holds no master of it.
	Seed(ctx context.Context, grant protocol.CheckoutGrant) (io.ReadCloser, error)
	// Export hands the agent an export in the CI format and returns once the
	// agent accepted it.
	Export(ctx context.Context, grant protocol.CheckoutGrant, export io.Reader) error
}

// ErrCold is the agent's answer that the node holds no master of the repository.
var ErrCold = errors.New("cold")

// Limits bound one arming's transfers. Zero fields take the defaults.
type Limits struct {
	// SeedTimeout and ExportTimeout bound a whole request, the agent's part
	// included.
	SeedTimeout, ExportTimeout time.Duration
	// SeedBytes bounds the tree relayed to the guest, ExportBytes the export
	// taken from it.
	SeedBytes, ExportBytes int64
}

const (
	// A checkout image holds at most 60 GB, and an export at most half of it
	// plus the archive's framing; the agent refuses anything larger too.
	defaultSeedBytes     = 60_000_000_000
	defaultExportBytes   = 30_000_000_000 + 64<<20
	defaultSeedTimeout   = 10 * time.Minute
	defaultExportTimeout = 6 * time.Minute
	requestTimeout       = 10 * time.Second
	maxRequestLine       = 1 << 10
	// A seed and an export may overlap; anything beyond is closed unanswered.
	maxConnections = 4
)

func (l Limits) withDefaults() Limits {
	if l.SeedTimeout <= 0 {
		l.SeedTimeout = defaultSeedTimeout
	}
	if l.ExportTimeout <= 0 {
		l.ExportTimeout = defaultExportTimeout
	}
	if l.SeedBytes <= 0 {
		l.SeedBytes = defaultSeedBytes
	}
	if l.ExportBytes <= 0 {
		l.ExportBytes = defaultExportBytes
	}
	return l
}

// Request is one guest request, a JSON line. One request per connection.
//
//	{"op":"seed"}
//	{"op":"export"}  followed by the export's tar stream
type Request struct {
	Op string `json:"op"`
}

type Response struct {
	OK    bool   `json:"ok,omitempty"`
	Error string `json:"error,omitempty"`
}

// Recorder starts keeping a copy of the tree a seed relays (see
// Workspaces.Recorder). It returns nil to keep none.
type Recorder func() Recording

type server struct {
	agent    Agent
	grant    protocol.CheckoutGrant
	limits   Limits
	log      *slog.Logger
	record   Recorder
	seeded   atomic.Bool
	exported atomic.Bool
}

// Serve answers one worker's guest for grant until ctx ends, then closes l and
// waits for the requests it accepted, which ctx ends too. An arming serves at
// most one seed and one export. A non-nil record keeps a copy of the seed's
// tree for the node's prepared workspaces.
func Serve(ctx context.Context, l net.Listener, agent Agent, grant protocol.CheckoutGrant, limits Limits, log *slog.Logger, record Recorder) {
	if log == nil {
		log = slog.Default()
	}
	s := &server{agent: agent, grant: grant, limits: limits.withDefaults(), log: log, record: record}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	go func() {
		<-ctx.Done()
		l.Close()
	}()
	slots := make(chan struct{}, maxConnections)
	var wg sync.WaitGroup
	defer wg.Wait()
	for {
		conn, err := l.Accept()
		if err != nil {
			return
		}
		select {
		case slots <- struct{}{}:
		default:
			conn.Close()
			continue
		}
		wg.Go(func() {
			defer func() { <-slots }()
			defer conn.Close()
			stop := context.AfterFunc(ctx, func() { conn.Close() })
			defer stop()
			s.handle(ctx, conn)
		})
	}
}

func (s *server) handle(ctx context.Context, conn net.Conn) {
	conn.SetDeadline(time.Now().Add(requestTimeout))
	reader := bufio.NewReaderSize(conn, 64<<10)
	line, err := reader.ReadSlice('\n')
	if err != nil || len(line) > maxRequestLine {
		return
	}
	var r Request
	if err := json.Unmarshal(line, &r); err != nil {
		reply(conn, Response{Error: "invalid request"})
		return
	}
	switch r.Op {
	case "seed":
		if !s.seeded.CompareAndSwap(false, true) {
			reply(conn, Response{Error: "seed already served"})
			return
		}
		s.seed(ctx, conn)
	case "export":
		if !s.exported.CompareAndSwap(false, true) {
			reply(conn, Response{Error: "export already taken"})
			return
		}
		s.export(ctx, conn, reader)
	default:
		reply(conn, Response{Error: "unknown op"})
	}
}

// seed relays the agent's tar of the master to the guest. A failure after
// the answer closes the connection before the archive's end-of-archive
// blocks, which only the agent writes, once the tree is complete.
func (s *server) seed(ctx context.Context, conn net.Conn) {
	start := time.Now()
	ctx, cancel := context.WithTimeout(ctx, s.limits.SeedTimeout)
	defer cancel()
	conn.SetDeadline(start.Add(s.limits.SeedTimeout))
	tree, err := s.agent.Seed(ctx, s.grant)
	if errors.Is(err, ErrCold) {
		s.log.Info("checkout seed: no master on this node", "use", s.grant.ID)
		reply(conn, Response{Error: "cold"})
		return
	}
	if err != nil {
		s.log.Warn("checkout seed unavailable", "use", s.grant.ID, "error", err)
		reply(conn, Response{Error: "unavailable"})
		return
	}
	defer tree.Close()
	if reply(conn, Response{OK: true}) != nil {
		return
	}
	// The copy sees what the guest is sent; a recording never fails the seed.
	var recording Recording
	if s.record != nil {
		recording = s.record()
	}
	var source io.Reader = io.LimitReader(tree, s.limits.SeedBytes)
	if recording != nil {
		source = io.TeeReader(source, recording)
	}
	n, err := io.Copy(conn, source)
	if err == nil && n == s.limits.SeedBytes {
		if extra, _ := tree.Read(make([]byte, 1)); extra > 0 {
			err = errors.New("seed exceeds its bound")
		}
	}
	if recording != nil {
		recording.Finish(err == nil)
	}
	if err != nil {
		s.log.Warn("checkout seed interrupted", "use", s.grant.ID, "bytes", n, "error", err)
		return
	}
	s.log.Info("checkout seeded", "use", s.grant.ID, "bytes", n, "duration", time.Since(start))
}

// export streams the guest's export to the agent and answers once the agent
// accepted it. Firecracker does not pass a guest's write shutdown on to the
// host socket, so the export ends at its tar end-of-archive blocks, not at EOF.
func (s *server) export(ctx context.Context, conn net.Conn, guest io.Reader) {
	start := time.Now()
	ctx, cancel := context.WithTimeout(ctx, s.limits.ExportTimeout)
	defer cancel()
	conn.SetDeadline(start.Add(s.limits.ExportTimeout))
	read, write := io.Pipe()
	counted := &bounded{reader: guest, left: s.limits.ExportBytes}
	framed := make(chan error, 1)
	go func() {
		err := copyArchive(io.TeeReader(counted, write))
		write.CloseWithError(err)
		framed <- err
	}()
	err := s.agent.Export(ctx, s.grant, read)
	// An agent that stopped reading must not leave the framing blocked on the pipe.
	read.CloseWithError(errors.New("export ended"))
	if frameErr := <-framed; err == nil {
		err = frameErr
	}
	if err != nil {
		s.log.Warn("checkout export refused", "use", s.grant.ID, "bytes", s.limits.ExportBytes-counted.left, "error", err)
		reply(conn, Response{Error: "export refused"})
		return
	}
	s.log.Info("checkout exported", "use", s.grant.ID, "bytes", s.limits.ExportBytes-counted.left, "duration", time.Since(start))
	reply(conn, Response{OK: true})
}

// copyArchive reads one tar archive from r to its end-of-archive blocks, so
// whatever r tees receives exactly the archive. It reads nothing past them.
func copyArchive(r io.Reader) error {
	archive := tar.NewReader(r)
	for {
		_, err := archive.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		if _, err := io.Copy(io.Discard, archive); err != nil {
			return err
		}
	}
}

var errTooLarge = errors.New("export exceeds its bound")

// bounded fails, rather than truncates, a stream longer than its bound: a cut
// archive could still end on an entry boundary. Its reader asks only for what
// the archive still holds, so a read past the bound is an archive past it.
type bounded struct {
	reader io.Reader
	left   int64
}

func (b *bounded) Read(p []byte) (int, error) {
	if b.left <= 0 {
		return 0, errTooLarge
	}
	if int64(len(p)) > b.left {
		p = p[:b.left]
	}
	n, err := b.reader.Read(p)
	b.left -= int64(n)
	return n, err
}

func reply(w io.Writer, r Response) error {
	b, _ := json.Marshal(r)
	_, err := w.Write(append(b, '\n'))
	return err
}
