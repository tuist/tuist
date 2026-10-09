// Command prep makes a pre-ordered bare-metal box claimable: it registers the
// fleet key with the provider and kicks off a clean OS install (Ubuntu + the
// fleet key + the bootstrap login), so the controller can self-join the box on
// the next claim with no hand-installing.
//
// The OVH template supplies the bootstrap account; the installer receives its
// authorized SSH key. This command only starts the install. Run it through
// baremetal:prep-ovh and poll the provider console for completion.
package main

import (
	"context"
	"flag"
	"fmt"
	"os"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

func main() {
	provider := flag.String("provider", "", "ovh")
	fleet := flag.String("fleet", "", "fleet name; the SSH key is registered under it (OVH) and is the default hostname")
	pubKey := flag.String("pubkey", "", "fleet public key in authorized_keys form (the <fleet>-ssh Secret's id_ed25519.pub)")
	server := flag.String("server", "", "OVH service name (nsXXXXXX.ip-...)")
	osLabel := flag.String("os", "ubuntu_24.04", "OS label to install")
	hostname := flag.String("hostname", "", "install hostname (default: the fleet name)")
	flag.Parse()

	if *provider == "" || *fleet == "" || *pubKey == "" || *server == "" {
		fmt.Fprintln(os.Stderr, "usage: prep --provider ovh --fleet <name> --pubkey <key> --server <service> [--os ubuntu_24.04]")
		os.Exit(2)
	}
	if *hostname == "" {
		*hostname = *fleet
	}

	var err error
	switch *provider {
	case "ovh":
		err = prepOVH(context.Background(), *pubKey, *server, *osLabel, *hostname)
	default:
		err = fmt.Errorf("unknown provider %q (want ovh)", *provider)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "prep failed: %v\n", err)
		os.Exit(1)
	}
	fmt.Printf("✓ install kicked off on %s %s — poll the provider console; once installed, tag/name it into the pool and the fleet self-joins it.\n", *provider, *server)
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
