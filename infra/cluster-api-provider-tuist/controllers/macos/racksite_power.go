package macos

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// PowerBudgetTaintKey is the NoSchedule taint a RackSite holds a Mac mini's
// Node under while the mini's chain, or the whole site, is over its power
// budget: no new runner VM lands there, and the runners-controller retires the
// idle runners already on it, so only the jobs already running keep drawing.
// Its value says which budget holds it, `chain` or `site`.
//
// CONTRACT: must match the runners-controller's `powerBudgetTaintKey`. The two
// live in separate Go modules, coupled by convention.
const PowerBudgetTaintKey = "tuist.dev/power-budget"

// RackSitePowerAdmissionCondition is True while every Mac mini at the site
// takes new runner VMs, False while a chain or the site is held, and Unknown
// while a chain with minis on it has no recent reading, which holds nothing.
const RackSitePowerAdmissionCondition clusterv1.ConditionType = "PowerAdmission"

const (
	// rackSitePowerInterval is how often a site with a budget is judged: as
	// often as its transfer switches are read (rackATSObserveInterval).
	rackSitePowerInterval = time.Minute
	// A transfer switch is read every minute and a PDU's outlets every ten
	// (rackPDUResyncInterval). A reading older than a few of its reads says
	// nothing about the draw now.
	atsReadingMaxAge = 5 * time.Minute
	pduReadingMaxAge = 3 * rackPDUResyncInterval
	// A held chain or site is released once it draws under this share of its
	// budget, and no sooner than powerMinimumHold after it was held, so that
	// retiring its idle runners, which lowers the draw a little, does not
	// release it straight away and start them again.
	powerReleaseFraction = 0.95
	powerMinimumHold     = 10 * time.Minute
)

var (
	rackSitePowerBudgetGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_racksite_power_budget_watts",
		Help: "What the site's transfer switches may draw together before its Mac minis take no new runner VMs: the contracted power in effect less spec.powerBudget.otherWatts. No series without a budget or a step. Labels: site.",
	}, []string{"site"})
	rackSiteMeteredPowerGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_racksite_metered_power_watts",
		Help: "What the site's transfer switches drew together at the last judgement. No series while a switch has no recent reading. Labels: site.",
	}, []string{"site"})
	rackSiteChainCurrentGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_racksite_chain_current_amps",
		Help: "A chain's output current at the last judgement. No series while it has no recent reading. Labels: site, chain (the transfer switch).",
	}, []string{"site", "chain"})
	rackSiteChainHeldGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_racksite_chain_held",
		Help: "1 while a chain's Mac minis take no new runner VMs because it is over spec.powerBudget.chainAmps. Labels: site, chain.",
	}, []string{"site", "chain"})
	rackSiteHeldGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_racksite_site_held",
		Help: "1 while every Mac mini at the site takes no new runner VMs because the site is over its budget. Labels: site.",
	}, []string{"site"})
)

func init() {
	metrics.Registry.MustRegister(rackSitePowerBudgetGauge, rackSiteMeteredPowerGauge, rackSiteChainCurrentGauge,
		rackSiteChainHeldGauge, rackSiteHeldGauge)
}

// powerReading is a chain's draw, or none when it has no recent reading.
type powerReading struct {
	amps, watts float64
	ok          bool
}

// atsReading is a transfer switch's output as its last observation reported
// it: the current of its outputs, and their active power, or current times
// voltage for an output that reports none.
func atsReading(ats *infrav1.RackATS, now time.Time) powerReading {
	if ats.Status.LastObserved == nil || now.Sub(ats.Status.LastObserved.Time) > atsReadingMaxAge {
		return powerReading{}
	}
	var r powerReading
	for _, out := range ats.Status.Outputs {
		amps, ok := parseMeasure(out.Current)
		if !ok {
			continue
		}
		watts, ok := parseMeasure(out.ActivePower)
		if !ok {
			volts, _ := parseMeasure(out.Voltage)
			watts = amps * volts
		}
		r.amps += amps
		r.watts += watts
		r.ok = true
	}
	return r
}

// pduReading is the sum of the PDUs' outlet meters, when every one of them
// was read recently.
func pduReading(pdus []*infrav1.RackPDU, now time.Time) powerReading {
	if len(pdus) == 0 {
		return powerReading{}
	}
	var r powerReading
	for _, pdu := range pdus {
		if pdu.Status.OutletsReadAt == nil || now.Sub(pdu.Status.OutletsReadAt.Time) > pduReadingMaxAge || len(pdu.Status.Outlets) == 0 {
			return powerReading{}
		}
		for _, outlet := range pdu.Status.Outlets {
			if outlet.CurrentAmps != nil {
				r.amps += quantityFloat(*outlet.CurrentAmps)
			}
			if outlet.ActivePowerWatts != nil {
				r.watts += quantityFloat(*outlet.ActivePowerWatts)
			}
		}
	}
	r.ok = true
	return r
}

func parseMeasure(measure string) (float64, bool) {
	var v float64
	if _, err := fmt.Sscan(measure, &v); err != nil {
		return 0, false
	}
	return v, true
}

// powerChain is one transfer switch's chain: what it draws and the minis its
// PDUs power.
type powerChain struct {
	name    string
	reading powerReading
	nodes   []string
	hosts   int
}

// powerChains groups the site's draw by chain. A transfer switch's chain is
// read from its own output, which covers everything it powers, and from its
// PDUs' outlets when the switch has no recent reading. A PDU that hangs off no
// switch is a chain of its own. A mini belongs to the chain of the PDU its
// outlet is on; a mini lent to another env's cluster has no Node here.
func powerChains(atses []*infrav1.RackATS, pdus []*infrav1.RackPDU, hosts []*infrav1.RackHost, now time.Time) []*powerChain {
	byName := map[string]*powerChain{}
	chainOf := map[string]string{}
	pdusOf := map[string][]*infrav1.RackPDU{}
	chain := func(name string) *powerChain {
		c, ok := byName[name]
		if !ok {
			c = &powerChain{name: name}
			byName[name] = c
		}
		return c
	}
	for _, ats := range atses {
		chain(ats.Name)
	}
	for _, pdu := range pdus {
		name := pdu.Spec.Chain
		if name == "" {
			name = pdu.Name
		}
		chain(name)
		chainOf[pdu.Name] = name
		pdusOf[name] = append(pdusOf[name], pdu)
	}
	for _, ats := range atses {
		c := byName[ats.Name]
		if c.reading = atsReading(ats, now); !c.reading.ok {
			c.reading = pduReading(pdusOf[ats.Name], now)
		}
	}
	for name, c := range byName {
		if _, isATS := findATS(atses, name); !isATS {
			c.reading = pduReading(pdusOf[name], now)
		}
	}
	for _, host := range hosts {
		if host.Spec.Power == nil || host.Spec.Power.PDU == "" {
			continue
		}
		name, ok := chainOf[host.Spec.Power.PDU]
		if !ok {
			continue
		}
		c := byName[name]
		c.hosts++
		if node := hostNode(host); node != "" {
			c.nodes = append(c.nodes, node)
		}
	}
	chains := make([]*powerChain, 0, len(byName))
	for _, c := range byName {
		sort.Strings(c.nodes)
		chains = append(chains, c)
	}
	sort.Slice(chains, func(i, j int) bool { return chains[i].name < chains[j].name })
	return chains
}

func findATS(atses []*infrav1.RackATS, name string) (*infrav1.RackATS, bool) {
	for _, ats := range atses {
		if ats.Name == name {
			return ats, true
		}
	}
	return nil, false
}

// hostNode is the Node a host registers in this cluster, empty when it has
// none yet or registers in another env's.
func hostNode(host *infrav1.RackHost) string {
	if host.Spec.LendTo != "" || host.Spec.NodeCluster != nil {
		return ""
	}
	return host.Status.Machine
}

// powerHold decides whether a budget holds its minis: held at or over the
// limit, and once held, until the draw is under powerReleaseFraction of it and
// powerMinimumHold has passed. Without a reading nothing is held: a meter that
// stops answering must not take capacity away. It returns the hold and when
// it started.
func powerHold(draw, limit float64, ok, wasHeld bool, heldSince *metav1.Time, now time.Time) (bool, *metav1.Time) {
	if !ok || limit <= 0 {
		return false, nil
	}
	if draw >= limit {
		if wasHeld && heldSince != nil {
			return true, heldSince
		}
		since := metav1.NewTime(now)
		return true, &since
	}
	if wasHeld && heldSince != nil && (draw > limit*powerReleaseFraction || now.Sub(heldSince.Time) < powerMinimumHold) {
		return true, heldSince
	}
	return false, nil
}

// admitPower judges the site's draw against its budget, records it in the
// status and metrics, and taints or untaints its minis' Nodes to match.
func (r *RackSiteReconciler) admitPower(ctx context.Context, site *infrav1.RackSite, previous *infrav1.RackSiteStatus, contracted *infrav1.RackSiteContractedPower, now time.Time) error {
	hosts, err := r.siteHosts(ctx, site.Namespace, site.Name)
	if err != nil {
		return err
	}
	budget := site.Spec.PowerBudget
	if budget == nil {
		forgetRackSitePower(site.Name)
		conditions.Delete(site, RackSitePowerAdmissionCondition)
		return r.holdNodes(ctx, hosts, nil)
	}

	atses := &infrav1.RackATSList{}
	if err := r.List(ctx, atses, client.InNamespace(site.Namespace)); err != nil {
		return err
	}
	pdus := &infrav1.RackPDUList{}
	if err := r.List(ctx, pdus, client.InNamespace(site.Namespace)); err != nil {
		return err
	}
	var siteATSes []*infrav1.RackATS
	for i := range atses.Items {
		if atses.Items[i].Spec.Site == site.Name {
			siteATSes = append(siteATSes, &atses.Items[i])
		}
	}
	var sitePDUs []*infrav1.RackPDU
	for i := range pdus.Items {
		if pdus.Items[i].Spec.Site == site.Name {
			sitePDUs = append(sitePDUs, &pdus.Items[i])
		}
	}
	chains := powerChains(siteATSes, sitePDUs, hosts, now)

	limitAmps := quantityFloat(budget.ChainAmps)
	var budgetWatts int64
	if contracted != nil {
		budgetWatts = contracted.Watts - budget.OtherWatts
	}
	site.Status.PowerBudgetWatts = budgetWatts
	forgetRackSitePower(site.Name)
	if budgetWatts > 0 {
		rackSitePowerBudgetGauge.WithLabelValues(site.Name).Set(float64(budgetWatts))
	}

	wasHeld := map[string]infrav1.RackSiteChain{}
	for _, c := range previous.Chains {
		wasHeld[c.Name] = c
	}
	metered, meteredOK := 0.0, len(chains) > 0
	held := map[string]bool{}
	var heldChains, unread []string
	for _, c := range chains {
		status := infrav1.RackSiteChain{Name: c.name, Hosts: c.hosts}
		if c.reading.ok {
			status.CurrentAmps = measureQuantity(&c.reading.amps)
			status.Watts = measureQuantity(&c.reading.watts)
			metered += c.reading.watts
			rackSiteChainCurrentGauge.WithLabelValues(site.Name, c.name).Set(c.reading.amps)
		} else {
			meteredOK = false
			if c.hosts > 0 {
				unread = append(unread, c.name)
			}
		}
		prev := wasHeld[c.name]
		status.Held, status.HeldSince = powerHold(c.reading.amps, limitAmps, c.reading.ok && c.hosts > 0, prev.Held, prev.HeldSince, now)
		if status.Held {
			held[c.name] = true
			heldChains = append(heldChains, fmt.Sprintf("%s at %.1f A", c.name, c.reading.amps))
		}
		rackSiteChainHeldGauge.WithLabelValues(site.Name, c.name).Set(flagValue(status.Held))
		site.Status.Chains = append(site.Status.Chains, status)
	}
	if meteredOK {
		site.Status.MeteredWatts = measureQuantity(&metered)
		rackSiteMeteredPowerGauge.WithLabelValues(site.Name).Set(metered)
	}
	site.Status.SiteHeld, site.Status.SiteHeldSince = powerHold(metered, float64(budgetWatts), meteredOK, previous.SiteHeld, previous.SiteHeldSince, now)
	rackSiteHeldGauge.WithLabelValues(site.Name).Set(flagValue(site.Status.SiteHeld))

	switch {
	case site.Status.SiteHeld:
		conditions.MarkFalse(site, RackSitePowerAdmissionCondition, "SiteOverBudget", clusterv1.ConditionSeverityWarning,
			"the site's transfer switches draw %.0f W against a budget of %d W; no Mac mini at the site takes new runner VMs", metered, budgetWatts)
	case len(heldChains) > 0:
		conditions.MarkFalse(site, RackSitePowerAdmissionCondition, "ChainOverBudget", clusterv1.ConditionSeverityWarning,
			"%s over %s A; its minis take no new runner VMs", strings.Join(heldChains, ", "), budget.ChainAmps.String())
	case len(unread) > 0:
		conditions.MarkUnknown(site, RackSitePowerAdmissionCondition, "ReadingsStale",
			"no recent reading of %s; nothing is held back on a missing reading", strings.Join(unread, ", "))
	default:
		conditions.MarkTrue(site, RackSitePowerAdmissionCondition)
	}

	holds := map[string]string{}
	for _, c := range chains {
		if held[c.name] {
			for _, node := range c.nodes {
				holds[node] = "chain"
			}
		}
	}
	if site.Status.SiteHeld {
		for _, host := range hosts {
			if node := hostNode(host); node != "" {
				holds[node] = "site"
			}
		}
	}
	return r.holdNodes(ctx, hosts, holds)
}

// siteHosts is the site's RackHosts.
func (r *RackSiteReconciler) siteHosts(ctx context.Context, namespace, site string) ([]*infrav1.RackHost, error) {
	list := &infrav1.RackHostList{}
	if err := r.List(ctx, list, client.InNamespace(namespace)); err != nil {
		return nil, err
	}
	var hosts []*infrav1.RackHost
	for i := range list.Items {
		if list.Items[i].Spec.Location.Site == site {
			hosts = append(hosts, &list.Items[i])
		}
	}
	return hosts, nil
}

// holdNodes makes each host's Node carry PowerBudgetTaintKey with the reason
// holds gives it, and takes it off every other host's Node.
func (r *RackSiteReconciler) holdNodes(ctx context.Context, hosts []*infrav1.RackHost, holds map[string]string) error {
	var errs []string
	for _, host := range hosts {
		name := hostNode(host)
		if name == "" {
			continue
		}
		if err := setPowerBudgetTaint(ctx, r.Client, name, holds[name]); err != nil {
			errs = append(errs, fmt.Sprintf("%s: %v", name, err))
		}
	}
	if len(errs) > 0 {
		return fmt.Errorf("power budget taints: %s", strings.Join(errs, "; "))
	}
	return nil
}

// setPowerBudgetTaint puts PowerBudgetTaintKey on the Node with value, or
// takes it off when value is empty. Every other taint is kept as it is. A
// Node that is gone needs nothing.
func setPowerBudgetTaint(ctx context.Context, c client.Client, name, value string) error {
	node := &corev1.Node{}
	if err := c.Get(ctx, types.NamespacedName{Name: name}, node); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	kept := make([]corev1.Taint, 0, len(node.Spec.Taints)+1)
	found, current := false, ""
	for _, taint := range node.Spec.Taints {
		if taint.Key == PowerBudgetTaintKey {
			found, current = true, taint.Value
			continue
		}
		kept = append(kept, taint)
	}
	if found == (value != "") && current == value {
		return nil
	}
	if value != "" {
		kept = append(kept, corev1.Taint{Key: PowerBudgetTaintKey, Value: value, Effect: corev1.TaintEffectNoSchedule})
	}
	base := node.DeepCopy()
	node.Spec.Taints = kept
	return c.Patch(ctx, node, client.MergeFrom(base))
}

// liftSiteHolds takes the hold off every mini of a site whose RackSite is
// gone.
func (r *RackSiteReconciler) liftSiteHolds(ctx context.Context, namespace, site string) error {
	forgetRackSitePower(site)
	hosts, err := r.siteHosts(ctx, namespace, site)
	if err != nil {
		return err
	}
	return r.holdNodes(ctx, hosts, nil)
}

func forgetRackSitePower(site string) {
	match := prometheus.Labels{"site": site}
	for _, g := range []*prometheus.GaugeVec{rackSitePowerBudgetGauge, rackSiteMeteredPowerGauge, rackSiteChainCurrentGauge,
		rackSiteChainHeldGauge, rackSiteHeldGauge} {
		g.DeletePartialMatch(match)
	}
}

func flagValue(ok bool) float64 {
	if ok {
		return 1
	}
	return 0
}
