// Package redfish drives the BMC of a rack x86 server over Redfish: what a
// box is, its BIOS settings, its virtual media, its next boot and its power.
//
// It is written against the AMI MegaRAC BMC (ASMB11-iKVM, AST2600) of the
// ASUS RS501A-E12, the edges' and storage nodes' platform from rack 2 on, and
// keeps to that BMC's behaviour where it departs from the standard:
//
//   - the system, manager and chassis are all `Self`;
//   - writes carry the resource's ETag in If-Match;
//   - BIOS settings are written to the pending settings object
//     (`Bios/SD`), which the BIOS applies at its next POST, and only while
//     the host is off: while it runs or is in POST the BMC answers 503, to a
//     one-time boot as well;
//   - the BIOS lists in its `MAPIDS` attribute which attributes Redfish may
//     set. Secure Boot is not one of them: it is enabled through the
//     SecureBoot resource instead;
//   - the attribute registry is served gzip-compressed;
//   - virtual media needs the OEM EnableRMedia and ConfigureCDInstance
//     actions before a CD instance exists, takes an HTTPS image only on port
//     443, and requires a user name and password for it.
package redfish

import (
	"bytes"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"
)

// ErrHostOn is returned for a write the BMC refuses because the host is
// running or in POST.
var ErrHostOn = errors.New("the BMC takes BIOS settings only while the host is off")

// Client talks to one BMC.
type Client struct {
	// Endpoint is the BMC's base URL, https://<address>.
	Endpoint string
	Username string
	Password string
	// TLSFingerprint pins the BMC's certificate by its SHA-256 (hex, colons
	// allowed). Empty accepts any certificate, which only the first contact
	// with a factory BMC does, to learn the fingerprint.
	TLSFingerprint string
	// HTTP overrides the client, for tests.
	HTTP *http.Client
}

// Error is a Redfish error answer.
type Error struct {
	Method, Path string
	Status       int
	Messages     []string
}

func (e *Error) Error() string {
	msg := strings.Join(e.Messages, "; ")
	if msg == "" {
		msg = http.StatusText(e.Status)
	}
	return fmt.Sprintf("%s %s: %d: %s", e.Method, e.Path, e.Status, msg)
}

func (c *Client) client() *http.Client {
	if c.HTTP != nil {
		return c.HTTP
	}
	pin := strings.ToLower(strings.ReplaceAll(c.TLSFingerprint, ":", ""))
	return &http.Client{
		Timeout: 60 * time.Second,
		Transport: &http.Transport{
			TLSClientConfig: &tls.Config{
				// A BMC presents a self-signed certificate for an address, so a
				// CA chain and a hostname mean nothing here; the pin does.
				InsecureSkipVerify: true,
				VerifyPeerCertificate: func(raw [][]byte, _ [][]*x509.Certificate) error {
					if pin == "" {
						return nil
					}
					if len(raw) == 0 {
						return errors.New("the BMC presented no certificate")
					}
					sum := sha256.Sum256(raw[0])
					if hex.EncodeToString(sum[:]) != pin {
						return fmt.Errorf("the BMC's certificate %x is not the pinned one", sum)
					}
					return nil
				},
			},
		},
	}
}

func (c *Client) do(ctx context.Context, method, path string, body any, header http.Header) (*http.Response, []byte, error) {
	var reader io.Reader
	if body != nil {
		b, err := json.Marshal(body)
		if err != nil {
			return nil, nil, err
		}
		reader = bytes.NewReader(b)
	}
	req, err := http.NewRequestWithContext(ctx, method, strings.TrimRight(c.Endpoint, "/")+path, reader)
	if err != nil {
		return nil, nil, err
	}
	req.SetBasicAuth(c.Username, c.Password)
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	for k, v := range header {
		req.Header[k] = v
	}
	resp, err := c.client().Do(req)
	if err != nil {
		return nil, nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 64<<20))
	if err != nil {
		return nil, nil, err
	}
	if len(data) > 2 && data[0] == 0x1f && data[1] == 0x8b {
		zr, err := gzip.NewReader(bytes.NewReader(data))
		if err != nil {
			return nil, nil, err
		}
		if data, err = io.ReadAll(io.LimitReader(zr, 256<<20)); err != nil {
			return nil, nil, err
		}
	}
	if resp.StatusCode >= 300 {
		return resp, data, redfishError(method, path, resp.StatusCode, data)
	}
	return resp, data, nil
}

func redfishError(method, path string, status int, data []byte) error {
	var answer struct {
		Error struct {
			Message string `json:"message"`
			Info    []struct {
				Message string
			} `json:"@Message.ExtendedInfo"`
		} `json:"error"`
	}
	e := &Error{Method: method, Path: path, Status: status}
	if json.Unmarshal(data, &answer) == nil {
		for _, i := range answer.Error.Info {
			e.Messages = append(e.Messages, i.Message)
		}
		if len(e.Messages) == 0 && answer.Error.Message != "" {
			e.Messages = []string{answer.Error.Message}
		}
	}
	return e
}

// Get reads a resource into out.
func (c *Client) Get(ctx context.Context, path string, out any) error {
	_, data, err := c.do(ctx, http.MethodGet, path, nil, nil)
	if err != nil {
		return err
	}
	return json.Unmarshal(data, out)
}

// Patch writes body to a resource, with its current ETag in If-Match.
func (c *Client) Patch(ctx context.Context, path string, body any) error {
	resp, _, err := c.do(ctx, http.MethodGet, path, nil, nil)
	if err != nil {
		return err
	}
	header := http.Header{}
	if etag := resp.Header.Get("ETag"); etag != "" {
		header.Set("If-Match", etag)
	}
	_, _, err = c.do(ctx, http.MethodPatch, path, body, header)
	return err
}

// Post runs an action.
func (c *Client) Post(ctx context.Context, path string, body any) error {
	_, _, err := c.do(ctx, http.MethodPost, path, body, nil)
	return err
}

// hostOn makes the BMC's refusal of a write while the host runs ErrHostOn.
func hostOn(err error) error {
	var rfErr *Error
	if errors.As(err, &rfErr) && rfErr.Status == http.StatusServiceUnavailable {
		return ErrHostOn
	}
	return err
}
