// Command prep makes a pre-ordered bare-metal box claimable: it registers the
// fleet key with the provider and kicks off a clean OS install (Ubuntu + the
// fleet key + the bootstrap login), so the controller can self-join the box on
// the next claim with no hand-installing.
//
// Passwordless sudo is NOT configured here. The install sets the login user's
// password to the fleet sudo password, and the controller's self-join uses it
// once (via `sudo -S`) to drop a NOPASSWD sudoers file before the rest of the
// bootstrap — so NOPASSWD is established by the self-join itself and survives any
// reinstall, with no post-install SSH step. prep just fires the install; poll the
// provider console for done. It reuses the same provider clients the reconciler
// uses. Run it through the mise wrappers (baremetal:prep-dedibox / prep-ovh).
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strconv"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/dedibox"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

func main() {
	provider := flag.String("provider", "", "dedibox | ovh")
	fleet := flag.String("fleet", "", "fleet name; the SSH key is registered under it (OVH) and is the default hostname")
	pubKey := flag.String("pubkey", "", "fleet public key in authorized_keys form (the <fleet>-ssh Secret's id_ed25519.pub)")
	sudoPassword := flag.String("sudo-password", "", "fleet sudo password (the <fleet>-ssh Secret's sudo-password); set as the login password so the self-join can establish NOPASSWD sudo")
	server := flag.String("server", "", "Dedibox numeric server id, or OVH service name (nsXXXXXX.ip-...)")
	zone := flag.String("zone", "", "Dedibox zone (fr-par-1 | fr-par-2 | nl-ams-1); auto-detected if empty")
	osLabel := flag.String("os", "ubuntu_24.04", "OS label to install")
	user := flag.String("user", "", "bootstrap login the install creates (default: tuist for dedibox, ubuntu for ovh)")
	hostname := flag.String("hostname", "", "install hostname (default: the fleet name)")
	flag.Parse()

	if *provider == "" || *fleet == "" || *pubKey == "" || *server == "" {
		fmt.Fprintln(os.Stderr, "usage: prep --provider <dedibox|ovh> --fleet <name> --pubkey <key> --server <id|service> [--sudo-password p] [--zone z] [--os ubuntu_24.04]")
		os.Exit(2)
	}
	if *hostname == "" {
		*hostname = *fleet
	}

	var err error
	switch *provider {
	case "dedibox":
		err = prepDedibox(context.Background(), *fleet, *pubKey, *sudoPassword, *server, *zone, *osLabel, firstNonEmpty(*user, "tuist"), *hostname)
	case "ovh":
		err = prepOVH(context.Background(), *pubKey, *server, *osLabel, *hostname)
	default:
		err = fmt.Errorf("unknown provider %q (want dedibox|ovh)", *provider)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "prep failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("✓ install kicked off on %s %s — poll the provider console; once installed, tag/name it into the pool and the fleet self-joins it.\n", *provider, *server)
}

func prepDedibox(ctx context.Context, fleet, pubKey, sudoPassword, server, zone, osLabel, user, hostname string) error {
	if sudoPassword == "" {
		return fmt.Errorf("--sudo-password is required for dedibox (the self-join uses it to establish NOPASSWD sudo)")
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
	// Set the login password to the fleet sudo password; the self-join escalates
	// with it once to drop the NOPASSWD sudoers file.
	return client.StartInstall(ctx, dedibox.InstallParams{
		Zone:         zone,
		ServerID:     id,
		OS:           osChoice,
		Hostname:     hostname,
		UserLogin:    user,
		UserPassword: sudoPassword,
		SSHKeyIDs:    []string{sshKeyID},
	})
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

func firstNonEmpty(a, b string) string {
	if a != "" {
		return a
	}
	return b
}
