// Tuist Labels submits previews and explicitly approved jobs to the Phoenix host.
// Bluetooth is exclusively handled by the nearby Chrome relay, not this CLI.
package main

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"
)

const help = `Tuist Labels — CLI-first rack labels, with a nearby Chrome Bluetooth relay.

Usage: tuist-labels <command>
  init <API-origin> [browser-HTTPS-origin]  Create a private eight-hour session
  links                                   Show the private Chrome connection link
  submit-text <file> [width-mm height-mm]   Queue one label per line (preview only)
  submit-png <file> [file ...]              Queue PNG previews
  status                                  Show JSON printer, supply and job status
  preview <job-id> <file.png>               Save a rendered preview without printing
  print-one <job-id>                       Request one explicitly authorized copy
  cut-once                                Request one separately authorized cut
  --help, --version

Example:
  tuist-labels init https://labels.example.com
  tuist-labels submit-text labels.txt
  tuist-labels status
  tuist-labels preview JOB-ID label.png

Open the private relay link in Chrome beside the printer and click Connect M211.
Keep the relay tab open. Zen/Firefox cannot relay Bluetooth.
Agents create sessions, prepare labels and inspect previews through this CLI;
the browser has connection/status controls only, not a preparation dashboard.
The Phoenix host must already be running. No Node runtime or printer driver is
needed on the CLI user's machine. Print/cut are disabled by default; the host
requires explicit single-use authorization. Commands never automatically retry.
M211_STATE_DIR / M211_SESSION retain compatible private credentials and markers.
Links are secrets. Do not paste links, credentials or approvals into public PRs.`

type session struct {
	ID           string `json:"id"`
	ControlToken string `json:"controlToken"`
	RelayToken   string `json:"relayToken"`
	ExpiresAt    int64  `json:"expiresAt"`
	Base         string `json:"base"`
	BrowserBase  string `json:"browserBase"`
}

type client struct {
	http *http.Client
	out  io.Writer
	file string
}

func main() {
	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	dir := os.Getenv("M211_STATE_DIR")
	if dir == "" {
		dir = filepath.Join(home, ".config", "m211-bridge")
	}
	file := os.Getenv("M211_SESSION")
	if file == "" {
		file = filepath.Join(dir, "session.json")
	}
	c := client{http: &http.Client{Timeout: 2 * time.Minute, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}, out: os.Stdout, file: file}
	if err := c.run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func origin(raw string, httpsOnly bool) (string, error) {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || (u.Path != "" && u.Path != "/") {
		return "", errors.New("use an origin URL without a path, query or credentials")
	}
	if u.Scheme != "https" && (httpsOnly || u.Scheme != "http" || (u.Hostname() != "localhost" && u.Hostname() != "127.0.0.1")) {
		return "", errors.New("use HTTPS, or loopback HTTP for local testing")
	}
	return u.Scheme + "://" + u.Host, nil
}

func (c client) request(s session, tail, method string, data any) (json.RawMessage, error) {
	base, err := origin(s.Base, false)
	if err != nil {
		return nil, err
	}
	var body io.Reader
	if data != nil {
		b, err := json.Marshal(data)
		if err != nil {
			return nil, err
		}
		body = bytes.NewReader(b)
	}
	req, err := http.NewRequest(method, base+tail, body)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	if s.ControlToken != "" {
		req.Header.Set("Authorization", "Bearer "+s.ControlToken)
	}
	// POST side effects are never retried, including after timeout or lost response.
	res, err := c.http.Do(req)
	if err != nil {
		return nil, errors.New("request failed; outcome may be uncertain—inspect status, never automatically retry output")
	}
	defer res.Body.Close()
	if !strings.Contains(res.Header.Get("Content-Type"), "application/json") {
		return nil, errors.New("host did not return JSON; check origin and portal access")
	}
	b, err := io.ReadAll(io.LimitReader(res.Body, 20*1024*1024+1))
	if err != nil || len(b) > 20*1024*1024 || !json.Valid(b) {
		return nil, errors.New("invalid or oversized JSON response")
	}
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		var result struct {
			Error string `json:"error"`
		}
		_ = json.Unmarshal(b, &result)
		return nil, fmt.Errorf("HTTP %d: %s", res.StatusCode, result.Error)
	}
	return b, nil
}

func (c client) links(s session) error {
	base := s.BrowserBase
	if base == "" {
		base = s.Base
	}
	base, err := origin(base, false)
	if err != nil {
		return err
	}
	relay := url.Values{"session": {s.ID}, "token": {s.RelayToken}}
	fmt.Fprintf(c.out, "Private Chrome connection link:\n%s/relay#%s\n\nOpen in Chrome beside the printer; keep the tab open.\nThis link expires with the eight-hour session. Keep it private.\n", base, relay.Encode())
	return nil
}

func (c client) preview(s session, job, path string) error {
	base, err := origin(s.Base, false)
	if err != nil {
		return err
	}
	req, err := http.NewRequest("GET", base+"/api/sessions/"+s.ID+"/jobs/"+url.PathEscape(job)+".png", nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+s.ControlToken)
	res, err := c.http.Do(req)
	if err != nil {
		return errors.New("preview download failed; check host access and job status")
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK || !strings.HasPrefix(res.Header.Get("Content-Type"), "image/png") {
		return fmt.Errorf("host did not return a PNG preview (HTTP %d)", res.StatusCode)
	}
	b, err := io.ReadAll(io.LimitReader(res.Body, 16_000_001))
	if err != nil || len(b) > 16_000_000 || !bytes.HasPrefix(b, []byte{137, 80, 78, 71, 13, 10, 26, 10}) {
		return errors.New("invalid or oversized PNG preview")
	}
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer f.Close()
	if _, err = f.Write(b); err != nil {
		return err
	}
	if err = f.Sync(); err != nil {
		return err
	}
	fmt.Fprintln(c.out, "Saved preview to", path, "— no printing requested.")
	return nil
}

func (c client) run(args []string) error {
	if len(args) == 0 || args[0] == "help" || args[0] == "--help" || args[0] == "-h" {
		fmt.Fprintln(c.out, help)
		return nil
	}
	command, args := args[0], args[1:]
	if command == "--version" {
		fmt.Fprintln(c.out, "Tuist Labels 0.1.0")
		return nil
	}
	if command == "init" {
		if len(args) < 1 || len(args) > 2 {
			return errors.New("usage: tuist-labels init <API-origin> [browser-HTTPS-origin]")
		}
		base, err := origin(args[0], false)
		if err != nil {
			return err
		}
		browserBase := base
		if len(args) == 2 {
			browserBase, err = origin(args[1], true)
			if err != nil {
				return err
			}
		}
		if err = os.MkdirAll(filepath.Dir(c.file), 0700); err != nil {
			return err
		}
		f, err := os.OpenFile(c.file, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
		if errors.Is(err, os.ErrExist) {
			return errors.New("saved session already exists; use links/status or choose a new private M211_STATE_DIR; never discard dispatch markers")
		}
		if err != nil {
			return err
		}
		defer f.Close()
		result, err := c.request(session{Base: base}, "/api/sessions", "POST", map[string]any{})
		if err != nil {
			_ = os.Remove(c.file)
			return err
		}
		var s session
		if err = json.Unmarshal(result, &s); err != nil || s.ID == "" || s.ControlToken == "" || s.RelayToken == "" {
			_ = os.Remove(c.file)
			return errors.New("invalid session response")
		}
		s.Base, s.BrowserBase = base, browserBase
		if err = json.NewEncoder(f).Encode(s); err == nil {
			err = f.Sync()
		}
		if err != nil {
			_ = os.Remove(c.file)
			return err
		}
		fmt.Fprintln(c.out, "Created preview-only session; private credentials saved with mode 0600.")
		return c.links(s)
	}
	if command != "links" && command != "status" && command != "preview" && command != "submit-text" && command != "submit-png" && command != "print-one" && command != "cut-once" {
		return fmt.Errorf("unknown command %q; run tuist-labels --help", command)
	}
	b, err := os.ReadFile(c.file)
	if errors.Is(err, os.ErrNotExist) {
		return errors.New("no saved session; run tuist-labels init first")
	}
	if err != nil {
		return err
	}
	var s session
	if err = json.Unmarshal(b, &s); err != nil {
		return errors.New("invalid saved session")
	}
	if s.ID == "" || strings.ContainsAny(s.ID, "/?#") || s.ControlToken == "" {
		return errors.New("invalid saved session credentials")
	}
	if err = os.Chmod(c.file, 0600); err != nil {
		return err
	}
	path, method := "/api/sessions/"+s.ID, "GET"
	var data any
	switch command {
	case "links":
		if len(args) != 0 {
			return errors.New("usage: tuist-labels links")
		}
		return c.links(s)
	case "status":
		if len(args) != 0 {
			return errors.New("usage: tuist-labels status")
		}
	case "preview":
		if len(args) != 2 {
			return errors.New("usage: tuist-labels preview <job-id> <file.png>")
		}
		return c.preview(s, args[0], args[1])
	case "print-one":
		if len(args) != 1 {
			return errors.New("usage: tuist-labels print-one <job-id>")
		}
		path += "/print"
		method = "POST"
		data = map[string]any{"jobId": args[0]}
	case "cut-once":
		if len(args) != 0 {
			return errors.New("usage: tuist-labels cut-once")
		}
		path += "/cut"
		method = "POST"
		data = map[string]any{}
	case "submit-text", "submit-png":
		if len(args) == 0 {
			return errors.New("a label file is required")
		}
		items := []map[string]string{}
		payload := map[string]any{}
		if command == "submit-text" {
			if len(args) != 1 && len(args) != 3 {
				return errors.New("usage: tuist-labels submit-text <file> [width-mm height-mm]")
			}
			b, err := os.ReadFile(args[0])
			if err != nil {
				return err
			}
			if len(b) > 24_000 {
				return errors.New("text file exceeds 24 KB")
			}
			for _, line := range strings.Split(strings.ReplaceAll(string(b), "\r\n", "\n"), "\n") {
				if strings.TrimSpace(line) != "" {
					items = append(items, map[string]string{"text": line})
				}
			}
			if len(args) == 3 {
				w, err := strconv.ParseFloat(args[1], 64)
				if err != nil {
					return errors.New("invalid width")
				}
				h, err := strconv.ParseFloat(args[2], 64)
				if err != nil {
					return errors.New("invalid height")
				}
				payload["widthMm"], payload["heightMm"] = w, h
			}
		} else {
			if len(args) > 50 {
				return errors.New("at most 50 files per batch")
			}
			for _, name := range args {
				b, err := os.ReadFile(name)
				if err != nil {
					return err
				}
				if len(b) > 2_250_000 {
					return errors.New("PNG exceeds upload size limit")
				}
				items = append(items, map[string]string{"png": base64.StdEncoding.EncodeToString(b)})
			}
		}
		if len(items) < 1 || len(items) > 50 {
			return errors.New("submit 1–50 labels per batch")
		}
		payload["items"] = items
		data = payload
		path += "/jobs"
		method = "POST"
	}
	result, err := c.request(s, path, method, data)
	if err != nil {
		return err
	}
	var pretty bytes.Buffer
	if err = json.Indent(&pretty, result, "", "  "); err != nil {
		return err
	}
	fmt.Fprintln(c.out, pretty.String())
	return nil
}
