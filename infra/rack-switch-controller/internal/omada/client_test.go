package omada_test

import (
	"context"
	"errors"
	"testing"

	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada/omadatest"
)

func newClient(t *testing.T, fake *omadatest.Server) *omada.Client {
	t.Helper()
	return omada.New(fake.URL, func() (string, string, error) {
		return omadatest.ClientID, omadatest.ClientSecret, nil
	})
}

func TestClientReusesItsToken(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	c := newClient(t, fake)
	ctx := context.Background()

	for i := 0; i < 3; i++ {
		if _, err := c.SiteID(ctx, omadatest.SiteName); err != nil {
			t.Fatal(err)
		}
	}
	if got := fake.TokensIssued(); got != 1 {
		t.Fatalf("tokens issued = %d, want 1", got)
	}
}

func TestClientIssuesANewTokenWhenTheControllerRejectsTheOldOne(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	c := newClient(t, fake)
	ctx := context.Background()

	if _, err := c.SiteID(ctx, omadatest.SiteName); err != nil {
		t.Fatal(err)
	}
	fake.ExpireTokens()
	id, err := c.SiteID(ctx, omadatest.SiteName)
	if err != nil {
		t.Fatalf("after expiry: %v", err)
	}
	if id != omadatest.SiteID {
		t.Fatalf("site id = %q", id)
	}
	if got := fake.TokensIssued(); got != 2 {
		t.Fatalf("tokens issued = %d, want 2", got)
	}
}

func TestClientIssuesANewTokenOnceItsLifetimeRunsOut(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	fake.TokenLifetime = 0
	c := newClient(t, fake)
	ctx := context.Background()

	for i := 0; i < 2; i++ {
		if _, err := c.SiteID(ctx, omadatest.SiteName); err != nil {
			t.Fatal(err)
		}
	}
	if got := fake.TokensIssued(); got != 2 {
		t.Fatalf("tokens issued = %d, want 2", got)
	}
}

func TestClientReportsTheControllersMessage(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	fake.AddSwitch(omadatest.Switch{MAC: "d4:d6:df:03:d8:b2", State: omadatest.Connected, Ports: omadatest.Ports(2)})
	c := newClient(t, fake)
	ctx := context.Background()

	fake.Update("d4:d6:df:03:d8:b2", func(sw *omadatest.Switch) { sw.Ports[0].LAGPort = true })
	ports, err := c.SwitchPorts(ctx, omadatest.SiteID, "d4:d6:df:03:d8:b2")
	if err != nil {
		t.Fatal(err)
	}
	err = c.SetPortName(ctx, omadatest.SiteID, "d4:d6:df:03:d8:b2", ports[0], "renamed")
	var apiErr *omada.Error
	if !errors.As(err, &apiErr) {
		t.Fatalf("err = %v, want an *omada.Error", err)
	}
	if apiErr.Message != "The ports in a LAG cannot be modified." {
		t.Fatalf("message = %q", apiErr.Message)
	}
}

func TestClientRefusedCredentialsAreAnError(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	c := omada.New(fake.URL, func() (string, string, error) { return omadatest.ClientID, "wrong", nil })

	_, err := c.SiteID(context.Background(), omadatest.SiteName)
	var apiErr *omada.Error
	if !errors.As(err, &apiErr) || apiErr.Code != -44106 {
		t.Fatalf("err = %v, want errorCode -44106", err)
	}
}

func TestClientUnknownSiteNamesTheOnesThereAre(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	c := newClient(t, fake)

	_, err := c.SiteID(context.Background(), "us1")
	if err == nil || err.Error() != `the controller has no site named "us1"; it has: Default, ber1` {
		t.Fatalf("err = %v", err)
	}
}

func TestDeleteSendsNoBody(t *testing.T) {
	fake := omadatest.New()
	defer fake.Close()
	mac := "d4:d6:df:03:d8:b2"
	fake.AddSwitch(omadatest.Switch{MAC: mac, State: omadatest.Connected, Ports: omadatest.Ports(4)})
	c := newClient(t, fake)
	ctx := context.Background()

	ports, err := c.SwitchPorts(ctx, omadatest.SiteID, mac)
	if err != nil {
		t.Fatal(err)
	}
	if err := c.CreateLAG(ctx, omadatest.SiteID, mac, ports[2], "isl", 1, []int{3, 4}); err != nil {
		t.Fatal(err)
	}
	if err := c.DeleteLAG(ctx, omadatest.SiteID, mac, 1); err != nil {
		t.Fatal(err)
	}
	writes := fake.Writes()
	last := writes[len(writes)-1]
	if last.Method != "DELETE" || last.Path != "/sites/site-ber1/switches/D4-D6-DF-03-D8-B2/lags/1" || last.Body != nil {
		t.Fatalf("last write = %+v", last)
	}
}

func TestControllerMAC(t *testing.T) {
	if got := omada.ControllerMAC("a8:29:48:fe:b4:be"); got != "A8-29-48-FE-B4-BE" {
		t.Fatalf("ControllerMAC = %q", got)
	}
}

func TestDeviceState(t *testing.T) {
	detail := 24
	cases := []struct {
		device omada.Device
		want   string
	}{
		{omada.Device{Status: 2, DetailStatus: &detail}, "adoption failed"},
		{omada.Device{Status: 1}, "connected"},
		{omada.Device{Status: 3}, "heartbeat missed"},
	}
	for _, tc := range cases {
		if got := tc.device.State(); got != tc.want {
			t.Errorf("State() = %q, want %q", got, tc.want)
		}
	}
}
