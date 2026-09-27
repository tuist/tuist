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
	return runOverSSH(ctx, user, host, privateKey, "bash -s", script, sshRunTimeout, hk)
}

// runOverSSH runs command on host with script on its stdin, within timeout.
// A non-zero exit is returned wrapping the *ssh.ExitError.
func runOverSSH(ctx context.Context, user, host string, privateKey []byte, command, script string, timeout time.Duration, hk *bootstrap.HostKeyState) (string, error) {
	sshClient, closeSSH, err := dialSSH(ctx, user, host, privateKey, timeout, hk)
	if err != nil {
		return "", err
	}
	defer closeSSH()

	session, err := sshClient.NewSession()
	if err != nil {
		return "", fmt.Errorf("open ssh session: %w", err)
	}
	defer session.Close()

	session.Stdin = strings.NewReader(script)
	out, runErr := session.CombinedOutput(command)
	if runErr != nil {
		return string(out), fmt.Errorf("run script on %s: %w (output: %s)", host, runErr, truncate(out, 2000))
	}
	return string(out), nil
}

// dialSSH opens an SSH client to host whose connection lasts at most timeout;
// closeSSH releases it.
func dialSSH(ctx context.Context, user, host string, privateKey []byte, timeout time.Duration, hk *bootstrap.HostKeyState) (sshClient *ssh.Client, closeSSH func(), err error) {
	signer, err := ssh.ParsePrivateKey(privateKey)
	if err != nil {
		return nil, nil, fmt.Errorf("parse ssh private key: %w", err)
	}
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: hk.Callback(),
		Timeout:         30 * time.Second,
	}

	dialCtx, cancel := context.WithTimeout(ctx, timeout)
	var d net.Dialer
	conn, err := d.DialContext(dialCtx, "tcp", net.JoinHostPort(host, "22"))
	if err != nil {
		cancel()
		return nil, nil, fmt.Errorf("dial %s:22: %w", host, err)
	}
	if deadline, ok := dialCtx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
	}

	sshConn, chans, reqs, err := ssh.NewClientConn(conn, net.JoinHostPort(host, "22"), cfg)
	if err != nil {
		conn.Close()
		cancel()
		return nil, nil, fmt.Errorf("ssh handshake %s: %w", host, err)
	}
	sshClient = ssh.NewClient(sshConn, chans, reqs)
	return sshClient, func() {
		sshClient.Close()
		conn.Close()
		cancel()
	}, nil
}
