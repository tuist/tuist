// Package picos reads and writes a PicOS switch: its CLI over SSH (port 22)
// for writes, and NETCONF over SSH (port 830) for reads.
//
// Both servers present the switch's RSA host key, so one pinned fingerprint
// covers both. PicOS rejects a source after 20 new SSH connections in 60
// seconds (iptables `recent`, and every attempt restarts the window), so a
// Client keeps one connection per port and runs every command as a session on
// it.
package picos

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strconv"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

const (
	defaultCLIPort     = 22
	defaultNetconfPort = 830
)

// ErrHostKeyMismatch is a switch that presented a host key other than the
// pinned one.
var ErrHostKeyMismatch = errors.New("host key does not match the pinned one")

// Dialer opens SSH connections to switches with the controller's key.
type Dialer struct {
	User    string
	Signer  ssh.Signer
	Timeout time.Duration
	// CLIPort and NetconfPort default to 22 and 830.
	CLIPort, NetconfPort int
}

func (d Dialer) cliPort() int {
	if d.CLIPort == 0 {
		return defaultCLIPort
	}
	return d.CLIPort
}

func (d Dialer) netconfPort() int {
	if d.NetconfPort == 0 {
		return defaultNetconfPort
	}
	return d.NetconfPort
}

// Dial connects to address:port. An empty pin accepts any host key, and the
// fingerprint it saw is returned either way, so the caller can pin it.
func (d Dialer) Dial(ctx context.Context, address string, port int, pin string) (*ssh.Client, string, error) {
	var seen string
	config := &ssh.ClientConfig{
		User: d.User,
		Auth: []ssh.AuthMethod{ssh.PublicKeys(d.Signer)},
		// The NETCONF server offers RSA only; asking sshd for RSA too makes
		// one pin cover both.
		HostKeyAlgorithms: []string{ssh.KeyAlgoRSASHA512, ssh.KeyAlgoRSASHA256},
		// The NETCONF server (libssh 0.8.7) hangs up during the handshake on
		// any other offer, Go's default list and curve25519-sha256@libssh.org
		// included. sshd takes it too.
		Config: ssh.Config{KeyExchanges: []string{ssh.KeyExchangeCurve25519}},
		HostKeyCallback: func(_ string, _ net.Addr, key ssh.PublicKey) error {
			seen = ssh.FingerprintSHA256(key)
			if pin != "" && seen != pin {
				return fmt.Errorf("%w: %s presented %s", ErrHostKeyMismatch, address, seen)
			}
			return nil
		},
		Timeout: d.Timeout,
	}
	dialer := net.Dialer{Timeout: d.Timeout}
	conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(address, strconv.Itoa(port)))
	if err != nil {
		return nil, "", err
	}
	if port == d.netconfPort() {
		conn = &newKeysPause{Conn: conn}
	}
	// A server that stalls mid-handshake would otherwise hold the dial forever.
	if d.Timeout > 0 {
		conn.SetDeadline(time.Now().Add(d.Timeout))
	}
	c, chans, reqs, err := ssh.NewClientConn(conn, net.JoinHostPort(address, strconv.Itoa(port)), config)
	if err != nil {
		conn.Close()
		return nil, seen, err
	}
	conn.SetDeadline(time.Time{})
	return ssh.NewClient(c, chans, reqs), seen, nil
}

// newKeysPause holds back the first packet the client sends after its
// SSH_MSG_NEWKEYS. The NETCONF server (libssh 0.8.7) loses a packet that
// arrives before it has switched to the new keys, and the handshake then
// stalls until the server gives up ten seconds later; without the pause about
// half of the handshakes stalled, with it none did.
type newKeysPause struct {
	net.Conn
	armed, done bool
}

const sshMsgNewKeys = 21

func (c *newKeysPause) Write(b []byte) (int, error) {
	if c.armed {
		c.armed, c.done = false, true
		time.Sleep(200 * time.Millisecond)
	}
	n, err := c.Conn.Write(b)
	// The first NEWKEYS goes out unencrypted: a 4-byte length, a padding
	// length, then the message number.
	if !c.done && len(b) > 5 && b[5] == sshMsgNewKeys {
		c.armed = true
	}
	return n, err
}

// Client is one switch: a CLI connection, opened on first use and kept, and
// a NETCONF connection per read.
type Client struct {
	Dialer  Dialer
	Address string
	// Pin is the host key fingerprint the switch must present. Empty
	// accepts the first one seen, which HostKey then reports.
	Pin string

	mu      sync.Mutex
	cli     *ssh.Client
	hostKey string
}

// HostKey is the fingerprint the switch presented on the last connection.
func (c *Client) HostKey() string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.hostKey
}

// Close drops both connections.
func (c *Client) Close() {
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.cli != nil {
		c.cli.Close()
	}
	c.cli = nil
}

func (c *Client) connection(ctx context.Context, port int) (*ssh.Client, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	slot := &c.cli
	if *slot != nil {
		if alive(ctx, *slot, c.Dialer.Timeout) {
			return *slot, nil
		}
		(*slot).Close()
		*slot = nil
	}
	conn, seen, err := c.Dialer.Dial(ctx, c.Address, port, c.Pin)
	if seen != "" {
		c.hostKey = seen
	}
	if err != nil {
		return nil, err
	}
	*slot = conn
	return conn, nil
}

// CLIError is a command line the switch refused, with what it printed.
type CLIError struct {
	Line   string
	Output string
}

func (e *CLIError) Error() string { return fmt.Sprintf("switch refused %q: %s", e.Line, e.Output) }

// refusals are what pica_sh prints for a line it did not run. It exits zero
// for some of them, so the output is what decides.
var refusals = []string{"ERROR:", "Failed to execute", "syntax error", "unknown command", "Commit failed", "is not valid"}

// RunCLI runs commands, separated by semicolons, in one pica_sh session and
// returns what it printed with carriage returns removed.
func (c *Client) RunCLI(ctx context.Context, commands []string) (string, error) {
	for _, command := range commands {
		if strings.ContainsAny(command, "'\n;") {
			return "", fmt.Errorf("command %q contains a quote, newline or semicolon", command)
		}
	}
	conn, err := c.connection(ctx, c.Dialer.cliPort())
	if err != nil {
		return "", err
	}
	session, err := conn.NewSession()
	if err != nil {
		return "", err
	}
	defer session.Close()
	type result struct {
		out []byte
		err error
	}
	done := make(chan result, 1)
	go func() {
		out, err := session.CombinedOutput("cli -c '" + strings.Join(commands, ";") + "'")
		done <- result{out, err}
	}()
	select {
	case <-ctx.Done():
		session.Signal(ssh.SIGTERM)
		return "", ctx.Err()
	case res := <-done:
		text, err := strings.ReplaceAll(string(res.out), "\r", ""), res.err
		if refused := refusal(text); refused != nil {
			return text, refused
		}
		if err != nil {
			return text, fmt.Errorf("cli: %w: %s", err, strings.TrimSpace(text))
		}
		return text, nil
	}
}

// refusal is the line pica_sh did not run in its output, and what it printed
// about it; nil when it ran every line.
func refusal(text string) *CLIError {
	for _, r := range refusals {
		if i := strings.Index(text, r); i >= 0 {
			return &CLIError{Line: failedLine(text, i), Output: strings.TrimSpace(text[outputStart(text, i):])}
		}
	}
	return nil
}

// outputStart is where the output of the line a refusal is about starts: the
// switch can explain before it refuses, as a commit does ("... in one group set
// either 25G or 10G/1G" then "Commit failed.").
func outputStart(text string, at int) int {
	i := strings.LastIndex(text[:at], "Execute command: ")
	if i < 0 {
		return at
	}
	if j := strings.IndexByte(text[i:at], '\n'); j >= 0 {
		return i + j + 1
	}
	return at
}

// failedLine is the "Execute command:" line before a refusal.
func failedLine(text string, at int) string {
	head := text[:at]
	i := strings.LastIndex(head, "Execute command: ")
	if i < 0 {
		return ""
	}
	line := head[i+len("Execute command: "):]
	if j := strings.IndexByte(line, '\n'); j >= 0 {
		line = line[:j]
	}
	return strings.TrimSuffix(strings.TrimSpace(line), ".")
}

// alive asks the server to answer a keepalive, giving up after timeout: a
// connection the switch dropped without a FIN never answers.
func alive(ctx context.Context, conn *ssh.Client, timeout time.Duration) bool {
	if timeout <= 0 {
		timeout = 30 * time.Second
	}
	done := make(chan error, 1)
	go func() {
		_, _, err := conn.SendRequest("keepalive@openssh.com", true, nil)
		done <- err
	}()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case err := <-done:
		return err == nil
	case <-timer.C:
		return false
	case <-ctx.Done():
		return false
	}
}
