package podagent

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// ImageMirror is a registry that serves the images of an upstream registry
// under the same repository names: a rack's image cache, which syncs the
// upstream's images and holds them on the rack's storage node. Tart has no
// mirror configuration of its own, so a pull through one names the mirror in
// the reference and the host decides which reference to hand Tart.
type ImageMirror struct {
	// Upstream is the registry host the mirror serves, as image references
	// name it (`ghcr.io`).
	Upstream string
	// Endpoint is the mirror's base URL. An `http` endpoint is pulled with
	// `tart pull --insecure`.
	Endpoint *url.URL
}

// ParseImageMirror reads `<upstream>=<endpoint>`, as `--image-mirror` takes it.
func ParseImageMirror(raw string) (ImageMirror, error) {
	upstream, endpoint, ok := strings.Cut(raw, "=")
	if !ok || upstream == "" || endpoint == "" {
		return ImageMirror{}, fmt.Errorf("image mirror %q is not <upstream>=<endpoint>", raw)
	}
	u, err := url.Parse(endpoint)
	if err != nil {
		return ImageMirror{}, fmt.Errorf("image mirror %q: %w", raw, err)
	}
	if (u.Scheme != "http" && u.Scheme != "https") || u.Host == "" || strings.Trim(u.Path, "/") != "" || u.RawQuery != "" {
		return ImageMirror{}, fmt.Errorf("image mirror %q: the endpoint must be http(s)://host[:port]", raw)
	}
	return ImageMirror{Upstream: upstream, Endpoint: &url.URL{Scheme: u.Scheme, Host: u.Host}}, nil
}

func (m ImageMirror) String() string { return m.Upstream + "=" + m.Endpoint.String() }

// insecure reports whether Tart has to reach the mirror over plain HTTP.
func (m ImageMirror) insecure() bool { return m.Endpoint.Scheme == "http" }

// ImageSources picks where a golden base's image is pulled from: the first of
// its mirrors that holds the image, else the upstream itself. Never failing to
// fall back is the point: a mirror that is down, slow, does not hold the
// image, holds something else or fails the pull costs a slower pull from the
// upstream, and never a VM.
type ImageSources struct {
	Mirrors []ImageMirror
	// HTTP is the client mirror probes use. Nil means a client with
	// mirrorProbeTimeout as its timeout.
	HTTP *http.Client
}

const (
	// Bounds each request to a mirror. A mirror is a plain registry on the
	// rack's own segment, which answers its ping and any manifest, held or
	// not, in milliseconds; one that takes longer is treated as down.
	mirrorProbeTimeout   = 10 * time.Second
	ociManifestMediaType = "application/vnd.oci.image.manifest.v1+json"
	maxManifestBytes     = 4 << 20
)

// imagePull is one place to pull an image from.
type imagePull struct {
	ref      string
	insecure bool
	// mirror is the endpoint pulled from, empty for the upstream.
	mirror string
}

// sources returns the mirror pulls to try for image, in order: each mirror of
// the image's registry that holds it, by the digest it served. The upstream is
// not among them; the caller falls back to it.
func (s *ImageSources) sources(ctx context.Context, image string) []imagePull {
	if s == nil || len(s.Mirrors) == 0 {
		return nil
	}
	registry, repository, reference, ok := splitImageRef(image)
	if !ok {
		return nil
	}
	var pulls []imagePull
	for _, mirror := range s.Mirrors {
		if mirror.Upstream != registry {
			continue
		}
		digest, err := s.probe(ctx, mirror, repository, reference)
		if err != nil {
			recordImageMirrorProbe(mirrorProbeResult(err))
			continue
		}
		recordImageMirrorProbe("ok")
		pulls = append(pulls, imagePull{
			ref:      mirror.Endpoint.Host + "/" + repository + "@" + digest,
			insecure: mirror.insecure(),
			mirror:   mirror.Endpoint.String(),
		})
	}
	return pulls
}

var (
	errMirrorUnavailable = errors.New("mirror unavailable")
	errMirrorAbsent      = errors.New("mirror does not hold the image")
)

func mirrorProbeResult(err error) string {
	switch {
	case errors.Is(err, errMirrorUnavailable):
		return "unavailable"
	case errors.Is(err, errMirrorAbsent):
		return "absent"
	default:
		return "error"
	}
}

// probe asks the mirror for the image's manifest and returns its digest, so
// the pull that follows names exactly the manifest the mirror served.
func (s *ImageSources) probe(ctx context.Context, mirror ImageMirror, repository, reference string) (string, error) {
	client := s.HTTP
	if client == nil {
		client = &http.Client{Timeout: mirrorProbeTimeout}
	}
	ping, err := mirrorGet(ctx, client, mirror.Endpoint.JoinPath("v2/").String(), "")
	if err != nil {
		return "", fmt.Errorf("%w: %v", errMirrorUnavailable, err)
	}
	_ = ping.Body.Close()
	if ping.StatusCode != http.StatusOK && ping.StatusCode != http.StatusUnauthorized {
		return "", fmt.Errorf("%w: /v2/ answered %d", errMirrorUnavailable, ping.StatusCode)
	}

	resp, err := mirrorGet(ctx, client, mirror.Endpoint.JoinPath("v2", repository, "manifests", reference).String(), ociManifestMediaType)
	if err != nil {
		return "", fmt.Errorf("%w: %v", errMirrorUnavailable, err)
	}
	defer resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
	case http.StatusNotFound:
		return "", errMirrorAbsent
	default:
		return "", fmt.Errorf("manifest answered %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, maxManifestBytes+1))
	if err != nil {
		return "", fmt.Errorf("%w: %v", errMirrorUnavailable, err)
	}
	if len(body) > maxManifestBytes {
		return "", fmt.Errorf("manifest is larger than %d bytes", maxManifestBytes)
	}
	sum := sha256.Sum256(body)
	digest := "sha256:" + hex.EncodeToString(sum[:])
	if header := resp.Header.Get("Docker-Content-Digest"); header != "" && header != digest {
		return "", fmt.Errorf("manifest digest %s does not match the %s it was served as", digest, header)
	}
	// A Pod that names its image by digest gets exactly that manifest or the
	// upstream: anything else would be materialized under the golden that
	// digest names.
	if strings.Contains(reference, ":") && reference != digest {
		return "", fmt.Errorf("manifest digest %s does not match the requested %s", digest, reference)
	}
	return digest, nil
}

func mirrorGet(ctx context.Context, client *http.Client, target, accept string) (*http.Response, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, target, nil)
	if err != nil {
		return nil, err
	}
	if accept != "" {
		req.Header.Set("Accept", accept)
	}
	return client.Do(req)
}

// mirroredRepositories returns the repository each mirror of repository's
// registry serves it under, so the GC keeps a mirror-pulled OCI entry exactly
// as it keeps one pulled from the upstream.
func (s *ImageSources) mirroredRepositories(repository string) []string {
	if s == nil {
		return nil
	}
	registry, name, ok := strings.Cut(repository, "/")
	if !ok {
		return nil
	}
	var out []string
	for _, mirror := range s.Mirrors {
		if mirror.Upstream == registry {
			out = append(out, mirror.Endpoint.Host+"/"+name)
		}
	}
	return out
}

// splitImageRef splits a fully qualified reference into its registry,
// repository and tag or digest. A reference without a registry host, or
// without a tag or digest, is not split: only qualified references can be
// mirrored.
func splitImageRef(image string) (registry, repository, reference string, ok bool) {
	registry, rest, found := strings.Cut(image, "/")
	if !found || !strings.ContainsAny(registry, ".:") {
		return "", "", "", false
	}
	if name, digest, found := strings.Cut(rest, "@"); found {
		return registry, name, digest, name != "" && digest != ""
	}
	i := strings.LastIndexByte(rest, ':')
	if i <= 0 || strings.Contains(rest[i+1:], "/") || i == len(rest)-1 {
		return "", "", "", false
	}
	return registry, rest[:i], rest[i+1:], true
}
