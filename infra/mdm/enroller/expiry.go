package main

// Renewal alarms for the credentials this server depends on.
//
// None of them can be renewed automatically: Apple exposes no API for the
// Push Certificates Portal or for Apple Business Manager, and Developer ID
// certificates are minted by hand. Being told early is the whole
// mitigation, which is why a critical finding also fails the process —
// a broken Slack path must not turn into silence.
//
// This lives in the enroller binary rather than a shell script in a
// sidecar image because parsing an RFC 3339 timestamp and an X.509
// NotAfter portably is exactly the kind of thing shell gets wrong: BSD
// and busybox `date` disagree with GNU `date` about -d, and the failure
// mode is a check that silently reports "no certificate present".

import (
	"crypto/x509"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

type expiryConfig struct {
	certDir      string
	nanodepURL   string
	nanodepKey   string
	depName      string
	warnDays     int
	critDays     int
	slackToken   string
	slackChannel string
}

type finding struct {
	name     string
	days     int
	critical bool
}

// readCertNotAfter returns the expiry of a PEM certificate on disk. A
// missing or empty file is not an error: these are archived copies that
// may not have been populated yet.
func readCertNotAfter(path string) (time.Time, bool, error) {
	raw, err := os.ReadFile(path)
	if err != nil || len(strings.TrimSpace(string(raw))) == 0 {
		return time.Time{}, false, nil
	}
	block, _ := pem.Decode(raw)
	if block == nil {
		return time.Time{}, false, fmt.Errorf("%s: not PEM", filepath.Base(path))
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return time.Time{}, false, fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	return cert.NotAfter, true, nil
}

func fetchDEPTokenExpiry(cfg expiryConfig, client *http.Client) (time.Time, error) {
	req, err := http.NewRequest(http.MethodGet, cfg.nanodepURL+"/v1/tokens/"+cfg.depName, nil)
	if err != nil {
		return time.Time{}, err
	}
	req.SetBasicAuth("depserver", cfg.nanodepKey)
	resp, err := client.Do(req)
	if err != nil {
		return time.Time{}, err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if resp.StatusCode >= 300 {
		return time.Time{}, fmt.Errorf("HTTP %d: %s", resp.StatusCode, body)
	}
	var t struct {
		Expiry string `json:"access_token_expiry"`
	}
	if err := json.Unmarshal(body, &t); err != nil {
		return time.Time{}, err
	}
	if t.Expiry == "" {
		return time.Time{}, fmt.Errorf("no access_token_expiry in response")
	}
	return time.Parse(time.RFC3339, t.Expiry)
}

func classify(name string, expires time.Time, now time.Time, cfg expiryConfig) (finding, bool) {
	days := int(expires.Sub(now).Hours() / 24)
	fmt.Printf("  %-32s %5d days  (%s)\n", name, days, expires.UTC().Format("2006-01-02"))
	switch {
	case days <= cfg.critDays:
		return finding{name, days, true}, true
	case days <= cfg.warnDays:
		return finding{name, days, false}, true
	}
	return finding{}, false
}

func postSlack(cfg expiryConfig, findings []finding, client *http.Client) error {
	var b strings.Builder
	b.WriteString(":key: *MDM credential renewal due* — none of these can be renewed by any API; see infra/mdm/README.md")
	for _, f := range findings {
		icon := ":warning:"
		if f.critical {
			icon = ":rotating_light:"
		}
		fmt.Fprintf(&b, "\n%s *%s* expires in *%d days*", icon, f.name, f.days)
	}
	payload, err := json.Marshal(map[string]string{"channel": cfg.slackChannel, "text": b.String()})
	if err != nil {
		return err
	}
	req, err := http.NewRequest(http.MethodPost, "https://slack.com/api/chat.postMessage", strings.NewReader(string(payload)))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+cfg.slackToken)
	req.Header.Set("Content-Type", "application/json; charset=utf-8")
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	body, _ := io.ReadAll(io.LimitReader(resp.Body, 1<<16))
	var r struct {
		OK    bool   `json:"ok"`
		Error string `json:"error"`
	}
	_ = json.Unmarshal(body, &r)
	if !r.OK {
		return fmt.Errorf("slack: %s", r.Error)
	}
	return nil
}

// runExpiryCheck returns the process exit code.
func runExpiryCheck(cfg expiryConfig, now time.Time, client *http.Client) int {
	fmt.Printf("expiry check %s (warn %dd, critical %dd)\n", now.UTC().Format(time.RFC3339), cfg.warnDays, cfg.critDays)

	var findings []finding
	worstCritical := false

	// The one source that is genuinely live rather than archived.
	if expires, err := fetchDEPTokenExpiry(cfg, client); err != nil {
		fmt.Printf("  ABM service token: UNREADABLE: %v\n", err)
		findings = append(findings, finding{"ABM service token (unreadable)", 0, true})
		worstCritical = true
	} else if f, hit := classify("ABM service token", expires, now, cfg); hit {
		findings = append(findings, f)
		worstCritical = worstCritical || f.critical
	}

	for _, c := range []struct{ name, file string }{
		{"APNs push certificate", "apns-push-cert.pem"},
		{"Developer ID Installer cert", "devid-installer-cert.pem"},
	} {
		expires, present, err := readCertNotAfter(filepath.Join(cfg.certDir, c.file))
		if err != nil {
			fmt.Printf("  %s: %v\n", c.name, err)
			continue
		}
		if !present {
			fmt.Printf("  %-32s   (no archived copy)\n", c.name)
			continue
		}
		if f, hit := classify(c.name, expires, now, cfg); hit {
			findings = append(findings, f)
			worstCritical = worstCritical || f.critical
		}
	}

	if len(findings) == 0 {
		fmt.Printf("all credentials outside the %d-day window\n", cfg.warnDays)
		return 0
	}
	if cfg.slackToken != "" && cfg.slackChannel != "" {
		if err := postSlack(cfg, findings, client); err != nil {
			fmt.Printf("WARNING: Slack post failed (%v); the exit status is the remaining signal\n", err)
		}
	}
	if worstCritical {
		return 1
	}
	return 0
}
