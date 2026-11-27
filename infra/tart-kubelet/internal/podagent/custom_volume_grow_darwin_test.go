//go:build darwin

package podagent

import (
	"context"
	"path/filepath"
	"strings"
	"testing"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
)

func TestGrowCustomImageExtendsOnlyTheImageAndNeverShrinks(t *testing.T) {
	image := filepath.Join(t.TempDir(), "copy.sparseimage")
	if err := createCustomImage(context.Background(), image, 1_000_000_000); err != nil {
		t.Fatal(err)
	}

	if err := growCustomImage(context.Background(), image, 2_000_000_000); err != nil {
		t.Fatal(err)
	}

	if size, err := customImageBytes(context.Background(), image); err != nil || size != 2_000_000_000 {
		t.Fatal("image was not grown to 2 GB:", size, err)
	}
	if err := growCustomImage(context.Background(), image, 1_000_000_000); err != nil {
		t.Fatal(err)
	}
	if size, err := customImageBytes(context.Background(), image); err != nil || size != 2_000_000_000 {
		t.Fatal("a smaller capacity shrank the image:", size, err)
	}
	// The APFS container is the guest's to grow; the image still verifies.
	if _, err := verifyCustomImage(image); err != nil {
		t.Fatal("grown image no longer verifies:", err)
	}
}

func TestGrowCustomDiskExtendsOnlyTheASIFImageAndNeverShrinks(t *testing.T) {
	image := filepath.Join(t.TempDir(), "copy.img")
	slot := cachevolumes.Slot{Identity: cachevolumes.Identity{Scope: strings.Repeat("a", 64)}}
	if err := createCustomDisk(context.Background(), slot, image, 1_000_000_000); err != nil {
		t.Fatal(err)
	}
	size := func() int64 {
		bytes, err := imageBytes(context.Background(), "diskutil", "image", "info", image)
		if err != nil {
			t.Fatal(err)
		}
		return bytes
	}
	if err := growCustomDisk(context.Background(), image, 2_000_000_000); err != nil {
		t.Fatal(err)
	}
	grown := size()
	if grown < 2_000_000_000 {
		t.Fatal("image was not grown to 2 GB:", grown)
	}
	if err := growCustomDisk(context.Background(), image, 1_000_000_000); err != nil {
		t.Fatal(err)
	}
	if size() != grown {
		t.Fatal("a smaller capacity shrank the image")
	}
	// The APFS container is the guest's to grow; the image still verifies.
	if _, err := verifyCustomDisk(image); err != nil {
		t.Fatal("grown image no longer verifies:", err)
	}
}
