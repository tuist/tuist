// Command prep makes a pre-ordered bare-metal box claimable: it installs a clean
// OS (Ubuntu + the fleet key + the bootstrap login) and, for Dedibox, configures
// passwordless sudo for the login — so the controller can self-join the box on the
// next claim with no hand-installing.
//
// The Scaleway Dedibox install grants the created user only *password* sudo, but
// the self-join shells in non-interactively and `sudo`s, so prep installs with a
// known password, waits for the install, then drops a NOPASSWD sudoers file over
// SSH (mirroring the macOS fleet's prepare-fleet-host). It reuses the same Dedibox/
// OVH clients the reconciler's release-path reinstall uses. Run it through the mise
// wrappers (baremetal:prep-dedibox / prep-ovh).
package main

import (
	"context"
	"crypto/rand"
	"flag"
	"fmt"
	"net"
	"os"
	"strconv"
	"strings"
	"time"

	"golang.org/x/crypto/ssh"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/dedibox"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

func main() {
	provider := flag.String("provider", "", "dedibox | ovh")
	fleet := flag.String("fleet", "", "fleet name; the SSH key is registered under it (OVH) and is the default hostname")
	pubKey := flag.String("pubkey", "", "fleet public key in authorized_keys form (the <fleet>-ssh Secret's id_ed25519.pub)")
	privKey := flag.String("privkey", "", "path to the fleet private key (the <fleet>-ssh Secret's id_ed25519); used to set NOPASSWD sudo over SSH")
	server := flag.String("server", "", "Dedibox numeric server id, or OVH service name (nsXXXXXX.ip-...)")
	zone := flag.String("zone", "", "Dedibox zone (fr-par-1 | fr-par-2 | nl-ams-1); auto-detected if empty")
	osLabel := flag.String("os", "ubuntu_24.04", "OS label to install")
	user := flag.String("user", "", "bootstrap login the install creates (default: tuist for dedibox, ubuntu for ovh)")
	hostname := flag.String("hostname", "", "install hostname (default: the fleet name)")
	flag.Parse()

	if *provider == "" || *fleet == "" || *pubKey == "" || *server == "" {
		fmt.Fprintln(os.Stderr, "usage: prep --provider <dedibox|ovh> --fleet <name> --pubkey <key> --privkey <path> --server <id|service> [--zone z] [--os ubuntu_24.04]")
		os.Exit(2)
	}
	if *hostname == "" {
		*hostname = *fleet
	}

	var err error
	switch *provider {
	case "dedibox":
		err = prepDedibox(context.Background(), *fleet, *pubKey, *privKey, *server, *zone, *osLabel, firstNonEmpty(*user, "tuist"), *hostname)
	case "ovh":
		err = prepOVH(context.Background(), *pubKey, *server, *osLabel, *hostname)
	default:
		err = fmt.Errorf("unknown provider %q (want dedibox|ovh)", *provider)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "prep failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("✓ %s %s prepped — tag/name it into the pool and the fleet self-joins it.\n", *provider, *server)
}

func prepDedibox(ctx context.Context, fleet, pubKey, privKeyPath, server, zone, osLabel, user, hostname string) error {
	if privKeyPath == "" {
		return fmt.Errorf("--privkey is required for dedibox (needed to set NOPASSWD sudo after install)")
	}
	id, err := strconv.ParseUint(server, 10, 64)
	if err != nil {
		return fmt.Errorf("dedibox --server must be a numeric id: %w", err)
	}
	client, err := dedibox.NewClientFromEnv()
	if err != nil {
		return err
	}
	if zone == "" {
		for _, z := range []string{"fr-par-1", "fr-par-2", "nl-ams-1"} {
			if _, e := client.GetServer(ctx, z, id); e == nil {
				zone = z
				break
			}
		}
		if zone == "" {
			return fmt.Errorf("server %d not found in any Dedibox zone", id)
		}
	}
	sshKeyID, err := client.RegisterSSHKey(ctx, fleet, pubKey)
	if err != nil {
		return fmt.Errorf("register fleet key: %w", err)
	}
	osChoice, err := client.ResolveOS(ctx, zone, id, osLabel)
	if err != nil {
		return fmt.Errorf("resolve OS %q: %w", osLabel, err)
	}
	password, err := randomPassword()
	if err != nil {
		return err
	}
	if err := client.StartInstall(ctx, dedibox.InstallParams{
		Zone:         zone,
		ServerID:     id,
		OS:           osChoice,
		Hostname:     hostname,
		UserLogin:    user,
		UserPassword: password,
		SSHKeyIDs:    []string{sshKeyID},
	}); err != nil {
		return err
	}
	fmt.Printf("install kicked off on dedibox %d (%s); waiting for it to finish…\n", id, zone)
	if err := waitDediboxInstall(ctx, client, zone, id); err != nil {
		return err
	}
	srv, err := client.GetServer(ctx, zone, id)
	if err != nil {
		return err
	}
	if srv.PublicIP == "" {
		return fmt.Errorf("server %d has no public IP after install", id)
	}
	fmt.Printf("install done; setting NOPASSWD sudo for %s@%s…\n", user, srv.PublicIP)
	return setNoPasswdSudo(srv.PublicIP, user, privKeyPath, password)
}

func prepOVH(ctx context.Context, pubKey, service, osLabel, hostname string) error {
	client, err := ovh.NewClientFromEnv()
	if err != nil {
		return err
	}
	template, err := client.ResolveTemplate(ctx, service, osLabel)
	if err != nil {
		return fmt.Errorf("resolve template %q: %w", osLabel, err)
	}
	return client.StartInstall(ctx, service, ovh.InstallParams{
		TemplateName: template,
		Hostname:     hostname,
		SSHKey:       pubKey,
	})
}

// waitDediboxInstall polls the install until it is done, up to ~50 min.
func waitDediboxInstall(ctx context.Context, client *dedibox.Client, zone string, id uint64) error {
	for i := 0; i < 100; i++ {
		state, err := client.InstallState(ctx, zone, id)
		if err != nil {
			return err
		}
		switch state {
		case dedibox.InstallDone:
			return nil
		case dedibox.InstallFailed:
			return fmt.Errorf("dedibox install failed for server %d", id)
		}
		time.Sleep(30 * time.Second)
	}
	return fmt.Errorf("dedibox install for server %d did not finish in time", id)
}

// setNoPasswdSudo SSHes in as the bootstrap user with the fleet key and drops a
// NOPASSWD sudoers file, escalating with the install-set password via `sudo -S`.
// Retries the dial since the box reboots into the fresh OS right after install.
func setNoPasswdSudo(host, user, privKeyPath, password string) error {
	pem, err := os.ReadFile(privKeyPath)
	if err != nil {
		return fmt.Errorf("read private key: %w", err)
	}
	signer, err := ssh.ParsePrivateKey(pem)
	if err != nil {
		return fmt.Errorf("parse private key: %w", err)
	}
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            []ssh.AuthMethod{ssh.PublicKeys(signer)},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         15 * time.Second,
	}
	var conn *ssh.Client
	for i := 0; i < 20; i++ {
		if c, e := ssh.Dial("tcp", net.JoinHostPort(host, "22"), cfg); e == nil {
			conn = c
			break
		}
		time.Sleep(15 * time.Second)
	}
	if conn == nil {
		return fmt.Errorf("ssh %s@%s unreachable after install", user, host)
	}
	defer conn.Close()
	session, err := conn.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()
	write := fmt.Sprintf("echo '%s ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/90-%s-nopasswd && chmod 440 /etc/sudoers.d/90-%s-nopasswd", user, user, user)
	cmd := fmt.Sprintf("echo %s | sudo -S sh -c %s", shellSingleQuote(password), shellSingleQuote(write))
	if out, runErr := session.CombinedOutput(cmd); runErr != nil {
		return fmt.Errorf("set NOPASSWD sudo: %w (output: %s)", runErr, strings.TrimSpace(string(out)))
	}
	return nil
}

// randomPassword returns a 14-char alphanumeric password (the Dedibox install API
// caps passwords at 15 chars and rejects symbols).
func randomPassword() (string, error) {
	const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789"
	b := make([]byte, 14)
	if _, err := rand.Read(b); err != nil {
		return "", fmt.Errorf("generate password: %w", err)
	}
	for i := range b {
		b[i] = alphabet[int(b[i])%len(alphabet)]
	}
	return string(b), nil
}

func shellSingleQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func firstNonEmpty(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
