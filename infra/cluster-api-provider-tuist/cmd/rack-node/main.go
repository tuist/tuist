// Command rack-node makes a rack Linux host the node its RackNodeConfig
// describes (internal/racknode).
//
//	rack-node apply   reads a racknode.Request on stdin and writes a Response
//	                  on stdout. The operator runs it over SSH to join a host.
//	rack-node agent   runs in the node agent's privileged pod on each rack node
//	                  and keeps the configuration in its RackLinuxMachine's
//	                  status applied, reporting there what it did.
//	rack-node ek      prints the TPM's RSA endorsement key, base64 PKIX DER.
//	                  The install stick announces it, and the operator reads
//	                  it over SSH from an installed host.
//	rack-node seed --server URL --out FILE MAC...
//	                  asks the site's boot server for the seed published under
//	                  one of the MACs (hyphenated), through the TPM when the
//	                  host's is pinned, writes it to FILE and prints the MAC.
//	                  It exits 4 when nothing is published under any.
package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"k8s.io/client-go/rest"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/racknode"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/rackseed"
)

// notPublished is rack-node seed's exit status when nothing is published
// under any of the MACs.
const notPublished = 4

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: rack-node apply|agent|ek|seed")
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "apply":
		err = apply(os.Stdin, os.Stdout)
	case "agent":
		err = agent(os.Args[2:])
	case "ek":
		err = printEK(os.Stdout)
	case "seed":
		var published bool
		if published, err = seed(os.Args[2:], os.Stdout); err == nil && !published {
			os.Exit(notPublished)
		}
	default:
		err = fmt.Errorf("unknown command %q", os.Args[1])
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "rack-node: %v\n", err)
		os.Exit(1)
	}
}

func apply(stdin io.Reader, stdout io.Writer) error {
	body, err := io.ReadAll(io.LimitReader(stdin, 4<<20))
	if err != nil {
		return err
	}
	var req racknode.Request
	if err := json.Unmarshal(body, &req); err != nil {
		return fmt.Errorf("read the request: %w", err)
	}
	host := racknode.LocalHost{}
	unlock, err := host.Lock()
	if err != nil {
		return err
	}
	defer unlock()
	res, applyErr := racknode.Apply(context.Background(), host, req, racknode.Options{})
	resp := racknode.Response{Result: res}
	if applyErr != nil {
		resp.Error = applyErr.Error()
	}
	return json.NewEncoder(stdout).Encode(resp)
}

func agent(args []string) error {
	fs := flag.NewFlagSet("agent", flag.ContinueOnError)
	root := fs.String("host-root", "/proc/1/root", "the host's root, as the privileged pod sees it")
	namespace := fs.String("namespace", os.Getenv("POD_NAMESPACE"), "the namespace of the rack's RackLinuxMachines")
	node := fs.String("node", os.Getenv("NODE_NAME"), "the node the agent runs on")
	apiFile := fs.String("kubernetes-api-file", "/etc/tuist/kubernetes-api", "a file on the node naming the API server its kubelet uses")
	interval := fs.Duration("interval", 30*time.Second, "how often the agent looks for a new configuration")
	reapply := fs.Duration("reapply", 5*time.Minute, "how often the agent applies an unchanged configuration, repairing drift")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *namespace == "" || *node == "" {
		return fmt.Errorf("--namespace and --node are required")
	}
	cfg, err := rest.InClusterConfig()
	if err != nil {
		return err
	}
	if server, err := os.ReadFile(*apiFile); err == nil && strings.TrimSpace(string(server)) != "" {
		cfg.Host = strings.TrimSpace(string(server))
	}
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		return err
	}
	if err := infrav1.AddToScheme(scheme); err != nil {
		return err
	}
	c, err := client.New(cfg, client.Options{Scheme: scheme})
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	a := &racknode.Agent{Client: c, Host: racknode.LocalHost{Root: *root}, Namespace: *namespace, Node: *node, Reapply: *reapply}
	ticker := time.NewTicker(*interval)
	defer ticker.Stop()
	for {
		if err := a.Once(ctx); err != nil {
			fmt.Fprintf(os.Stderr, "rack-node: %v\n", err)
		}
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

func printEK(stdout io.Writer) error {
	tpm, err := rackseed.Open()
	if err != nil {
		return err
	}
	defer tpm.Close()
	ek, err := tpm.EK()
	if err != nil {
		return err
	}
	_, err = fmt.Fprintln(stdout, base64.StdEncoding.EncodeToString(ek))
	return err
}

// seed asks for the seed published under the first of the MACs that has
// one, and reports whether one had.
func seed(args []string, stdout io.Writer) (bool, error) {
	fs := flag.NewFlagSet("seed", flag.ContinueOnError)
	server := fs.String("server", "", "the site's boot server, http://<provisioning address>:<port>")
	out := fs.String("out", "", "where to write the seed")
	if err := fs.Parse(args); err != nil {
		return false, err
	}
	if *server == "" || *out == "" || fs.NArg() == 0 {
		return false, errors.New("usage: rack-node seed --server URL --out FILE MAC...")
	}
	a := &rackseed.Asker{Client: &http.Client{Timeout: 30 * time.Second}, Server: *server, OpenTPM: rackseed.Open}
	defer a.Close()
	var errs []error
	for _, mac := range fs.Args() {
		seed, err := a.Ask(context.Background(), strings.ToLower(mac))
		switch {
		case errors.Is(err, rackseed.ErrNotPublished):
			continue
		case err != nil:
			errs = append(errs, fmt.Errorf("%s: %w", mac, err))
			continue
		}
		if err := os.WriteFile(*out+".new", seed, 0o600); err != nil {
			return false, err
		}
		if err := os.Rename(*out+".new", *out); err != nil {
			return false, err
		}
		_, err = fmt.Fprintln(stdout, mac)
		return true, err
	}
	return false, errors.Join(errs...)
}
