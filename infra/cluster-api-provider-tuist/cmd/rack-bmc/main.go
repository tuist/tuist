// Command rack-bmc adopts and drives a rack x86 server through its BMC's
// Redfish: what the box is, its BIOS against the rack's baseline, its BMC
// passwords, its virtual CD, its next boot and its power.
//
//	rack-bmc -bmc https://192.168.1.248 inventory
//	rack-bmc -bmc https://192.168.1.248 check
//	rack-bmc -bmc https://192.168.1.248 apply
//	rack-bmc -bmc https://192.168.1.248 rotate Administrator <new-password-file
//	rack-bmc -bmc https://192.168.1.248 cd insert https://192.168.1.141/tuist_preinstall.iso
//	rack-bmc -bmc https://192.168.1.248 boot-once Cd
//	rack-bmc -bmc https://192.168.1.248 power cycle
//
// The BMC login is -user with the password in RACK_BMC_PASSWORD; a CD's
// server login is -media-user with RACK_BMC_MEDIA_PASSWORD.
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/redfish"
)

func main() {
	if err := run(context.Background(), os.Args[1:], os.Stdin, os.Stdout); err != nil {
		fmt.Fprintf(os.Stderr, "rack-bmc: %v\n", err)
		var drift driftError
		if errors.As(err, &drift) {
			os.Exit(3)
		}
		os.Exit(1)
	}
}

type driftError int

func (d driftError) Error() string {
	return fmt.Sprintf("%d settings differ from the baseline", int(d))
}

func run(ctx context.Context, args []string, stdin io.Reader, stdout io.Writer) error {
	fs := flag.NewFlagSet("rack-bmc", flag.ContinueOnError)
	endpoint := fs.String("bmc", "", "the BMC, https://<address>")
	user := fs.String("user", "admin", "the BMC account")
	fingerprint := fs.String("fingerprint", "", "SHA-256 of the BMC's certificate to pin")
	mediaUser := fs.String("media-user", "vm", "the CD server's account, for cd insert")
	asJSON := fs.Bool("json", false, "inventory as JSON")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *endpoint == "" || fs.NArg() == 0 {
		return errors.New("usage: rack-bmc -bmc https://<address> inventory|check|apply|rotate|cd|boot-once|power ...")
	}
	c := &redfish.Client{Endpoint: *endpoint, Username: *user, Password: os.Getenv("RACK_BMC_PASSWORD"), TLSFingerprint: *fingerprint}
	cmd, rest := fs.Arg(0), fs.Args()[1:]
	switch cmd {
	case "inventory":
		inv, err := c.Inventory(ctx)
		if err != nil {
			return err
		}
		if *asJSON {
			enc := json.NewEncoder(stdout)
			enc.SetIndent("", "  ")
			return enc.Encode(inv)
		}
		return writeSheet(stdout, inv)
	case "check", "apply":
		drift, err := c.Check(ctx, redfish.Baseline)
		if err != nil {
			return err
		}
		for _, d := range drift {
			fmt.Fprintf(stdout, "%s: have %v\n", d.What, d.Have)
		}
		if len(drift) == 0 {
			fmt.Fprintln(stdout, "the BIOS matches the baseline")
			return nil
		}
		if cmd == "check" {
			return driftError(len(drift))
		}
		if err := c.Apply(ctx, drift); err != nil {
			return err
		}
		fmt.Fprintln(stdout, "written; the BIOS applies it at its next POST")
		return nil
	case "rotate":
		if len(rest) != 1 {
			return errors.New("usage: rack-bmc rotate <account> <new-password")
		}
		password, err := bufio.NewReader(stdin).ReadString('\n')
		if err != nil && !errors.Is(err, io.EOF) {
			return err
		}
		return c.SetPassword(ctx, rest[0], strings.TrimRight(password, "\r\n"))
	case "cd":
		switch {
		case len(rest) == 2 && rest[0] == "insert":
			return c.InsertCD(ctx, redfish.Media{URL: rest[1], Username: *mediaUser, Password: os.Getenv("RACK_BMC_MEDIA_PASSWORD")})
		case len(rest) == 1 && rest[0] == "eject":
			return c.EjectCD(ctx)
		case len(rest) == 0:
			image, err := c.CD(ctx)
			if err == nil {
				fmt.Fprintln(stdout, image)
			}
			return err
		}
		return errors.New("usage: rack-bmc cd [insert <url> | eject]")
	case "boot-once":
		if len(rest) != 1 {
			return errors.New("usage: rack-bmc boot-once Cd|Pxe|Hdd|UefiHttp")
		}
		return c.BootOnce(ctx, rest[0])
	case "power":
		if len(rest) != 1 {
			return errors.New("usage: rack-bmc power state|on|off|shutdown|restart|cycle")
		}
		return power(ctx, c, rest[0], stdout)
	}
	return fmt.Errorf("unknown command %q", cmd)
}

func power(ctx context.Context, c *redfish.Client, action string, stdout io.Writer) error {
	switch action {
	case "state":
		state, err := c.PowerState(ctx)
		if err == nil {
			fmt.Fprintln(stdout, state)
		}
		return err
	case "on":
		return c.Reset(ctx, redfish.ResetOn)
	case "off":
		return c.Reset(ctx, redfish.ResetForceOff)
	case "shutdown":
		return c.Reset(ctx, redfish.ResetGracefulShutdown)
	case "restart":
		return c.Reset(ctx, redfish.ResetForceRestart)
	case "cycle":
		if err := c.Reset(ctx, redfish.ResetForceOff); err != nil {
			return err
		}
		if err := waitFor(ctx, c, "Off"); err != nil {
			return err
		}
		return c.Reset(ctx, redfish.ResetOn)
	}
	return fmt.Errorf("unknown power action %q", action)
}

var pollInterval = 2 * time.Second

func waitFor(ctx context.Context, c *redfish.Client, state string) error {
	deadline := time.Now().Add(2 * time.Minute)
	for {
		have, err := c.PowerState(ctx)
		if err != nil {
			return err
		}
		if have == state {
			return nil
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("the host is still %s after two minutes", have)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(pollInterval):
		}
	}
}

// writeSheet prints the unit sheet: what a vendor writes on a box's acceptance
// report and a host's declaration takes.
func writeSheet(w io.Writer, inv redfish.Inventory) error {
	fmt.Fprintf(w, "product: %s %s\n", inv.Manufacturer, inv.Model)
	fmt.Fprintf(w, "serial: %s\n", inv.Serial)
	fmt.Fprintf(w, "uuid: %s\n", inv.UUID)
	fmt.Fprintf(w, "bios: %s\nbmc: %s\n", inv.BIOSVersion, inv.BMCVersion)
	fmt.Fprintf(w, "bmc mac: %s\n", inv.BMCMAC)
	for _, n := range inv.NICs {
		fmt.Fprintf(w, "nic: %s %s\n", n.MAC, map[bool]string{true: "link", false: "no link"}[n.Link])
	}
	fmt.Fprintf(w, "tpm: %s\n", orNone(inv.TPM))
	fmt.Fprintf(w, "secure boot: set %t, last boot %t\n", inv.SecureBoot, inv.SecureBootActive)
	_, err := fmt.Fprintf(w, "power: %s\n", inv.PowerState)
	return err
}

func orNone(s string) string {
	if s == "" {
		return "none"
	}
	return s
}
