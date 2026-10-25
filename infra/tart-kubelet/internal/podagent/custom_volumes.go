package podagent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/go-logr/logr"
	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
	"golang.org/x/sys/unix"
	authenticationv1 "k8s.io/api/authentication/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// CustomVolumes uses the existing private virtio-fs transport as a mailbox.
// Pod/node identity comes from the host, never from the writable request. The
// trusted service-account token and signed object URLs stay entirely on the host.
type CustomVolumes struct {
	Root, URL, Node, Namespace, ServiceAccount string
	Kube                                       kubernetes.Interface
	Tart                                       *tart.Client
	Space                                      *CacheSpace
	Checkouts                                  *cachevolumes.Checkouts
	Store                                      *cachevolumes.Store
	HTTP                                       *http.Client
	Running                                    func(context.Context, string) (bool, error)
	// MaxVolumeBytes is the largest volume this host accepts; zero is
	// cachevolumes.DefaultMaxVolumeBytes.
	MaxVolumeBytes   int64
	shareMu          sync.Mutex
	reservations     map[string]cachevolumes.Slot
	prefetch         atomic.Pointer[customPrefetcher]
	tokenMu          sync.Mutex
	tokenValue       string
	tokenUntil       time.Time
	checkoutReserved uint64
	checkoutMu       sync.Mutex
	checkoutJobs     map[string]cachevolumes.CheckoutTask
	executionWaits   cachevolumes.ExecutionWaits
	// spare cancels the running background prefetch; guarded by Space.mu.
	spare context.CancelCauseFunc
	// spareScope is the scope that prefetch restores; guarded by Space.mu.
	spareScope string
	// images is the backend run() serves; nil until then.
	images *cachevolumes.APFSImages
}

func (c *CustomVolumes) Share(pod *corev1.Pod) (string, error) {
	c.shareMu.Lock()
	defer c.shareMu.Unlock()
	mounted, err := c.Space.backend.isMounted(c.Space.Root)
	if err != nil || !mounted {
		return "", errors.New("cache filesystem unavailable")
	}
	uid := string(pod.UID)
	if err = os.MkdirAll(filepath.Join(c.Root, "owners"), 0700); err != nil {
		return "", err
	}
	path := filepath.Join(c.Root, "pods", uid)
	if err := os.MkdirAll(path, 0777); err != nil {
		return "", err
	}
	if err = os.WriteFile(filepath.Join(c.Root, "owners", uid), []byte(pod.Name), 0600); err != nil {
		return "", err
	}
	return path, os.Chmod(path, 0777)
}

func (c *CustomVolumes) maxVolumeBytes() int64 {
	if c.MaxVolumeBytes > 0 {
		return c.MaxVolumeBytes
	}
	return cachevolumes.DefaultMaxVolumeBytes
}

func (c *CustomVolumes) token(ctx context.Context) (string, error) {
	c.tokenMu.Lock()
	defer c.tokenMu.Unlock()
	if c.tokenValue != "" && time.Now().Before(c.tokenUntil) {
		return c.tokenValue, nil
	}
	ttl := int64(600)
	token, err := c.Kube.CoreV1().ServiceAccounts(c.Namespace).CreateToken(ctx, c.ServiceAccount,
		&authenticationv1.TokenRequest{Spec: authenticationv1.TokenRequestSpec{ExpirationSeconds: &ttl}}, metav1.CreateOptions{})
	if err != nil {
		return "", err
	}
	c.tokenValue = token.Status.Token
	c.tokenUntil = time.Now().Add(5 * time.Minute)
	if expiry := token.Status.ExpirationTimestamp.Time.Add(-30 * time.Second); !token.Status.ExpirationTimestamp.IsZero() && expiry.Before(c.tokenUntil) {
		c.tokenUntil = expiry
	}
	return c.tokenValue, nil
}

func (c *CustomVolumes) request(ctx context.Context, operation string, body any, result any) (int, error) {
	data, err := json.Marshal(body)
	if err != nil {
		return 0, err
	}
	req, err := http.NewRequestWithContext(ctx, "POST", c.URL+"/"+operation, bytes.NewReader(data))
	if err != nil {
		return 0, err
	}
	token, err := c.token(ctx)
	if err != nil {
		return 0, err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	response, err := cachevolumes.DoServer(c.HTTP, req, customCacheLog())
	if err != nil {
		return 0, err
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return response.StatusCode, fmt.Errorf("cache metadata status %d", response.StatusCode)
	}
	return 200, json.NewDecoder(io.LimitReader(response.Body, 16384)).Decode(result)
}

func (c *CustomVolumes) Start(ctx context.Context) error {
	for {
		if err := c.run(ctx); err != nil {
			log.FromContext(ctx).Error(err, "custom cache agent unavailable; jobs continue cold")
		}
		select {
		case <-ctx.Done():
			return nil
		case <-time.After(30 * time.Second):
		}
	}
}

func (c *CustomVolumes) run(ctx context.Context) error {
	mounted, err := c.Space.backend.isMounted(c.Space.Root)
	if err != nil || !mounted {
		return errors.New("cache filesystem unavailable")
	}
	// The timeout bounds metadata requests; archive transfers use masterDownloadClient and end on a stall instead.
	c.HTTP = cachevolumes.NewServerClient(6 * time.Minute)
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{
		Observe: observeCustomCache, Root: c.Root, SizeGB: 20, MinFreeBytes: 40_000_000_000, MaxVolumeBytes: c.maxVolumeBytes(),
		Transfer:         &cachevolumes.HTTPTransfer{URL: c.URL + "/image", Node: c.Node, Client: c.HTTP, ObjectClient: masterDownloadClient, MaxBytes: c.maxVolumeBytes(), Token: c.token, Log: customCacheLog()},
		FreeBytesContext: c.freeBytesContext,
		Reclaim:          c.reclaim,
		Displace:         c.displaceSpare,
		Log:              customCacheLog(),
	}, Reserve: c.reserve, Create: createCustomImage, Verify: verifyCustomImage, Detach: detachCustomInspection, Grow: growCustomImage}
	if c.Checkouts != nil {
		backend.Seed = c.Checkouts.Seed
		c.Checkouts.Room = c.reserveCheckout
		c.Checkouts.Observe = observeCustomCache
		c.Checkouts.Log = slog.New(logr.ToSlogHandler(log.FromContext(ctx)))
		// Checkout images are larger than custom ones, so their archives get their own bound.
		c.Checkouts.Transfer = &cachevolumes.HTTPTransfer{URL: c.URL + "/image", Node: c.Node, Client: c.HTTP, ObjectClient: masterDownloadClient, MaxBytes: cachevolumes.CheckoutCapacity + 1_000_000_000, Token: c.token, Log: customCacheLog()}
	}
	// A superseded master stays mountable until its successor is downloaded here.
	backend.Replace = func(next cachevolumes.Identity) bool { return c.prefetch.Load().start(next, false) != nil }
	if err := os.MkdirAll(c.Root, 0700); err != nil {
		return err
	}
	lock, err := os.OpenFile(filepath.Join(c.Root, ".lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err = unix.Flock(int(lock.Fd()), unix.LOCK_EX|unix.LOCK_NB); err != nil {
		return err
	}
	if err := backend.Init(); err != nil {
		return err
	}
	store, err := cachevolumes.Open(c.Root, backend)
	if err != nil {
		return err
	}
	defer store.Close()
	store.MaxVolumeBytes = c.maxVolumeBytes()
	c.Store = store
	c.images = backend
	// Pressure eviction takes the masters of lineages a job holds or is cloning last.
	backend.InUse = store.InUse
	if c.Checkouts != nil {
		// Pressure eviction never takes a master a job holds or is cloning.
		c.Checkouts.InUse = store.InUse
	}
	if err := c.refreshReservations(ctx); err != nil {
		return err
	}
	prefetchCtx, stopPrefetch := context.WithCancel(ctx)
	prefetch := newCustomPrefetcher(prefetchCtx, func(ctx context.Context, slot cachevolumes.Slot, requested bool) error {
		if requested {
			return backend.Prefetch(ctx, slot)
		}
		return c.prefetchSpare(ctx, slot.Scope, func(ctx context.Context) error { return backend.PrefetchSpare(ctx, slot) })
	}, backend.HasMaster)
	c.prefetch.Store(prefetch)
	var builds sync.WaitGroup
	defer func() {
		c.prefetch.Store(nil)
		stopPrefetch()
		prefetch.wait.Wait()
		builds.Wait()
	}()
	if c.Checkouts != nil {
		builds.Go(func() { c.Checkouts.Start(prefetchCtx) })
	}
	requests := time.NewTicker(time.Second)
	defer requests.Stop()
	reports := time.NewTicker(30 * time.Second)
	defer reports.Stop()
	return c.serve(ctx, requests.C, reports.C)
}

// Publication and each pod's mailbox make progress independently. At most eight
// pods have a worker, with no queued work and no concurrent scans of one mailbox.
func (c *CustomVolumes) serve(ctx context.Context, requests, reports <-chan time.Time) error {
	ctx, cancel := context.WithCancel(ctx)
	var workers sync.WaitGroup
	defer func() {
		cancel()
		workers.Wait()
	}()
	finished := make(chan string, 9)
	active := make(map[string]bool)
	publishing := false
	// A finished job's branch can only be sealed once its VM has stopped, which
	// trails the Pod by tens of seconds. Pods that stopped running are
	// reconciled every few seconds until then instead of on the next report tick.
	running := make(map[string]bool)
	settling := make(map[string]time.Time)
	var reconciled time.Time
	reconcile := func() {
		publishing = true
		reconciled = time.Now()
		workers.Go(func() {
			if err := c.reconcile(ctx); err != nil {
				log.FromContext(ctx).Error(err, "custom cache reconciliation")
			}
			finished <- ""
		})
	}
	for {
		select {
		case <-ctx.Done():
			return nil
		case uid := <-finished:
			if uid == "" {
				publishing = false
			} else {
				delete(active, uid)
			}
		case <-reports:
			if publishing {
				continue
			}
			reconcile()
		case <-requests:
			c.notePressure(ctx)
			listCtx, stop := context.WithTimeout(ctx, 5*time.Second)
			pods, err := c.Kube.CoreV1().Pods(c.Namespace).List(listCtx, metav1.ListOptions{FieldSelector: "spec.nodeName=" + c.Node})
			stop()
			if err != nil {
				log.FromContext(ctx).Error(err, "custom cache pod discovery")
				continue
			}
			now := time.Now()
			current := make(map[string]bool)
			for _, pod := range pods.Items {
				if pod.Labels["tuist.dev/runner"] == "true" && pod.Spec.NodeName == c.Node && pod.DeletionTimestamp == nil && pod.Status.Phase == corev1.PodRunning {
					current[string(pod.UID)] = true
				}
			}
			for uid := range running {
				if !current[uid] {
					settling[uid] = now.Add(customSettleWindow)
				}
			}
			running = current
			for uid, until := range settling {
				if now.After(until) {
					delete(settling, uid)
				}
			}
			if len(settling) > 0 && !publishing && now.Sub(reconciled) >= customSettleInterval {
				reconcile()
			}
			for _, pod := range pods.Items {
				uid := string(pod.UID)
				if len(active) >= 8 || active[uid] || uid == "" || pod.Spec.NodeName != c.Node || pod.DeletionTimestamp != nil || pod.Status.Phase != corev1.PodRunning || pod.Labels["tuist.dev/runner"] != "true" {
					continue
				}
				active[uid] = true
				workers.Go(func() {
					if err := c.requests(ctx, &pod); err != nil {
						log.FromContext(ctx).Error(err, "custom cache request", "pod", pod.Name)
					}
					finished <- uid
				})
			}
		}
	}
}

func (c *CustomVolumes) freeBytes(string) (uint64, error) {
	return c.freeBytesContext(context.Background(), "")
}

func (c *CustomVolumes) freeBytesContext(ctx context.Context, _ string) (uint64, error) {
	release, err := c.guard(ctx)
	if err != nil {
		return 0, err
	}
	defer release()
	return c.freeBytesLocked()
}

func (c *CustomVolumes) freeBytesLocked() (uint64, error) {
	mounted, err := c.Space.backend.isMounted(c.Space.Root)
	if err != nil || !mounted {
		return 0, errors.New("cache filesystem unavailable")
	}
	free, err := c.Space.availableBytes()
	if err != nil {
		return 0, err
	}
	reserved := c.reservedBytes() + c.checkoutReserved
	if free <= reserved {
		return 0, nil
	}
	return free - reserved, nil
}

func (c *CustomVolumes) gone(name, uid string) (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pod, err := c.Kube.CoreV1().Pods(c.Namespace).Get(ctx, name, metav1.GetOptions{})
	if err == nil && string(pod.UID) == uid {
		return false, nil
	}
	if err != nil && !apierrors.IsNotFound(err) {
		return false, err
	}
	// VM names are deterministic and reused only after the previous VM is gone.
	vm := VMNameForPod(&corev1.Pod{ObjectMeta: metav1.ObjectMeta{Namespace: c.Namespace, Name: name}})
	probe := c.Running
	if probe == nil {
		probe = c.Tart.IsRunning
	}
	running, err := probe(ctx, vm)
	return !running && err == nil, err
}

func (c *CustomVolumes) report(slot cachevolumes.Slot, gone bool) (string, error) {
	path := filepath.Join(c.Root, "pods", slot.PodUID, slot.Scope)
	if slot.State == "active" && !cachevolumes.APFSMarker(path, ".mounted", slot.ID) {
		if gone {
			if reason := attachError(path); reason != "" {
				log.Log.WithName("custom-cache-volumes").Info("guest could not mount its volume; job ran cold", "pod", slot.PodName, "use", slot.ID, "error", reason)
			}
			return "delete", nil
		}
		return "hold", nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var result struct {
		Action      string `json:"action"`
		ColdPublish bool   `json:"cold_publish"`
	}
	_, err := c.request(ctx, "report", map[string]any{"id": slot.ID, "node_name": c.Node, "state": slot.State, "gone": gone, "warm": slot.Warm, "size_bytes": slot.SizeBytes, "capacity_bytes": slot.CapacityBytes, "attach_ms": nil, "mounted_generation": mountedGeneration(slot)}, &result)
	// Only an explicit server decision lets a branch that started empty replace
	// the saved version; a plain seal keeps withholding it.
	if result.Action == "seal" && result.ColdPublish {
		return "publish", err
	}
	return result.Action, err
}

func (c *CustomVolumes) reconcile(ctx context.Context) error {
	c.relieve(ctx)
	if err := c.refreshReservations(ctx); err != nil {
		return err
	}
	if err := c.Store.Reconcile(c.gone, c.report); err != nil {
		return err
	}
	c.Checkouts.Maintain()
	err := c.Store.CleanPods(func(uid string) (bool, error) {
		name, err := os.ReadFile(filepath.Join(c.Root, "owners", uid))
		if err != nil {
			return false, err
		}
		gone, err := c.gone(string(name), uid)
		if err == nil && gone {
			c.collectCheckout(uid)
		}
		return gone, err
	})
	if err != nil {
		return err
	}
	c.shareMu.Lock()
	defer c.shareMu.Unlock()
	owners, err := os.ReadDir(filepath.Join(c.Root, "owners"))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	for _, owner := range owners {
		if _, e := os.Lstat(filepath.Join(c.Root, "pods", owner.Name())); os.IsNotExist(e) {
			_ = os.Remove(filepath.Join(c.Root, "owners", owner.Name()))
		}
	}
	return nil

}

func (c *CustomVolumes) requests(ctx context.Context, pod *corev1.Pod) error {
	root, err := os.OpenRoot(filepath.Join(c.Root, "pods", string(pod.UID)))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	defer root.Close()
	dir, err := root.Open(".")
	if err != nil {
		return err
	}
	defer dir.Close()
	// Bound work and input even when a malicious guest fills its own mailbox.
	names, err := dir.Readdirnames(64)
	if err != nil && err != io.EOF {
		return err
	}
	for _, name := range names {
		if !strings.HasSuffix(name, ".request") {
			continue
		}
		if _, err := root.Stat(name + ".response"); err == nil {
			continue
		}
		file, err := root.OpenFile(name, os.O_RDONLY|unix.O_NONBLOCK, 0)
		if err != nil {
			continue
		}
		info, err := file.Stat()
		if err != nil || !info.Mode().IsRegular() {
			file.Close()
			continue
		}
		var input struct {
			Key       string                     `json:"key"`
			UID       int                        `json:"uid"`
			Checkout  bool                       `json:"checkout"`
			Requested cachevolumes.RequestedSize `json:"requested_volume_bytes"`
		}
		err = json.NewDecoder(io.LimitReader(file, 4096)).Decode(&input)
		file.Close()
		if err != nil {
			continue
		}
		// A checkout never makes a job wait longer than a cold checkout would cost.
		budget := customAcquireBudget
		if input.Checkout {
			budget = 15 * time.Second
		}
		asked := time.Now()
		if info.ModTime().Before(asked) {
			asked = info.ModTime()
		}
		acquireCtx, cancel := context.WithDeadline(ctx, asked.Add(budget))
		if input.Checkout {
			response := map[string]any{"error": "unavailable", "reason": "error"}
			if c.Checkouts != nil {
				response = c.checkout(acquireCtx, pod, input.UID, asked)
			}
			cancel()
			if response == nil {
				continue
			}
			data, _ := json.Marshal(response)
			if published, err := publishResponse(root, name+".response", data); err != nil {
				return err
			} else if !published {
				continue
			}
			if _, err := root.Stat(name); os.IsNotExist(err) {
				_ = root.Remove(name + ".response")
			}
			continue
		}
		var identity cachevolumes.Identity
		body := map[string]any{"pod_name": pod.Name, "pod_uid": string(pod.UID), "node_name": c.Node, "key": input.Key, "architecture": "arm64", "uid": input.UID, "max_volume_bytes": c.maxVolumeBytes()}
		// RequestedSize drops an invalid size, so it never fails the request.
		if input.Requested > 0 {
			body["requested_volume_bytes"] = int64(input.Requested)
		}
		status, err := c.request(acquireCtx, "authorize", body, &identity)
		// 425 means GitHub has not yet reported which job this runner executes.
		if status == http.StatusTooEarly {
			pendingCtx, stop := context.WithDeadline(acquireCtx, c.executionWaits.Deadline(string(pod.UID), asked))
			for status == http.StatusTooEarly {
				select {
				case <-pendingCtx.Done():
				case <-time.After(customAuthorizeRetry):
					status, err = c.request(pendingCtx, "authorize", body, &identity)
				}
				if pendingCtx.Err() != nil && status != http.StatusOK {
					err = cachevolumes.ErrExecutionPending
					break
				}
			}
			stop()
		}
		// 507: the volume is larger than this host's maximum.
		if status == http.StatusInsufficientStorage {
			err = cachevolumes.ErrCapacity
		}
		// The reserved checkout name is only ever allocated through the checkout path.
		identity.Kind, identity.Generation = "", 0
		identity.ManagedKey = cachevolumes.ManagedKey(input.Key)
		response := map[string]any{"error": "unavailable", "reason": "denied"}
		if errors.Is(err, cachevolumes.ErrExecutionPending) {
			response["reason"] = "execution_pending"
			log.FromContext(ctx).Info("custom cache volume not authorized in time: GitHub has not reported the job running on this pod; job continues cold", "pod", pod.Name)
		} else if errors.Is(err, cachevolumes.ErrCapacity) {
			response["reason"] = "capacity"
			log.FromContext(ctx).Info("custom cache volume larger than this host holds; job continues cold", "pod", pod.Name)
		} else if err != nil {
			log.FromContext(ctx).Info("custom cache volume not authorized; job continues cold", "pod", pod.Name, "error", err.Error())
		} else {
			warm, err := c.Store.Acquire(acquireCtx, identity, pod.Name, string(pod.UID))
			if err == nil {
				response = map[string]any{"id": identity.ID, "directory": identity.Scope, "warm": warm}
				// A job that mounted an older generation leaves its HEAD to the background.
				c.prefetch.Load().start(identity, true)
			} else {
				if errors.Is(err, context.DeadlineExceeded) {
					c.prefetch.Load().start(identity, true)
				}
				response["reason"] = cachevolumes.Result(err)
				subject := cachevolumes.SubjectOf(cachevolumes.Slot{Identity: identity, PodName: pod.Name})
				log.FromContext(ctx).Info("custom cache volume unavailable; job continues cold",
					append(subject.Fields(), "reason", response["reason"], "error", err.Error())...)
			}
		}
		cancel()
		data, _ := json.Marshal(response)
		if published, err := publishResponse(root, name+".response", data); err != nil {
			return err
		} else if !published {
			continue
		}
		if _, err := root.Stat(name); os.IsNotExist(err) {
			_ = root.Remove(name + ".response")
		}
	}
	return nil
}

// Guests only ever see complete responses. O_EXCL and link never follow or
// replace a guest-created path, so an existing response is kept.
func publishResponse(root *os.Root, name string, data []byte) (bool, error) {
	temp := name + ".tmp"
	_ = root.Remove(temp)
	out, err := root.OpenFile(temp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return false, nil
	}
	defer root.Remove(temp)
	_, err = out.Write(data)
	if closeErr := out.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return false, err
	}
	return root.Link(temp, name) == nil, nil
}

func (c *CustomVolumes) guard(ctx context.Context) (func(), error) {
	for {
		if err := ctx.Err(); err != nil {
			return nil, err
		}
		if c.Space.mu.TryLock() {
			return c.Space.mu.Unlock, nil
		}
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-time.After(10 * time.Millisecond):
		}
	}
}

// mountedGeneration is the older generation a job mounted, or nil when it got
// its base.
func mountedGeneration(slot cachevolumes.Slot) any {
	if slot.MountedGeneration <= 0 {
		return nil
	}
	return slot.MountedGeneration
}

// attachError reads the reason the guest recorded for a mount that failed.
// The share is guest-writable, so the read never follows it out of the pod's directory.
func attachError(path string) string {
	root, err := os.OpenRoot(filepath.Dir(path))
	if err != nil {
		return ""
	}
	defer root.Close()
	file, err := root.Open(filepath.Join(filepath.Base(path), ".attach-error"))
	if err != nil {
		return ""
	}
	defer file.Close()
	data, _ := io.ReadAll(io.LimitReader(file, 1024))
	return strings.ToValidUTF8(strings.TrimSpace(string(data)), "?")
}
