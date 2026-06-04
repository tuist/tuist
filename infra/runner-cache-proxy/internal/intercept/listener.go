package intercept

import (
	"context"
	"crypto/tls"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/netip"
	"sync"
	"sync/atomic"
	"time"

	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/allowlist"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/metrics"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/mitm"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/sni"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/splice"
	"github.com/tuist/tuist/infra/runner-cache-proxy/internal/upstream"
)

// Listener is the host-side accept loop. For each DNAT'd guest
// connection it recovers the original destination, peeks the SNI, then
// MITMs the GitHub cache plane or blind-splices everything else.
type Listener struct {
	ln      net.Listener
	origDst OriginalDst
	allow   *allowlist.Matcher
	leaves  *mitm.LeafCache
	proxy   *upstream.Proxy
	log     *slog.Logger
}

// Options configure a Listener.
type Options struct {
	Listener    net.Listener
	OriginalDst OriginalDst
	Allow       *allowlist.Matcher
	Leaves      *mitm.LeafCache
	Proxy       *upstream.Proxy
	Logger      *slog.Logger
}

// NewListener builds a Listener.
func NewListener(o Options) *Listener {
	log := o.Logger
	if log == nil {
		log = slog.Default()
	}
	return &Listener{
		ln:      o.Listener,
		origDst: o.OriginalDst,
		allow:   o.Allow,
		leaves:  o.Leaves,
		proxy:   o.Proxy,
		log:     log,
	}
}

// Serve accepts connections until ctx is cancelled.
func (l *Listener) Serve(ctx context.Context) error {
	go func() {
		<-ctx.Done()
		_ = l.ln.Close()
	}()
	for {
		conn, err := l.ln.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return err
		}
		go l.handle(ctx, conn)
	}
}

func (l *Listener) handle(ctx context.Context, conn net.Conn) {
	defer conn.Close()

	tcp, _ := conn.(*net.TCPConn)
	var orig netip.AddrPort
	if tcp != nil && l.origDst != nil {
		if o, err := l.origDst.Lookup(tcp); err == nil {
			orig = o
		} else {
			metrics.DNATLookupFailures.Inc()
		}
	}

	srcIP := remoteIP(conn)

	serverName, peeked, perr := sni.Peek(conn)
	// Replay the peeked bytes ahead of any further reads.
	replayed := &prefixConn{Conn: conn, prefix: peeked}

	if perr != nil || serverName == "" || l.allow == nil || !l.allow.Match(serverName) {
		// Not the cache plane (or unparseable): blind-splice through.
		if perr != nil {
			metrics.SNIParseFailures.Inc()
		}
		l.blindSplice(replayed, orig, serverName)
		return
	}

	// Cache plane: MITM with an on-the-fly leaf, then route by path.
	tlsConn := tls.Server(replayed, l.leaves.TLSConfig())
	if err := tlsConn.HandshakeContext(ctx); err != nil {
		metrics.MITMHandshakes.WithLabelValues("leaf_error").Inc()
		return
	}
	metrics.MITMHandshakes.WithLabelValues("ok").Inc()

	cc := upstream.ConnContext{SrcIP: srcIP, SNI: serverName, OriginalDst: orig}
	l.serveHTTP(ctx, tlsConn, cc)
}

func (l *Listener) blindSplice(client net.Conn, orig netip.AddrPort, serverName string) {
	target := ""
	switch {
	case orig.IsValid():
		target = orig.String()
	case serverName != "":
		target = net.JoinHostPort(serverName, "443")
	default:
		return // nothing to dial
	}
	up, err := net.DialTimeout("tcp", target, 10*time.Second)
	if err != nil {
		return
	}
	defer up.Close()
	toUp, toClient := splice.Splice(client, up)
	metrics.Connections.WithLabelValues("splice_blind").Inc()
	metrics.BytesProxied.WithLabelValues("up", "splice_blind").Add(float64(toUp))
	metrics.BytesProxied.WithLabelValues("down", "splice_blind").Add(float64(toClient))
}

// serveHTTP serves the decrypted connection's HTTP requests through the
// routing proxy, for the lifetime of the connection.
func (l *Listener) serveHTTP(ctx context.Context, conn net.Conn, cc upstream.ConnContext) {
	nc := &notifyConn{Conn: conn, done: make(chan struct{})}
	srv := &http.Server{
		Handler:     l.proxy.Handler(cc),
		IdleTimeout: 30 * time.Second,
		BaseContext: func(net.Listener) context.Context { return ctx },
	}
	_ = srv.Serve(&singleConnListener{conn: nc, done: nc.done})
}

func remoteIP(conn net.Conn) netip.Addr {
	if ta, ok := conn.RemoteAddr().(*net.TCPAddr); ok {
		if a, ok := netip.AddrFromSlice(ta.IP); ok {
			return a.Unmap()
		}
	}
	return netip.Addr{}
}

// prefixConn replays a peeked prefix before reading from the underlying
// connection, so the SNI peek is non-destructive.
type prefixConn struct {
	net.Conn
	prefix []byte
}

func (c *prefixConn) Read(p []byte) (int, error) {
	if len(c.prefix) > 0 {
		n := copy(p, c.prefix)
		c.prefix = c.prefix[n:]
		return n, nil
	}
	return c.Conn.Read(p)
}

// notifyConn closes a channel when the connection closes, so the
// single-connection HTTP server can stop accepting.
type notifyConn struct {
	net.Conn
	once sync.Once
	done chan struct{}
}

func (c *notifyConn) Close() error {
	c.once.Do(func() { close(c.done) })
	return c.Conn.Close()
}

// singleConnListener yields one connection to http.Server.Serve, then
// blocks until the connection closes so Serve stays alive for its
// lifetime without accepting anything else.
type singleConnListener struct {
	conn   net.Conn
	served int32
	done   chan struct{}
}

func (l *singleConnListener) Accept() (net.Conn, error) {
	if atomic.CompareAndSwapInt32(&l.served, 0, 1) {
		return l.conn, nil
	}
	<-l.done
	return nil, io.EOF
}

func (l *singleConnListener) Close() error   { return nil }
func (l *singleConnListener) Addr() net.Addr { return l.conn.LocalAddr() }
