// Package telemetry exports the health of the rack's switches, as the Omada
// controller reports it, on the manager's metrics endpoint.
//
// It reads the controller rather than the switches. A switch allows only a
// handful of SSH logins per boot (infra/rack-switch-fleet/AGENTS.md), so
// polling it directly would lock out the operators, and SNMP is off on every
// switch in the site. The controller already talks to each adopted switch, so
// its API is the one read path that costs the switches nothing.
package telemetry

import (
	"context"
	"strconv"
	"sync"
	"time"

	"github.com/go-logr/logr"
	"github.com/prometheus/client_golang/prometheus"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
)

const (
	// The controller samples its devices on its own schedule, so reading it
	// more often only returns the same numbers.
	pollInterval = time.Minute
	pollTimeout  = 30 * time.Second
	// The span the health detail averages the chassis temperature over.
	healthWindow = 10 * time.Minute
)

var (
	upDesc = prometheus.NewDesc("rack_switch_up",
		"1 when the Omada controller reports the switch connected, 0 when it reports it in any other state.",
		[]string{"switch"}, nil)
	cpuDesc = prometheus.NewDesc("rack_switch_cpu_utilization_ratio",
		"CPU utilization as the Omada controller last measured it.",
		[]string{"switch"}, nil)
	memoryDesc = prometheus.NewDesc("rack_switch_memory_utilization_ratio",
		"Memory utilization as the Omada controller last measured it.",
		[]string{"switch"}, nil)
	temperatureDesc = prometheus.NewDesc("rack_switch_temperature_celsius",
		"Chassis temperature from the Omada controller's health detail, averaged over the last ten minutes. Absent on a model without the sensor.",
		[]string{"switch"}, nil)
	opticDesc = prometheus.NewDesc("rack_switch_optic_temperature_celsius",
		"Transceiver temperature from its digital diagnostics.",
		[]string{"switch", "port"}, nil)
	lastSuccessDesc = prometheus.NewDesc("rack_switch_telemetry_last_success_timestamp_seconds",
		"When the switches were last read from the Omada controller.",
		nil, nil)
)

type reading struct {
	name        string
	up          bool
	cpu         *int
	memory      *int
	temperature *int
	optics      []omada.Optic
}

// Poller reads every switch the controller manages from the Omada controller
// once a minute. It runs on the leader only, so the controller is read once
// however many replicas there are, and a replica that is not leading exports
// nothing.
type Poller struct {
	Omada     *omada.Client
	Site      string
	Reader    client.Reader
	Namespace string
	Log       logr.Logger
	Now       func() time.Time

	errors *prometheus.CounterVec

	mu          sync.Mutex
	readings    []reading
	lastSuccess time.Time
}

// New returns a Poller for the switches in namespace, adopted into site.
func New(o *omada.Client, site string, reader client.Reader, namespace string, log logr.Logger) *Poller {
	return &Poller{
		Omada:     o,
		Site:      site,
		Reader:    reader,
		Namespace: namespace,
		Log:       log,
		Now:       time.Now,
		errors: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "rack_switch_telemetry_errors_total",
			Help: "Failed reads while polling the switches, by what was being read.",
		}, []string{"stage"}),
	}
}

// NeedLeaderElection keeps the poller on the leader.
func (p *Poller) NeedLeaderElection() bool { return true }

// Start polls until ctx is done.
func (p *Poller) Start(ctx context.Context) error {
	ticker := time.NewTicker(pollInterval)
	defer ticker.Stop()
	for {
		p.poll(ctx)
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
		}
	}
}

func (p *Poller) poll(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, pollTimeout)
	defer cancel()

	var switches v1alpha1.RackSwitchList
	if err := p.Reader.List(ctx, &switches, client.InNamespace(p.Namespace)); err != nil {
		p.fail("switches", err)
		return
	}
	siteID, err := p.Omada.SiteID(ctx, p.Site)
	if err != nil {
		p.fail("site", err)
		return
	}
	devices, err := p.Omada.Devices(ctx, siteID)
	if err != nil {
		p.fail("devices", err)
		return
	}
	byMAC := make(map[string]omada.Device, len(devices))
	for _, d := range devices {
		byMAC[d.MAC] = d
	}

	now := p.Now()
	var readings []reading
	for _, sw := range switches.Items {
		// A standalone switch is changed over SSH and is not adopted, so the
		// controller has nothing to report for it.
		if sw.Spec.ManagedBy != v1alpha1.ManagedByController || sw.Spec.MAC == "" {
			continue
		}
		device, ok := byMAC[omada.ControllerMAC(sw.Spec.MAC)]
		if !ok {
			continue
		}
		r := reading{name: sw.Name, up: device.Status == omada.StatusConnected}
		// The controller keeps the last numbers of a switch it has lost, and
		// those are not current.
		if r.up {
			r.cpu, r.memory = device.CPUUtil, device.MemUtil
			health, err := p.Omada.SwitchHealth(ctx, siteID, sw.Spec.MAC, now.Add(-healthWindow), now)
			switch {
			case err != nil:
				p.count("health", sw.Name, err)
			case health.Temperature.Support:
				r.temperature = health.Temperature.Average
			}
			optics, err := p.Omada.SwitchOptics(ctx, siteID, sw.Spec.MAC)
			if err != nil {
				p.count("optics", sw.Name, err)
			} else {
				r.optics = optics
			}
		}
		readings = append(readings, r)
	}

	p.mu.Lock()
	p.readings = readings
	p.lastSuccess = now
	p.mu.Unlock()
}

// fail drops every reading, since the last ones can no longer be told apart
// from current ones, and leaves the last success where it was.
func (p *Poller) fail(stage string, err error) {
	p.errors.WithLabelValues(stage).Inc()
	p.Log.Error(err, "read switch telemetry", "stage", stage)
	p.mu.Lock()
	p.readings = nil
	p.mu.Unlock()
}

func (p *Poller) count(stage, name string, err error) {
	p.errors.WithLabelValues(stage).Inc()
	p.Log.Error(err, "read switch telemetry", "stage", stage, "switch", name)
}

// Describe implements prometheus.Collector.
func (p *Poller) Describe(ch chan<- *prometheus.Desc) {
	for _, d := range []*prometheus.Desc{upDesc, cpuDesc, memoryDesc, temperatureDesc, opticDesc, lastSuccessDesc} {
		ch <- d
	}
	p.errors.Describe(ch)
}

// Collect implements prometheus.Collector.
func (p *Poller) Collect(ch chan<- prometheus.Metric) {
	p.mu.Lock()
	readings, lastSuccess := p.readings, p.lastSuccess
	p.mu.Unlock()

	for _, r := range readings {
		up := 0.0
		if r.up {
			up = 1
		}
		ch <- prometheus.MustNewConstMetric(upDesc, prometheus.GaugeValue, up, r.name)
		if r.cpu != nil {
			ch <- prometheus.MustNewConstMetric(cpuDesc, prometheus.GaugeValue, float64(*r.cpu)/100, r.name)
		}
		if r.memory != nil {
			ch <- prometheus.MustNewConstMetric(memoryDesc, prometheus.GaugeValue, float64(*r.memory)/100, r.name)
		}
		if r.temperature != nil {
			ch <- prometheus.MustNewConstMetric(temperatureDesc, prometheus.GaugeValue, float64(*r.temperature), r.name)
		}
		for _, o := range r.optics {
			if o.Valid() {
				ch <- prometheus.MustNewConstMetric(opticDesc, prometheus.GaugeValue, *o.Temperature, r.name, strconv.Itoa(o.Port))
			}
		}
	}
	if !lastSuccess.IsZero() {
		ch <- prometheus.MustNewConstMetric(lastSuccessDesc, prometheus.GaugeValue, float64(lastSuccess.UnixNano())/1e9)
	}
	p.errors.Collect(ch)
}
