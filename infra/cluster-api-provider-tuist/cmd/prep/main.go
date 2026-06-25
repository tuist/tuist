// Command prep makes a pre-ordered bare-metal box claimable: it registers the
// fleet's SSH key with the provider and kicks off a clean OS install (Ubuntu +
// the fleet key + the bootstrap login), so the operator never hand-installs a box.
// Once the install finishes the box can be tagged/named into the pool and the
// controller self-joins it on adoption.
//
// It reuses the same provider clients the reconciler's release-path reinstall
// uses, so the install body (Dedibox partitioning, OVH template resolution) stays
// in one place. Run it through the mise wrapper (baremetal:prep-dedibox /
// prep-ovh), which sources creds + the fleet pubkey for you.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"
	"strconv"
	"time"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/dedibox"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

func main() {
	provider := flag.String("provider", "", "dedibox | ovh")
	fleet := flag.String("fleet", "", "fleet name; the SSH key is registered under it (OVH) and it is the default hostname")
	pubKey := flag.String("pubkey", "", "fleet public key in authorized_keys format (from the <fleet>-ssh Secret's id_ed25519.pub)")
	server := flag.String("server", "", "Dedibox numeric server id, or OVH service name (nsXXXXXX.ip-...)")
	zone := flag.String("zone", "", "Dedibox zone (fr-par-1 | fr-par-2 | nl-ams-1); ignored for OVH")
	osLabel := flag.String("os", "ubuntu_24.04", "OS label to install")
	user := flag.String("user", "", "bootstrap login the install creates (default: tuist for dedibox, ubuntu for ovh)")
	hostname := flag.String("hostname", "", "install hostname (default: the fleet name)")
	flag.Parse()

	if *provider == "" || *fleet == "" || *pubKey == "" || *server == "" {
		fmt.Fprintln(os.Stderr, "usage: prep --provider <dedibox|ovh> --fleet <name> --pubkey <authorized_key> --server <id|service> [--zone z] [--os ubuntu_24.04]")
		os.Exit(2)
	}
	if *hostname == "" {
		*hostname = *fleet
	}

	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()

	var err error
	switch *provider {
	case "dedibox":
		err = prepDedibox(ctx, *fleet, *pubKey, *server, *zone, *osLabel, firstNonEmpty(*user, "tuist"), *hostname)
	case "ovh":
		err = prepOVH(ctx, *pubKey, *server, *osLabel, *hostname)
	default:
		err = fmt.Errorf("unknown provider %q (want dedibox|ovh)", *provider)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "prep failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("✓ install kicked off on %s %s — poll the provider console; once it finishes, tag/name it into the pool and the fleet self-joins it.\n", *provider, *server)
}

func prepDedibox(ctx context.Context, fleet, pubKey, server, zone, osLabel, user, hostname string) error {
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
	return client.StartInstall(ctx, dedibox.InstallParams{
		Zone:      zone,
		ServerID:  id,
		OS:        osChoice,
		Hostname:  hostname,
		UserLogin: user,
		SSHKeyIDs: []string{sshKeyID},
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
