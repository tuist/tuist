package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/tuist/tuist/infra/runners-controller/internal/cachevolumes"
)

type imageTransfer struct {
	URL, Node, TokenPath string
	Client               *http.Client
	MaxBytes             int64
}
type transferResponse struct {
	DownloadURL string `json:"download_url"`
	UploadURL   string `json:"upload_url"`
	Checksum    string `json:"checksum_sha256"`
	Generation  int64  `json:"generation"`
	Conflict    bool   `json:"conflict"`
}

func (t *imageTransfer) request(slot cachevolumes.Slot, operation, digest, content string) (transferResponse, error) {
	body, _ := json.Marshal(map[string]any{"id": slot.ID, "node_name": t.Node, "operation": operation, "image_digest": digest, "content_digest": content})
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, "POST", t.URL, bytes.NewReader(body))
	if err != nil {
		return transferResponse{}, err
	}
	token, err := os.ReadFile(t.TokenPath)
	if err != nil {
		return transferResponse{}, err
	}
	req.Header.Set("Authorization", "Bearer "+strings.TrimSpace(string(token)))
	req.Header.Set("Content-Type", "application/json")
	response, err := t.Client.Do(req)
	if err != nil {
		return transferResponse{}, errors.New("image metadata request failed")
	}
	defer response.Body.Close()
	if response.StatusCode == 409 {
		return transferResponse{}, cachevolumes.ErrConflict
	}
	if response.StatusCode != 200 {
		return transferResponse{}, fmt.Errorf("image metadata status %d", response.StatusCode)
	}
	var result transferResponse
	if err = json.NewDecoder(io.LimitReader(response.Body, 16384)).Decode(&result); err != nil {
		return result, err
	}
	if result.Conflict {
		return result, cachevolumes.ErrConflict
	}
	return result, nil
}
func (t *imageTransfer) Download(slot cachevolumes.Slot, path string) error {
	result, err := t.request(slot, "download", "", "")
	if err != nil {
		return err
	}
	if result.Generation != slot.BaseGeneration || result.DownloadURL == "" {
		return errors.New("cache master identity mismatch")
	}
	req, err := http.NewRequest("GET", result.DownloadURL, nil)
	if err != nil {
		return errors.New("invalid download URL")
	}
	response, err := t.Client.Do(req)
	if err != nil {
		return errors.New("image download failed")
	}
	defer response.Body.Close()
	if response.StatusCode != 200 {
		return fmt.Errorf("image download status %d", response.StatusCode)
	}
	return cachevolumes.RestoreImage(response.Body, path, slot.ContentDigest, t.MaxBytes)
}
func (t *imageTransfer) Publish(slot cachevolumes.Slot, path, digest, content string) (int64, error) {
	result, err := t.request(slot, "upload", digest, content)
	if err != nil {
		return 0, err
	}
	if result.Generation > 0 {
		return result.Generation, nil
	}
	file, err := os.Open(path)
	if err != nil {
		return 0, err
	}
	defer file.Close()
	stat, err := file.Stat()
	if err != nil {
		return 0, err
	}
	req, err := http.NewRequest("PUT", result.UploadURL, file)
	if err != nil {
		return 0, errors.New("invalid upload URL")
	}
	req.ContentLength = stat.Size()
	if result.Checksum != "" {
		req.Header.Set("x-amz-checksum-sha256", result.Checksum)
	}
	response, err := t.Client.Do(req)
	if err != nil {
		return 0, errors.New("image upload failed")
	}
	response.Body.Close()
	if response.StatusCode < 200 || response.StatusCode >= 300 {
		return 0, fmt.Errorf("image upload status %d", response.StatusCode)
	}
	result, err = t.request(slot, "publish", digest, content)
	if err == nil && result.Generation <= slot.BaseGeneration {
		return 0, errors.New("invalid published generation")
	}
	return result.Generation, err
}

func (t *imageTransfer) IsCurrent(slot cachevolumes.Slot) (bool, error) {
	result, err := t.request(slot, "retain", "", "")
	if errors.Is(err, cachevolumes.ErrConflict) {
		return false, nil
	}
	return result.Generation == slot.BaseGeneration, err
}
