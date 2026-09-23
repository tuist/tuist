package controllers

import (
	"context"
	"reflect"
	"strings"
	"testing"
	"time"

	"k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/converge"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada/omadatest"
)

const (
	namespace         = "tuist-staging"
	torBMAC           = "d4:d6:df:03:d8:b2"
	torAMAC           = "d4:d6:df:06:fd:3b"
	mgmtMAC           = "a8:29:48:fe:b4:be"
	resync            = 10 * time.Minute
	controllerAddress = "100.84.132.92"
)

var (
	deviceAccount = omada.Login{Username: "tuist", Password: "Device-Pass1!"}
	creds         = converge.Credentials{
		ClientID:      omadatest.ClientID,
		ClientSecret:  omadatest.ClientSecret,
		DeviceAccount: deviceAccount,
		FactoryLogin:  converge.DefaultFactoryLogin,
	}
)

type harness struct {
	t        *testing.T
	omada    *omadatest.Server
	client   client.Client
	recorder *record.FakeRecorder
	r        *RackSwitchReconciler
	now      time.Time
}

func newHarness(t *testing.T, objects ...client.Object) *harness {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := v1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	k8s := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objects...).
		WithStatusSubresource(&v1alpha1.RackSwitch{}).
		Build()
	fakeOmada := omadatest.New()
	t.Cleanup(fakeOmada.Close)
	h := &harness{
		t:        t,
		omada:    fakeOmada,
		client:   k8s,
		recorder: record.NewFakeRecorder(100),
		now:      time.Date(2026, 9, 23, 12, 0, 0, 0, time.UTC),
	}
	h.r = &RackSwitchReconciler{
		Client:   k8s,
		Recorder: h.recorder,
		Engine: &converge.Engine{
			Omada: omada.New(fakeOmada.URL, func() (string, string, error) {
				return creds.ClientID, creds.ClientSecret, nil
			}),
			Site:              omadatest.SiteName,
			ControllerAddress: controllerAddress,
		},
		Credentials:    func() (converge.Credentials, error) { return creds, nil },
		ResyncInterval: resync,
		Now:            func() time.Time { return h.now },
	}
	return h
}

func (h *harness) reconcile(name string) ctrl.Result {
	h.t.Helper()
	result, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: namespace, Name: name}})
	if err != nil {
		h.t.Fatalf("reconcile %s: %v", name, err)
	}
	return result
}

func (h *harness) get(name string) *v1alpha1.RackSwitch {
	h.t.Helper()
	var rs v1alpha1.RackSwitch
	if err := h.client.Get(context.Background(), types.NamespacedName{Namespace: namespace, Name: name}, &rs); err != nil {
		h.t.Fatal(err)
	}
	return &rs
}

// editSpec changes a spec the way an apply of a new render does, generation
// included, which the fake client does not bump on its own.
func (h *harness) editSpec(name string, edit func(*v1alpha1.RackSwitchSpec)) {
	h.t.Helper()
	rs := h.get(name)
	edit(&rs.Spec)
	rs.Generation++
	if err := h.client.Update(context.Background(), rs); err != nil {
		h.t.Fatal(err)
	}
}

func (h *harness) events() []string {
	var events []string
	for {
		select {
		case e := <-h.recorder.Events:
			events = append(events, e)
		default:
			return events
		}
	}
}

// switchWrites is every write to one switch, as "METHOD /rest".
func (h *harness) switchWrites(mac string) []string {
	prefix := "/sites/" + omadatest.SiteID + "/switches/" + omada.ControllerMAC(mac)
	var writes []string
	for _, w := range h.omada.Writes() {
		if strings.HasPrefix(w.Path, prefix) {
			writes = append(writes, w.Method+" "+strings.TrimPrefix(w.Path, prefix))
		}
	}
	return writes
}

func rackSwitch(name, mac string, order int, managedBy v1alpha1.ManagedBy) *v1alpha1.RackSwitch {
	cfg := &v1alpha1.SwitchConfig{Hostname: name, SpanningTree: v1alpha1.SpanningTreeRSTP}
	for p := 1; p <= 8; p++ {
		cfg.Ports = append(cfg.Ports, v1alpha1.PortConfig{Port: p})
	}
	cfg.Ports[7].Description = "isl"
	return &v1alpha1.RackSwitch{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace, Generation: 1},
		Spec: v1alpha1.RackSwitchSpec{
			Site:              "ber1",
			Role:              "tor",
			Model:             "sx3832",
			ManagementAddress: "192.168.0.12",
			ApplyOrder:        order,
			ConfigRevision:    "rev-1",
			MAC:               mac,
			ManagedBy:         managedBy,
			Config:            cfg,
		},
	}
}

// connected adds a switch the controller has adopted, already carrying its
// hostname and descriptions, so a test changes only what it is about.
func (h *harness) connected(name, mac string) {
	ports := omadatest.Ports(8)
	ports[7].Name = "isl"
	h.omada.AddSwitch(omadatest.Switch{MAC: mac, State: omadatest.Connected, Hostname: name, Ports: ports})
}

func condition(rs *v1alpha1.RackSwitch, conditionType string) metav1.Condition {
	c := meta.FindStatusCondition(rs.Status.Conditions, conditionType)
	if c == nil {
		return metav1.Condition{}
	}
	return *c
}

func TestAStandaloneSwitchIsLeftAlone(t *testing.T) {
	rs := rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByStandalone)
	rs.Status = v1alpha1.RackSwitchStatus{ObservedRevision: "rev-1", Drift: v1alpha1.DriftNone, Reachable: true, ConnectionsUsedSinceBoot: 3}
	h := newHarness(t, rs)

	result := h.reconcile("ber1-tor-b")
	if result != (ctrl.Result{}) {
		t.Fatalf("result = %+v, want no requeue", result)
	}
	if requests := h.omada.Requests(); len(requests) != 0 {
		t.Fatalf("called the Omada controller %d times", len(requests))
	}
	got := h.get("ber1-tor-b").Status
	want := rs.Status
	want.Message = StandaloneMessage
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("status = %+v, want only the message added to %+v", got, rs.Status)
	}
}

func TestAPendingSwitchIsAdoptedWithTheDeviceAccount(t *testing.T) {
	h := newHarness(t, rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController))
	h.omada.AddSwitch(omadatest.Switch{MAC: torBMAC, State: omadatest.Pending, Ports: omadatest.Ports(8), Logins: []omada.Login{deviceAccount}})

	result := h.reconcile("ber1-tor-b")
	if result.RequeueAfter != adoptionPollInterval {
		t.Fatalf("requeue = %v while adopting", result.RequeueAfter)
	}
	if c := condition(h.get("ber1-tor-b"), v1alpha1.ConditionAdopted); c.Reason != "Adopting" {
		t.Fatalf("Adopted = %+v", c)
	}
	for i := 0; i < 5 && !h.get("ber1-tor-b").Status.Adopted; i++ {
		h.reconcile("ber1-tor-b")
	}

	rs := h.get("ber1-tor-b")
	if !rs.Status.Adopted || condition(rs, v1alpha1.ConditionAdopted).Status != metav1.ConditionTrue {
		t.Fatalf("status = %+v", rs.Status)
	}
	if got := h.omada.Switch(torBMAC).AdoptedWith; !reflect.DeepEqual(got, []omada.Login{deviceAccount}) {
		t.Fatalf("adopted with %+v", got)
	}
	events := strings.Join(h.events(), "\n")
	for _, want := range []string{"Normal AdoptionStarted adopting with the site's device account", "Normal Adopted adopted with the site's device account"} {
		if !strings.Contains(events, want) {
			t.Fatalf("events = %s, want %q", events, want)
		}
	}
	if h.omada.Switch(torBMAC).Hostname != "ber1-tor-b" {
		t.Fatal("the pass that saw the switch adopted did not converge it")
	}
}

func TestAdoptionFallsBackToTheFactoryLogin(t *testing.T) {
	h := newHarness(t, rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController))
	h.omada.AddSwitch(omadatest.Switch{MAC: torBMAC, State: omadatest.Pending, Ports: omadatest.Ports(8), Logins: []omada.Login{converge.DefaultFactoryLogin}})

	for i := 0; i < 8 && !h.get("ber1-tor-b").Status.Adopted; i++ {
		h.reconcile("ber1-tor-b")
	}
	if !h.get("ber1-tor-b").Status.Adopted {
		t.Fatal("never adopted")
	}
	got := h.omada.Switch(torBMAC).AdoptedWith
	if !reflect.DeepEqual(got, []omada.Login{deviceAccount, converge.DefaultFactoryLogin}) {
		t.Fatalf("adopted with %+v", got)
	}
	events := strings.Join(h.events(), "\n")
	for _, want := range []string{
		"Warning AdoptionRetried the controller reports adopting with the site's device account failed; trying the factory login",
		"Normal Adopted adopted with the factory login",
	} {
		if !strings.Contains(events, want) {
			t.Fatalf("events = %s, want %q", events, want)
		}
	}
}

func TestConvergenceWritesOnlyWhatDiffers(t *testing.T) {
	h := newHarness(t, rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController))
	h.connected("ber1-tor-b", torBMAC)
	h.omada.Update(torBMAC, func(sw *omadatest.Switch) { sw.Ports[4].Name = "changed in the UI" })

	h.reconcile("ber1-tor-b")
	want := []string{"PATCH /ports/5", "PUT /config/loopback"}
	if got := h.switchWrites(torBMAC); !reflect.DeepEqual(got, want) {
		t.Fatalf("writes = %v, want %v", got, want)
	}
	if !strings.Contains(strings.Join(h.events(), "\n"), "Normal Wrote port 5: changed in the UI -> Port5; spanning tree: rstp") {
		t.Fatal("no event lists the writes")
	}
}

func TestSpanningTreeIsWrittenOnARevisionChangeAndNotOnAResync(t *testing.T) {
	h := newHarness(t, rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController))
	h.connected("ber1-tor-b", torBMAC)

	h.reconcile("ber1-tor-b")
	if got := h.switchWrites(torBMAC); !reflect.DeepEqual(got, []string{"PUT /config/loopback"}) {
		t.Fatalf("first pass wrote %v", got)
	}

	h.omada.ResetRequests()
	result := h.reconcile("ber1-tor-b")
	if writes := h.omada.Writes(); len(writes) != 0 {
		t.Fatalf("a resync wrote %+v", writes)
	}
	if result.RequeueAfter != resync {
		t.Fatalf("requeue = %v, want the resync interval", result.RequeueAfter)
	}

	h.editSpec("ber1-tor-b", func(s *v1alpha1.RackSwitchSpec) { s.ConfigRevision = "rev-2" })
	h.reconcile("ber1-tor-b")
	if got := h.switchWrites(torBMAC); !reflect.DeepEqual(got, []string{"PUT /config/loopback"}) {
		t.Fatalf("a new revision wrote %v", got)
	}
	if got := h.get("ber1-tor-b").Status.ObservedRevision; got != "rev-2" {
		t.Fatalf("observedRevision = %q", got)
	}

	h.omada.ResetRequests()
	h.editSpec("ber1-tor-b", func(s *v1alpha1.RackSwitchSpec) { s.Config.SpanningTree = v1alpha1.SpanningTreeMSTP })
	h.reconcile("ber1-tor-b")
	if got := h.omada.Switch(torBMAC).Loopback; got == nil || got.STP != omada.STPMSTP {
		t.Fatalf("a changed mode at the same revision was not written: %+v", got)
	}
}

func TestApplyOrderHoldsAHigherSwitchUntilTheLowerOneIsReady(t *testing.T) {
	h := newHarness(t,
		rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController),
		rackSwitch("ber1-tor-a", torAMAC, 2, v1alpha1.ManagedByController),
		rackSwitch("ber1-mgmt", mgmtMAC, 3, v1alpha1.ManagedByController),
	)
	h.connected("ber1-tor-b", torBMAC)
	h.connected("ber1-tor-a", torAMAC)
	h.omada.AddSwitch(omadatest.Switch{MAC: mgmtMAC, State: omadatest.Pending, Ports: omadatest.Ports(8), Logins: []omada.Login{deviceAccount}})
	h.omada.Update(torAMAC, func(sw *omadatest.Switch) { sw.Hostname = "D4-D6-DF-06-FD-3B" })

	result := h.reconcile("ber1-tor-a")
	if result.RequeueAfter != applyOrderPollInterval {
		t.Fatalf("requeue = %v", result.RequeueAfter)
	}
	if writes := h.omada.Writes(); len(writes) != 0 {
		t.Fatalf("a held switch wrote %+v", writes)
	}
	torA := h.get("ber1-tor-a")
	if c := condition(torA, v1alpha1.ConditionConverged); c.Reason != "WaitingForApplyOrder" || !strings.Contains(c.Message, "ber1-tor-b (applyOrder 1)") {
		t.Fatalf("Converged = %+v", c)
	}
	if torA.Status.Drift != v1alpha1.DriftDrifted {
		t.Fatalf("a held switch still reports what it read: drift = %q", torA.Status.Drift)
	}

	h.reconcile("ber1-mgmt")
	if got := h.omada.Switch(mgmtMAC).AdoptedWith; len(got) != 0 {
		t.Fatalf("a held switch was adopted with %+v", got)
	}
	if c := condition(h.get("ber1-mgmt"), v1alpha1.ConditionAdopted); c.Reason != "WaitingForApplyOrder" {
		t.Fatalf("Adopted = %+v", c)
	}

	h.reconcile("ber1-tor-b")
	if !isReady(h.get("ber1-tor-b")) {
		t.Fatalf("ber1-tor-b is not Ready: %+v", h.get("ber1-tor-b").Status)
	}
	h.reconcile("ber1-tor-a")
	if got := h.omada.Switch(torAMAC).Hostname; got != "ber1-tor-a" {
		t.Fatalf("once ber1-tor-b was Ready, ber1-tor-a should converge; hostname = %q", got)
	}
	h.reconcile("ber1-mgmt")
	if got := h.omada.Switch(mgmtMAC).AdoptedWith; len(got) != 1 {
		t.Fatalf("once both ToRs were Ready, ber1-mgmt should be adopted; adopted with %+v", got)
	}

	// A new render moves both ToRs at once. ber1-tor-b still carries Ready
	// from its previous revision, and that must not let ber1-tor-a go first.
	h.editSpec("ber1-tor-b", func(s *v1alpha1.RackSwitchSpec) { s.ConfigRevision = "rev-2" })
	h.editSpec("ber1-tor-a", func(s *v1alpha1.RackSwitchSpec) { s.ConfigRevision = "rev-2" })
	h.omada.ResetRequests()
	h.reconcile("ber1-tor-a")
	if got := h.switchWrites(torAMAC); len(got) != 0 {
		t.Fatalf("ber1-tor-a changed before ber1-tor-b reached its new revision: %v", got)
	}
	h.reconcile("ber1-tor-b")
	h.reconcile("ber1-tor-a")
	if got := h.get("ber1-tor-a").Status.ObservedRevision; got != "rev-2" {
		t.Fatalf("ber1-tor-a observedRevision = %q after ber1-tor-b reached rev-2", got)
	}
}

func TestAStandaloneLowerSwitchHoldsUntilPublishedAtItsRevision(t *testing.T) {
	torB := rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByStandalone)
	torB.Status = v1alpha1.RackSwitchStatus{ObservedRevision: "rev-1", Drift: v1alpha1.DriftDrifted}
	h := newHarness(t, torB, rackSwitch("ber1-tor-a", torAMAC, 2, v1alpha1.ManagedByController))
	h.connected("ber1-tor-a", torAMAC)

	h.reconcile("ber1-tor-a")
	if c := condition(h.get("ber1-tor-a"), v1alpha1.ConditionConverged); c.Reason != "WaitingForApplyOrder" {
		t.Fatalf("Converged = %+v", c)
	}

	published := h.get("ber1-tor-b")
	published.Status.Drift = v1alpha1.DriftNone
	if err := h.client.Status().Update(context.Background(), published); err != nil {
		t.Fatal(err)
	}
	h.reconcile("ber1-tor-a")
	if c := condition(h.get("ber1-tor-a"), v1alpha1.ConditionReady); c.Status != metav1.ConditionTrue {
		t.Fatalf("Ready = %+v", c)
	}
}

func TestStatusAndConditions(t *testing.T) {
	h := newHarness(t, rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController))
	h.connected("ber1-tor-b", torBMAC)

	h.reconcile("ber1-tor-b")
	rs := h.get("ber1-tor-b")
	st := rs.Status
	if !st.Adopted || !st.Reachable || st.ControllerStatus != "connected" || st.ObservedRevision != "rev-1" ||
		st.ObservedGeneration != 1 || st.Drift != v1alpha1.DriftNone || st.LastVerified == nil || !st.LastVerified.Time.Equal(h.now) {
		t.Fatalf("status = %+v", st)
	}
	for _, conditionType := range []string{v1alpha1.ConditionAdopted, v1alpha1.ConditionConverged, v1alpha1.ConditionReady} {
		if c := condition(rs, conditionType); c.Status != metav1.ConditionTrue {
			t.Fatalf("%s = %+v", conditionType, c)
		}
	}
	if st.Message != "adopted, connected, and at revision rev-1" {
		t.Fatalf("message = %q", st.Message)
	}
	h.events()

	h.omada.ResetRequests()
	h.omada.Update(torBMAC, func(sw *omadatest.Switch) { sw.Ports[2].Name = "changed in the UI" })
	h.now = h.now.Add(resync)
	h.reconcile("ber1-tor-b")
	rs = h.get("ber1-tor-b")
	if writes := h.omada.Writes(); len(writes) != 0 {
		t.Fatalf("drift was written over: %+v", writes)
	}
	if rs.Status.Drift != v1alpha1.DriftDrifted || rs.Status.ObservedRevision != "rev-1" || !rs.Status.LastVerified.Time.Equal(h.now) {
		t.Fatalf("status = %+v", rs.Status)
	}
	converged := condition(rs, v1alpha1.ConditionConverged)
	if converged.Reason != "Drifted" || !strings.Contains(converged.Message, `port 3 description is "changed in the UI", want "Port3"`) {
		t.Fatalf("Converged = %+v", converged)
	}
	if c := condition(rs, v1alpha1.ConditionReady); c.Status != metav1.ConditionFalse || c.Reason != "Drifted" {
		t.Fatalf("Ready = %+v", c)
	}
	if events := h.events(); len(events) != 1 || !strings.HasPrefix(events[0], "Warning Drifted") {
		t.Fatalf("events = %v", events)
	}
	h.reconcile("ber1-tor-b")
	if events := h.events(); len(events) != 0 {
		t.Fatalf("drift that was already reported was reported again: %v", events)
	}
}

func TestASwitchTheControllerDoesNotListIsNotSeen(t *testing.T) {
	h := newHarness(t, rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController))

	result := h.reconcile("ber1-tor-b")
	rs := h.get("ber1-tor-b")
	if c := condition(rs, v1alpha1.ConditionAdopted); c.Status != metav1.ConditionFalse || c.Reason != "NotSeen" {
		t.Fatalf("Adopted = %+v", c)
	}
	if rs.Status.Drift != v1alpha1.DriftUnknown || rs.Status.Adopted || result.RequeueAfter != resync {
		t.Fatalf("status = %+v, result = %+v", rs.Status, result)
	}
}

func TestADisconnectedSwitchIsUnreachableWithUnknownDrift(t *testing.T) {
	h := newHarness(t, rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController))
	h.omada.AddSwitch(omadatest.Switch{MAC: torBMAC, State: omadatest.Disconnected, Ports: omadatest.Ports(8)})

	h.reconcile("ber1-tor-b")
	rs := h.get("ber1-tor-b")
	if !rs.Status.Adopted || rs.Status.Reachable || rs.Status.Drift != v1alpha1.DriftUnknown || rs.Status.ControllerStatus != "disconnected" {
		t.Fatalf("status = %+v", rs.Status)
	}
	if c := condition(rs, v1alpha1.ConditionConverged); c.Reason != "Unreachable" {
		t.Fatalf("Converged = %+v", c)
	}
	if got := h.switchWrites(torBMAC); len(got) != 0 {
		t.Fatalf("wrote %v to a disconnected switch", got)
	}
}

func TestASwitchWithoutConfigIsAdoptedButNotConverged(t *testing.T) {
	rs := rackSwitch("ber1-tor-b", torBMAC, 1, v1alpha1.ManagedByController)
	rs.Spec.Config = nil
	h := newHarness(t, rs)
	h.connected("ber1-tor-b", torBMAC)

	h.reconcile("ber1-tor-b")
	got := h.get("ber1-tor-b")
	if c := condition(got, v1alpha1.ConditionConverged); c.Reason != "ConfigMissing" {
		t.Fatalf("Converged = %+v", c)
	}
	if writes := h.switchWrites(torBMAC); len(writes) != 0 {
		t.Fatalf("wrote %v with no config", writes)
	}
}
