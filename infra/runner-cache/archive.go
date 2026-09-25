package cachevolumes

import (
	"bytes"
	"compress/gzip"
	"crypto/sha1"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
)

// Raw ext4 images have a fixed logical length. Compress holes for object storage
// and restore them sparsely; transferring the raw 20 GB file would waste the
// locality benefit. The shared macOS object protocol verifies the archive bytes.
func compressImage(src, dst string) (string, string, error) {
	in, err := os.Open(src)
	if err != nil {
		return "", "", err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_TRUNC|os.O_WRONLY, 0600)
	if err != nil {
		return "", "", err
	}
	defer out.Close()
	inventory, content := sha1.New(), sha256.New()
	gz, _ := gzip.NewWriterLevel(io.MultiWriter(out, inventory, content), gzip.BestSpeed)
	if _, err = io.Copy(gz, in); err != nil {
		return "", "", err
	}
	if err = gz.Close(); err != nil {
		return "", "", err
	}
	if err = out.Sync(); err != nil {
		return "", "", err
	}
	return hex.EncodeToString(inventory.Sum(nil)), hex.EncodeToString(content.Sum(nil)), nil
}

// RestoreImage validates the transferred bytes before the caller installs the
// image as a master. Both compressed and expanded input are bounded.
func RestoreImage(src io.Reader, dst, digest string, maxBytes int64) error {
	h := sha256.New()
	// Incompressible payloads can grow slightly in gzip. Bound that overhead
	// separately while retaining the exact limit on expanded image bytes.
	bounded := &io.LimitedReader{R: src, N: maxBytes + maxBytes/100 + (1 << 20) + 1}
	gz, err := gzip.NewReader(io.TeeReader(bounded, h))
	if err != nil {
		return err
	}
	defer gz.Close()
	out, err := os.OpenFile(dst, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0600)
	if err != nil {
		return err
	}
	defer out.Close()
	valid := false
	defer func() {
		if !valid {
			os.Remove(dst)
		}
	}()
	buf, zero := make([]byte, 128*1024), make([]byte, 128*1024)
	var total int64
	for {
		n, e := io.ReadFull(gz, buf)
		total += int64(n)
		if total > maxBytes {
			return errors.New("cache image exceeds capacity")
		}
		if n > 0 {
			if bytes.Equal(buf[:n], zero[:n]) {
				_, err = out.Seek(int64(n), io.SeekCurrent)
			} else {
				_, err = out.Write(buf[:n])
			}
			if err != nil {
				return err
			}
		}
		if e == io.EOF || e == io.ErrUnexpectedEOF {
			break
		}
		if e != nil {
			return e
		}
	}
	if bounded.N <= 0 || hex.EncodeToString(h.Sum(nil)) != digest {
		return errors.New("cache image checksum mismatch")
	}
	if total == 0 {
		return errors.New("empty cache image")
	}
	if err = out.Truncate(total); err != nil {
		return err
	}
	if err = out.Sync(); err != nil {
		return err
	}
	valid = true
	return nil
}
