// Package payload fetches the runner payload a Pod pins by digest and
// unpacks it into a per-digest host directory that is shared read-only into
// the guest.
package payload

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
)

const (
	Annotation     = "tuist.dev/runner-payload"
	LayerMediaType = "application/vnd.tuist.runner-payload.v1.tar+gzip"

	manifestMediaType = "application/vnd.oci.image.manifest.v1+json"
	maxManifestBytes  = 1 << 20
	maxLayerBytes     = 1 << 30
	keptPayloads      = 3
)

var refPattern = regexp.MustCompile(`^([a-z0-9.-]+(?::[0-9]+)?)/([a-z0-9._/-]+)@sha256:([a-f0-9]{64})$`)

type Reference struct {
	Registry   string
	Repository string
	Digest     string
}

func ParseReference(ref string) (Reference, error) {
	m := refPattern.FindStringSubmatch(ref)
	if m == nil {
		return Reference{}, fmt.Errorf("runner payload %q is not a <registry>/<repository>@sha256:<digest> reference", ref)
	}
	return Reference{Registry: m[1], Repository: m[2], Digest: m[3]}, nil
}

type Fetcher struct {
	Root       string
	HTTPClient *http.Client
	Scheme     string

	mu    sync.Mutex
	locks map[string]*sync.Mutex
}

// Ensure returns the unpacked payload directory for ref, downloading and
// verifying it when this host does not have it yet.
func (f *Fetcher) Ensure(ctx context.Context, ref string) (string, error) {
	parsed, err := ParseReference(ref)
	if err != nil {
		return "", err
	}
	lock := f.lock(parsed.Digest)
	lock.Lock()
	defer lock.Unlock()

	dir := filepath.Join(f.Root, parsed.Digest)
	if info, err := os.Stat(dir); err == nil && info.IsDir() {
		now := time.Now()
		_ = os.Chtimes(dir, now, now)
		return dir, nil
	}
	if err := os.MkdirAll(f.Root, 0o755); err != nil {
		return "", err
	}
	staging, err := os.MkdirTemp(f.Root, ".staging-")
	if err != nil {
		return "", err
	}
	defer os.RemoveAll(staging)

	if err := f.fetch(ctx, parsed, staging); err != nil {
		return "", fmt.Errorf("fetch runner payload %s: %w", ref, err)
	}
	if err := os.Chmod(staging, 0o755); err != nil {
		return "", err
	}
	if err := os.Rename(staging, dir); err != nil {
		return "", err
	}
	f.prune(parsed.Digest)
	return dir, nil
}

func (f *Fetcher) lock(digest string) *sync.Mutex {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.locks == nil {
		f.locks = map[string]*sync.Mutex{}
	}
	if f.locks[digest] == nil {
		f.locks[digest] = &sync.Mutex{}
	}
	return f.locks[digest]
}

type descriptor struct {
	MediaType string `json:"mediaType"`
	Digest    string `json:"digest"`
	Size      int64  `json:"size"`
}

type manifest struct {
	MediaType string       `json:"mediaType"`
	Layers    []descriptor `json:"layers"`
}

func (f *Fetcher) fetch(ctx context.Context, ref Reference, dest string) error {
	c := &registryClient{http: f.httpClient(), scheme: f.scheme(), ref: ref}

	body, err := c.get(ctx, "manifests/sha256:"+ref.Digest, manifestMediaType, maxManifestBytes)
	if err != nil {
		return err
	}
	raw, err := io.ReadAll(io.LimitReader(body, maxManifestBytes+1))
	body.Close()
	if err != nil {
		return err
	}
	if len(raw) > maxManifestBytes {
		return errors.New("manifest exceeds size limit")
	}
	if sum := sha256.Sum256(raw); hex.EncodeToString(sum[:]) != ref.Digest {
		return errors.New("manifest digest mismatch")
	}
	var m manifest
	if err := json.Unmarshal(raw, &m); err != nil {
		return fmt.Errorf("decode manifest: %w", err)
	}
	if len(m.Layers) != 1 || m.Layers[0].MediaType != LayerMediaType {
		return fmt.Errorf("manifest must carry exactly one %s layer", LayerMediaType)
	}
	layer := m.Layers[0]
	layerDigest, ok := strings.CutPrefix(layer.Digest, "sha256:")
	if !ok || len(layerDigest) != 64 {
		return fmt.Errorf("unsupported layer digest %q", layer.Digest)
	}
	if layer.Size <= 0 || layer.Size > maxLayerBytes {
		return fmt.Errorf("layer size %d outside limits", layer.Size)
	}

	blob, err := c.get(ctx, "blobs/"+layer.Digest, "", layer.Size)
	if err != nil {
		return err
	}
	defer blob.Close()

	archive, err := os.CreateTemp(filepath.Dir(dest), ".layer-")
	if err != nil {
		return err
	}
	defer os.Remove(archive.Name())
	defer archive.Close()

	hash := sha256.New()
	n, err := io.Copy(io.MultiWriter(archive, hash), io.LimitReader(blob, layer.Size+1))
	if err != nil {
		return fmt.Errorf("download layer: %w", err)
	}
	if n != layer.Size {
		return fmt.Errorf("layer is %d bytes, manifest says %d", n, layer.Size)
	}
	if hex.EncodeToString(hash.Sum(nil)) != layerDigest {
		return errors.New("layer digest mismatch")
	}
	if _, err := archive.Seek(0, io.SeekStart); err != nil {
		return err
	}
	return extract(archive, dest)
}

func extract(r io.Reader, dest string) error {
	gz, err := gzip.NewReader(r)
	if err != nil {
		return err
	}
	defer gz.Close()
	root, err := os.OpenRoot(dest)
	if err != nil {
		return err
	}
	defer root.Close()

	tr := tar.NewReader(gz)
	for {
		hdr, err := tr.Next()
		if errors.Is(err, io.EOF) {
			return nil
		}
		if err != nil {
			return err
		}
		name := filepath.Clean(strings.TrimPrefix(hdr.Name, "./"))
		if name == "." {
			continue
		}
		if !filepath.IsLocal(name) {
			return fmt.Errorf("archive entry %q escapes the payload root", hdr.Name)
		}
		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := root.MkdirAll(name, 0o755); err != nil {
				return err
			}
		case tar.TypeReg:
			if dir := filepath.Dir(name); dir != "." {
				if err := root.MkdirAll(dir, 0o755); err != nil {
					return err
				}
			}
			mode := os.FileMode(0o644)
			if hdr.FileInfo().Mode()&0o111 != 0 {
				mode = 0o755
			}
			out, err := root.OpenFile(name, os.O_CREATE|os.O_EXCL|os.O_WRONLY, mode)
			if err != nil {
				return err
			}
			if _, err := io.Copy(out, tr); err != nil {
				out.Close()
				return err
			}
			if err := out.Close(); err != nil {
				return err
			}
			if err := root.Chmod(name, mode); err != nil {
				return err
			}
		default:
			return fmt.Errorf("archive entry %q has unsupported type %q", hdr.Name, hdr.Typeflag)
		}
	}
}

func (f *Fetcher) prune(current string) {
	entries, err := os.ReadDir(f.Root)
	if err != nil {
		return
	}
	type cached struct {
		name    string
		modTime time.Time
	}
	var payloads []cached
	for _, e := range entries {
		if !e.IsDir() || e.Name() == current || strings.HasPrefix(e.Name(), ".") {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		payloads = append(payloads, cached{e.Name(), info.ModTime()})
	}
	sort.Slice(payloads, func(i, j int) bool { return payloads[i].modTime.After(payloads[j].modTime) })
	for i, p := range payloads {
		if i >= keptPayloads-1 {
			_ = os.RemoveAll(filepath.Join(f.Root, p.name))
		}
	}
}

func (f *Fetcher) httpClient() *http.Client {
	if f.HTTPClient != nil {
		return f.HTTPClient
	}
	return &http.Client{Timeout: 5 * time.Minute}
}

func (f *Fetcher) scheme() string {
	if f.Scheme != "" {
		return f.Scheme
	}
	return "https"
}

type registryClient struct {
	http   *http.Client
	scheme string
	ref    Reference
	token  string
}

func (c *registryClient) get(ctx context.Context, path, accept string, limit int64) (io.ReadCloser, error) {
	u := fmt.Sprintf("%s://%s/v2/%s/%s", c.scheme, c.ref.Registry, c.ref.Repository, path)
	resp, err := c.do(ctx, u, accept)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode == http.StatusUnauthorized && c.token == "" {
		challenge := resp.Header.Get("WWW-Authenticate")
		resp.Body.Close()
		if c.token, err = c.authenticate(ctx, challenge); err != nil {
			return nil, err
		}
		if resp, err = c.do(ctx, u, accept); err != nil {
			return nil, err
		}
	}
	if resp.StatusCode != http.StatusOK {
		resp.Body.Close()
		return nil, fmt.Errorf("GET %s: %s", u, resp.Status)
	}
	if resp.ContentLength > limit {
		resp.Body.Close()
		return nil, fmt.Errorf("GET %s: %d bytes exceeds the %d byte limit", u, resp.ContentLength, limit)
	}
	return resp.Body, nil
}

func (c *registryClient) do(ctx context.Context, u, accept string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
	if err != nil {
		return nil, err
	}
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
	if c.token != "" {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	return c.http.Do(req)
}

var challengeParam = regexp.MustCompile(`(\w+)="([^"]*)"`)

func (c *registryClient) authenticate(ctx context.Context, challenge string) (string, error) {
	scheme, params, ok := strings.Cut(challenge, " ")
	if !ok || !strings.EqualFold(scheme, "Bearer") {
		return "", fmt.Errorf("unsupported registry auth challenge %q", challenge)
	}
	values := map[string]string{}
	for _, m := range challengeParam.FindAllStringSubmatch(params, -1) {
		values[m[1]] = m[2]
	}
	realm, err := url.Parse(values["realm"])
	if err != nil || realm.Host == "" {
		return "", fmt.Errorf("registry auth challenge has no realm: %q", challenge)
	}
	q := realm.Query()
	if s := values["service"]; s != "" {
		q.Set("service", s)
	}
	q.Set("scope", "repository:"+c.ref.Repository+":pull")
	realm.RawQuery = q.Encode()

	resp, err := c.do(ctx, realm.String(), "")
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("anonymous pull token: %s", resp.Status)
	}
	var token struct {
		Token       string `json:"token"`
		AccessToken string `json:"access_token"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxManifestBytes)).Decode(&token); err != nil {
		return "", fmt.Errorf("decode pull token: %w", err)
	}
	if token.Token != "" {
		return token.Token, nil
	}
	if token.AccessToken != "" {
		return token.AccessToken, nil
	}
	return "", errors.New("registry returned an empty pull token")
}
