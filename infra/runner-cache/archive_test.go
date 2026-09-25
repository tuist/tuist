package cachevolumes

import (
	"bytes"
	"crypto/rand"
	"os"
	"path/filepath"
	"testing"
)

func TestImageArchiveRestoresIncompressibleImageAtCapacity(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "image")
	data := make([]byte, 1<<20)
	if _, err := rand.Read(data); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(src, data, 0600); err != nil {
		t.Fatal(err)
	}
	_, digest, err := compressImage(src, src+".gz")
	if err != nil {
		t.Fatal(err)
	}
	compressed, err := os.ReadFile(src + ".gz")
	if err != nil {
		t.Fatal(err)
	}
	if len(compressed) <= len(data) {
		t.Fatal("fixture must exercise compression overhead")
	}
	target := filepath.Join(dir, "restored")
	if err := RestoreImage(bytes.NewReader(compressed), target, digest, int64(len(data))); err != nil {
		t.Fatal(err)
	}
	restored, err := os.ReadFile(target)
	if err != nil || !bytes.Equal(restored, data) {
		t.Fatal("restoration changed bytes", err)
	}
}

func TestImageArchiveRestoresZerosAndRejectsCorruptionAndOversize(t *testing.T) {
	dir := t.TempDir()
	src := filepath.Join(dir, "image")
	archive := src + ".gz"
	data := make([]byte, 2<<20)
	copy(data[1<<20:], "cache payload")
	os.WriteFile(src, data, 0600)
	_, digest, err := compressImage(src, archive)
	if err != nil {
		t.Fatal(err)
	}
	compressed, _ := os.ReadFile(archive)
	target := filepath.Join(dir, "restored")
	if err := RestoreImage(bytes.NewReader(compressed), target, digest, int64(len(data))); err != nil {
		t.Fatal(err)
	}
	restored, _ := os.ReadFile(target)
	if !bytes.Equal(restored, data) {
		t.Fatal("restoration changed bytes")
	}
	for name, limit := range map[string]int64{"corrupt": int64(len(data)), "oversize": 100} {
		target := filepath.Join(dir, name)
		hash := digest
		if name == "corrupt" {
			hash = "bad"
		}
		if err := RestoreImage(bytes.NewReader(compressed), target, hash, limit); err == nil {
			t.Fatal("accepted", name)
		}
		if _, err := os.Stat(target); !os.IsNotExist(err) {
			t.Fatal("retained unverified image")
		}
	}
}
