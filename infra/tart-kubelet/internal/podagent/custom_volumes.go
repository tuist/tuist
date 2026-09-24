package podagent

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"time"

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
	Builtins                                   *VolumeManager
	Store                                      *cachevolumes.Store
	HTTP                                       *http.Client
	Running                                    func(context.Context, string) (bool, error)
	ready                                      atomic.Bool
	tokenMu                                    sync.Mutex
	tokenValue                                 string
	tokenUntil                                 time.Time
	lastReport                                 time.Time
}

func (c *CustomVolumes) Share(pod *corev1.Pod) (string, error) {
	if !c.ready.Load() {
		return "", errors.New("custom cache agent unavailable")
	}
	mounted, err := c.Builtins.backend.isMounted(c.Builtins.Root)
	if err != nil || !mounted {
		return "", errors.New("cache filesystem unavailable")
	}
	uid := string(pod.UID)
	if err = os.MkdirAll(filepath.Join(c.Root, "owners"), 0700); err != nil {
		return "", err
	}
	if err = os.WriteFile(filepath.Join(c.Root, "owners", uid), []byte(pod.Name), 0600); err != nil {
		return "", err
	}

	path := filepath.Join(c.Root, "pods", uid)
	if err := os.MkdirAll(path, 0777); err != nil {
		return "", err
	}
	return path, os.Chmod(path, 0777)
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
	response, err := c.HTTP.Do(req)
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
	mounted, err := c.Builtins.backend.isMounted(c.Builtins.Root)
	if err != nil || !mounted {
		return errors.New("cache filesystem unavailable")
	}
	c.HTTP = &http.Client{Timeout: 6 * time.Minute, CheckRedirect: func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }}
	backend := &cachevolumes.APFSImages{LocalImages: cachevolumes.LocalImages{
		Root: c.Root, SizeGB: 20, MinFreeBytes: 40_000_000_000,
		Transfer:  &cachevolumes.HTTPTransfer{URL: c.URL + "/image", Node: c.Node, Client: c.HTTP, MaxBytes: 21_000_000_000, Token: c.token},
		FreeBytes: c.freeBytes,
	}, Guard: func() func() { c.Builtins.mu.Lock(); return c.Builtins.mu.Unlock }, Create: createCustomImage, Verify: verifyCustomImage, Detach: detachCustomInspection}
	c.Builtins.mu.Lock()
	c.Builtins.CustomReserved = func() uint64 {
		images, err := filepath.Glob(filepath.Join(c.Root, "images", "*.img"))
		if err != nil {
			return ^uint64(0) / 2
		}
		return uint64(len(images)) * 20_000_000_000
	}
	c.Builtins.mu.Unlock()
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
	c.Store = store
	c.ready.Store(true)
	defer c.ready.Store(false)
	ticker := time.NewTicker(time.Second)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return nil
		case <-ticker.C:
			if err := c.reconcile(ctx); err != nil {
				log.FromContext(ctx).Error(err, "custom cache reconciliation")
			}
		}
	}
}

func (c *CustomVolumes) freeBytes(string) (uint64, error) {
	mounted, err := c.Builtins.backend.isMounted(c.Builtins.Root)
	if err != nil || !mounted {
		return 0, errors.New("cache filesystem unavailable")
	}
	free, err := c.Builtins.backend.freeBytes(c.Root)
	if err != nil {
		return 0, err
	}
	reserved := uint64(len(c.Builtins.reserved)) * c.Builtins.capBytes()
	images, err := filepath.Glob(filepath.Join(c.Root, "images", "*.img"))
	if err != nil {
		return 0, err
	}
	reserved += uint64(len(images)) * 20_000_000_000
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
			return "delete", nil
		}
		return "hold", nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	var result struct {
		Action string `json:"action"`
	}
	_, err := c.request(ctx, "report", map[string]any{"id": slot.ID, "node_name": c.Node, "state": slot.State, "gone": gone, "warm": slot.Warm, "size_bytes": slot.SizeBytes, "capacity_bytes": slot.CapacityBytes, "attach_ms": nil}, &result)
	return result.Action, err
}

func (c *CustomVolumes) reconcile(ctx context.Context) error {
	pods, err := c.Kube.CoreV1().Pods(c.Namespace).List(ctx, metav1.ListOptions{FieldSelector: "spec.nodeName=" + c.Node})
	if err != nil {
		return err
	}
	for _, pod := range pods.Items {
		if pod.DeletionTimestamp != nil || pod.Status.Phase != corev1.PodRunning || pod.Labels["tuist.dev/runner"] != "true" {
			continue
		}
		if err := c.requests(ctx, &pod); err != nil {
			log.FromContext(ctx).Error(err, "custom cache request", "pod", pod.Name)
		}
	}
	if time.Since(c.lastReport) < 30*time.Second {
		return nil
	}
	c.lastReport = time.Now()
	if err = c.Store.Reconcile(c.gone, c.report); err != nil {
		return err
	}
	err = c.Store.CleanPods(func(uid string) (bool, error) {
		name, err := os.ReadFile(filepath.Join(c.Root, "owners", uid))
		if err != nil {
			return false, err
		}
		return c.gone(string(name), uid)
	})
	if err != nil {
		return err
	}
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
			Key string `json:"key"`
			UID int    `json:"uid"`
		}
		err = json.NewDecoder(io.LimitReader(file, 4096)).Decode(&input)
		file.Close()
		if err != nil {
			continue
		}
		var identity cachevolumes.Identity
		status, err := c.request(ctx, "authorize", map[string]any{"pod_name": pod.Name, "pod_uid": string(pod.UID), "node_name": c.Node, "key": input.Key, "architecture": "arm64", "uid": input.UID}, &identity)
		if status == http.StatusTooEarly && time.Since(info.ModTime()) < 30*time.Second {
			continue
		}
		response := map[string]any{"error": "unavailable"}
		if err == nil {
			warm, err := c.Store.Acquire(identity, pod.Name, string(pod.UID))
			if err == nil {
				response = map[string]any{"id": identity.ID, "directory": identity.Scope, "warm": warm}
			}
		}
		data, _ := json.Marshal(response)
		// O_EXCL prevents following a guest-created output symlink.
		out, err := root.OpenFile(name+".response", os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
		if err != nil {
			continue
		}
		_, err = out.Write(data)
		out.Close()
		if err != nil {
			return err
		}
	}
	return nil
}
