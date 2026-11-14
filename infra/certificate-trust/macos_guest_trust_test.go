package main

import (
	"encoding/json"
	"slices"
	"strings"
	"testing"
)

// The macOS image templates once carried separate copies of this step, and a
// fix that landed in only one broke the other image's release.
func TestMacOSImagesShareGuestTrustScript(t *testing.T) {
	upload := `source      = "${path.root}/../certificate-trust/macos-guest-trust.sh"
    destination = "/tmp/tuist-macos-guest-trust.sh"`
	for _, template := range []string{"../runner-image/runner.pkr.hcl", "../xcresult-processor-image/xcresult-processor.pkr.hcl"} {
		source := string(read(t, template))
		if !strings.Contains(source, upload) || !strings.Contains(source, `inline = ["bash /tmp/tuist-macos-guest-trust.sh"]`) {
			t.Fatalf("template must upload and run macos-guest-trust.sh: %s", template)
		}
		for _, inlined := range []string{"add-trusted-cert", "trust-settings.admin", "SystemRootCertificates.keychain"} {
			if strings.Contains(source, inlined) {
				t.Fatalf("move trust changes into macos-guest-trust.sh instead of %s: %s", template, inlined)
			}
		}
	}

	var release struct {
		Components []struct {
			Name         string   `json:"name"`
			IncludePaths []string `json:"include_paths"`
		} `json:"components"`
	}
	if err := json.Unmarshal(read(t, "../../mise/tasks/release/components.json"), &release); err != nil {
		t.Fatal(err)
	}
	for _, component := range release.Components {
		if (component.Name == "runner-image" || component.Name == "xcresult-processor-image") &&
			!slices.Contains(component.IncludePaths, "infra/certificate-trust/macos-guest-trust.sh") {
			t.Fatalf("%s must release when macos-guest-trust.sh changes", component.Name)
		}
	}
}
