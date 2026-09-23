package converge_test

import (
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/rack-switch-controller/internal/converge"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/omada/omadatest"
)

const (
	torMAC            = "d4:d6:df:03:d8:b2"
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

func newEngine(t *testing.T, gates converge.Gates) (*omadatest.Server, *converge.Engine) {
	t.Helper()
	fake := omadatest.New()
	t.Cleanup(fake.Close)
	client := omada.New(fake.URL, func() (string, string, error) { return creds.ClientID, creds.ClientSecret, nil })
	return fake, &converge.Engine{Omada: client, Site: omadatest.SiteName, ControllerAddress: controllerAddress, Gates: gates}
}

func TestEnsureSiteWritesOnlyWhatDiffers(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	ctx := context.Background()

	changes, err := engine.EnsureSite(ctx, omadatest.SiteID, deviceAccount)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 3 {
		t.Fatalf("changes = %v, want device host, SSH and device account", changes)
	}
	for _, c := range changes {
		if strings.Contains(c.String(), deviceAccount.Password) || strings.Contains(c.String(), "wizard-password") {
			t.Fatalf("a change names a password: %s", c)
		}
	}
	if got := fake.DeviceHost(); got != controllerAddress {
		t.Fatalf("device host = %q", got)
	}
	ssh := fake.SSH()
	if ssh["sshEnable"] != true || ssh["sshServerPort"] != float64(22) || ssh["layer3Access"] != false {
		t.Fatalf("ssh = %v", ssh)
	}
	if got := fake.Account(); got != deviceAccount {
		t.Fatalf("device account = %+v", got)
	}

	writes := len(fake.Writes())
	changes, err = engine.EnsureSite(ctx, omadatest.SiteID, deviceAccount)
	if err != nil {
		t.Fatal(err)
	}
	if len(changes) != 0 || len(fake.Writes()) != writes {
		t.Fatalf("second pass wrote %v", changes)
	}
}

// adoptUntilConnected polls the way the reconciler and the apply command do,
// and returns every note and the login the adoption finished with.
func adoptUntilConnected(t *testing.T, fake *omadatest.Server, engine *converge.Engine, now func() time.Time) ([]converge.Note, converge.AdoptionOutcome, *converge.Attempt) {
	t.Helper()
	ctx := context.Background()
	var (
		notes   []converge.Note
		attempt *converge.Attempt
	)
	for i := 0; i < 20; i++ {
		dev, err := engine.Find(ctx, omadatest.SiteID, torMAC)
		if err != nil {
			t.Fatal(err)
		}
		if dev == nil {
			t.Fatal("the switch is not in the site")
		}
		if dev.Status == omada.StatusConnected {
			return notes, converge.AdoptionWaiting, attempt
		}
		adoption, err := engine.Adopt(ctx, omadatest.SiteID, *dev, attempt, creds, now())
		if err != nil {
			t.Fatal(err)
		}
		notes = append(notes, adoption.Notes...)
		if adoption.Outcome != converge.AdoptionWaiting {
			return notes, adoption.Outcome, nil
		}
		attempt = adoption.Attempt
	}
	t.Fatal("adoption never finished")
	return nil, 0, nil
}

func reasons(notes []converge.Note) string {
	var r []string
	for _, n := range notes {
		r = append(r, n.Reason)
	}
	return strings.Join(r, ",")
}

func TestAdoptWithTheDeviceAccount(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	fake.AddSwitch(omadatest.Switch{MAC: torMAC, State: omadatest.Pending, Logins: []omada.Login{deviceAccount}})

	notes, _, attempt := adoptUntilConnected(t, fake, engine, time.Now)
	if attempt == nil || attempt.Login != converge.LoginDeviceAccount {
		t.Fatalf("attempt = %+v", attempt)
	}
	if got := fake.Switch(torMAC).AdoptedWith; len(got) != 1 || got[0] != deviceAccount {
		t.Fatalf("adopted with %+v", got)
	}
	if reasons(notes) != "AdoptionStarted" {
		t.Fatalf("notes = %v", notes)
	}
}

func TestAdoptFallsBackToTheFactoryLogin(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	fake.AddSwitch(omadatest.Switch{MAC: torMAC, State: omadatest.Pending, Logins: []omada.Login{converge.DefaultFactoryLogin}})

	notes, _, attempt := adoptUntilConnected(t, fake, engine, time.Now)
	if attempt == nil || attempt.Login != converge.LoginFactory {
		t.Fatalf("attempt = %+v", attempt)
	}
	got := fake.Switch(torMAC).AdoptedWith
	if len(got) != 2 || got[0] != deviceAccount || got[1] != converge.DefaultFactoryLogin {
		t.Fatalf("adopted with %+v", got)
	}
	if reasons(notes) != "AdoptionStarted,AdoptionRetried,AdoptionStarted" {
		t.Fatalf("notes = %v", notes)
	}
}

func TestAdoptWaitsOutAFailureLeftByAnEarlierAttempt(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	fake.AddSwitch(omadatest.Switch{MAC: torMAC, State: omadatest.AdoptionFailed, Logins: []omada.Login{deviceAccount}})

	_, _, attempt := adoptUntilConnected(t, fake, engine, time.Now)
	if attempt == nil || attempt.Login != converge.LoginDeviceAccount {
		t.Fatalf("attempt = %+v", attempt)
	}
	if got := fake.Switch(torMAC).AdoptedWith; len(got) != 1 {
		t.Fatalf("adopted with %+v; the stale failure was taken for this attempt's", got)
	}
}

func TestAdoptGivesUpOnceBothLoginsFail(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	fake.AddSwitch(omadatest.Switch{MAC: torMAC, State: omadatest.Pending})

	notes, outcome, _ := adoptUntilConnected(t, fake, engine, time.Now)
	if outcome != converge.AdoptionFailed {
		t.Fatalf("outcome = %v", outcome)
	}
	if reasons(notes) != "AdoptionStarted,AdoptionRetried,AdoptionStarted,AdoptionFailed" {
		t.Fatalf("notes = %v", notes)
	}
}

func TestAdoptCountsAnAttemptThatNeverConnectsAsFailed(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	fake.AddSwitch(omadatest.Switch{MAC: torMAC, State: omadatest.Pending})
	ctx := context.Background()

	start := time.Now()
	dev, _ := engine.Find(ctx, omadatest.SiteID, torMAC)
	adoption, err := engine.Adopt(ctx, omadatest.SiteID, *dev, nil, creds, start)
	if err != nil {
		t.Fatal(err)
	}
	fake.Update(torMAC, func(sw *omadatest.Switch) { sw.State = omadatest.Adopting })
	dev.Status, dev.DetailStatus = omada.StatusPending, nil
	adoption, err = engine.Adopt(ctx, omadatest.SiteID, *dev, adoption.Attempt, creds, start.Add(converge.AdoptTimeout+time.Second))
	if err != nil {
		t.Fatal(err)
	}
	if adoption.Attempt == nil || adoption.Attempt.Login != converge.LoginFactory {
		t.Fatalf("attempt = %+v, want a fresh one with the factory login", adoption.Attempt)
	}
}

func TestAdoptRefusesASwitchAnotherControllerManages(t *testing.T) {
	_, engine := newEngine(t, converge.Gates{})
	detail := omada.DetailManagedByOthers
	adoption, err := engine.Adopt(context.Background(), omadatest.SiteID, omada.Device{MAC: "D4-D6-DF-03-D8-B2", Status: omada.StatusPending, DetailStatus: &detail}, nil, creds, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	if adoption.Outcome != converge.AdoptionManagedByOthers {
		t.Fatalf("outcome = %v", adoption.Outcome)
	}
}

func TestFindLooksInThePendingListToo(t *testing.T) {
	fake, engine := newEngine(t, converge.Gates{})
	fake.AddSwitch(omadatest.Switch{MAC: torMAC, State: omadatest.Pending})

	dev, err := engine.Find(context.Background(), omadatest.SiteID, torMAC)
	if err != nil || dev == nil || dev.MAC != "D4-D6-DF-03-D8-B2" {
		t.Fatalf("dev = %+v, err = %v", dev, err)
	}
	missing, err := engine.Find(context.Background(), omadatest.SiteID, "a8:29:48:fe:b4:be")
	if err != nil || missing != nil {
		t.Fatalf("missing = %+v, err = %v", missing, err)
	}
}

func TestLoadCredentials(t *testing.T) {
	write := func(t *testing.T, files map[string]string) string {
		dir := t.TempDir()
		for name, value := range files {
			if err := os.WriteFile(filepath.Join(dir, name), []byte(value), 0o600); err != nil {
				t.Fatal(err)
			}
		}
		return dir
	}
	base := map[string]string{"client-id": "id\n", "client-secret": "secret", "device-username": "tuist", "device-password": "Device-Pass1!\n"}

	got, err := converge.LoadCredentials(write(t, base))
	if err != nil {
		t.Fatal(err)
	}
	if got.ClientID != "id" || got.DeviceAccount.Password != "Device-Pass1!" || got.FactoryLogin != converge.DefaultFactoryLogin {
		t.Fatalf("credentials = %+v", got)
	}

	withFactory := map[string]string{"factory-username": "root", "factory-password": "hunter2"}
	for k, v := range base {
		withFactory[k] = v
	}
	got, err = converge.LoadCredentials(write(t, withFactory))
	if err != nil || got.FactoryLogin != (omada.Login{Username: "root", Password: "hunter2"}) {
		t.Fatalf("factory login = %+v, err = %v", got.FactoryLogin, err)
	}

	halfFactory := map[string]string{"factory-username": "root"}
	for k, v := range base {
		halfFactory[k] = v
	}
	if _, err := converge.LoadCredentials(write(t, halfFactory)); err == nil {
		t.Fatal("a factory username without a password was accepted")
	}

	delete(base, "device-password")
	if _, err := converge.LoadCredentials(write(t, base)); err == nil || !strings.Contains(err.Error(), "device-password") {
		t.Fatalf("err = %v, want device-password named", err)
	}
}
