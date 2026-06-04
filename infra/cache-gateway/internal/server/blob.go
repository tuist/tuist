package server

import (
	"context"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"

	"github.com/tuist/tuist/infra/cache-gateway/internal/metrics"
	"github.com/tuist/tuist/infra/cache-gateway/internal/sign"
)

func (s *Server) handleBlob(w http.ResponseWriter, r *http.Request) {
	objectKey, op, err := s.cfg.Signer.Verify(r)
	if err != nil {
		http.Error(w, "forbidden", http.StatusForbidden)
		return
	}

	ctx, cancel := context.WithTimeout(r.Context(), s.cfg.BlobTimeout)
	defer cancel()

	switch r.Method {
	case http.MethodPut:
		if op != sign.OpPut {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		s.handleBlobPut(ctx, w, r, objectKey)
	case http.MethodHead:
		if op != sign.OpRead {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		s.handleBlobHead(ctx, w, objectKey)
	case http.MethodGet:
		if op != sign.OpRead {
			http.Error(w, "forbidden", http.StatusForbidden)
			return
		}
		s.handleBlobGet(ctx, w, r, objectKey)
	default:
		http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
	}
}

func (s *Server) handleBlobPut(ctx context.Context, w http.ResponseWriter, r *http.Request, objectKey string) {
	comp := r.URL.Query().Get("comp")
	switch comp {
	case "": // Put Blob (single-shot)
		size := r.ContentLength
		err := s.cfg.Store.PutObject(ctx, objectKey, r.Body, size)
		s.recordBackend(err)
		if err != nil {
			metrics.BlobUpload.WithLabelValues("put_blob", "error").Inc()
			metrics.TranslationErrors.WithLabelValues("put_blob", "s3").Inc()
			http.Error(w, "upload failed", http.StatusBadGateway)
			return
		}
		if size > 0 {
			s.observeBandwidth(objectKey, "up", size)
		}
		metrics.BlobUpload.WithLabelValues("put_blob", "ok").Inc()
		w.WriteHeader(http.StatusCreated)

	case "block": // Put Block
		blockID := r.URL.Query().Get("blockid")
		if blockID == "" {
			http.Error(w, "missing blockid", http.StatusBadRequest)
			return
		}
		body, err := io.ReadAll(r.Body)
		if err != nil {
			http.Error(w, "read failed", http.StatusBadRequest)
			return
		}
		if err := s.cfg.Multipart.PutBlock(ctx, objectKey, blockID, body); err != nil {
			metrics.BlobUpload.WithLabelValues("put_block", "error").Inc()
			http.Error(w, "stage block failed", http.StatusBadGateway)
			return
		}
		s.observeBandwidth(objectKey, "up", int64(len(body)))
		metrics.BlobUpload.WithLabelValues("put_block", "ok").Inc()
		w.WriteHeader(http.StatusCreated)

	case "blocklist": // Put Block List
		ids, err := parseBlockList(r.Body)
		if err != nil {
			http.Error(w, "invalid block list", http.StatusBadRequest)
			return
		}
		err = s.cfg.Multipart.PutBlockList(ctx, objectKey, ids)
		s.recordBackend(err)
		if err != nil {
			metrics.BlobUpload.WithLabelValues("put_block_list", "error").Inc()
			metrics.TranslationErrors.WithLabelValues("put_block_list", "multipart").Inc()
			http.Error(w, "commit failed", http.StatusBadGateway)
			return
		}
		metrics.BlobUpload.WithLabelValues("put_block_list", "ok").Inc()
		w.WriteHeader(http.StatusCreated)

	default:
		http.Error(w, "unsupported comp", http.StatusBadRequest)
	}
}

func (s *Server) handleBlobHead(ctx context.Context, w http.ResponseWriter, objectKey string) {
	info, err := s.cfg.Store.HeadObject(ctx, objectKey)
	s.recordBackend(err)
	if err != nil {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	w.Header().Set("x-ms-blob-type", "BlockBlob")
	w.Header().Set("Content-Length", strconv.FormatInt(info.Size, 10))
	if info.ETag != "" {
		w.Header().Set("ETag", info.ETag)
	}
	if !info.LastModified.IsZero() {
		w.Header().Set("Last-Modified", info.LastModified.UTC().Format(http.TimeFormat))
	}
	w.Header().Set("Accept-Ranges", "bytes")
	w.WriteHeader(http.StatusOK)
}

func (s *Server) handleBlobGet(ctx context.Context, w http.ResponseWriter, r *http.Request, objectKey string) {
	start := s.now()
	off, length, ranged, err := parseRange(r.Header.Get("Range"))
	if err != nil {
		http.Error(w, "invalid range", http.StatusBadRequest)
		return
	}

	rc, info, err := s.cfg.Store.GetObjectRange(ctx, objectKey, off, length)
	s.recordBackend(err)
	if err != nil {
		metrics.BlobDownload.WithLabelValues("get_blob", "error").Inc()
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	defer rc.Close()

	metrics.FirstByteSeconds.WithLabelValues("down").Observe(s.now().Sub(start).Seconds())

	w.Header().Set("x-ms-blob-type", "BlockBlob")
	w.Header().Set("Accept-Ranges", "bytes")
	if info.ETag != "" {
		w.Header().Set("ETag", info.ETag)
	}

	if ranged {
		end := off + length - 1
		if length < 0 {
			end = info.Size - 1
		}
		w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", off, end, info.Size))
		w.Header().Set("Content-Length", strconv.FormatInt(end-off+1, 10))
		w.WriteHeader(http.StatusPartialContent)
	} else {
		w.Header().Set("Content-Length", strconv.FormatInt(info.Size, 10))
		w.WriteHeader(http.StatusOK)
	}

	n, _ := io.Copy(w, rc)
	s.observeBandwidth(objectKey, "down", n)
	metrics.BlobThroughput.WithLabelValues("down").Observe(float64(n))
	metrics.BlobDownload.WithLabelValues("get_blob", "ok").Inc()
}

func (s *Server) observeBandwidth(objectKey, direction string, n int64) {
	if direction == "up" {
		metrics.BlobThroughput.WithLabelValues("up").Observe(float64(n))
	}
	metrics.TenantBandwidth.WithLabelValues(accountFromObjectKey(objectKey), direction).Add(float64(n))
}

// accountFromObjectKey extracts the account segment from an opaque
// object key "acct/<acct>/blob/<id>" for per-tenant metrics. It returns
// "unknown" if the shape is unexpected.
func accountFromObjectKey(objectKey string) string {
	parts := strings.Split(objectKey, "/")
	if len(parts) >= 2 && parts[0] == "acct" {
		return parts[1]
	}
	return "unknown"
}

type blockListXML struct {
	XMLName     xml.Name `xml:"BlockList"`
	Latest      []string `xml:"Latest"`
	Committed   []string `xml:"Committed"`
	Uncommitted []string `xml:"Uncommitted"`
}

// parseBlockList reads the ordered block-id list. The actions/cache
// client commits freshly-staged blocks via <Latest>; <Committed> and
// <Uncommitted> are accepted too. Within an element type, document order
// is preserved, which is the commit order we replay.
func parseBlockList(body io.Reader) ([]string, error) {
	var bl blockListXML
	if err := xml.NewDecoder(body).Decode(&bl); err != nil {
		return nil, err
	}
	ids := make([]string, 0, len(bl.Latest)+len(bl.Committed)+len(bl.Uncommitted))
	ids = append(ids, bl.Latest...)
	ids = append(ids, bl.Committed...)
	ids = append(ids, bl.Uncommitted...)
	if len(ids) == 0 {
		return nil, fmt.Errorf("empty block list")
	}
	return ids, nil
}

// parseRange parses an Azure/HTTP byte range header "bytes=start-end" or
// "bytes=start-". ranged is false when no header is present (full read).
func parseRange(h string) (off, length int64, ranged bool, err error) {
	if h == "" {
		return 0, -1, false, nil
	}
	if !strings.HasPrefix(h, "bytes=") {
		return 0, 0, false, fmt.Errorf("unsupported range unit")
	}
	spec := strings.TrimPrefix(h, "bytes=")
	dash := strings.IndexByte(spec, '-')
	if dash < 0 {
		return 0, 0, false, fmt.Errorf("malformed range")
	}
	start, err := strconv.ParseInt(spec[:dash], 10, 64)
	if err != nil {
		return 0, 0, false, fmt.Errorf("malformed range start")
	}
	endStr := spec[dash+1:]
	if endStr == "" {
		return start, -1, true, nil // to end
	}
	end, err := strconv.ParseInt(endStr, 10, 64)
	if err != nil {
		return 0, 0, false, fmt.Errorf("malformed range end")
	}
	if end < start {
		return 0, 0, false, fmt.Errorf("range end before start")
	}
	return start, end - start + 1, true, nil
}
