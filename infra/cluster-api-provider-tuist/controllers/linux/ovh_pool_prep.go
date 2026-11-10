package linux

import (
	"context"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

// A box's displayName drives its prep, and records how far it got, so a
// restart or a leader change resumes it from OVH alone:
//
//	prep-<prefix>              a person asks for the box to be prepped for the
//	                           fleet whose adoptDisplayNamePrefix is <prefix>
//	prepping-<id>-<prefix>     the controller claimed it; <id> is the newest
//	                           install task the box had before, so a later one
//	                           is the controller's own
//	<prefix>                   prepped: the fleet adopts it
//	prep-failed-<prefix>       the install failed; rename it to prep-<prefix>
//	                           to try again
//
// None of the markers starts with a prefix, so no fleet adopts a box mid-prep.
const (
	ovhPrepRequestedPrefix  = "prep-"
	ovhPrepInstallingPrefix = "prepping-"
	ovhPrepFailedPrefix     = "prep-failed-"
)

// ovhPrepAPI is the slice of the OVH client the prep pass uses.
type ovhPrepAPI interface {
	ListServers(ctx context.Context) ([]string, error)
	GetServer(ctx context.Context, serviceName string) (*ovh.Server, error)
	ServerDisplayName(ctx context.Context, serviceName string) (string, error)
	SetServerDisplayName(ctx context.Context, serviceName, displayName string) error
	Tasks(ctx context.Context, serviceName string) ([]ovh.Task, error)
	ResolveTemplate(ctx context.Context, serviceName, osLabel string) (string, error)
	StartInstall(ctx context.Context, serviceName string, p ovh.InstallParams) error
}

// OVHPoolPrep prepares newly delivered OVH boxes for their fleet, the step
// `baremetal:prep-ovh` used to be: it installs Ubuntu with the fleet's SSH key
// and the /data layout (StartInstall), then names the box into the fleet's
// pool. Adoption deliberately never installs (see reconcileNormal), and this
// keeps it that way: the box only reaches the pool once it is prepped, so the
// fleet still adopts it with a fast self-join.
//
// A person or an agent starts it by renaming the box to prep-<prefix>, which
// needs no fleet credential. The fleet's key and OVH token stay with the
// controller, which already reinstalls boxes with them on release.
type OVHPoolPrep struct {
	// Client reads the fleets' OVHDedicatedMachineTemplates.
	Client client.Client
	// APIReader lists the Machines' claims uncached, so a box a Machine holds is
	// never wiped because the cache had not seen the claim yet.
	APIReader client.Reader
	OVH       ovhPrepAPI
	// FleetKey returns the fleet's authorized-keys line.
	FleetKey func(ctx context.Context, fleet string) (string, error)
	Recorder record.EventRecorder
	Interval time.Duration
	// DefaultDatacenter and DefaultOS fill a template that left them empty, as
	// the Machine reconciler does.
	DefaultDatacenter string
	DefaultOS         string
	Log               logr.Logger
}

func (p *OVHPoolPrep) NeedLeaderElection() bool { return true }

func (p *OVHPoolPrep) Start(ctx context.Context) error {
	p.Log.Info("OVH pool prep starting", "interval", p.Interval)
	wait.UntilWithContext(ctx, func(ctx context.Context) {
		if err := p.prepOnce(ctx); err != nil {
			p.Log.Error(err, "OVH pool prep pass failed; retrying next interval")
		}
	}, p.Interval)
	return nil
}

// ovhPrepFleet is what one OVHDedicatedMachineTemplate says about its fleet.
type ovhPrepFleet struct {
	template   *infrav1.OVHDedicatedMachineTemplate
	name       string
	prefix     string
	datacenter string
	offer      string
	os         string
}

func (p *OVHPoolPrep) prepOnce(ctx context.Context) error {
	fleets, err := p.fleets(ctx)
	if err != nil {
		return err
	}
	if len(fleets) == 0 {
		return nil
	}
	claimed, err := p.claimed(ctx)
	if err != nil {
		return err
	}
	names, err := p.OVH.ListServers(ctx)
	if err != nil {
		return err
	}
	for _, name := range names {
		if claimed[name] {
			continue
		}
		displayName, err := p.OVH.ServerDisplayName(ctx, name)
		if err != nil {
			p.Log.Error(err, "read OVH displayName; skipping this pass", "service", name)
			continue
		}
		var stepErr error
		if fleet, ok := parseOVHPrepRequest(displayName, fleets); ok {
			stepErr = p.claim(ctx, name, fleet)
		} else if fleet, baseline, ok := parseOVHPrepping(displayName, fleets); ok {
			stepErr = p.advance(ctx, name, fleet, baseline)
		} else {
			continue
		}
		if stepErr != nil {
			p.Log.Error(stepErr, "OVH pool prep step failed; retrying next pass", "service", name, "displayName", displayName)
		}
	}
	return nil
}

// fleets maps each adoptDisplayNamePrefix to its fleet. A prefix two templates
// describe differently is left out, since a box asking for it could be prepped
// for the wrong one.
func (p *OVHPoolPrep) fleets(ctx context.Context) (map[string]*ovhPrepFleet, error) {
	list := &infrav1.OVHDedicatedMachineTemplateList{}
	if err := p.Client.List(ctx, list); err != nil {
		return nil, fmt.Errorf("list OVHDedicatedMachineTemplates: %w", err)
	}
	fleets := map[string]*ovhPrepFleet{}
	conflicting := map[string]bool{}
	for i := range list.Items {
		t := &list.Items[i]
		spec := t.Spec.Template.Spec
		if spec.AdoptDisplayNamePrefix == "" || spec.FleetName == "" {
			continue
		}
		f := &ovhPrepFleet{
			template:   t,
			name:       spec.FleetName,
			prefix:     spec.AdoptDisplayNamePrefix,
			datacenter: firstNonEmpty(spec.Datacenter, p.DefaultDatacenter),
			offer:      spec.Offer,
			os:         firstNonEmpty(spec.OS, p.DefaultOS),
		}
		if prev, ok := fleets[f.prefix]; ok && (prev.name != f.name || prev.datacenter != f.datacenter || prev.offer != f.offer || prev.os != f.os) {
			conflicting[f.prefix] = true
		}
		fleets[f.prefix] = f
	}
	for prefix := range conflicting {
		p.Log.Error(errors.New("conflicting OVHDedicatedMachineTemplates"), "not prepping boxes for a prefix two templates describe differently", "prefix", prefix)
		delete(fleets, prefix)
	}
	return fleets, nil
}

func (p *OVHPoolPrep) claimed(ctx context.Context) (map[string]bool, error) {
	list := &infrav1.OVHDedicatedMachineList{}
	if err := p.APIReader.List(ctx, list); err != nil {
		return nil, fmt.Errorf("list OVHDedicatedMachines: %w", err)
	}
	claimed := make(map[string]bool, len(list.Items))
	for i := range list.Items {
		if s := list.Items[i].Status.ServiceName; s != "" {
			claimed[s] = true
		}
	}
	return claimed, nil
}

// parseOVHPrepRequest reads prep-<prefix>. prep-failed-<prefix> is not one,
// since no fleet's prefix starts with failed-.
func parseOVHPrepRequest(displayName string, fleets map[string]*ovhPrepFleet) (*ovhPrepFleet, bool) {
	prefix, ok := strings.CutPrefix(displayName, ovhPrepRequestedPrefix)
	if !ok {
		return nil, false
	}
	fleet, ok := fleets[prefix]
	return fleet, ok
}

// parseOVHPrepping reads prepping-<id>-<prefix>.
func parseOVHPrepping(displayName string, fleets map[string]*ovhPrepFleet) (*ovhPrepFleet, int64, bool) {
	rest, ok := strings.CutPrefix(displayName, ovhPrepInstallingPrefix)
	if !ok {
		return nil, 0, false
	}
	id, prefix, ok := strings.Cut(rest, "-")
	if !ok {
		return nil, 0, false
	}
	baseline, err := strconv.ParseInt(id, 10, 64)
	if err != nil {
		return nil, 0, false
	}
	fleet, ok := fleets[prefix]
	return fleet, baseline, ok
}

// claim takes a box asked for with prep-<prefix>: it renames it to
// prepping-<id>-<prefix> before installing, so the install it starts is known
// to be its own by its task ID, and a box OVH is still delivering is never
// mistaken for one this pass prepped.
func (p *OVHPoolPrep) claim(ctx context.Context, name string, fleet *ovhPrepFleet) error {
	server, err := p.OVH.GetServer(ctx, name)
	if err != nil {
		return err
	}
	if !(ovh.AdoptParams{Datacenter: fleet.datacenter, Offer: fleet.offer}).MatchesShape(server) {
		p.event(fleet, corev1.EventTypeWarning, "PrepRefused",
			"OVH server %s asks to be prepped for %s, but it is in %s (%s), not the fleet's datacenter %q and offer %q",
			name, fleet.name, server.Datacenter, server.CommercialRange, fleet.datacenter, fleet.offer)
		return nil
	}
	tasks, err := p.OVH.Tasks(ctx, name)
	if err != nil {
		return err
	}
	if pendingOVHTask(tasks) {
		p.Log.Info("OVH server has a pending task; waiting before prepping it", "service", name)
		return nil
	}
	var baseline int64
	if latest, ok := ovh.LatestInstallTask(tasks); ok {
		baseline = latest.ID
	}
	if renamed, err := p.rename(ctx, name, fmt.Sprintf("%s%d-%s", ovhPrepInstallingPrefix, baseline, fleet.prefix)); err != nil || !renamed {
		return err
	}
	if err := p.install(ctx, name, fleet); err != nil {
		return err
	}
	p.event(fleet, corev1.EventTypeNormal, "PrepInstallStarted", "Installing OVH server %s for %s", name, fleet.name)
	return nil
}

// advance moves a prepping box on from its install task: the first install
// task after the baseline is the controller's.
func (p *OVHPoolPrep) advance(ctx context.Context, name string, fleet *ovhPrepFleet, baseline int64) error {
	tasks, err := p.OVH.Tasks(ctx, name)
	if err != nil {
		return err
	}
	latest, ok := ovh.LatestInstallTask(tasks)
	if !ok || latest.ID <= baseline {
		// Claimed but not installing: the install request failed, or the
		// controller stopped between the rename and it.
		if pendingOVHTask(tasks) {
			return nil
		}
		if err := p.install(ctx, name, fleet); err != nil {
			return err
		}
		p.event(fleet, corev1.EventTypeNormal, "PrepInstallStarted", "Installing OVH server %s for %s", name, fleet.name)
		return nil
	}
	switch latest.State() {
	case ovh.InstallDone:
		// OVH drops a rename while any task is pending on the server.
		if pendingOVHTask(tasks) {
			return nil
		}
		renamed, err := p.rename(ctx, name, fleet.prefix)
		if err == nil && renamed {
			p.event(fleet, corev1.EventTypeNormal, "Prepped", "OVH server %s is installed and named into %s's pool", name, fleet.name)
		}
		return err
	case ovh.InstallFailed:
		renamed, err := p.rename(ctx, name, ovhPrepFailedPrefix+fleet.prefix)
		if err == nil && renamed {
			p.event(fleet, corev1.EventTypeWarning, "PrepFailed",
				"OVH install task %d on %s ended %q; rename the box to %s%s to try again", latest.ID, name, latest.Status, ovhPrepRequestedPrefix, fleet.prefix)
		}
		return err
	default:
		return nil
	}
}

func (p *OVHPoolPrep) install(ctx context.Context, name string, fleet *ovhPrepFleet) error {
	key, err := p.FleetKey(ctx, fleet.name)
	if err != nil {
		return fmt.Errorf("fleet key for %s: %w", fleet.name, err)
	}
	template, err := p.OVH.ResolveTemplate(ctx, name, fleet.os)
	if err != nil {
		return err
	}
	err = p.OVH.StartInstall(ctx, name, ovh.InstallParams{TemplateName: template, Hostname: fleet.name, SSHKey: key})
	if ovh.IsTaskAlreadyExists(err) {
		// Something was queued meanwhile; the next pass reads what it was.
		return nil
	}
	return err
}

// rename sets the displayName and reports whether it reads back, since OVH
// answers 200 to a rename it drops.
func (p *OVHPoolPrep) rename(ctx context.Context, name, displayName string) (bool, error) {
	if err := p.OVH.SetServerDisplayName(ctx, name, displayName); err != nil {
		return false, err
	}
	got, err := p.OVH.ServerDisplayName(ctx, name)
	if err != nil {
		return false, err
	}
	if got != displayName {
		p.Log.Info("OVH did not apply the rename yet; retrying next pass", "service", name, "want", displayName, "got", got)
		return false, nil
	}
	return true, nil
}

func (p *OVHPoolPrep) event(fleet *ovhPrepFleet, eventType, reason, format string, args ...any) {
	p.Log.Info(fmt.Sprintf(format, args...), "reason", reason, "fleet", fleet.name)
	if p.Recorder != nil {
		p.Recorder.Eventf(fleet.template, eventType, reason, format, args...)
	}
}

func pendingOVHTask(tasks []ovh.Task) bool {
	for _, t := range tasks {
		if t.State() == ovh.InstallRunning {
			return true
		}
	}
	return false
}
