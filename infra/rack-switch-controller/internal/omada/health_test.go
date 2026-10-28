package omada_test

import (
	"context"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada/omadatest"
)

const healthMAC = "A8-29-48-FE-B4-BE"

func TestSwitchHealthAsksForTheWindowInMilliseconds(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	temperature := 41
	fake.AddSwitch(omadatest.Switch{MAC: healthMAC, State: omadatest.Connected, Temperature: &temperature})
	c := newClient(t, fake)
	start := time.UnixMilli(1790000000000)
	end := start.Add(10 * time.Minute)

	health, err := c.SwitchHealth(context.Background(), omadatest.SiteID, "a8:29:48:fe:b4:be", start, end)
	if err != nil {
		t.Fatal(err)
	}
	if !health.Temperature.Support || health.Temperature.Average == nil || *health.Temperature.Average != 41 {
		t.Fatalf("temperature = %+v", health.Temperature)
	}
	requests := fake.Requests()
	last := requests[len(requests)-1]
	if want := "start=1790000000000&end=1790000600000"; last.Query != want {
		t.Fatalf("query = %q, want %q", last.Query, want)
	}
}

func TestSwitchHealthReportsAModelWithoutTheSensor(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	fake.AddSwitch(omadatest.Switch{MAC: healthMAC, State: omadatest.Connected})
	c := newClient(t, fake)
	now := time.Now()

	health, err := c.SwitchHealth(context.Background(), omadatest.SiteID, healthMAC, now.Add(-time.Minute), now)
	if err != nil {
		t.Fatal(err)
	}
	if health.Temperature.Support || health.Temperature.Average != nil {
		t.Fatalf("temperature = %+v, want unsupported with no average", health.Temperature)
	}
}

func TestSwitchOpticsListsEachTransceiver(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	fake.AddSwitch(omadatest.Switch{MAC: healthMAC, State: omadatest.Connected, Optics: []omada.Optic{
		{Port: 25, Temperature: ptr(38.5), DataReady: ptr(1)},
		{Port: 26, Temperature: ptr(0.0), DataReady: ptr(0)},
	}})
	c := newClient(t, fake)

	optics, err := c.SwitchOptics(context.Background(), omadatest.SiteID, healthMAC)
	if err != nil {
		t.Fatal(err)
	}
	if len(optics) != 2 {
		t.Fatalf("optics = %+v", optics)
	}
	if o := optics[0]; o.Port != 25 || o.Temperature == nil || *o.Temperature != 38.5 || !o.Valid() {
		t.Fatalf("optics[0] = %+v, want port 25 at 38.5 and valid", o)
	}
	if o := optics[1]; o.Port != 26 || o.Valid() {
		t.Fatalf("optics[1] = %+v, want port 26 and not valid", o)
	}
}

func TestOpticWithoutDataReadyIsNotValid(t *testing.T) {
	if (omada.Optic{Port: 1, Temperature: ptr(30.0)}).Valid() {
		t.Fatal("a reading the controller did not mark valid was treated as valid")
	}
}

func TestDevicesCarryUtilization(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	fake.AddSwitch(omadatest.Switch{MAC: healthMAC, State: omadatest.Connected, CPU: 7, Memory: 63})
	c := newClient(t, fake)

	devices, err := c.Devices(context.Background(), omadatest.SiteID)
	if err != nil {
		t.Fatal(err)
	}
	if len(devices) != 1 || devices[0].CPUUtil == nil || *devices[0].CPUUtil != 7 || devices[0].MemUtil == nil || *devices[0].MemUtil != 63 {
		t.Fatalf("devices = %+v", devices)
	}
}

func ptr[T any](v T) *T { return &v }
