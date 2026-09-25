package rackboot

import (
	"context"
	"errors"
	"fmt"
	"net"
	"net/http"
	"strconv"
	"time"

	"github.com/pin/tftp/v3"
)

// Run prepares the ISO, then serves TFTP and HTTP on the provisioning address
// and the ISO to the other edges on the edges' link, reporting servable
// installs every few seconds, until ctx ends or a listener fails. It listens
// on the provisioning address before this edge holds it, so the edge answers
// as soon as the address moves to it.
func (s *Server) Run(ctx context.Context) error {
	if err := s.PrepareISO(ctx); err != nil {
		return err
	}
	ctx, cancel := context.WithCancel(ctx)
	defer cancel()
	errc := make(chan error, 3)

	lc := freebindListenConfig()
	httpAddr := net.JoinHostPort(s.cfg.Address, strconv.Itoa(s.cfg.HTTPPort))
	httpListener, err := lc.Listen(ctx, "tcp4", httpAddr)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", httpAddr, err)
	}
	httpServer := newHTTPServer(s.Handler())
	go func() { errc <- fmt.Errorf("HTTP on %s: %w", httpAddr, httpServer.Serve(httpListener)) }()

	tftpAddr := net.JoinHostPort(s.cfg.Address, "69")
	tftpConn, err := lc.ListenPacket(ctx, "udp4", tftpAddr)
	if err != nil {
		return fmt.Errorf("listen on %s: %w", tftpAddr, err)
	}
	tftpServer := tftp.NewServer(s.TFTPRead, nil)
	go func() {
		err := tftpServer.Serve(tftpConn)
		if err == nil {
			err = errors.New("stopped")
		}
		errc <- fmt.Errorf("TFTP on %s: %w", tftpAddr, err)
	}()

	go s.servePeers(ctx)
	s.log.Info("serving netboots", "address", s.cfg.Address, "http", s.cfg.HTTPPort, "holding", s.Holds())

	ticker := time.NewTicker(5 * time.Second)
	defer ticker.Stop()
	for {
		s.Acknowledge(ctx)
		select {
		case <-ctx.Done():
			shutdown, done := context.WithTimeout(context.Background(), 5*time.Second)
			_ = httpServer.Shutdown(shutdown)
			done()
			tftpServer.Shutdown()
			return nil
		case err := <-errc:
			return err
		case <-ticker.C:
		}
	}
}

// servePeers offers the ISO on this edge's address on the edges' link once
// the link is up, until ctx ends.
func (s *Server) servePeers(ctx context.Context) {
	for {
		if self := s.PeerNet(); self != nil {
			addr := net.JoinHostPort(self.IP.String(), strconv.Itoa(s.cfg.HTTPPort))
			if listener, err := (&net.ListenConfig{}).Listen(ctx, "tcp4", addr); err == nil {
				s.log.Info("offering the ISO to the other edges", "address", addr)
				server := newHTTPServer(s.PeerHandler())
				go func() {
					<-ctx.Done()
					_ = server.Close()
				}()
				err := server.Serve(listener)
				if ctx.Err() != nil {
					return
				}
				s.log.Error(err, "offer the ISO to the other edges", "address", addr)
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(5 * time.Second):
		}
	}
}

func newHTTPServer(h http.Handler) *http.Server {
	return &http.Server{Handler: h, ReadHeaderTimeout: 10 * time.Second, IdleTimeout: time.Minute}
}
