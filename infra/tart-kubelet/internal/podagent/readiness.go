package podagent

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
	"sigs.k8s.io/controller-runtime/pkg/event"
)

// Readiness probing for Tart Pods.
//
// A Pod whose container declares a readinessProbe gets one prober
// goroutine per VM, started the first time the guest has an IP. The
// prober runs on its own period against the guest's IP and keeps the
// result in memory; podStatus only reads that result, so the reconcile
// path never waits on a guest. A Pod without a readinessProbe never
// starts one and keeps reading Ready as soon as its VM has an IP.
//
// Only httpGet and tcpSocket are evaluated. exec would need a guest
// agent and gRPC is unused, so a probe with either handler is treated as
// absent (VM-IP readiness) and reported through a Warning event.
//
// A prober never sits on the deletion path: deleteByKey cancels it
// without waiting, and the in-flight probe aborts with its context.

const (
	defaultReadinessPeriod  = 10 * time.Second
	defaultReadinessTimeout = 1 * time.Second
	// maxReadinessTimeout caps a single probe. A guest that accepts the
	// connection and then hangs must not hold a prober for longer than
	// this, whatever the PodSpec asks for.
	maxReadinessTimeout       = 10 * time.Second
	defaultSuccessThreshold   = 1
	defaultFailureThreshold   = 3
	maxReadinessResponseBytes = 10 << 10
)

var errUnsupportedReadinessProbe = errors.New("readinessProbe handler is not supported by tart-kubelet (only httpGet and tcpSocket)")

// readinessHTTPClient is shared by every prober. Mirrors the kubelet:
// no keep-alives (each probe is a fresh connection, so a wedged
// listener is noticed), no proxy from the host environment, redirects
// are not followed (a 3xx counts as success), and HTTPS skips
// verification because the guest's certificate is not something the
// host can validate.
var readinessHTTPClient = &http.Client{
	Transport: &http.Transport{
		Proxy:             nil,
		DisableKeepAlives: true,
		TLSClientConfig:   &tls.Config{InsecureSkipVerify: true}, //nolint:gosec // see above
	},
	CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse },
}

// readinessProbeFor returns the Pod's readinessProbe, or nil when it has
// none. errUnsupportedReadinessProbe means a probe is declared with a
// handler this runtime cannot evaluate.
func readinessProbeFor(pod *corev1.Pod) (*corev1.Probe, error) {
	if len(pod.Spec.Containers) == 0 {
		return nil, nil
	}
	probe := pod.Spec.Containers[0].ReadinessProbe
	if probe == nil {
		return nil, nil
	}
	if probe.HTTPGet == nil && probe.TCPSocket == nil {
		return nil, errUnsupportedReadinessProbe
	}
	return probe, nil
}

// readinessProber evaluates one Pod's readinessProbe against its guest.
type readinessProber struct {
	container        corev1.Container
	probe            corev1.Probe
	startedAt        time.Time
	period           time.Duration
	timeout          time.Duration
	successThreshold int
	failureThreshold int
	// onResult is called from the prober goroutine after every probe
	// with the new readiness, whether it changed, and the probe error.
	onResult func(ready, changed bool, err error)

	mu        sync.Mutex
	target    string
	ready     bool
	successes int
	failures  int

	cancel context.CancelFunc
	done   chan struct{}
}

// newReadinessProber builds a prober for container's readinessProbe.
// startedAt anchors initialDelaySeconds, as the container start does on
// a real kubelet. initiallyReady seeds the result so a tart-kubelet
// restart does not flip an already-Ready Pod to NotReady while the
// first probe is pending; a fresh Pod starts NotReady.
func newReadinessProber(
	container corev1.Container,
	startedAt time.Time,
	initiallyReady bool,
	onResult func(ready, changed bool, err error),
) *readinessProber {
	probe := *container.ReadinessProbe
	period := time.Duration(probe.PeriodSeconds) * time.Second
	if period <= 0 {
		period = defaultReadinessPeriod
	}
	timeout := time.Duration(probe.TimeoutSeconds) * time.Second
	if timeout <= 0 {
		timeout = defaultReadinessTimeout
	}
	timeout = min(timeout, maxReadinessTimeout)
	successThreshold := int(probe.SuccessThreshold)
	if successThreshold <= 0 {
		successThreshold = defaultSuccessThreshold
	}
	failureThreshold := int(probe.FailureThreshold)
	if failureThreshold <= 0 {
		failureThreshold = defaultFailureThreshold
	}
	return &readinessProber{
		container:        container,
		probe:            probe,
		startedAt:        startedAt,
		period:           period,
		timeout:          timeout,
		successThreshold: successThreshold,
		failureThreshold: failureThreshold,
		onResult:         onResult,
		ready:            initiallyReady,
	}
}

// Start launches the probe loop against ip. Idempotent.
func (p *readinessProber) Start(ip string) {
	p.SetTarget(ip)
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.cancel != nil {
		return
	}
	ctx, cancel := context.WithCancel(context.Background())
	p.cancel = cancel
	p.done = make(chan struct{})
	go p.run(ctx, p.done)
}

// Stop cancels the probe loop and returns without waiting for it.
func (p *readinessProber) Stop() {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.cancel != nil {
		p.cancel()
	}
}

// SetTarget points subsequent probes at ip.
func (p *readinessProber) SetTarget(ip string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.target = ip
}

// Ready reports the latest readiness result.
func (p *readinessProber) Ready() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.ready
}

func (p *readinessProber) run(ctx context.Context, done chan struct{}) {
	defer close(done)
	delay := time.Until(p.startedAt.Add(time.Duration(p.probe.InitialDelaySeconds) * time.Second))
	if delay > 0 {
		timer := time.NewTimer(delay)
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
	}
	ticker := time.NewTicker(p.period)
	defer ticker.Stop()
	for {
		p.mu.Lock()
		target := p.target
		p.mu.Unlock()
		err := p.check(ctx, target)
		if ctx.Err() != nil {
			return
		}
		p.record(err)
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

// record folds one probe result into the readiness state with the
// kubelet's semantics: successThreshold consecutive successes make a
// NotReady Pod Ready, failureThreshold consecutive failures make a Ready
// Pod NotReady, and anything in between keeps the current result.
func (p *readinessProber) record(err error) {
	p.mu.Lock()
	was := p.ready
	if err == nil {
		p.successes++
		p.failures = 0
		if p.successes >= p.successThreshold {
			p.ready = true
		}
	} else {
		p.failures++
		p.successes = 0
		if p.failures >= p.failureThreshold {
			p.ready = false
		}
	}
	ready := p.ready
	p.mu.Unlock()
	if p.onResult != nil {
		p.onResult(ready, ready != was, err)
	}
}

// check runs a single probe against ip, bounded by the probe timeout.
func (p *readinessProber) check(ctx context.Context, ip string) error {
	if ip == "" {
		return errors.New("guest has no IP")
	}
	ctx, cancel := context.WithTimeout(ctx, p.timeout)
	defer cancel()

	switch {
	case p.probe.HTTPGet != nil:
		return p.checkHTTP(ctx, ip, p.probe.HTTPGet)
	case p.probe.TCPSocket != nil:
		port, err := resolveProbePort(p.probe.TCPSocket.Port, p.container)
		if err != nil {
			return err
		}
		var dialer net.Dialer
		conn, err := dialer.DialContext(ctx, "tcp", net.JoinHostPort(ip, strconv.Itoa(port)))
		if err != nil {
			return err
		}
		return conn.Close()
	default:
		return errUnsupportedReadinessProbe
	}
}

// checkHTTP always targets the guest IP; httpGet.host is ignored so a
// PodSpec cannot point the host's prober at another address.
func (p *readinessProber) checkHTTP(ctx context.Context, ip string, action *corev1.HTTPGetAction) error {
	port, err := resolveProbePort(action.Port, p.container)
	if err != nil {
		return err
	}
	scheme := strings.ToLower(string(action.Scheme))
	if scheme == "" {
		scheme = "http"
	}
	path := action.Path
	if !strings.HasPrefix(path, "/") {
		path = "/" + path
	}
	u, err := url.Parse(path)
	if err != nil {
		return fmt.Errorf("parse probe path %q: %w", action.Path, err)
	}
	u.Scheme = scheme
	u.Host = net.JoinHostPort(ip, strconv.Itoa(port))

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "tart-kubelet/readiness-probe")
	for _, h := range action.HTTPHeaders {
		if strings.EqualFold(h.Name, "Host") {
			req.Host = h.Value
			continue
		}
		req.Header.Set(h.Name, h.Value)
	}
	resp, err := readinessHTTPClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, maxReadinessResponseBytes))
	if resp.StatusCode < http.StatusOK || resp.StatusCode >= http.StatusBadRequest {
		return fmt.Errorf("HTTP probe failed with statuscode: %d", resp.StatusCode)
	}
	return nil
}

func resolveProbePort(port intstr.IntOrString, container corev1.Container) (int, error) {
	if port.Type == intstr.Int {
		if port.IntVal <= 0 || port.IntVal > 65535 {
			return 0, fmt.Errorf("invalid probe port %d", port.IntVal)
		}
		return int(port.IntVal), nil
	}
	for _, p := range container.Ports {
		if p.Name == port.StrVal {
			return int(p.ContainerPort), nil
		}
	}
	if n, err := strconv.Atoi(port.StrVal); err == nil && n > 0 && n <= 65535 {
		return n, nil
	}
	return 0, fmt.Errorf("probe port %q matches no container port", port.StrVal)
}

// syncReadinessProbe returns whether the Pod reads Ready now that its
// guest has ip. Pods without a readinessProbe are Ready, unchanged from
// before probes existed. Only reads cached state; the prober does the
// network work on its own goroutine.
func (r *Reconciler) syncReadinessProbe(pod *corev1.Pod, entry *Entry, ip string) bool {
	probe, err := readinessProbeFor(pod)
	if errors.Is(err, errUnsupportedReadinessProbe) {
		if !entry.readinessUnsupportedReported && r.Recorder != nil {
			r.Recorder.Event(pod, corev1.EventTypeWarning, "ReadinessProbeUnsupported",
				err.Error()+"; readiness falls back to the VM having an IP")
		}
		entry.readinessUnsupportedReported = true
		return true
	}
	if probe == nil {
		return true
	}
	if entry.Readiness == nil {
		entry.Readiness = newReadinessProber(
			pod.Spec.Containers[0],
			entry.StartTS.Time,
			publishedReady(pod, entry.VMName),
			r.readinessResultHandler(pod),
		)
	}
	entry.Readiness.Start(ip)
	return entry.Readiness.Ready()
}

// publishedReady reports whether the Pod already reads Ready for this
// same VM, i.e. a previous tart-kubelet process published it.
func publishedReady(pod *corev1.Pod, vmName string) bool {
	for _, cs := range pod.Status.ContainerStatuses {
		if cs.ContainerID == "tart://"+vmName && cs.Ready {
			return true
		}
	}
	return false
}

// readinessResultHandler records failed probes as Events, like the
// kubelet does, and re-enqueues the Pod when its readiness flips.
func (r *Reconciler) readinessResultHandler(pod *corev1.Pod) func(ready, changed bool, err error) {
	ref := &corev1.Pod{
		TypeMeta: pod.TypeMeta,
		ObjectMeta: metav1.ObjectMeta{
			Namespace: pod.Namespace,
			Name:      pod.Name,
			UID:       pod.UID,
		},
	}
	return func(_, changed bool, err error) {
		if err != nil && r.Recorder != nil {
			r.Recorder.Event(ref, corev1.EventTypeWarning, "Unhealthy", "Readiness probe failed: "+err.Error())
		}
		if !changed || r.readinessEvents == nil {
			return
		}
		select {
		case r.readinessEvents <- event.GenericEvent{Object: ref}:
		default:
			// Queue full; the periodic requeue publishes it instead.
		}
	}
}
