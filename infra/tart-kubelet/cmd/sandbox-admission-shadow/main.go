// sandbox-admission-shadow consumes one trusted host observation per JSON line.
// It never talks to the cluster or changes reservations, Pods or VMs.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"os"
	"time"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/sandboxpolicy"
)

func main() {
	grace := flag.Duration("warm-grace", sandboxpolicy.DefaultWarmGrace, "idle grace (capped at 60s, bypassed when CI queues)")
	flag.Parse()
	decoder := json.NewDecoder(os.Stdin)
	decoder.DisallowUnknownFields()
	encoder := json.NewEncoder(os.Stdout)
	for {
		var o sandboxpolicy.Observation
		if err := decoder.Decode(&o); err == io.EOF {
			return
		} else if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		if err := encoder.Encode(sandboxpolicy.Evaluate(time.Now(), *grace, o)); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	}
}
