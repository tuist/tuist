// Node-local cache agent. This trusted process alone sees the cache filesystem;
// Kata guests see only pods/<uid>. Never mount the cache root into a runner.
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/runners-controller/internal/cachevolumes"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
)

type agent struct {
	store                                  *cachevolumes.Store
	kube                                   kubernetes.Interface
	namespace, node, kubelet, authorizeURL string
	http                                   *http.Client
	requests                               chan struct{}
	tokenPath                              string
}
type request struct {
	PodName      string `json:"pod_name"`
	PodUID       string `json:"pod_uid"`
	Key          string `json:"key"`
	Architecture string `json:"architecture"`
	UID          int    `json:"uid"`
}

func (a *agent) serve(w http.ResponseWriter, r *http.Request) {
	if a.requests != nil {
		select {
		case a.requests <- struct{}{}:
			defer func() { <-a.requests }()
		default:
			http.Error(w, "unavailable", http.StatusServiceUnavailable)
			return
		}
	}

	if r.Method != "POST" || r.URL.Path != "/acquire" {
		http.NotFound(w, r)
		return
	}
	var input request
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&input); err != nil {
		http.Error(w, "invalid request", 400)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 6*time.Minute)
	defer cancel()
	pod, err := a.kube.CoreV1().Pods(a.namespace).Get(ctx, input.PodName, metav1.GetOptions{})
	ip, _, _ := net.SplitHostPort(r.RemoteAddr)
	if err != nil || pod.Spec.NodeName != a.node || string(pod.UID) != input.PodUID || pod.Status.PodIP != ip || ip == "" || pod.Labels["tuist.dev/runner"] != "true" || pod.DeletionTimestamp != nil || pod.Status.Phase != corev1.PodRunning {
		http.Error(w, "unavailable", 403)
		return
	}
	// The agent authenticates to the server. Repository and publication rights
	// come from the job GitHub actually assigned to this live runner.
	body, _ := json.Marshal(map[string]any{"pod_name": input.PodName, "pod_uid": input.PodUID, "node_name": a.node, "key": input.Key, "architecture": input.Architecture, "uid": input.UID})
	auth, err := http.NewRequestWithContext(ctx, "POST", a.authorizeURL, bytes.NewReader(body))
	if err != nil {
		http.Error(w, "unavailable", 503)
		return
	}
	token, err := os.ReadFile(a.tokenPath)
	if err != nil {
		http.Error(w, "unavailable", 503)
		return
	}
	auth.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	auth.Header.Set("Content-Type", "application/json")
	response, err := a.http.Do(auth)
	if err != nil {
		http.Error(w, "unavailable", 503)
		return
	}
	defer response.Body.Close()
	var identity cachevolumes.Identity
	if response.StatusCode != 200 || json.NewDecoder(io.LimitReader(response.Body, 4096)).Decode(&identity) != nil {
		http.Error(w, "unavailable", 403)
		return
	}
	warm, err := a.store.Acquire(identity, input.PodName, input.PodUID)
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
	_, err = os.Lstat(filepath.Join(a.kubelet, uid))
	if os.IsNotExist(err) {
		return true, nil
	}
	return false, err
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
	labels := map[string]any{"tuist.dev/linux-cache-volumes": "local-images-v1"}
	patch, _ := json.Marshal(map[string]any{"metadata": map[string]any{"labels": labels}})
	_, err = a.kube.CoreV1().Nodes().Patch(ctx, a.node, types.MergePatchType, patch, metav1.PatchOptions{})
	return err
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
	sizeGB := flag.Int("volume-gb", 20, "Capacity of each new volume in decimal GB")
	tokenPath := flag.String("token-path", "/var/run/secrets/kubernetes.io/serviceaccount/token", "Storage agent token")
	flag.Parse()
	if *url == "" || *node == "" || *maxSlots < 1 || *sizeGB < 1 || *minFreeGB < *sizeGB {
		log.Fatal("invalid configuration")
	}
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
	client := &http.Client{Timeout: 6 * time.Minute, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	transfer := &imageTransfer{URL: strings.TrimSuffix(*url, "/authorize") + "/image", Node: *node, TokenPath: *tokenPath, Client: client, MaxBytes: int64(*sizeGB) * 1_000_000_000}
	backend := &cachevolumes.LocalImages{Root: *root, SizeGB: *sizeGB, MinFreeBytes: uint64(*minFreeGB) * 1_000_000_000, Transfer: transfer, Mount: cachevolumes.Mount, Unmount: cachevolumes.Unmount, MeasureFS: cachevolumes.MeasureFS, FreeBytes: cachevolumes.FreeBytes}
	store, err := cachevolumes.Open(*root, backend)
	if err != nil {
		log.Fatal(err)
	}
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
	a := &agent{tokenPath: *tokenPath, requests: make(chan struct{}, 4), store: store, kube: kube, namespace: *namespace, node: *node, kubelet: *kubelet, authorizeURL: *url, http: client}
	go func() {
		for {
			if err := a.reconcile(); err != nil {
				log.Printf("cache maintenance failed: %v", err)
			}
			time.Sleep(30 * time.Second)
		}
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
	body, _ := json.Marshal(map[string]any{"id": slot.ID, "node_name": a.node, "state": state, "gone": gone, "warm": slot.Warm, "size_bytes": slot.SizeBytes, "capacity_bytes": slot.CapacityBytes, "attach_ms": slot.AttachMS})
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
	resp, err := a.http.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("report status %d", resp.StatusCode)
	}
	var result struct {
		Action string `json:"action"`
	}
	err = json.NewDecoder(io.LimitReader(resp.Body, 4096)).Decode(&result)
	return result.Action, err
}
