//go:build darwin

package podagent

import (
	"context"
	"path/filepath"
	"testing"
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
	if err := verifyCustomImage(image); err != nil {
		t.Fatal("grown image no longer verifies:", err)
	}
}
