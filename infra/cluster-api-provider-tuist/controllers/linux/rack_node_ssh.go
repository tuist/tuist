package linux

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"

	"golang.org/x/crypto/ssh"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/racknode"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// rackNodeDir is where a rack host keeps the rack-node binary the operator
// runs, named after its digest.
const rackNodeDir = "/usr/local/lib/tuist"

// ApplyRackNode runs `rack-node apply` with req as root on a rack host over
// SSH.
type ApplyRackNode func(ctx context.Context, user, host string, privateKey []byte, hk *bootstrap.HostKeyState, req racknode.Request) (racknode.Result, error)

// applyRackNodeOverSSH installs binary on the host when the host lacks it,
// removing earlier ones, and runs it with the request on its stdin.
func applyRackNodeOverSSH(binary []byte) ApplyRackNode {
	return func(ctx context.Context, user, host string, privateKey []byte, hk *bootstrap.HostKeyState, req racknode.Request) (racknode.Result, error) {
		if len(binary) == 0 {
			return racknode.Result{}, errors.New("the operator has no rack-node binary (--rack-node-binary)")
		}
		sshClient, closeSSH, err := dialSSH(ctx, user, host, privateKey, rackConvergeTimeout, hk)
		if err != nil {
			return racknode.Result{}, err
		}
		defer closeSSH()

		sum := sha256.Sum256(binary)
		name := "rack-node-" + hex.EncodeToString(sum[:])[:16]
		path := rackNodeDir + "/" + name
		if _, _, err := runSSHSession(sshClient, "sudo -n test -x "+path, nil); err != nil {
			install := fmt.Sprintf(`sudo -n sh -c 'set -e; mkdir -p %[1]s; cat > %[2]s.new; chmod 755 %[2]s.new; mv %[2]s.new %[2]s; find %[1]s -maxdepth 1 -name "rack-node-*" ! -name %[3]s -delete'`,
				rackNodeDir, path, name)
			if _, stderr, err := runSSHSession(sshClient, install, binary); err != nil {
				return racknode.Result{}, fmt.Errorf("install rack-node on %s: %w: %s", host, err, truncate(stderr, 2000))
			}
		}
		body, err := json.Marshal(req)
		if err != nil {
			return racknode.Result{}, err
		}
		stdout, stderr, err := runSSHSession(sshClient, "sudo -n "+path+" apply", body)
		if err != nil {
			return racknode.Result{}, fmt.Errorf("rack-node apply on %s: %w: %s", host, err, truncate(stderr, 2000))
		}
		var resp racknode.Response
		if err := json.Unmarshal(stdout, &resp); err != nil {
			return racknode.Result{}, fmt.Errorf("read rack-node's answer from %s: %w", host, err)
		}
		if resp.Error != "" {
			return resp.Result, errors.New(resp.Error)
		}
		return resp.Result, nil
	}
}

func runSSHSession(c *ssh.Client, command string, stdin []byte) (stdout, stderr []byte, err error) {
	session, err := c.NewSession()
	if err != nil {
		return nil, nil, fmt.Errorf("open ssh session: %w", err)
	}
	defer session.Close()
	if stdin != nil {
		session.Stdin = bytes.NewReader(stdin)
	}
	var out, errOut bytes.Buffer
	session.Stdout, session.Stderr = &out, &errOut
	err = session.Run(command)
	return out.Bytes(), errOut.Bytes(), err
}
