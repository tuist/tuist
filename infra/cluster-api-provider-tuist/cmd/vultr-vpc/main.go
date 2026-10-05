// Command vultr-vpc plans or creates a regional VPC without touching hosts.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net/netip"
	"os"
	"os/signal"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/vultr"
)

func main() {
	region := flag.String("region", "", "Vultr location (ord, scl)")
	description := flag.String("description", "", "unique, environment-scoped VPC name")
	cidr := flag.String("cidr", "", "private IPv4 subnet; check cluster, host and tailnet overlaps before attachment")
	apply := flag.Bool("apply", false, "create an empty VPC if missing; never attach or restart hosts")
	flag.Parse()
	if err := run(*region, *description, *cidr, *apply); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func run(region, description, cidr string, apply bool) error {
	prefix, err := netip.ParsePrefix(cidr)
	if err != nil {
		return fmt.Errorf("parse --cidr: %w", err)
	}
	client, err := vultr.NewClientFromEnv()
	if err != nil {
		return err
	}
	ctx, cancel := signal.NotifyContext(context.Background(), os.Interrupt)
	defer cancel()
	network, err := client.EnsureVPC(ctx, vultr.VPC{Region: region, Description: description, Subnet: prefix.Addr().String(), Mask: prefix.Bits()}, apply)
	if err != nil {
		return err
	}
	return json.NewEncoder(os.Stdout).Encode(struct {
		Exists  bool       `json:"exists"`
		Network *vultr.VPC `json:"network"`
	}{network.ID != "", network})
}
