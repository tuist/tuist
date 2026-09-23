package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"syscall"
	"time"

	"sigs.k8s.io/yaml"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/converge"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
)

const applyUsage = `usage: rack-switch-controller apply --object <RackSwitch yaml> --omada-url <url> --site <omada site>
       --controller-address <tailnet ip> --credentials-dir <dir> [--enable-...]

Runs the reconciler's steps once for one object, without a cluster: the site
settings, adoption when the switch is pending, and every write its spec asks
for. It sees one object, so it checks no apply order.`

// runApply is `rack-switch-controller apply`.
func runApply(args []string, stdout, stderr io.Writer) int {
	fs := flag.NewFlagSet("apply", flag.ContinueOnError)
	fs.SetOutput(stderr)
	fs.Usage = func() {
		fmt.Fprintln(stderr, applyUsage)
		fs.PrintDefaults()
	}
	var object string
	var ef engineFlags
	fs.StringVar(&object, "object", "", "Path to a RackSwitch YAML")
	ef.register(fs, "site")
	if err := fs.Parse(args); err != nil {
		return 2
	}
	if object == "" {
		fs.Usage()
		return 2
	}

	rs, err := readRackSwitch(object)
	if err != nil {
		fmt.Fprintln(stderr, "error:", err)
		return 1
	}
	if rs.Spec.ManagedBy != v1alpha1.ManagedByController {
		fmt.Fprintf(stderr, "error: %s is not managedBy: controller; a standalone switch changes with rack:fleet apply\n", rs.Name)
		return 1
	}
	engine, credentials, err := ef.engine("site")
	if err != nil {
		fmt.Fprintln(stderr, "error:", err)
		return 2
	}
	creds, err := credentials()
	if err != nil {
		fmt.Fprintln(stderr, "error:", err)
		return 1
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	a := applier{engine: engine, creds: creds, out: stdout, poll: 5 * time.Second, now: time.Now}
	if err := a.run(ctx, rs); err != nil {
		fmt.Fprintln(stderr, "error:", err)
		return 1
	}
	return 0
}

func readRackSwitch(path string) (*v1alpha1.RackSwitch, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	var rs v1alpha1.RackSwitch
	if err := yaml.UnmarshalStrict(raw, &rs); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if rs.Kind != "RackSwitch" {
		return nil, fmt.Errorf("%s is a %q, not a RackSwitch", path, rs.Kind)
	}
	if rs.Spec.MAC == "" {
		return nil, fmt.Errorf("%s has no spec.mac, which is how the controller knows the switch", path)
	}
	return &rs, nil
}

type applier struct {
	engine *converge.Engine
	creds  converge.Credentials
	out    io.Writer
	poll   time.Duration
	now    func() time.Time
}

func (a *applier) run(ctx context.Context, rs *v1alpha1.RackSwitch) error {
	siteID, err := a.engine.SiteID(ctx)
	if err != nil {
		return err
	}
	changes, err := a.engine.EnsureSite(ctx, siteID, a.creds.DeviceAccount)
	a.print("site "+a.engine.Site, changes)
	if err != nil {
		return err
	}

	mac := omada.ControllerMAC(rs.Spec.MAC)
	var attempt *converge.Attempt
	for {
		dev, err := a.engine.Find(ctx, siteID, rs.Spec.MAC)
		if err != nil {
			return err
		}
		if dev == nil {
			return fmt.Errorf("%s (%s) is not in the Omada site %q; point it at the controller with rack:omada inform", rs.Name, mac, a.engine.Site)
		}
		if dev.Status == omada.StatusConnected {
			if attempt != nil {
				fmt.Fprintf(a.out, "%s is adopted with %s\n", rs.Name, attempt.Login)
			}
			break
		}
		if attempt == nil && dev.Status != omada.StatusPending {
			return fmt.Errorf("the controller reports %s %s", rs.Name, dev.State())
		}
		adoption, err := a.engine.Adopt(ctx, siteID, *dev, attempt, a.creds, a.now())
		for _, note := range adoption.Notes {
			fmt.Fprintf(a.out, "%s: %s\n", rs.Name, note.Message)
		}
		if err != nil {
			return err
		}
		if adoption.Outcome != converge.AdoptionWaiting {
			return errors.New(adoption.Notes[len(adoption.Notes)-1].Message)
		}
		attempt = adoption.Attempt
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(a.poll):
		}
	}

	report, err := a.engine.Converge(ctx, siteID, rs, true)
	a.print(fmt.Sprintf("%s (%s)", rs.Name, mac), report.Changes)
	if err != nil {
		return err
	}
	if len(report.Drift) > 0 {
		fmt.Fprintf(a.out, "%s still differs from its spec:\n", rs.Name)
		for _, d := range report.Drift {
			fmt.Fprintf(a.out, "  %s\n", d)
		}
		return fmt.Errorf("%s does not match revision %s", rs.Name, rs.Spec.ConfigRevision)
	}
	fmt.Fprintf(a.out, "%s matches revision %s as far as the API reads back\n", rs.Name, rs.Spec.ConfigRevision)
	fmt.Fprintf(a.out, "verify the rest with: mise run rack:fleet diff %s\n", rs.Name)
	return nil
}

func (a *applier) print(subject string, changes []converge.Change) {
	if len(changes) == 0 {
		fmt.Fprintf(a.out, "%s: nothing to write\n", subject)
		return
	}
	fmt.Fprintf(a.out, "%s:\n", subject)
	for _, c := range changes {
		fmt.Fprintf(a.out, "  %s\n", c)
	}
}
