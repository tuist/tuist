package bootstrap

import (
	"bytes"
	"context"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"
)

func kubeletInstallEnv(t *testing.T, validSignature bool) []string {
	t.Helper()
	bin := t.TempDir()
	result := "0"
	if !validSignature {
		result = "1"
	}
	if err := os.WriteFile(filepath.Join(bin, "codesign"), []byte("#!/bin/sh\nexit "+result+"\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	env := passthroughSudo(t)
	env[0] = strings.Replace(env[0], "PATH=", "PATH="+bin+":", 1)
	return env
}

func assertKubeletFile(t *testing.T, path string, want []byte) {
	t.Helper()
	got, err := os.ReadFile(path)
	if err != nil || !bytes.Equal(got, want) {
		t.Fatalf("installed file = %q, %v; want %q", got, err, want)
	}
	stages, err := filepath.Glob(filepath.Join(filepath.Dir(path), ".tart-kubelet.*"))
	if err != nil || len(stages) != 0 {
		t.Fatalf("staging directories leaked: %v, %v", stages, err)
	}
}

func TestTartKubeletInstallPreservesLiveFileOnInvalidUpload(t *testing.T) {
	for _, shell := range loginShells(t) {
		for _, tc := range []struct {
			name, upload string
			signed       bool
		}{
			{"truncated", "new", true},
			{"corrupt", "bad executable", true},
			{"bad signature", "new executable", false},
		} {
			t.Run(filepath.Base(shell)+"/"+tc.name, func(t *testing.T) {
				path := filepath.Join(t.TempDir(), "tart-kubelet")
				old := []byte("running executable")
				if err := os.WriteFile(path, old, 0o755); err != nil {
					t.Fatal(err)
				}
				before, _ := os.Stat(path)
				input := []byte(sha256Hex([]byte("new executable")) + "\n" + tc.upload)
				out, err := runTartScript(t, shell, renderTartKubeletInstallAt(path, 10), input, kubeletInstallEnv(t, tc.signed))
				if err == nil {
					t.Fatalf("accepted invalid upload: %s", out)
				}
				assertKubeletFile(t, path, old)
				after, _ := os.Stat(path)
				if !os.SameFile(before, after) {
					t.Fatal("replaced the live inode on failure")
				}
			})
		}
	}
}

func TestTartKubeletInstallReplacesInodeAndPreservesSignature(t *testing.T) {
	// On macOS exercise the real signature verifier as well as the shell
	// protocol. On Linux the verifier is stubbed, like the other host scripts.
	binary := []byte("new executable")
	for _, shell := range loginShells(t) {
		t.Run(filepath.Base(shell), func(t *testing.T) {
			env := kubeletInstallEnv(t, true)
			if runtime.GOOS == "darwin" {
				self, err := os.Executable()
				if err != nil {
					t.Fatal(err)
				}
				binary, err = os.ReadFile(self)
				if err != nil {
					t.Fatal(err)
				}
				env = passthroughSudo(t)
			}
			path := filepath.Join(t.TempDir(), "tart-kubelet")
			old := []byte("running executable")
			if err := os.WriteFile(path, old, 0o755); err != nil {
				t.Fatal(err)
			}
			open, err := os.Open(path)
			if err != nil {
				t.Fatal(err)
			}
			defer open.Close()
			input := append([]byte(sha256Hex(binary)+"\n"), binary...)
			out, err := runTartScript(t, shell, renderTartKubeletInstallAt(path, 10), input, env)
			if err != nil {
				t.Fatalf("install: %v: %s", err, out)
			}
			assertKubeletFile(t, path, binary)
			stillOpen, _ := io.ReadAll(open)
			if !bytes.Equal(stillOpen, old) {
				t.Fatalf("changed the running inode: %q", stillOpen)
			}
			before, _ := open.Stat()
			after, _ := os.Stat(path)
			if os.SameFile(before, after) || after.Mode().Perm() != 0o755 {
				t.Fatal("did not atomically replace with an executable inode")
			}
			out, err = runTartScript(t, shell, renderTartKubeletProbeScript(path, sha256Hex(binary)), nil, env)
			if err != nil || strings.TrimSpace(out) != "installed" {
				t.Fatalf("fresh install is not reusable: %v: %s", err, out)
			}
		})
	}
}

func TestTartKubeletProbeRejectsDamagedOrUnsignedExecutable(t *testing.T) {
	for _, shell := range loginShells(t) {
		for _, signed := range []bool{true, false} {
			path := filepath.Join(t.TempDir(), "tart-kubelet")
			binary := []byte("complete binary")
			content := binary
			if signed {
				content = binary[:3]
			}
			if err := os.WriteFile(path, content, 0o755); err != nil {
				t.Fatal(err)
			}
			out, err := runTartScript(t, shell, renderTartKubeletProbeScript(path, sha256Hex(binary)), nil, kubeletInstallEnv(t, signed))
			if err != nil || strings.TrimSpace(out) != "" {
				t.Fatalf("probe accepted damaged/unsigned executable: %v: %s", err, out)
			}
		}
	}
}

func TestTartKubeletInstallTimesOutWithoutSSHDisconnect(t *testing.T) {
	for _, shell := range loginShells(t) {
		t.Run(filepath.Base(shell), func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "tart-kubelet")
			old := []byte("running executable")
			if err := os.WriteFile(path, old, 0o755); err != nil {
				t.Fatal(err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			cmd := exec.CommandContext(ctx, shell, "-c", renderTartKubeletInstallAt(path, 1))
			cmd.Env = append(os.Environ(), kubeletInstallEnv(t, true)...)
			reader, writer, err := os.Pipe()
			if err != nil {
				t.Fatal(err)
			}
			defer reader.Close()
			defer writer.Close()
			cmd.Stdin = reader
			// Keep stdin open forever, like an orphaned SSH stream. The host
			// must kill its own writer and remove its partial file anyway.
			if _, err := io.WriteString(writer, sha256Hex([]byte("new executable"))+"\nnew"); err != nil {
				t.Fatal(err)
			}
			out, err := cmd.CombinedOutput()
			if err == nil || ctx.Err() != nil || !strings.Contains(string(out), "host-side deadline") {
				t.Fatalf("watchdog did not end blocked upload: %v, context: %v, output: %s", err, ctx.Err(), out)
			}
			assertKubeletFile(t, path, old)
		})
	}
}

// Execute the real installer over SSH, redirecting only its destination and
// privilege/signature commands into the fixture. This covers manifest framing
// and the decision to send no binary bytes on a config-only reconciliation.
func TestInstallTartKubeletSkipsMatchingFileAndRepairsCorruption(t *testing.T) {
	root := t.TempDir()
	path := filepath.Join(root, "tart-kubelet")
	env := append(os.Environ(), kubeletInstallEnv(t, true)...)
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()
	signer, _ := clientSigner(t)
	config := &ssh.ServerConfig{NoClientAuth: true}
	config.AddHostKey(signer)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	var uploads atomic.Int32
	go func() {
		connection, err := listener.Accept()
		if err != nil {
			return
		}
		defer connection.Close()
		server, channels, requests, err := ssh.NewServerConn(connection, config)
		if err != nil {
			return
		}
		defer server.Close()
		go ssh.DiscardRequests(requests)
		for incoming := range channels {
			channel, requests, err := incoming.Accept()
			if err != nil {
				return
			}
			go func() {
				defer channel.Close()
				for request := range requests {
					if request.Type != "exec" {
						_ = request.Reply(false, nil)
						continue
					}
					var payload struct{ Command string }
					if ssh.Unmarshal(request.Payload, &payload) != nil {
						_ = request.Reply(false, nil)
						return
					}
					_ = request.Reply(true, nil)
					if strings.Contains(payload.Command, "mktemp -d") {
						uploads.Add(1)
					}
					command := exec.CommandContext(ctx, "/bin/sh", "-c", strings.ReplaceAll(payload.Command, "/usr/local/bin", root))
					command.Env = env
					command.Stdin, command.Stdout, command.Stderr = channel, channel, channel.Stderr()
					var code uint32
					if err := command.Run(); err != nil {
						code = 1
					}
					_, _ = channel.SendRequest("exit-status", false, ssh.Marshal(struct{ Code uint32 }{code}))
					return
				}
			}()
		}
	}()
	client, err := ssh.Dial("tcp", listener.Addr().String(), &ssh.ClientConfig{
		User: "test", HostKeyCallback: ssh.FixedHostKey(signer.PublicKey()), Timeout: 5 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
	binary := []byte("complete binary\x00with binary bytes\xff")
	if err := installTartKubelet(ctx, client, binary); err != nil {
		t.Fatal(err)
	}
	before, _ := os.Stat(path)
	if err := installTartKubelet(ctx, client, binary); err != nil {
		t.Fatal(err)
	}
	after, _ := os.Stat(path)
	if uploads.Load() != 1 || !os.SameFile(before, after) {
		t.Fatal("unchanged binary was uploaded or replaced again")
	}
	if err := os.WriteFile(path, binary[:4], 0o755); err != nil {
		t.Fatal(err)
	}
	if err := installTartKubelet(ctx, client, binary); err != nil {
		t.Fatal(err)
	}
	if uploads.Load() != 2 {
		t.Fatal("damaged binary did not trigger repair")
	}
	assertKubeletFile(t, path, binary)
}
