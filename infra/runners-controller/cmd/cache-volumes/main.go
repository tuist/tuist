// Node-local cache agent. This trusted process alone sees the cache filesystem;
// Kata guests see only pods/<uid>. Never mount the cache root into a runner.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
)

type agent struct {
	store                                  *cachevolumes.Store
	kube                                   kubernetes.Interface
	namespace, node, kubelet, authorizeURL string
	root                                   string
	http                                   *http.Client
	requests                               chan struct{}
	tokenPath                              string
	runtime                                runtimeapi.RuntimeServiceClient
	observe                                cachevolumes.Observer
	prefetch                               *prefetcher
	checkouts                              *cachevolumes.Checkouts
	space                                  *checkoutSpace
	grants                                 checkoutGrants
	exports                                chan struct{}
	checkoutRequests                       chan struct{}
	// maxVolumeBytes is the largest volume this host accepts.
	maxVolumeBytes int64
	// log receives server request retries; nil is slog.Default.
	log *slog.Logger
}
type request struct {
	PodName      string `json:"pod_name"`
	PodUID       string `json:"pod_uid"`
	Key          string `json:"key"`
	Architecture string `json:"architecture"`
	UID          int    `json:"uid"`
	// RequestedVolumeBytes is forwarded only when valid; anything else is dropped.
	RequestedVolumeBytes cachevolumes.RequestedSize `json:"requested_volume_bytes"`
}

func (a *agent) serve(w http.ResponseWriter, r *http.Request) {
	switch {
	case r.Method == "POST" && r.URL.Path == "/checkout":
		a.serveCheckout(w, r)
		return
	case r.Method == "POST" && r.URL.Path == "/checkout-export":
		a.serveCheckoutExport(w, r)
		return
	case r.Method != "POST" || r.URL.Path != "/acquire":
		http.NotFound(w, r)
		return
	}
	outcome := errors.New("invalid acquisition")
	var subject cachevolumes.Subject
	start := time.Now()
	defer func() { a.observe.With(subject).Report("acquire", "none", start, outcome) }()
	if a.requests != nil {
		select {
		case a.requests <- struct{}{}:
			defer func() { <-a.requests }()
		default:
			outcome = cachevolumes.ErrBusy
			http.Error(w, "unavailable", http.StatusServiceUnavailable)
			return
		}
	}

	var input request
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&input); err != nil {
		http.Error(w, "invalid request", 400)
		return
	}
	subject.Pod = input.PodName
	ctx, cancel := context.WithTimeout(r.Context(), 25*time.Second)
	defer cancel()
	if !a.runnerPod(ctx, r, input.PodName, input.PodUID) {
		http.Error(w, "unavailable", 403)
		return
	}
	// The agent authenticates to the server. Repository and publication rights
	// come from the job GitHub actually assigned to this live runner.
	fields := map[string]any{"pod_name": input.PodName, "pod_uid": input.PodUID, "node_name": a.node, "key": input.Key, "architecture": input.Architecture, "uid": input.UID, "max_volume_bytes": a.maxVolumeBytes}
	if input.RequestedVolumeBytes > 0 {
		fields["requested_volume_bytes"] = int64(input.RequestedVolumeBytes)
	}
	body, _ := json.Marshal(fields)
	authorizing := time.Now()
	identity, err := a.authorize(ctx, body)
	identity.ManagedKey = cachevolumes.ManagedKey(input.Key)
	if err == nil {
		subject = cachevolumes.SubjectOf(cachevolumes.Slot{Identity: identity, PodName: input.PodName})
	}
	a.observe.With(subject).Report("authorize", "none", authorizing, err)
	outcome = err
	if errors.Is(err, cachevolumes.ErrExecutionPending) {
		log.Printf("cache authorization timed out: GitHub has not reported the job running on pod %s", input.PodName)
		http.Error(w, "execution pending", http.StatusTooEarly)
		return
	}
	if errors.Is(err, cachevolumes.ErrCapacity) {
		log.Printf("cache volume for pod %s is larger than this host holds", input.PodName)
		http.Error(w, "unavailable", 503)
		return
	}
	if err != nil {
		http.Error(w, "unavailable", 403)
		return
	}
	warm, err := a.store.Acquire(ctx, identity, input.PodName, input.PodUID)
	outcome = err
	// A job that mounted an older copy, started empty or timed out fetches the
	// saved version in the background for the next job on this host.
	if err == nil || errors.Is(err, context.DeadlineExceeded) {
		a.prefetch.start(identity)
	}
	if err != nil {
		log.Printf("cache acquire failed: %v", err)
		http.Error(w, "unavailable", 503)
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"directory": identity.Scope, "warm": warm, "id": identity.ID})
}
func (a *agent) gone(name, uid string) (bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pod, err := a.kube.CoreV1().Pods(a.namespace).Get(ctx, name, metav1.GetOptions{})
	if err == nil && string(pod.UID) == uid {
		return false, nil
	}
	if err != nil && !apierrors.IsNotFound(err) {
		return false, err
	}
	return runtimeGone(ctx, a.runtime, uid)
}
func (a *agent) reconcile() error {
	if err := a.store.Reconcile(a.gone, a.report); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	pods, err := a.kube.CoreV1().Pods(a.namespace).List(ctx, metav1.ListOptions{})
	if err != nil {
		return err
	}
	live := map[string]bool{}
	for _, pod := range pods.Items {
		live[string(pod.UID)] = true
	}
	a.grants.forget(live)
	a.checkouts.Maintain()
	if err := a.store.CleanPods(func(uid string) (bool, error) {
		if live[uid] {
			return false, nil
		}
		_, err := os.Lstat(filepath.Join(a.kubelet, uid))
		if os.IsNotExist(err) {
			return true, nil
		}
		return false, err
	}); err != nil {
		return err
	}
	node, err := a.kube.CoreV1().Nodes().Get(ctx, a.node, metav1.GetOptions{})
	if err != nil {
		return err
	}
	masters, err := cachevolumes.MasterNodeLabels(a.root)
	if err != nil {
		return err
	}
	patch, _ := json.Marshal(map[string]any{"metadata": map[string]any{"labels": nodeLabels(node.Labels, masters)}})
	_, err = a.kube.CoreV1().Nodes().Patch(ctx, a.node, types.MergePatchType, patch, metav1.PatchOptions{})
	return err
}

const readinessLabel, readinessValue = "tuist.dev/linux-cache-volumes", "local-images-v1"

// nodeLabels is the merge patch advertising this node's readiness and the
// lineages it holds a master of. A master evicted since the last patch has its
// label removed.
func nodeLabels(current, masters map[string]string) map[string]any {
	labels := map[string]any{readinessLabel: readinessValue}
	for key := range current {
		if strings.HasPrefix(key, cachevolumes.MasterNodeLabelPrefix) {
			labels[key] = nil
		}
	}
	for key, value := range masters {
		labels[key] = value
	}
	return labels
}
func main() {
	root := flag.String("root", "/cache", "Dedicated cache filesystem")
	kubelet := flag.String("kubelet-pods", "/kubelet-pods", "Read-only kubelet pod directory")
	rootDevice := flag.String("host-root-device", "/host-root-device", "A read-only file on the host root filesystem")
	url := flag.String("authorize-url", "", "Tuist cache-volume authorization URL")
	namespace := flag.String("namespace", "tuist-runners", "Runner namespace")
	node := flag.String("node", os.Getenv("NODE_NAME"), "Local node")
	maxSlots := flag.Int("max-slots", 100, "Maximum active clones on this host")
	minFreeGB := flag.Int("min-free-gb", 40, "Free filesystem reserve before creating a branch")
	sizeGB := flag.Int("volume-gb", 20, "Capacity of a new volume the server sends no size for, in decimal GB")
	maxGB := flag.Int("max-volume-gb", cachevolumes.DefaultMaxVolumeBytes/1_000_000_000, "Largest volume this host accepts, in decimal GB")
	runtimeEndpoint := flag.String("runtime-endpoint", "unix:///run/host-containerd.sock", "Host CRI endpoint for writer teardown verification")
	tokenPath := flag.String("token-path", "/var/run/secrets/kubernetes.io/serviceaccount/token", "Storage agent token")
	flag.Parse()
	if *url == "" || *node == "" || *maxSlots < 1 || *sizeGB < 1 || *minFreeGB < *sizeGB || *maxGB < *sizeGB {
		log.Fatal("invalid configuration")
	}
	maxBytes := int64(*maxGB) * 1_000_000_000
	// A full cache must never fill the kubelet/root filesystem. This check is
	// intentional even though both paths are bind mounts in the DaemonSet.
	if err := dedicatedFilesystem(*root, *kubelet, *rootDevice); err != nil {
		log.Fatal(err)
	}
	cfg, err := rest.InClusterConfig()
	if err != nil {
		log.Fatal(err)
	}
	kube, err := kubernetes.NewForConfig(cfg)
	if err != nil {
		log.Fatal(err)
	}
	// The timeout bounds metadata requests; archive transfers drop it and end on a stall instead.
	client := cachevolumes.NewServerClient(6 * time.Minute)
	metrics := newVolumeMetrics(slog.New(slog.NewJSONHandler(os.Stderr, nil)), uint64(*minFreeGB)*1_000_000_000)
	transfer := &imageTransfer{URL: strings.TrimSuffix(*url, "/authorize") + "/image", Node: *node, TokenPath: *tokenPath, Client: client, MaxBytes: maxBytes, Log: metrics.logger}
	backend := &cachevolumes.LocalImages{Observe: metrics.observe, Log: metrics.logger, Root: *root, SizeGB: *sizeGB, MinFreeBytes: uint64(*minFreeGB) * 1_000_000_000, Transfer: transfer, Mount: cachevolumes.Mount, Unmount: cachevolumes.Unmount, MeasureFS: cachevolumes.MeasureFS, FreeBytes: cachevolumes.FreeBytes}
	// A master another host superseded is refreshed in the background when it was
	// used within the last day, so this host's next job attaches locally.
	backend.RefreshWithin = 24 * time.Hour
	// Checkout masters share the cache filesystem, its reserve and this agent.
	checkouts := &cachevolumes.Checkouts{Root: filepath.Join(*root, "checkouts"), Images: &cachevolumes.Ext4CheckoutImages{}, Path: checkoutPath, Tools: pinnedGitLFS(gitLFSCommand), Observe: metrics.observe, Log: metrics.logger,
		// Checkout images are larger than custom ones, so their archives get their own bound.
		Transfer: &imageTransfer{URL: transfer.URL, Node: *node, TokenPath: *tokenPath, Client: client, MaxBytes: cachevolumes.CheckoutCapacity + 1_000_000_000, Log: metrics.logger}}
	space := &checkoutSpace{root: *root, reserve: backend.MinFreeBytes, checkouts: checkouts}
	checkouts.Room = space.room
	backend.Seed, backend.FreeBytesContext, backend.Reclaim = checkouts.Seed, space.free, space.reclaim
	store, err := cachevolumes.Open(*root, backend)
	if err != nil {
		log.Fatal(err)
	}
	checkouts.InUse, backend.InUse = store.InUse, store.InUse
	defer store.Close()
	// Lock survives requests and prevents an overlapping/restarted DaemonSet from
	// allocating the same directory. Kubernetes rollout uses maxSurge=0 as well.
	lock, err := os.OpenFile(filepath.Join(*root, ".lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		log.Fatal(err)
	}
	defer lock.Close()
	if err := syscall.Flock(int(lock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		log.Fatal(err)
	}
	if err := backend.Probe(); err != nil {
		log.Fatal(err)
	}
	store.MaxSlots = *maxSlots
	store.MaxVolumeBytes = maxBytes
	a := &agent{maxVolumeBytes: maxBytes, checkouts: checkouts, space: space, exports: make(chan struct{}, 2), checkoutRequests: make(chan struct{}, 4), prefetch: &prefetcher{slots: make(chan struct{}, 1), restore: backend.Prefetch, local: backend.HasMaster, observe: metrics.observe}, observe: metrics.observe, tokenPath: *tokenPath, requests: make(chan struct{}, 4), store: store, root: *root, kube: kube, namespace: *namespace, node: *node, kubelet: *kubelet, authorizeURL: *url, http: client, log: metrics.logger}
	runtimeConn, err := grpc.NewClient(*runtimeEndpoint, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		log.Fatal(err)
	}
	defer runtimeConn.Close()
	a.runtime = runtimeapi.NewRuntimeServiceClient(runtimeConn)
	runtimeCtx, cancelRuntime := context.WithTimeout(context.Background(), 10*time.Second)
	_, err = a.runtime.Version(runtimeCtx, &runtimeapi.VersionRequest{Version: "0.1.0"})
	cancelRuntime()
	if err != nil {
		log.Fatalf("runtime teardown verification unavailable: %v", err)
	}
	// Without git and git-lfs the worker logs why and retries; the host answers
	// denied meanwhile, so runners export nothing.
	go checkouts.Start(context.Background())
	go func() {
		for {
			start := time.Now()
			err := a.reconcile()
			metrics.observe(cachevolumes.Observation{Operation: "maintenance", Source: "none", Duration: time.Since(start), Err: err})
			metrics.checkouts.Set(map[bool]float64{true: 1}[checkouts.Ready()])
			if available, capacity, e := cachevolumes.FilesystemSpace(*root); e == nil {
				metrics.free.Set(float64(available))
				metrics.capacity.Set(float64(capacity))
			}
			time.Sleep(30 * time.Second)
		}
	}()
	go func() {
		metricsServer := &http.Server{Addr: ":9091", Handler: metrics.handler(), ReadHeaderTimeout: 5 * time.Second, WriteTimeout: 10 * time.Second}
		log.Fatal(metricsServer.ListenAndServe())
	}()
	server := &http.Server{Addr: ":8090", Handler: http.HandlerFunc(a.serve), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 20 * time.Second, WriteTimeout: 7 * time.Minute, MaxHeaderBytes: 32768}
	log.Fatal(server.ListenAndServe())
}
func dedicatedFilesystem(root string, references ...string) error {
	var cacheStat syscall.Stat_t
	if err := syscall.Stat(root, &cacheStat); err != nil {
		return err
	}
	for _, reference := range references {
		var refStat syscall.Stat_t
		if err := syscall.Stat(reference, &refStat); err != nil {
			return err
		}
		if cacheStat.Dev == refStat.Dev {
			return fmt.Errorf("cache root must be on a dedicated filesystem separate from host root and kubelet")
		}
	}
	return nil
}

func (a *agent) report(slot cachevolumes.Slot, gone bool) (string, error) {
	state := slot.State
	body, _ := json.Marshal(map[string]any{"id": slot.ID, "node_name": a.node, "state": state, "gone": gone, "warm": slot.Warm, "size_bytes": slot.SizeBytes, "capacity_bytes": slot.CapacityBytes, "attach_ms": slot.AttachMS, "mounted_generation": mountedGeneration(slot)})
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "POST", strings.TrimSuffix(a.authorizeURL, "/authorize")+"/report", bytes.NewReader(body))
	if err != nil {
		return "", err
	}
	token, err := os.ReadFile(a.tokenPath)
	if err != nil {
		return "", err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", "application/json")
	resp, err := cachevolumes.DoServer(a.http, req, a.log)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("report status %d", resp.StatusCode)
	}
	var result struct {
		Action      string `json:"action"`
		ColdPublish bool   `json:"cold_publish"`
	}
	err = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&result)
	// Only an explicit server decision lets a branch that started empty replace
	// the saved version; a plain seal keeps withholding it.
	if result.Action == "seal" && result.ColdPublish {
		return "publish", err
	}
	return result.Action, err
}

func mountedGeneration(slot cachevolumes.Slot) any {
	if slot.MountedGeneration <= 0 {
		return nil
	}
	return slot.MountedGeneration
}

// runnerPod reports whether the request comes from the live runner pod it names
// on this node: the caller's address must be that pod's.
func (a *agent) runnerPod(ctx context.Context, r *http.Request, name, uid string) bool {
	pod, err := a.kube.CoreV1().Pods(a.namespace).Get(ctx, name, metav1.GetOptions{})
	ip, _, _ := net.SplitHostPort(r.RemoteAddr)
	return err == nil && pod.Spec.NodeName == a.node && string(pod.UID) == uid && pod.Status.PodIP == ip && ip != "" && pod.Labels["tuist.dev/runner"] == "true" && pod.DeletionTimestamp == nil && pod.Status.Phase == corev1.PodRunning
}
