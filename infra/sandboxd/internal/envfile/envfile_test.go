package envfile

import (
	"os"
	"path/filepath"
	"testing"
)

func TestLoadFillsOnlyUnsetVariables(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config")
	content := "# deploy config\nENVFILE_TEST_A=from-file\n\nENVFILE_TEST_B = spaced=value\nENVFILE_TEST_EMPTY=\n"
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Setenv("ENVFILE_TEST_A", "from-pod")
	if err := Load(path); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.Unsetenv("ENVFILE_TEST_B"); os.Unsetenv("ENVFILE_TEST_EMPTY") })
	if got := os.Getenv("ENVFILE_TEST_A"); got != "from-pod" {
		t.Fatalf("the file overrode the Pod's variable: %q", got)
	}
	if got := os.Getenv("ENVFILE_TEST_B"); got != " spaced=value" {
		t.Fatalf("B = %q", got)
	}
	if got, set := os.LookupEnv("ENVFILE_TEST_EMPTY"); !set || got != "" {
		t.Fatalf("an empty value was not applied: %q %v", got, set)
	}
}

func TestLoadRejectsMalformedLinesAndMissingFiles(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config")
	if err := os.WriteFile(path, []byte("NOT A PAIR\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := Load(path); err == nil {
		t.Fatal("accepted a line without =")
	}
	if err := Load(filepath.Join(t.TempDir(), "missing")); err == nil {
		t.Fatal("accepted a missing file")
	}
	if err := Load(""); err != nil {
		t.Fatal(err)
	}
}
