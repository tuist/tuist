// Command rack-node makes a rack Linux host the node its RackNodeConfig
// describes (internal/racknode).
//
//	rack-node apply   reads a racknode.Request on stdin and writes a Response
//	                  on stdout. The operator runs it over SSH to join a host.
//	rack-node agent   runs in the node agent's privileged pod on each rack node
//	                  and keeps the configuration in its RackLinuxMachine's
//	                  status applied, reporting there what it did.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
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
)

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: rack-node apply|agent")
		os.Exit(2)
	}
	var err error
	switch os.Args[1] {
	case "apply":
		err = apply(os.Stdin, os.Stdout)
	case "agent":
		err = agent(os.Args[2:])
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
