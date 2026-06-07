// host-tcp-forwarder is a minimal multi-connection TCP relay installed
// on Mac mini hosts to bridge Tart VM outbound traffic into cluster
// Services exposed on the tailnet.
//
// Why a custom binary instead of socat: socat is not part of macOS,
// and the bootstrap layer (`infra/macos-host-bootstrap`) ships
// operator-image binaries via SSH rather than installing Homebrew
// packages on every host. A 60-line cross-compiled Go binary
// (~5 MiB darwin/arm64) drops into the same /usr/local/bin path
// node_exporter and tart-kubelet use.
//
// Routing chain for the xcresult-processor case:
//
//   Tart VM ─► vmnet gateway (host's 192.168.64.1:5432)
//           ─► this binary
//           ─► host's tailscale0 interface
//           ─► Tailscale operator-managed proxy on the tailnet
//           ─► CNPG pooler Service ClusterIP
//           ─► PgBouncer pod
//
// The VM has no tailnet identity of its own; only the Mac mini host
// does. Without this relay the VM has no path to tailnet CGNAT
// addresses (or any in-cluster Service) because vmnet's NAT routes
// outbound through the host's public-internet uplink, not through
// tailscale0.
package main

import (
	"flag"
	"io"
	"log/slog"
	"net"
	"os"
	"sync"
)

func main() {
	bind := flag.String("bind", "0.0.0.0:5432", "listen address (default 0.0.0.0:5432)")
	target := flag.String("target", "", "upstream host:port (required)")
	flag.Parse()

	if *target == "" {
		slog.Error("--target is required")
		os.Exit(2)
	}

	ln, err := net.Listen("tcp", *bind)
	if err != nil {
		slog.Error("listen failed", "bind", *bind, "err", err)
		os.Exit(1)
	}
	slog.Info("forwarding", "bind", *bind, "target", *target)

	for {
		client, err := ln.Accept()
		if err != nil {
			slog.Error("accept failed", "err", err)
			continue
		}
		go handle(client, *target)
	}
}

// handle dials the upstream and shovels bytes in both directions.
// We use TCPConn's CloseWrite for graceful half-close so the upstream
// sees EOF on the client's read side once the client finishes sending
// — important for line-oriented protocols like the Postgres startup
// message, where the upstream may otherwise wait forever for more
// bytes that aren't coming. io.Copy alone doesn't propagate FIN.
func handle(client net.Conn, target string) {
	defer client.Close()

	upstream, err := net.Dial("tcp", target)
	if err != nil {
		slog.Error("dial upstream failed", "target", target, "remote", client.RemoteAddr(), "err", err)
		return
	}
	defer upstream.Close()

	var wg sync.WaitGroup
	wg.Add(2)
	go relay(&wg, upstream, client)
	go relay(&wg, client, upstream)
	wg.Wait()
}

func relay(wg *sync.WaitGroup, dst, src net.Conn) {
	defer wg.Done()
	_, _ = io.Copy(dst, src)
	if tc, ok := dst.(*net.TCPConn); ok {
		_ = tc.CloseWrite()
	}
}
