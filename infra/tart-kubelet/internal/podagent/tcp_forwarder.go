package podagent

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"sync"
	"syscall"
	"time"
)

// TCPForwarder is a guarded host-side TCP relay. tart-kubelet uses it
// for opt-in VNC access: clients dial the Mac mini's node IP, and the
// relay forwards to Tart's host-local VNC endpoint.
type TCPForwarder struct {
	listener net.Listener
	logger   *slog.Logger

	stopOnce sync.Once
	doneOnce sync.Once
	done     chan struct{}

	mu    sync.Mutex
	conns map[net.Conn]struct{}
	wg    sync.WaitGroup
}

// TCPForwarderOptions controls client-side restrictions.
type TCPForwarderOptions struct {
	// AllowedCIDRs is the set of source ranges accepted by the relay.
	// Empty = allow all (tests only).
	AllowedCIDRs []*net.IPNet

	// Logger receives detailed relay errors. Nil falls back to slog.Default().
	Logger *slog.Logger

	// Relay handles one accepted client connection after the upstream
	// target has been resolved. Nil uses a raw TCP byte relay.
	Relay func(client net.Conn, target string, logger *slog.Logger)
}

// NewTCPForwarder starts a TCP relay on listenAddr. Resolve is called for
// each accepted connection to compute the upstream host:port.
func NewTCPForwarder(listenAddr string, resolve func() (string, error), opts TCPForwarderOptions) (*TCPForwarder, error) {
	if resolve == nil {
		return nil, errors.New("resolve function is required")
	}
	l, err := net.Listen("tcp", listenAddr)
	if err != nil {
		return nil, fmt.Errorf("listen on %s: %w", listenAddr, err)
	}

	logger := opts.Logger
	if logger == nil {
		logger = slog.Default()
	}

	f := &TCPForwarder{
		listener: l,
		logger:   logger,
		done:     make(chan struct{}),
		conns:    map[net.Conn]struct{}{},
	}

	f.wg.Add(1)
	go func() {
		defer f.doneOnce.Do(func() { close(f.done) })
		defer f.wg.Done()
		for {
			client, err := l.Accept()
			if err != nil {
				return
			}
			if !sourceIPAllowed(client.RemoteAddr(), opts.AllowedCIDRs) {
				_ = client.Close()
				continue
			}
			target, err := resolve()
			if err != nil || target == "" {
				logger.Warn("tcp forwarder: upstream resolve failed",
					"listen", listenAddr, "remote", client.RemoteAddr().String(), "err", err)
				_ = client.Close()
				continue
			}
			f.track(client)
			f.wg.Add(1)
			relay := opts.Relay
			if relay == nil {
				relay = rawTCPRelay
			}
			go f.relay(client, target, relay)
		}
	}()

	return f, nil
}

// Addr returns the address the forwarder is bound to.
func (f *TCPForwarder) Addr() net.Addr { return f.listener.Addr() }

// Stop closes the listener and active client connections, then waits
// for relay goroutines to exit. Safe to call multiple times.
func (f *TCPForwarder) Stop() {
	f.stopOnce.Do(func() {
		_ = f.listener.Close()
		f.mu.Lock()
		for conn := range f.conns {
			_ = conn.Close()
		}
		f.mu.Unlock()
	})
	f.wg.Wait()
	<-f.done
}

func (f *TCPForwarder) relay(client net.Conn, target string, relay func(net.Conn, string, *slog.Logger)) {
	defer f.wg.Done()
	defer f.untrack(client)
	defer client.Close()

	relay(client, target, f.logger)
}

func rawTCPRelay(client net.Conn, target string, logger *slog.Logger) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	upstream, err := (&net.Dialer{
		Timeout: 5 * time.Second,
		Control: func(network, address string, c syscall.RawConn) error {
			return bindDialToTargetInterface(network, address, c)
		},
	}).DialContext(ctx, "tcp", target)
	if err != nil {
		logger.Warn("tcp forwarder: upstream dial failed",
			"target", target, "remote", client.RemoteAddr().String(), "err", err)
		return
	}
	defer upstream.Close()

	copyBidirectional(client, upstream)
}

func copyBidirectional(client net.Conn, upstream net.Conn) {
	var copies sync.WaitGroup
	copies.Add(2)
	go func() {
		defer copies.Done()
		_, _ = io.Copy(upstream, client)
		if tcp, ok := upstream.(*net.TCPConn); ok {
			_ = tcp.CloseWrite()
		} else {
			_ = upstream.Close()
		}
	}()
	go func() {
		defer copies.Done()
		_, _ = io.Copy(client, upstream)
		if tcp, ok := client.(*net.TCPConn); ok {
			_ = tcp.CloseWrite()
		} else {
			_ = client.Close()
		}
	}()
	copies.Wait()
}

func dialForwarderUpstream(target string) (net.Conn, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	return (&net.Dialer{
		Timeout: 5 * time.Second,
		Control: func(network, address string, c syscall.RawConn) error {
			return bindDialToTargetInterface(network, address, c)
		},
	}).DialContext(ctx, "tcp", target)
}

func (f *TCPForwarder) track(conn net.Conn) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.conns[conn] = struct{}{}
}

func (f *TCPForwarder) untrack(conn net.Conn) {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.conns, conn)
}

func sourceIPAllowed(addr net.Addr, allowed []*net.IPNet) bool {
	if len(allowed) == 0 {
		return true
	}
	if addr == nil {
		return false
	}
	host, _, err := net.SplitHostPort(addr.String())
	if err != nil {
		host = addr.String()
	}
	ip := net.ParseIP(host)
	if ip == nil {
		return false
	}
	for _, c := range allowed {
		if c.Contains(ip) {
			return true
		}
	}
	return false
}
