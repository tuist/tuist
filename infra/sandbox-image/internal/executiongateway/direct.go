package executiongateway

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
)

// Direct execution: while a project is active, the gateway holds a VM the
// control plane leased to it and runs the project's next action by claiming
// that VM's pending exec on its node. The control plane still authorizes
// credentials, bounds capacity and owns every VM; a lease only takes its
// request path out of one action. Without a lease, or for a credential the
// control plane has not authorized within authorizationTTL, Execute submits
// to the control plane.

const (
	// The control plane reuses its authorization decisions as long.
	authorizationTTL = 10 * time.Second
	// A project stays leased this long after its last action.
	leaseIdle        = time.Minute
	leaseRetry       = time.Second
	leaseUnsupported = time.Minute
	maxProjects      = 4096
	maxStdout        = 256 << 10
)

type lease struct {
	SandboxID   string `json:"sandbox_id"`
	Endpoint    string `json:"endpoint"`
	Nonce       []byte `json:"nonce"`
	Image       string `json:"image"`
	CASEndpoint string `json:"cas_endpoint"`
	ExpiresInMs int64  `json:"expires_in_ms"`
	expires     time.Time
}

type projectLeases struct {
	auth        string
	active      time.Time
	lease       *lease
	wake        chan struct{}
	running     bool
	unsupported time.Time
}

// direct runs the action on a leased VM. ok is false when the action must
// go to the control plane instead; the leased VM is then released unused or
// already consumed, and either way the control plane replaces it.
func (g *Gateway) direct(ctx context.Context, account, project, auth string, r *re.ExecuteRequest, inputs string) (operation, bool) {
	admitted := time.Now()
	g.touch(account, project, auth)
	if !g.authorized(auth, account, project) {
		return operation{}, false
	}
	l := g.take(account, project)
	if l == nil {
		return operation{}, false
	}
	request := map[string]any{"endpoint": l.CASEndpoint, "account": account, "instance": project, "hash": r.ActionDigest.Hash, "size": r.ActionDigest.SizeBytes, "image": l.Image}
	if inputs != "" {
		request["inputs"] = inputs
	}
	value, _ := json.Marshal(request)
	body, _ := json.Marshal(map[string]any{"sandbox_id": l.SandboxID, "nonce": l.Nonce, "value": string(value)})
	claim, err := http.NewRequestWithContext(ctx, http.MethodPost, l.Endpoint+"/v1/claims", bytes.NewReader(body))
	if err != nil {
		return operation{}, false
	}
	claim.Header.Set("Content-Type", "application/json")
	response, err := g.Direct.Do(claim)
	if err != nil {
		return operation{}, false
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return operation{}, false
	}
	var outcome struct {
		ExitCode int    `json:"exit_code"`
		Stdout   []byte `json:"stdout"`
	}
	if err := json.NewDecoder(io.LimitReader(response.Body, 2*maxStdout)).Decode(&outcome); err != nil {
		return operation{}, false
	}
	op := operation{ID: newOperationID(), State: "completed", Done: true, QueuedAtUnixUS: admitted.UnixMicro()}
	var result struct {
		Response  string `json:"response"`
		Cacheable *bool  `json:"cacheable"`
	}
	switch {
	case outcome.ExitCode != 0 || len(outcome.Stdout) > maxStdout:
		op.Code, op.Message = 14, "execution worker failed"
	case json.Unmarshal(outcome.Stdout, &result) != nil || result.Cacheable == nil || base64.StdEncoding.DecodedLen(len(result.Response)) > worker.MaxResponse:
		op.Code, op.Message = 13, "invalid execution result"
	default:
		op.Response = result.Response
		if *result.Cacheable {
			op.Cacheable, op.ActionHash, op.ActionSize, op.CASEndpoint = true, r.ActionDigest.Hash, r.ActionDigest.SizeBytes, l.CASEndpoint
		}
	}
	return op, true
}

func newOperationID() string {
	var b [16]byte
	_, _ = rand.Read(b[:])
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

func authorizationKey(auth, account, project string) [sha256.Size]byte {
	return sha256.Sum256([]byte(auth + "\x00" + account + "\x00" + project))
}

// rememberAuthorization records that the control plane accepted auth for
// executing in the project, for as long as it reuses that decision itself.
func (g *Gateway) rememberAuthorization(auth, account, project string) {
	expires := time.Now().Add(authorizationTTL)
	if exp, ok := tokenExpiry(auth); !ok {
		return
	} else if exp.Before(expires) {
		expires = exp
	}
	g.mu.Lock()
	defer g.mu.Unlock()
	if len(g.authorizations) >= maxProjects {
		clear(g.authorizations)
	}
	g.authorizations[authorizationKey(auth, account, project)] = expires
}

func (g *Gateway) authorized(auth, account, project string) bool {
	g.mu.Lock()
	defer g.mu.Unlock()
	expires, ok := g.authorizations[authorizationKey(auth, account, project)]
	return ok && time.Now().Before(expires)
}

// tokenExpiry reads a JWT credential's expiry without verifying it; only the
// control plane's acceptance makes it trusted.
func tokenExpiry(auth string) (time.Time, bool) {
	parts := strings.Split(strings.TrimPrefix(auth, "Bearer "), ".")
	if len(parts) != 3 {
		return time.Time{}, false
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return time.Time{}, false
	}
	var claims struct {
		Exp *int64 `json:"exp"`
	}
	if json.Unmarshal(payload, &claims) != nil || claims.Exp == nil {
		return time.Time{}, false
	}
	return time.Unix(*claims.Exp, 0), true
}

// touch marks the project active with the credential of its latest action
// and keeps a lease for it.
func (g *Gateway) touch(account, project, auth string) {
	if !g.leasable(account, project) {
		return
	}
	key := account + "/" + project
	g.mu.Lock()
	defer g.mu.Unlock()
	p, ok := g.projects[key]
	if !ok {
		if len(g.projects) >= maxProjects {
			return
		}
		p = &projectLeases{wake: make(chan struct{}, 1)}
		g.projects[key] = p
	}
	p.auth, p.active = auth, time.Now()
	if !p.running {
		p.running = true
		go g.keepLeased(key, account, project, p)
	}
}

func (g *Gateway) take(account, project string) *lease {
	g.mu.Lock()
	defer g.mu.Unlock()
	p, ok := g.projects[account+"/"+project]
	if !ok || p.lease == nil || !time.Now().Before(p.lease.expires) {
		return nil
	}
	l := p.lease
	p.lease = nil
	select {
	case p.wake <- struct{}{}:
	default:
	}
	return l
}

// keepLeased holds one lease for the project until it has been idle for
// leaseIdle, replacing each lease once used or expired.
func (g *Gateway) keepLeased(key, account, project string, p *projectLeases) {
	for {
		g.mu.Lock()
		now := time.Now()
		if now.Sub(p.active) > leaseIdle || now.Before(p.unsupported) {
			p.lease, p.running = nil, false
			if now.Sub(p.active) > leaseIdle {
				delete(g.projects, key)
			}
			g.mu.Unlock()
			return
		}
		if p.lease != nil && now.Before(p.lease.expires) {
			wait := p.lease.expires.Sub(now)
			g.mu.Unlock()
			select {
			case <-p.wake:
			case <-time.After(wait):
			}
			continue
		}
		p.lease = nil
		auth := p.auth
		g.mu.Unlock()

		l, code := g.requestLease(account, project, auth)
		switch code {
		case http.StatusOK, http.StatusNoContent:
			g.rememberAuthorization(auth, account, project)
			if l != nil {
				g.remember(account, project, l.CASEndpoint, true)
			}
			g.mu.Lock()
			p.lease = l
			g.mu.Unlock()
		case http.StatusNotFound:
			g.mu.Lock()
			p.unsupported = time.Now().Add(leaseUnsupported)
			g.mu.Unlock()
		default:
			time.Sleep(leaseRetry)
		}
	}
}

func (g *Gateway) requestLease(account, project, auth string) (*lease, int) {
	u := g.URL + "/api/remote-execution/" + url.PathEscape(account) + "/" + url.PathEscape(project) + "/leases"
	r, err := http.NewRequest(http.MethodPost, u, http.NoBody)
	if err != nil {
		return nil, 0
	}
	r.Header.Set("Authorization", auth)
	response, err := g.Client.Do(r)
	if err != nil {
		return nil, 0
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, response.StatusCode
	}
	var l lease
	if err := json.NewDecoder(io.LimitReader(response.Body, 64<<10)).Decode(&l); err != nil || len(l.Nonce) != 32 || l.SandboxID == "" || l.ExpiresInMs <= 0 ||
		!(strings.HasPrefix(l.Endpoint, "http://") || strings.HasPrefix(l.Endpoint, "https://")) {
		return nil, 0
	}
	l.expires = time.Now().Add(time.Duration(l.ExpiresInMs) * time.Millisecond)
	return &l, http.StatusOK
}
