package diskusage

import (
	"os"
	"path/filepath"
	"testing"
)

func write(t *testing.T, path string, size int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, make([]byte, size), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestReportCountsEachInodeOnceAndTemplatesBeforeJails(t *testing.T) {
	dataDir := t.TempDir()
	templates := filepath.Join(dataDir, "templates")
	jail := filepath.Join(dataDir, "jail")
	write(t, filepath.Join(templates, "default", "sha-1", "vmlinux"), 100)
	write(t, filepath.Join(templates, "default", "sha-1", "shapes", "2x4096", "mem"), 400)
	write(t, filepath.Join(jail, "a", "root", "workspace.ext4"), 30)
	write(t, filepath.Join(jail, "b", "root", "mem"), 50)
	if err := os.MkdirAll(filepath.Join(jail, "a", "root"), 0o755); err != nil {
		t.Fatal(err)
	}
	// Fresh jails hardlink the template's kernel and memory image.
	if err := os.Link(filepath.Join(templates, "default", "sha-1", "vmlinux"), filepath.Join(jail, "a", "root", "vmlinux")); err != nil {
		t.Fatal(err)
	}
	if err := os.Link(filepath.Join(templates, "default", "sha-1", "shapes", "2x4096", "mem"), filepath.Join(jail, "a", "root", "mem")); err != nil {
		t.Fatal(err)
	}
	// Sockets and pid files are not regular files and never count.
	if err := os.Mkdir(filepath.Join(jail, "a", "root", "run"), 0o755); err != nil {
		t.Fatal(err)
	}

	sizes := Accounter{
		DataDir: dataDir, TemplatesDir: templates, JailDir: jail, BudgetBytes: 1000,
		Exclusive: func(_ string, info os.FileInfo) (uint64, error) { return uint64(info.Size()), nil },
	}
	report, err := sizes.Report()
	if err != nil {
		t.Fatal(err)
	}
	if report.TemplatesBytes != 500 {
		t.Fatalf("templates = %d, want 500", report.TemplatesBytes)
	}
	if report.SandboxesBytes != 80 {
		t.Fatalf("sandboxes = %d, want 80 (hardlinked template files belong to the template)", report.SandboxesBytes)
	}
	if report.BudgetBytes != 1000 {
		t.Fatalf("budget = %d", report.BudgetBytes)
	}
	if report.TotalBytes == 0 || report.AvailableBytes == 0 || report.AvailableBytes > report.TotalBytes {
		t.Fatalf("filesystem numbers look wrong: total %d available %d", report.TotalBytes, report.AvailableBytes)
	}
}

func TestReportToleratesMissingDirectories(t *testing.T) {
	dataDir := t.TempDir()
	report, err := Accounter{DataDir: dataDir, TemplatesDir: filepath.Join(dataDir, "templates"), JailDir: filepath.Join(dataDir, "jail")}.Report()
	if err != nil {
		t.Fatal(err)
	}
	if report.TemplatesBytes != 0 || report.SandboxesBytes != 0 {
		t.Fatalf("empty data dir measured %+v", report)
	}
}

func TestDefaultExclusiveCountsAllocatedBytesOfSparseFiles(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "workspace.ext4")
	file, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := file.Truncate(64 << 20); err != nil {
		t.Fatal(err)
	}
	if _, err := file.WriteAt(make([]byte, 1<<20), 0); err != nil {
		t.Fatal(err)
	}
	if err := file.Close(); err != nil {
		t.Fatal(err)
	}
	info, err := os.Stat(path)
	if err != nil {
		t.Fatal(err)
	}
	bytes, err := exclusiveBytes(path, info)
	if err != nil {
		t.Fatal(err)
	}
	if bytes < 1<<20 || bytes >= 64<<20 {
		t.Fatalf("sparse 64 MiB file with 1 MiB written measured %d bytes", bytes)
	}
}
