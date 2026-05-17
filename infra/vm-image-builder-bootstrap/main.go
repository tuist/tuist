package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"strings"
	"syscall"

	"golang.org/x/term"
)

func main() {
	ip := flag.String("ip", "", "Public IPv4 of the freshly-ordered Mac mini.")
	hostname := flag.String("hostname", "", "Hostname to set on the host (e.g. vm-image-builder-2).")
	sshUser := flag.String("ssh-user", "m1", "SSH user on the host. Scaleway Apple Silicon defaults to m1.")
	sshKey := flag.String("ssh-key", "", "Path to the SSH private key registered with Scaleway IAM. Mutually exclusive with --use-ssh-agent.")
	useSSHAgent := flag.Bool("use-ssh-agent", false, "Source the SSH signers from $SSH_AUTH_SOCK instead of a key file. Recommended path when the fleet keypair lives in 1Password: enable the SSH Key item for 1Password's SSH agent in the GUI, then run with this flag.")
	ghRepo := flag.String("gh-repo", "tuist/tuist", "owner/repo to register the Actions runner against.")
	ghToken := flag.String("gh-token", "", "Actions runner registration token. Mint via:\n  gh api -X POST /repos/<owner>/<repo>/actions/runners/registration-token --jq .token")
	runnerName := flag.String("runner-name", "", "Runner name to register. Defaults to --hostname.")
	runnerLabels := flag.String("runner-labels", DefaultRunnerLabels, "Comma-separated runner labels.")
	runnerVersion := flag.String("runner-version", DefaultRunnerVersion, "actions/runner release to install.")
	buildCacheRoot := flag.String("build-cache-root", DefaultTuistMixBuildRoot, "TUIST_MIX_BUILD_ROOT to set in /etc/zshenv.")
	knownFingerprint := flag.String("known-fingerprint", "", "Persisted SHA256 host key. Empty on first bootstrap; the CLI prints the captured value.")
	noPasswordPrompt := flag.Bool("no-password-prompt", false, "Skip the m1-password TTY prompt. Use when re-bootstrapping a host past Scaleway's password-disclosure window: the upstream helpers' idempotency-only path skips sudo+kcpassword when their artefacts already exist.")
	flag.Parse()

	if err := requireFlags(map[string]string{
		"--ip":       *ip,
		"--hostname": *hostname,
		"--gh-token": *ghToken,
	}); err != nil {
		fmt.Fprintln(os.Stderr, err)
		flag.Usage()
		os.Exit(2)
	}
	switch {
	case *useSSHAgent && *sshKey != "":
		fmt.Fprintln(os.Stderr, "--ssh-key and --use-ssh-agent are mutually exclusive")
		os.Exit(2)
	case !*useSSHAgent && *sshKey == "":
		fmt.Fprintln(os.Stderr, "one of --ssh-key or --use-ssh-agent is required")
		flag.Usage()
		os.Exit(2)
	}

	var keyBytes []byte
	if *sshKey != "" {
		b, err := os.ReadFile(*sshKey)
		if err != nil {
			fatalf("read ssh key: %v", err)
		}
		keyBytes = b
	}

	var password string
	if !*noPasswordPrompt {
		p, err := promptPassword("m1 password (from Scaleway email): ")
		if err != nil {
			fatalf("read m1 password: %v", err)
		}
		password = p
	}

	cfg := Config{
		IP:                   *ip,
		SSHUser:              *sshUser,
		UserPassword:         password,
		SSHPrivateKey:        keyBytes,
		UseSSHAgent:          *useSSHAgent,
		Hostname:             *hostname,
		KnownHostFingerprint: *knownFingerprint,
		TuistMixBuildRoot:    *buildCacheRoot,
		GHRepo:               *ghRepo,
		GHToken:              *ghToken,
		RunnerName:           *runnerName,
		RunnerLabels:         *runnerLabels,
		RunnerVersion:        *runnerVersion,
		LogOut:               os.Stderr,
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	go func() {
		<-sigs
		fmt.Fprintln(os.Stderr, "\ninterrupt received, cancelling")
		cancel()
	}()

	fingerprint, err := Run(ctx, cfg)
	if fingerprint != "" {
		fmt.Printf("ssh-fingerprint: %s\n", fingerprint)
	}
	if err != nil {
		fatalf("bootstrap failed: %v", err)
	}
	fmt.Println("bootstrap complete")
	fmt.Println("Next step: trigger both image workflows on a throwaway branch and confirm")
	fmt.Println("the new host appears in tuist/tuist -> Settings -> Actions -> Runners.")
}

func requireFlags(flags map[string]string) error {
	missing := []string{}
	for name, value := range flags {
		if value == "" {
			missing = append(missing, name)
		}
	}
	if len(missing) == 0 {
		return nil
	}
	return fmt.Errorf("missing required flag(s): %s", strings.Join(missing, ", "))
}

// promptPassword reads from /dev/tty when possible so the password
// can't be captured in the parent shell's history or pipe buffer
// even if stdin is redirected. Falls back to stdin when no TTY is
// attached (e.g. CI dry-run).
func promptPassword(prompt string) (string, error) {
	fmt.Fprint(os.Stderr, prompt)
	tty, err := os.OpenFile("/dev/tty", os.O_RDONLY, 0)
	var fd int
	if err == nil {
		defer tty.Close()
		fd = int(tty.Fd())
	} else {
		fd = int(syscall.Stdin)
	}
	b, err := term.ReadPassword(fd)
	fmt.Fprintln(os.Stderr)
	if err != nil {
		return "", err
	}
	return string(b), nil
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
