// Command rack-card-password prints one password of a rack power card (a
// RackPDU's or a RackATS's), derived from the root key read from stdin the
// way the operator derives it, for a person who needs the card's web UI. The
// device's MAC comes from its site definition in infra/rack-switch-fleet. The
// root key is never printed.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackcard"
)

// rackCardHardware is the site definition's hardware of the devices the
// operator adopts the cards of.
var rackCardHardware = map[string]bool{"evmafc20a": true, "eats16n": true}

func main() {
	if err := run(os.Args[1:], os.Stdin, os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string, stdin io.Reader, stdout io.Writer) error {
	fs := flag.NewFlagSet("rack-card-password", flag.ContinueOnError)
	site := fs.String("site", "ber1", "the rack site")
	device := fs.String("device", "", "the PDU or transfer switch, as the site definition names it")
	role := fs.String("role", "admin", "admin, or controller for the operator's own account")
	sites := fs.String("sites", filepath.Join("..", "rack-switch-fleet", "sites"), "the directory of site definitions")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if fs.NArg() > 0 {
		return fmt.Errorf("unexpected arguments; the root key is read from stdin")
	}
	if *device == "" {
		return fmt.Errorf("--device is required")
	}
	var r rackcard.Role
	switch *role {
	case string(rackcard.RoleAdmin), string(rackcard.RoleController):
		r = rackcard.Role(*role)
	default:
		return fmt.Errorf("--role is admin or controller, not %q", *role)
	}

	definition, err := os.ReadFile(filepath.Join(*sites, *site+".json"))
	if err != nil {
		return fmt.Errorf("read the site definition: %w", err)
	}
	var parsed struct {
		Site  string `json:"site"`
		Nodes []struct {
			Name     string  `json:"name"`
			Hardware string  `json:"hardware"`
			MAC      *string `json:"mac"`
		} `json:"nodes"`
	}
	if err := json.Unmarshal(definition, &parsed); err != nil {
		return fmt.Errorf("parse the site definition: %w", err)
	}
	identity := ""
	for _, node := range parsed.Nodes {
		if node.Name != *device {
			continue
		}
		if !rackCardHardware[node.Hardware] {
			return fmt.Errorf("%s is a %s, not a PDU or transfer switch whose card the operator adopts", node.Name, node.Hardware)
		}
		mac := ""
		if node.MAC != nil {
			mac = *node.MAC
		}
		identity = rackcard.Identity(mac, node.Name)
	}
	if identity == "" {
		return fmt.Errorf("site %s has no device %s", parsed.Site, *device)
	}

	raw, err := io.ReadAll(io.LimitReader(stdin, 4096))
	if err != nil {
		return fmt.Errorf("read the root key: %w", err)
	}
	key, err := rackcard.ParseRootKey(raw)
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(stdout, rackcard.Password(key, parsed.Site, identity, r))
	return err
}
