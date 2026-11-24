// Staging qualification build for step 2b; drop before merging.
package main

// An in-place upgrade of the daemon's container (step 2b) leaves the VMs
// running in the vmm container for the next daemon. The updater arms it by
// annotating the daemon's Pod: the annotation names this container and an
// expiry, and reaches the daemon through the downward API file
// HANDOVER_FILE, which the kubelet refreshes. Only an armed SIGTERM hands
// the VMs over; any other (the Pod deleted, the node draining, an expired or
// another container's annotation) pauses them as before.

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"log/slog"
	"os"
	"regexp"
	"strconv"
	"strings"
	"time"
)

const handoverAnnotation = "sandboxes.tuist.dev/handover"

type handoverMarker struct {
	Container string    `json:"container"`
	Until     time.Time `json:"until"`
	Nonce     string    `json:"nonce"`
}

type handoverArm struct {
	file      string
	container string
	config    string
	log       *slog.Logger
	now       func() time.Time
}

// newHandoverArm is nil when nothing can arm a handover: no file, or a
// container this process cannot name.
func newHandoverArm(log *slog.Logger, file, config string) *handoverArm {
	if file == "" {
		return nil
	}
	data, err := os.ReadFile("/proc/self/cgroup")
	container := ""
	if err == nil {
		container = containerID(string(data))
	}
	if container == "" {
		log.Warn("handovers are off: the daemon cannot read its container id", "error", err)
		return nil
	}
	return &handoverArm{file: file, container: container, config: config, log: log, now: time.Now}
}

var containerIDPattern = regexp.MustCompile(`[0-9a-f]{64}`)

// containerID is the last 64-hex segment of the cgroup path, the
// container's id under both the systemd and the cgroupfs drivers
// (`cri-containerd-<id>.scope`, `/kubepods/.../<id>`).
func containerID(cgroup string) string {
	ids := containerIDPattern.FindAllString(cgroup, -1)
	if len(ids) == 0 {
		return ""
	}
	return ids[len(ids)-1]
}

// armed is the marker when it names this container and has not expired.
func (h *handoverArm) armed() (handoverMarker, bool) {
	data, err := os.ReadFile(h.file)
	if err != nil {
		return handoverMarker{}, false
	}
	value, ok := downwardAPIValue(string(data), handoverAnnotation)
	if !ok {
		return handoverMarker{}, false
	}
	var marker handoverMarker
	if err := json.Unmarshal([]byte(value), &marker); err != nil {
		return handoverMarker{}, false
	}
	// The pod status names it containerd://<id>.
	container := marker.Container[strings.LastIndexByte(marker.Container, '/')+1:]
	if container != h.container || !h.now().Before(marker.Until) {
		return handoverMarker{}, false
	}
	return marker, true
}

// watch logs each marker as it arms, with the hash of the configuration
// file a restarted daemon would read now, until ctx ends. The updater
// patches the image only once it saw its marker's nonce and the new
// configuration's hash here, since the kubelet refreshes both files on its
// own schedule.
func (h *handoverArm) watch(ctx context.Context) {
	logged := ""
	ticker := time.NewTicker(2 * time.Second)
	defer ticker.Stop()
	for {
		if marker, ok := h.armed(); ok {
			sum := h.configSum()
			if key := marker.Nonce + "/" + sum; key != logged {
				logged = key
				h.log.Info("handover armed", "nonce", marker.Nonce, "until", marker.Until, "config_sha256", sum)
			}
		}
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (h *handoverArm) configSum() string {
	if h.config == "" {
		return ""
	}
	data, err := os.ReadFile(h.config)
	if err != nil {
		return ""
	}
	sum := sha256.Sum256(data)
	return hex.EncodeToString(sum[:])
}

// downwardAPIValue reads one key of a downward API annotations file, which
// holds a `key="quoted value"` line per annotation.
func downwardAPIValue(text, key string) (string, bool) {
	scanner := bufio.NewScanner(strings.NewReader(text))
	scanner.Buffer(make([]byte, 0, 64<<10), 1<<20)
	for scanner.Scan() {
		k, v, ok := strings.Cut(scanner.Text(), "=")
		if !ok || k != key {
			continue
		}
		value, err := strconv.Unquote(v)
		return value, err == nil
	}
	return "", false
}
