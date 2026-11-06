//go:build linux

package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Run only inside a disposable privileged Docker 28 DinD container. This uses
// the real cleanup, clean unmount and a new daemon and client for every job.
func TestDockerBuildCacheAcrossJobs(t *testing.T) {
	if os.Getenv("TUIST_TEST_DOCKER_CACHE") != "1" {
		t.Skip("requires the isolated Docker cache integration container")
	}
	for _, driver := range []string{"docker", "docker-container"} {
		t.Run(driver, func(t *testing.T) { testDockerBuildCacheAcrossJobs(t, driver) })
	}
}

func testDockerBuildCacheAcrossJobs(t *testing.T, driver string) {
	root := t.TempDir()
	scope := filepath.Join(root, dockerTestScope)
	dataRoot := filepath.Join(root, "data")
	for _, path := range []string{scope, dataRoot} {
		if err := os.MkdirAll(path, 0700); err != nil {
			t.Fatal(err)
		}
	}
	image := filepath.Join(scope, dockerImageName)
	file, err := os.Create(image)
	if err != nil {
		t.Fatal(err)
	}
	if err := file.Truncate(2 << 30); err != nil {
		t.Fatal(err)
	}
	file.Close()
	ctx, cancel := context.WithTimeout(context.Background(), 12*time.Minute)
	defer cancel()
	run := func(ctx context.Context, name string, args ...string) ([]byte, error) {
		return exec.CommandContext(ctx, name, args...).CombinedOutput()
	}
	command := func(name string, args ...string) string {
		t.Helper()
		out, err := run(ctx, name, args...)
		if err != nil {
			t.Fatalf("%s %v: %v\n%s", name, args, err, out)
		}
		return string(out)
	}
	command("mkfs.ext4", append(dockerFormatArgs, image)...)
	buildContext := filepath.Join(root, "context")
	if err := os.MkdirAll(buildContext, 0700); err != nil {
		t.Fatal(err)
	}
	write := func(name, contents string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(buildContext, name), []byte(contents), 0600); err != nil {
			t.Fatal(err)
		}
	}
	// A real Go compile makes the cache mount useful when COPY invalidates the
	// layer. The marker proves the command ran and read the prior job's mount;
	// a CACHED log alone would not prove mutable cache persistence.
	write("Dockerfile", `FROM golang:1.26.5-alpine AS build
WORKDIR /src
COPY main.go .
RUN --mount=type=cache,id=tuist-build-proof,target=/root/.cache/go-build \
    if [ -f /root/.cache/go-build/proof ]; then echo MOUNT_REUSED; else echo MOUNT_COLD; fi; \
    cat /root/.cache/go-build/proof 2>/dev/null || true; \
    CGO_ENABLED=0 go build -o /app main.go && cp main.go /root/.cache/go-build/proof
FROM scratch
COPY --from=build /app /app
`)
	program := func(version string) string {
		return fmt.Sprintf("package main\nimport (\"fmt\"; _ \"net/http\")\nfunc main() { fmt.Println(%q) }\n", version)
	}
	write("main.go", program("first"))
	builder := "tuist-" + digest(driver)[:32]
	volume := "buildx_buildkit_" + builder + "0_state"
	for job, phase := range []string{"cold", "warm-layers", "changed-source", "same-size-mount-write", "verify-same-size-write"} {
		t.Logf("starting %s job %s", driver, phase)
		command("mount", "-o", "loop", image, dataRoot)
		d := &daemon{root: root, source: dockerTestScope + "/" + dockerImageName, dataRoot: dataRoot, mergeRoot: filepath.Join(root, "merge"), state: "volume", run: run, pipe: pipeDocker,
			args: []string{"dockerd", "--data-root", dataRoot, "--host", "unix:///var/run/docker.sock", "--pidfile", filepath.Join(root, "docker.pid"), "--storage-driver", "overlay2"}}
		if err := d.start(); err != nil {
			t.Fatal(err)
		}
		t.Cleanup(func() {
			d.mu.Lock()
			d.stop()
			d.mu.Unlock()
			_, _ = run(context.Background(), "umount", dataRoot)
		})
		if err := d.ready(ctx); err != nil {
			t.Fatal(err)
		}
		d.base, err = d.snapshot(ctx, "")
		if err != nil {
			t.Fatal(err)
		}
		d.ledger = readDockerLedger(dockerLedgerFile(dataRoot))
		// New Buildx metadata each job: only persisted daemon/volume state can hit.
		t.Setenv("DOCKER_CONFIG", t.TempDir())
		selected := "default"
		if driver == "docker-container" {
			command("docker", "volume", "create", "--label", buildkitVolumeLabel, volume)
			command("docker", "buildx", "create", "--name", builder, "--driver", driver, "--bootstrap")
			selected = builder
		}
		command("docker", "volume", "create", "ordinary-service-data")
		if job >= 2 {
			write("main.go", program([]string{"second", "third!", "fourth"}[job-2]))
		}
		started := time.Now()
		output := command("docker", "buildx", "build", "--builder", selected, "--progress=plain", "--output", "type=local,dest="+filepath.Join(root, phase), buildContext)
		t.Logf("DOCKER_CACHE_MEASUREMENT driver=%s phase=%s elapsed_ms=%d", driver, phase, time.Since(started).Milliseconds())
		if phase == "cold" && !strings.Contains(output, "MOUNT_COLD") {
			t.Fatalf("cold build was not cold:\n%s", output)
		}
		if phase == "warm-layers" && (!strings.Contains(output, "CACHED") || strings.Contains(output, "MOUNT_REUSED\n") || strings.Contains(output, "MOUNT_COLD\n")) {
			t.Fatalf("identical build did not reuse its layers:\n%s", output)
		}
		if job >= 2 {
			previous := []string{"first", "second", "third!"}[job-2]
			if !strings.Contains(output, "MOUNT_REUSED") || !strings.Contains(output, fmt.Sprintf("fmt.Println(%q)", previous)) {
				t.Fatalf("re-executed step did not read %s from the previous job's cache mount:\n%s", previous, output)
			}
		}
		binary := filepath.Join(root, phase, "app")
		want := "first"
		if job >= 2 {
			want = []string{"second", "third!", "fourth"}[job-2]
		}
		if got := strings.TrimSpace(command(binary)); got != want {
			t.Fatalf("stale build output: got %q, want %q", got, want)
		}
		if driver == "docker-container" {
			// This is docker/setup-buildx-action's keep-state post-action path.
			command("docker", "buildx", "rm", "--keep-state", builder)
		}
		message := dockerMessage{Docker: "teardown"}
		if job == 2 {
			message.Merge, message.Generation = dockerTestScope+"/"+dockerMergeImageName, 2
		}
		if _, err := d.handle(message); err != nil {
			t.Fatal(err)
		}
		report := readTeardownReport(t, d)
		if !report.Clean || (job != 1 && !report.Changed) {
			t.Fatalf("build state would not be published: %+v", report)
		}
		if job == 0 {
			command("cp", "--sparse=always", image, filepath.Join(scope, dockerMergeImageName))
		}
		if job == 2 {
			if report.MergedGeneration != 2 {
				t.Fatalf("build-only merge failed: %+v", report)
			}
			if report.MergedInto == "head" {
				// The host adopts the merged head clone before the next job.
				if err := os.Rename(filepath.Join(scope, dockerMergeImageName), image); err != nil {
					t.Fatal(err)
				}
			}
		}
		// Inspect the saved filesystem offline, then let the next job's daemon
		// read it. The ordinary service volume must not be part of the cache.
		command("mount", "-o", "loop", image, dataRoot)
		if _, err := os.Stat(filepath.Join(dataRoot, "volumes", "ordinary-service-data")); !os.IsNotExist(err) {
			t.Fatalf("ordinary service volume survived: %v", err)
		}
		command("umount", dataRoot)
	}
}
