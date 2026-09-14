package linux

import (
	"context"
	"fmt"
	"net"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"

	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// sshRunTimeout caps a single dial plus script run.
const sshRunTimeout = 5 * time.Minute

// bootstrapOverSSH runs script on host and discards its output on success. The
// Linux kinds whose bootstrap is fire-and-forget use this.
func bootstrapOverSSH(ctx context.Context, user, host string, privateKey []byte, script string, hk *bootstrap.HostKeyState) error {
	_, err := runScriptOverSSH(ctx, user, host, privateKey, script, hk)
	return err
}

// runScriptOverSSH dials host, runs script under `bash -s`, and returns its
// combined output whether or not it succeeded. Separate from bootstrapOverSSH
// because the Vultr disk conversion needs the output: its result line is what
// status records, and a zero exit alone does not prove the layout is right.
//
// Host keys are pinned TOFU-style through hk, so whichever call makes first
// contact establishes the fingerprint every later one verifies against.
func runScriptOverSSH(ctx context.Context, user, host string, privateKey []byte, script string, hk *bootstrap.HostKeyState) (string, error) {
	signer, err := ssh.ParsePrivateKey(privateKey)
	if err != nil {
		return "", fmt.Errorf("parse ssh private key: %w", err)
	}
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: hk.Callback(),
		Timeout:         30 * time.Second,
	}

	dialCtx, cancel := context.WithTimeout(ctx, sshRunTimeout)
	defer cancel()

	var d net.Dialer
	conn, err := d.DialContext(dialCtx, "tcp", net.JoinHostPort(host, "22"))
	if err != nil {
		return "", fmt.Errorf("dial %s:22: %w", host, err)
	}
	defer conn.Close()
	if deadline, ok := dialCtx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	sshConn, chans, reqs, err := ssh.NewClientConn(conn, net.JoinHostPort(host, "22"), cfg)
	if err != nil {
		return "", fmt.Errorf("ssh handshake %s: %w", host, err)
	}
	sshClient := ssh.NewClient(sshConn, chans, reqs)
	defer sshClient.Close()

	session, err := sshClient.NewSession()
	if err != nil {
		return "", fmt.Errorf("open ssh session: %w", err)
	}
	defer session.Close()

	session.Stdin = strings.NewReader(script)
	out, runErr := session.CombinedOutput("bash -s")
	if runErr != nil {
		return string(out), fmt.Errorf("run script on %s: %w (output: %s)", host, runErr, truncate(out, 2000))
	}
	return string(out), nil
}
