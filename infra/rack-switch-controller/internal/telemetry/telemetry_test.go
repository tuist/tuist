package telemetry

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/go-logr/logr"
	"github.com/prometheus/client_golang/prometheus/testutil"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada/omadatest"
)

const (
	namespace = "omada"
	mgmtMAC   = "a8:29:48:fe:b4:be"
	torMAC    = "a8:29:48:fe:c0:01"
)

var now = time.Unix(1790000000, 0)

func rackSwitch(name, mac string, managedBy v1alpha1.ManagedBy) *v1alpha1.RackSwitch {
	return &v1alpha1.RackSwitch{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace},
		Spec:       v1alpha1.RackSwitchSpec{MAC: mac, ManagedBy: managedBy},
	}
}

func newPoller(t *testing.T, fakeOmada *omadatest.Server, objects ...client.Object) (*Poller, client.Client) {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := v1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	k8s := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build()
	c := omada.New(fakeOmada.URL, func() (string, string, error) {
		return omadatest.ClientID, omadatest.ClientSecret, nil
	}, fakeOmada.RootCAs())
	p := New(c, omadatest.SiteName, k8s, namespace, logr.Discard())
	p.Now = func() time.Time { return now }
	return p, k8s
}

func expect(t *testing.T, p *Poller, exposition string, names ...string) {
	t.Helper()
	if err := testutil.CollectAndCompare(p, strings.NewReader(exposition), names...); err != nil {
		t.Fatal(err)
	}
}

const (
	helpUp          = "# HELP rack_switch_up 1 when the Omada controller reports the switch connected, 0 when it reports it in any other state.\n# TYPE rack_switch_up gauge\n"
	helpCPU         = "# HELP rack_switch_cpu_utilization_ratio CPU utilization as the Omada controller last measured it.\n# TYPE rack_switch_cpu_utilization_ratio gauge\n"
	helpMemory      = "# HELP rack_switch_memory_utilization_ratio Memory utilization as the Omada controller last measured it.\n# TYPE rack_switch_memory_utilization_ratio gauge\n"
	helpTemperature = "# HELP rack_switch_temperature_celsius Chassis temperature from the Omada controller's health detail, averaged over the last ten minutes. Absent on a model without the sensor.\n# TYPE rack_switch_temperature_celsius gauge\n"
	helpOptic       = "# HELP rack_switch_optic_temperature_celsius Transceiver temperature from its digital diagnostics.\n# TYPE rack_switch_optic_temperature_celsius gauge\n"
	helpLast        = "# HELP rack_switch_telemetry_last_success_timestamp_seconds When the switches were last read from the Omada controller.\n# TYPE rack_switch_telemetry_last_success_timestamp_seconds gauge\n"
	helpErrors      = "# HELP rack_switch_telemetry_errors_total Failed reads while polling the switches, by what was being read.\n# TYPE rack_switch_telemetry_errors_total counter\n"
)

func TestPollExportsAConnectedSwitch(t *testing.T) {
	o := omadatest.New()
	defer o.Close()
	temperature := 41
	o.AddSwitch(omadatest.Switch{MAC: mgmtMAC, State: omadatest.Connected, CPU: 7, Memory: 63, Temperature: &temperature, Optics: map[int]float64{49: 38.5}})
	p, _ := newPoller(t, o, rackSwitch("ber1-mgmt", mgmtMAC, v1alpha1.ManagedByController))

	p.poll(context.Background())

	expect(t, p, helpUp+`rack_switch_up{switch="ber1-mgmt"} 1
`+helpCPU+`rack_switch_cpu_utilization_ratio{switch="ber1-mgmt"} 0.07
`+helpMemory+`rack_switch_memory_utilization_ratio{switch="ber1-mgmt"} 0.63
`+helpTemperature+`rack_switch_temperature_celsius{switch="ber1-mgmt"} 41
`+helpOptic+`rack_switch_optic_temperature_celsius{port="49",switch="ber1-mgmt"} 38.5
`+helpLast+`rack_switch_telemetry_last_success_timestamp_seconds 1.79e+09
`,
		"rack_switch_up", "rack_switch_cpu_utilization_ratio", "rack_switch_memory_utilization_ratio",
		"rack_switch_temperature_celsius", "rack_switch_optic_temperature_celsius",
		"rack_switch_telemetry_last_success_timestamp_seconds")

	var healthQuery string
	for _, r := range o.Requests() {
		if strings.HasSuffix(r.Path, "/health/detail") {
			healthQuery = r.Query
		}
	}
	if want := "start=1789999400000&end=1790000000000"; healthQuery != want {
		t.Fatalf("health window = %q, want %q", healthQuery, want)
	}
}

func TestPollExportsNoTemperatureForAModelWithoutTheSensor(t *testing.T) {
	o := omadatest.New()
	defer o.Close()
	o.AddSwitch(omadatest.Switch{MAC: mgmtMAC, State: omadatest.Connected, CPU: 7, Memory: 63})
	p, _ := newPoller(t, o, rackSwitch("ber1-mgmt", mgmtMAC, v1alpha1.ManagedByController))

	p.poll(context.Background())

	expect(t, p, helpUp+`rack_switch_up{switch="ber1-mgmt"} 1
`, "rack_switch_up", "rack_switch_temperature_celsius")
}

func TestPollReportsADisconnectedSwitchAsDownAndNothingElse(t *testing.T) {
	o := omadatest.New()
	defer o.Close()
	o.AddSwitch(omadatest.Switch{MAC: mgmtMAC, State: omadatest.Disconnected, CPU: 7, Memory: 63})
	p, _ := newPoller(t, o, rackSwitch("ber1-mgmt", mgmtMAC, v1alpha1.ManagedByController))

	p.poll(context.Background())

	expect(t, p, helpUp+`rack_switch_up{switch="ber1-mgmt"} 0
`, "rack_switch_up", "rack_switch_cpu_utilization_ratio", "rack_switch_memory_utilization_ratio",
		"rack_switch_temperature_celsius", "rack_switch_optic_temperature_celsius")
	for _, r := range o.Requests() {
		if strings.Contains(r.Path, "/switches/") {
			t.Fatalf("read a disconnected switch: %s %s", r.Method, r.Path)
		}
	}
}

func TestPollExportsNothingForSwitchesTheControllerDoesNotManage(t *testing.T) {
	o := omadatest.New()
	defer o.Close()
	o.AddSwitch(omadatest.Switch{MAC: torMAC, State: omadatest.Connected, CPU: 3, Memory: 40})
	p, _ := newPoller(t, o,
		rackSwitch("ber1-tor-a", torMAC, v1alpha1.ManagedByStandalone),
		rackSwitch("ber1-tor-b", "", v1alpha1.ManagedByController),
		rackSwitch("ber1-mgmt", mgmtMAC, v1alpha1.ManagedByController),
	)

	p.poll(context.Background())

	expect(t, p, "", "rack_switch_up")
}

func TestPollForgetsASwitchThatIsRemoved(t *testing.T) {
	o := omadatest.New()
	defer o.Close()
	o.AddSwitch(omadatest.Switch{MAC: mgmtMAC, State: omadatest.Connected})
	o.AddSwitch(omadatest.Switch{MAC: torMAC, State: omadatest.Connected})
	tor := rackSwitch("ber1-tor-a", torMAC, v1alpha1.ManagedByController)
	p, k8s := newPoller(t, o, rackSwitch("ber1-mgmt", mgmtMAC, v1alpha1.ManagedByController), tor)
	p.poll(context.Background())

	if err := k8s.Delete(context.Background(), tor); err != nil {
		t.Fatal(err)
	}
	p.poll(context.Background())

	expect(t, p, helpUp+`rack_switch_up{switch="ber1-mgmt"} 1
`, "rack_switch_up")
}

func TestPollClearsReadingsWhenTheControllerCannotBeRead(t *testing.T) {
	o := omadatest.New()
	o.AddSwitch(omadatest.Switch{MAC: mgmtMAC, State: omadatest.Connected})
	p, _ := newPoller(t, o, rackSwitch("ber1-mgmt", mgmtMAC, v1alpha1.ManagedByController))
	p.poll(context.Background())
	o.Close()
	p.Now = func() time.Time { return now.Add(time.Minute) }

	p.poll(context.Background())

	expect(t, p, helpLast+`rack_switch_telemetry_last_success_timestamp_seconds 1.79e+09
`+helpErrors+`rack_switch_telemetry_errors_total{stage="site"} 1
`, "rack_switch_up", "rack_switch_telemetry_last_success_timestamp_seconds", "rack_switch_telemetry_errors_total")
}

func TestPollerIsLeaderOnly(t *testing.T) {
	var p Poller
	if !p.NeedLeaderElection() {
		t.Fatal("every replica would poll the controller")
	}
}
