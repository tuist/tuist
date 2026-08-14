// Command tuist-log-shipper tails host log files on a Mac mini and pushes the
// lines to a Loki-compatible endpoint over the tailnet.
//
// Installed by the CAPI provider's macOS bootstrap as the launchd daemon
// `dev.tuist.log-shipper`, alongside node_exporter. See
// infra/macos-log-shipper/AGENTS.md.
package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/macos-log-shipper/internal/shipper"
)

// fileFlag collects repeated `--file <job>=<path>` arguments.
type fileFlag []shipper.Source

func (f *fileFlag) String() string {
	parts := make([]string, 0, len(*f))
	for _, source := range *f {
		parts = append(parts, source.Job+"="+source.Path)
	}
	return strings.Join(parts, ",")
}

func (f *fileFlag) Set(value string) error {
	job, path, ok := strings.Cut(value, "=")
	if !ok || job == "" || path == "" {
		return fmt.Errorf("expected <job>=<path>, got %q", value)
	}
	*f = append(*f, shipper.Source{Job: job, Path: path})
	return nil
}

func main() {
	var (
		files     fileFlag
		url       string
		instance  string
		env       string
		positions string
	)
	flag.Var(&files, "file",
		"Log file to tail, as <job>=<path>. Repeatable. The job name becomes the "+
			"stream's `job` label, so it is what a Loki query selects on "+
			"(e.g. tuist-macos-tart-kubelet=/var/log/tart-kubelet.log).")
	flag.StringVar(&url, "url", "",
		"Loki push endpoint, including the /loki/api/v1/push path. Points at the "+
			"in-cluster Alloy receiver's tailnet hostname; Alloy holds the Grafana "+
			"Cloud credentials so this host carries none.")
	flag.StringVar(&instance, "instance", "",
		"Value of the `instance` label — the Node / CAPI Machine name, so a line "+
			"can be tied back to a specific Mac mini. Defaults to the hostname, "+
			"which the bootstrap sets to the Machine name.")
	flag.StringVar(&env, "env", "",
		"Value of the `env` label (staging / canary / production). Empty omits it.")
	flag.StringVar(&positions, "positions", "/var/lib/tuist-log-shipper/positions.json",
		"Where read offsets are persisted so a restart resumes instead of "+
			"re-shipping or skipping.")
	flag.Parse()

	if url == "" {
		log.Fatal("--url is required")
	}
	if len(files) == 0 {
		log.Fatal("at least one --file is required")
	}
	if instance == "" {
		hostname, err := os.Hostname()
		if err != nil {
			log.Fatalf("resolve hostname for --instance: %v", err)
		}
		instance = hostname
	}

	labels := map[string]string{"instance": instance}
	if env != "" {
		labels["env"] = env
	}

	agent, err := shipper.New(shipper.Options{
		Sources:    files,
		BaseLabels: labels,
		Positions:  shipper.LoadPositions(positions),
		Client: &shipper.Client{
			URL: url,
			// A bounded timeout, not the default's absence of one: a push that
			// hangs against a half-open tailnet connection would otherwise stall
			// this file's tail indefinitely, which looks identical to "the host
			// stopped logging".
			HTTP: &http.Client{Timeout: 30 * time.Second},
		},
	})
	if err != nil {
		log.Fatalf("start log shipper: %v", err)
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	log.Printf("shipping %s to %s as instance=%s", files.String(), url, instance)
	agent.Run(ctx)
}
