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
	"sort"
	"strings"
	"time"

	"sigs.k8s.io/controller-runtime/pkg/log"
)

const (
	usageRetryDelay   = time.Minute
	usageReportMaxAge = 24 * time.Hour
)

var (
	// The server will never accept this report: its execution binding cannot
	// arrive (410) or the report is invalid (422).
	errUsageRejected = errors.New("volume usage report rejected")
	// The job's execution binding has not reached the server yet (425).
	errUsagePending = errors.New("volume usage execution pending")
)

type volumeUsage struct {
	PodName           string `json:"pod_name"`
	PodUID            string `json:"pod_uid"`
	VolumeName        string `json:"volume_name"`
	AttachedAt        string `json:"attached_at"`
	AttachMS          int64  `json:"attach_ms"`
	AttachedSizeBytes int64  `json:"attached_size_bytes"`
	SizeBytes         int64  `json:"size_bytes"`
	CapacityBytes     int64  `json:"capacity_bytes"`
	Warm              *bool  `json:"warm"`
	Outcome           string `json:"outcome"`
	Generation        int    `json:"generation"`
	BaseGeneration    int    `json:"base_generation"`
}

func readVolumeUsage(dir string) *volumeUsage {
	data, ok := readGuestFile(dir, "cache-usage.json", guestMarkerMaxBytes)
	if !ok {
		return nil
	}
	var u volumeUsage
	if json.Unmarshal(data, &u) != nil {
		return nil
	}
	if _, err := time.Parse(time.RFC3339, u.AttachedAt); err != nil {
		return nil
	}
	if u.Warm == nil || u.AttachMS < 0 || u.AttachMS > 3600000 || u.CapacityBytes <= 0 || u.CapacityBytes > 9_000_000_000_000_000 || u.SizeBytes < 0 || u.SizeBytes > u.CapacityBytes || u.AttachedSizeBytes < 0 || u.AttachedSizeBytes > u.CapacityBytes {
		return nil
	}
	return &u
}

// The queue lives outside the guest share and survives host restarts. Only the
// host adds job/volume identity and the actual finalization outcome.
func (w *ConvergeWorker) queueUsage(entry *Entry, usage *volumeUsage, outcome VolumeOutcome) error {
	if w == nil || usage == nil || entry.PodName == "" || entry.PodUID == "" {
		return nil
	}
	usage.PodName, usage.PodUID, usage.VolumeName = entry.PodName, entry.PodUID, entry.Volume.VolumeName
	usage.Outcome, usage.Generation = string(outcome), entry.Volume.PromotedGeneration
	usage.BaseGeneration = 0
	if data, ok := readGuestFile(entry.VolumeStatusDir, baseGenerationFile, guestMarkerMaxBytes); ok {
		_, _ = fmt.Sscanf(string(data), "%d", &usage.BaseGeneration)
	}
	dir := filepath.Join(w.Volumes.Root, "usage-reports")
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	if entries, err := os.ReadDir(dir); err != nil {
		return err
	} else if len(entries) >= 4096 {
		return fmt.Errorf("volume usage queue full")
	}
	data, err := json.Marshal(usage)
	if err != nil {
		return err
	}
	path := filepath.Join(dir, entry.PodUID+".json")
	file, err := os.CreateTemp(dir, ".pending-")
	if err != nil {
		return err
	}
	defer os.Remove(file.Name())
	if _, err = file.Write(data); err != nil {
		file.Close()
		return err
	}
	if err = file.Sync(); err != nil {
		file.Close()
		return err
	}
	if err = file.Close(); err != nil {
		return err
	}
	if err = os.Rename(file.Name(), path); err != nil {
		return err
	}
	directory, err := os.Open(dir)
	if err != nil {
		return err
	}
	err = directory.Sync()
	_ = directory.Close()
	if err != nil {
		return err
	}
	w.signal()
	return nil
}

func (w *ConvergeWorker) reportUsage(ctx context.Context) {
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	source, ok := w.Prefetch.(*ServerPrefetch)
	if !ok {
		return
	}
	dir := filepath.Join(w.Volumes.Root, "usage-reports")
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	// A pending execution binding must not starve reports from other jobs.
	sort.SliceStable(entries, func(i, j int) bool {
		a, errA := entries[i].Info()
		b, errB := entries[j].Info()
		return errA == nil && errB == nil && a.ModTime().Before(b.ModTime())
	})
	sent := 0
	now := time.Now()
	for _, entry := range entries {
		if sent >= 8 || ctx.Err() != nil {
			return
		}
		if !strings.HasSuffix(entry.Name(), ".json") || !entry.Type().IsRegular() {
			continue
		}
		// A failed report's mtime is pushed into the future until its next attempt.
		if info, err := entry.Info(); err != nil || info.ModTime().After(now) {
			continue
		}
		data, ok := readGuestFile(dir, entry.Name(), guestMarkerMaxBytes)
		if !ok {
			continue
		}
		sent++
		path := filepath.Join(dir, entry.Name())
		err := source.reportUsage(ctx, data)
		// Only the server's verdict expires a report. Local failures such as an
		// unknown endpoint keep it queued, bounded by the queue cap.
		pending := errors.Is(err, errUsagePending)
		if err != nil && !errors.Is(err, errUsageRejected) && (!pending || !usageReportExpired(data, now)) {
			if pending {
				log.FromContext(ctx).V(1).Info("volume usage execution pending", "report", entry.Name())
			} else {
				log.FromContext(ctx).Error(err, "report volume usage", "report", entry.Name())
			}
			retry := now.Add(usageRetryDelay)
			_ = os.Chtimes(path, retry, retry)
			continue
		}
		if err != nil {
			log.FromContext(ctx).Info("drop volume usage report", "report", entry.Name(), "error", err.Error())
		}
		_ = os.Remove(path)
	}
}

func usageReportExpired(data []byte, now time.Time) bool {
	var usage volumeUsage
	if json.Unmarshal(data, &usage) != nil {
		return true
	}
	attached, err := time.Parse(time.RFC3339, usage.AttachedAt)
	return err != nil || now.Sub(attached) > usageReportMaxAge
}

func (s *ServerPrefetch) reportUsage(ctx context.Context, data []byte) error {
	s.mu.Lock()
	endpoint := s.endpoint
	s.mu.Unlock()
	if endpoint == "" {
		return errPrefetchUnavailable
	}
	ctx, cancel := context.WithTimeout(ctx, prefetchRequestTimeout)
	defer cancel()
	token, err := s.hostToken(ctx)
	if err != nil {
		return err
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint+"/usage", bytes.NewReader(data))
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	client := s.HTTP
	if client == nil {
		client = prefetchHTTPClient
	}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
	switch resp.StatusCode {
	case http.StatusOK:
		return nil
	case http.StatusGone, http.StatusUnprocessableEntity:
		return fmt.Errorf("%w: HTTP %d", errUsageRejected, resp.StatusCode)
	case http.StatusTooEarly:
		return fmt.Errorf("%w: HTTP %d", errUsagePending, resp.StatusCode)
	default:
		return fmt.Errorf("report volume usage: HTTP %d", resp.StatusCode)
	}
}
