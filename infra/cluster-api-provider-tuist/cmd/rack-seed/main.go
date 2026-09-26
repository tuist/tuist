// Command rack-seed renders a rack Linux host's Ubuntu autoinstall seed, the
// one the operator publishes for a netboot install, into a directory for
// rack:write-install-usb to bake into a stick. The console password is read
// from stdin, and the installed system hashes it.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackinstall"
)

func main() {
	if err := run(os.Args[1:], os.Stdin); err != nil {
		fmt.Fprintf(os.Stderr, "error: %v\n", err)
		os.Exit(1)
	}
}

func run(args []string, stdin io.Reader) error {
	fs := flag.NewFlagSet("rack-seed", flag.ContinueOnError)
	out := fs.String("out", "", "directory to write user-data, meta-data and vendor-data to")
	host := fs.String("host", "", "the host's name")
	role := fs.String("role", "", "the host's role")
	user := fs.String("user", "tuist", "the account the install creates")
	tags := fs.String("tags", "", "the host's tailnet tags, comma-separated")
	keysFile := fs.String("authorized-keys", "", "file of SSH public keys to authorize, one per line")
	keyFile := fs.String("tailnet-key-file", "", "file holding the single-use tailnet join key")
	keyID := fs.String("tailnet-key-id", "", "the join key's ID")
	stickServer := fs.String("stick-server", "", "render the seed of a stick that installs any host, which asks the boot server at this address for the install published for the machine, instead of one host's")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *out == "" {
		return fmt.Errorf("-out is required")
	}
	if *stickServer != "" {
		return writeStickSeed(*out, *stickServer)
	}

	password, err := io.ReadAll(io.LimitReader(stdin, 4096))
	if err != nil {
		return fmt.Errorf("read the console password: %w", err)
	}
	trimmed := strings.TrimRight(string(password), "\r\n")
	if trimmed == "" {
		return fmt.Errorf("no console password on stdin")
	}
	keys, err := readLines(*keysFile)
	if err != nil {
		return fmt.Errorf("read the authorized keys: %w", err)
	}
	tailnetKey, err := os.ReadFile(*keyFile)
	if err != nil {
		return fmt.Errorf("read the tailnet key: %w", err)
	}
	var tagList []string
	for _, t := range strings.Split(*tags, ",") {
		if t = strings.TrimSpace(t); t != "" {
			tagList = append(tagList, t)
		}
	}

	seed := rackinstall.Seed{
		Host:            *host,
		Role:            *role,
		User:            *user,
		ConsolePassword: trimmed,
		AuthorizedKeys:  keys,
		TailnetTags:     tagList,
		TailnetKey:      strings.TrimSpace(string(tailnetKey)),
		TailnetKeyID:    *keyID,
		Built:           time.Now(),
	}
	userData, err := rackinstall.UserData(seed)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(*out, 0o700); err != nil {
		return err
	}
	for name, content := range map[string]string{
		"user-data":   userData,
		"meta-data":   rackinstall.MetaData(seed),
		"vendor-data": "",
	} {
		if err := os.WriteFile(filepath.Join(*out, name), []byte(content), 0o600); err != nil {
			return err
		}
	}
	return nil
}

func writeStickSeed(out, server string) error {
	userData, err := rackinstall.StickUserData(server)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(out, 0o755); err != nil {
		return err
	}
	for name, content := range map[string]string{
		"user-data":             userData,
		"meta-data":             rackinstall.StickMetaData(),
		"vendor-data":           "",
		"network-config":        rackinstall.StickNetworkConfig(),
		rackinstall.StickMarker: "",
	} {
		if err := os.WriteFile(filepath.Join(out, name), []byte(content), 0o644); err != nil {
			return err
		}
	}
	return nil
}

func readLines(path string) ([]string, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	var lines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		if line := strings.TrimSpace(scanner.Text()); line != "" {
			lines = append(lines, line)
		}
	}
	return lines, scanner.Err()
}
