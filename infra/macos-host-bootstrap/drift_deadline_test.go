package bootstrap

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"encoding/pem"
	"net"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"
)

// listenSSH serves on a loopback port and points the package's dials at it.
func listenSSH(t *testing.T) net.Listener {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatalf("listen: %v", err)
	}
	t.Cleanup(func() { _ = l.Close() })
	_, port, _ := net.SplitHostPort(l.Addr().String())
	previous := sshPort
	sshPort = port
	t.Cleanup(func() { sshPort = previous })
	return l
}

func clientSigner(t *testing.T) (ssh.Signer, []byte) {
	t.Helper()
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	signer, err := ssh.NewSignerFromKey(priv)
	if err != nil {
		t.Fatalf("signer: %v", err)
	}
	block, err := ssh.MarshalPrivateKey(priv, "")
	if err != nil {
		t.Fatalf("marshal key: %v", err)
	}
	return signer, pem.EncodeToMemory(block)
}

func returnsWithin(t *testing.T, limit time.Duration, f func() error) error {
	t.Helper()
	done := make(chan error, 1)
	go func() { done <- f() }()
	select {
	case err := <-done:
		return err
	case <-time.After(limit):
		t.Fatalf("still blocked after %s", limit)
		return nil
	}
}

// launchd owns a Mac mini's :22 and accepts the connection before sshd runs,
// so a wedged host completes TCP and never sends a banner. The dial timeout
// covers only the connect, so the handshake needs its own deadline, or the
// caller's reconcile blocks until the operator restarts.
func TestDialAuth_GivesUpOnAHostThatNeverSendsABanner(t *testing.T) {
	l := listenSSH(t)
	accepted := make(chan net.Conn, 8)
	t.Cleanup(func() {
		_ = l.Close()
		for len(accepted) > 0 {
			_ = (<-accepted).Close()
		}
	})
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			accepted <- conn
		}
	}()
	previous := sshHandshakeTimeout
	sshHandshakeTimeout = 200 * time.Millisecond
	t.Cleanup(func() { sshHandshakeTimeout = previous })

	signer, _ := clientSigner(t)
	hk := NewHostKeyState("")
	err := returnsWithin(t, 5*time.Second, func() error {
		_, err := Dial("127.0.0.1", "admin", signer, hk)
		return err
	})
	if err == nil {
		t.Fatal("dial succeeded against a host that never spoke SSH")
	}
	if hk.Observed() != "" {
		t.Fatal("a handshake that never completed must leave no fingerprint, which is what sends the drift loop to the tailnet")
	}
}

// A host can also complete the handshake and then never answer a session
// request. The update bounds itself, so a reconcile context without a deadline
// still gets the host back.
func TestUpdateTartKubelet_GivesUpOnAHostThatNeverAnswers(t *testing.T) {
	l := listenSSH(t)
	_, hostKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate host key: %v", err)
	}
	hostSigner, err := ssh.NewSignerFromKey(hostKey)
	if err != nil {
		t.Fatalf("host signer: %v", err)
	}
	server := &ssh.ServerConfig{NoClientAuth: true}
	server.AddHostKey(hostSigner)
	go func() {
		for {
			conn, err := l.Accept()
			if err != nil {
				return
			}
			go func() {
				_, chans, reqs, err := ssh.NewServerConn(conn, server)
				if err != nil {
					return
				}
				go ssh.DiscardRequests(reqs)
				// Never accept or reject a channel: the client's NewSession waits.
				for range chans {
				}
			}()
		}
	}()
	previous := hostConfigUpdateTimeout
	hostConfigUpdateTimeout = 300 * time.Millisecond
	t.Cleanup(func() { hostConfigUpdateTimeout = previous })

	_, key := clientSigner(t)
	err = returnsWithin(t, 5*time.Second, func() error {
		_, err := UpdateTartKubelet(context.Background(), Config{IP: "127.0.0.1", SSHUser: "admin", SSHPrivateKey: key, Kubeconfig: "apiVersion: v1\n"})
		return err
	})
	if err == nil || !strings.Contains(err.Error(), "gave up after") {
		t.Fatalf("update did not give up on its deadline: %v", err)
	}
}
