package driver

import (
	"bytes"
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

func mountCapability(mode csi.VolumeCapability_AccessMode_Mode) *csi.VolumeCapability {
	return &csi.VolumeCapability{
		AccessType: &csi.VolumeCapability_Mount{Mount: &csi.VolumeCapability_MountVolume{}},
		AccessMode: &csi.VolumeCapability_AccessMode{Mode: mode},
	}
}

var rwo = mountCapability(csi.VolumeCapability_AccessMode_SINGLE_NODE_WRITER)

func nodeTopology(node string) *csi.TopologyRequirement {
	t := []*csi.Topology{{Segments: map[string]string{TopologyKey: node}}}
	return &csi.TopologyRequirement{Requisite: t, Preferred: t}
}

func createRequest(required int64) *csi.CreateVolumeRequest {
	return &csi.CreateVolumeRequest{
		Name:                      testVolumeID,
		CapacityRange:             &csi.CapacityRange{RequiredBytes: required},
		VolumeCapabilities:        []*csi.VolumeCapability{rwo},
		AccessibilityRequirements: nodeTopology(testNode),
	}
}

func TestNewRejectsUnsafeStateDir(t *testing.T) {
	root, err := filepath.EvalSymlinks(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	real := filepath.Join(root, "real")
	link := filepath.Join(root, "link")
	file := filepath.Join(root, "file")
	if err := os.Mkdir(real, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(real, link); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(file, nil, 0o600); err != nil {
		t.Fatal(err)
	}

	for _, dir := range []string{"", "/", "relative/dir", real + "/", real + "/../real", link, filepath.Join(link, "nested"), file, filepath.Join(root, "missing")} {
		t.Run(dir, func(t *testing.T) {
			_, err := New(Config{NodeID: testNode, StateDir: dir, Keys: &fakeKeys{}, Runner: &fakeRunner{t: t}, Mounts: &fakeMounts{}, Host: &fakeHost{}})
			if err == nil {
				t.Fatalf("New accepted state dir %q", dir)
			}
		})
	}
	if _, err := New(Config{NodeID: testNode, StateDir: real, Keys: &fakeKeys{}, Runner: &fakeRunner{t: t}, Mounts: &fakeMounts{}, Host: &fakeHost{}}); err != nil {
		t.Fatalf("New rejected canonical dir: %v", err)
	}
}

func TestInvalidVolumeIDsAreRejected(t *testing.T) {
	ids := []string{
		"",
		"pvc-0B5A7F7E-3C1D-4B8E-9F2A-6D4C1E2B3A59",
		"pvc-0b5a7f7e-3c1d-4b8e-9f2a-6d4c1e2b3a5",
		"pvc-0b5a7f7e-3c1d-4b8e-9f2a-6d4c1e2b3a59/../../etc",
		"../pvc-0b5a7f7e-3c1d-4b8e-9f2a-6d4c1e2b3a59",
		"pvc-../../../../../../../etc/passwd/aaaaaa",
		"pvc-0b5a7f7e-3c1d-4b8e-9f2a-6d4c1e2b3a59\n",
		"/data/kura-volumes/pvc-0b5a7f7e-3c1d-4b8e-9f2a-6d4c1e2b3a59",
		"vol-0b5a7f7e-3c1d-4b8e-9f2a-6d4c1e2b3a59",
	}
	for _, id := range ids {
		t.Run(id, func(t *testing.T) {
			e := newEnv(t)
			ctx := context.Background()
			req := createRequest(mib)
			req.Name = id
			calls := map[string]func() error{
				"CreateVolume": func() error { _, err := e.d.CreateVolume(ctx, req); return err },
				"DeleteVolume": func() error {
					_, err := e.d.DeleteVolume(ctx, &csi.DeleteVolumeRequest{VolumeId: id})
					return err
				},
				"NodeStageVolume": func() error {
					_, err := e.d.NodeStageVolume(ctx, &csi.NodeStageVolumeRequest{VolumeId: id, StagingTargetPath: e.staging, VolumeCapability: rwo})
					return err
				},
				"NodeUnstageVolume": func() error {
					_, err := e.d.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: id, StagingTargetPath: e.staging})
					return err
				},
				"NodePublishVolume": func() error {
					_, err := e.d.NodePublishVolume(ctx, &csi.NodePublishVolumeRequest{VolumeId: id, StagingTargetPath: e.staging, TargetPath: "/target", VolumeCapability: rwo})
					return err
				},
				"NodeUnpublishVolume": func() error {
					_, err := e.d.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: id, TargetPath: "/target"})
					return err
				},
				"NodeGetVolumeStats": func() error {
					_, err := e.d.NodeGetVolumeStats(ctx, &csi.NodeGetVolumeStatsRequest{VolumeId: id, VolumePath: "/target"})
					return err
				},
				"ValidateVolumeCapabilities": func() error {
					_, err := e.d.ValidateVolumeCapabilities(ctx, &csi.ValidateVolumeCapabilitiesRequest{VolumeId: id, VolumeCapabilities: []*csi.VolumeCapability{rwo}})
					return err
				},
			}
			for name, fn := range calls {
				if got := status.Code(fn()); got != codes.InvalidArgument {
					t.Errorf("%s code = %v, want InvalidArgument", name, got)
				}
			}
			entries, err := os.ReadDir(e.dir)
			if err != nil {
				t.Fatal(err)
			}
			if len(entries) != 0 {
				t.Fatalf("state dir was touched: %v", entries)
			}
		})
	}
}

func TestCreateVolume(t *testing.T) {
	tests := []struct {
		name      string
		setup     func(e *env)
		req       func() *csi.CreateVolumeRequest
		wantCode  codes.Code
		wantImage bool
	}{
		{
			name: "allocates the backing file and marks it unformatted",
			setup: func(e *env) {
				e.runner.expect(call{
					cmd:    "fallocate -l 2097152 " + e.v.temp,
					effect: func() { _ = os.Truncate(e.v.temp, 2*mib) },
				})
			},
			req:       func() *csi.CreateVolumeRequest { return createRequest(mib + 1) },
			wantImage: true,
		},
		{
			name: "removes a stale temporary file from an interrupted create",
			setup: func(e *env) {
				if err := os.WriteFile(e.v.temp, []byte("stale"), 0o600); err != nil {
					t.Fatal(err)
				}
				e.runner.expect(call{
					cmd:    "fallocate -l 1048576 " + e.v.temp,
					effect: func() { _ = os.Truncate(e.v.temp, mib) },
				})
			},
			req:       func() *csi.CreateVolumeRequest { return createRequest(mib) },
			wantImage: true,
		},
		{
			name:      "is idempotent for an existing volume of the same size",
			setup:     func(e *env) { e.writeImage(2 * mib) },
			req:       func() *csi.CreateVolumeRequest { return createRequest(2 * mib) },
			wantImage: true,
		},
		{
			name:      "rejects an existing volume of another size",
			setup:     func(e *env) { e.writeImage(4 * mib) },
			req:       func() *csi.CreateVolumeRequest { return createRequest(2 * mib) },
			wantCode:  codes.AlreadyExists,
			wantImage: true,
		},
		{
			name:     "keeps the node reserve free",
			setup:    func(e *env) { e.host.stats.AvailableBytes = 20<<30 + mib - 1 },
			req:      func() *csi.CreateVolumeRequest { return createRequest(mib) },
			wantCode: codes.ResourceExhausted,
		},
		{
			name:  "rejects a volume requested for another node",
			setup: func(*env) {},
			req: func() *csi.CreateVolumeRequest {
				r := createRequest(mib)
				r.AccessibilityRequirements = nodeTopology("node-b")
				return r
			},
			wantCode: codes.ResourceExhausted,
		},
		{
			name:  "rejects a request without topology",
			setup: func(*env) {},
			req: func() *csi.CreateVolumeRequest {
				r := createRequest(mib)
				r.AccessibilityRequirements = nil
				return r
			},
			wantCode: codes.ResourceExhausted,
		},
		{
			name:  "rejects block volumes",
			setup: func(*env) {},
			req: func() *csi.CreateVolumeRequest {
				r := createRequest(mib)
				r.VolumeCapabilities = []*csi.VolumeCapability{{
					AccessType: &csi.VolumeCapability_Block{Block: &csi.VolumeCapability_BlockVolume{}},
					AccessMode: rwo.AccessMode,
				}}
				return r
			},
			wantCode: codes.InvalidArgument,
		},
		{
			name:  "rejects multi-node access",
			setup: func(*env) {},
			req: func() *csi.CreateVolumeRequest {
				r := createRequest(mib)
				r.VolumeCapabilities = []*csi.VolumeCapability{mountCapability(csi.VolumeCapability_AccessMode_MULTI_NODE_MULTI_WRITER)}
				return r
			},
			wantCode: codes.InvalidArgument,
		},
		{
			name:  "rejects other filesystems",
			setup: func(*env) {},
			req: func() *csi.CreateVolumeRequest {
				r := createRequest(mib)
				c := mountCapability(csi.VolumeCapability_AccessMode_SINGLE_NODE_WRITER)
				c.GetMount().FsType = "ext4"
				r.VolumeCapabilities = []*csi.VolumeCapability{c}
				return r
			},
			wantCode: codes.InvalidArgument,
		},
		{
			name:  "rejects a capacity whose MiB rounding exceeds the limit",
			setup: func(*env) {},
			req: func() *csi.CreateVolumeRequest {
				r := createRequest(mib + 1)
				r.CapacityRange.LimitBytes = mib + 1
				return r
			},
			wantCode: codes.OutOfRange,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newEnv(t)
			tt.setup(e)
			resp, err := e.d.CreateVolume(context.Background(), tt.req())
			requireCode(t, err, tt.wantCode)
			if e.exists(e.v.image) != tt.wantImage {
				t.Fatalf("image exists = %v, want %v", e.exists(e.v.image), tt.wantImage)
			}
			if e.exists(e.v.temp) {
				t.Fatalf("temporary file left behind")
			}
			if err != nil {
				return
			}
			info, err := os.Stat(e.v.image)
			if err != nil {
				t.Fatal(err)
			}
			if info.Size() != resp.Volume.CapacityBytes {
				t.Fatalf("image size %d, capacity %d", info.Size(), resp.Volume.CapacityBytes)
			}
			if resp.Volume.VolumeId != testVolumeID || resp.Volume.AccessibleTopology[0].Segments[TopologyKey] != testNode {
				t.Fatalf("unexpected volume %v", resp.Volume)
			}
		})
	}
}

func TestCreateVolumeWritesPrivateFilesAndMarker(t *testing.T) {
	e := newEnv(t)
	e.runner.expect(call{cmd: "fallocate -l 1048576 " + e.v.temp, effect: func() { _ = os.Truncate(e.v.temp, mib) }})
	if _, err := e.d.CreateVolume(context.Background(), createRequest(mib)); err != nil {
		t.Fatal(err)
	}
	for _, path := range []string{e.v.image, e.v.marker} {
		info, err := os.Lstat(path)
		if err != nil {
			t.Fatal(err)
		}
		if info.Mode().Perm() != 0o600 || !info.Mode().IsRegular() {
			t.Fatalf("%s mode = %v", path, info.Mode())
		}
	}
}

func (e *env) stageRequest() *csi.NodeStageVolumeRequest {
	return &csi.NodeStageVolumeRequest{VolumeId: testVolumeID, StagingTargetPath: e.staging, VolumeCapability: rwo}
}

func (e *env) formatCalls(attach bool, luks bool) []call {
	loopCalls := []call{{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"}}
	if attach {
		loopCalls = []call{
			{cmd: "losetup --noheadings --output NAME -j " + e.v.image},
			{cmd: "losetup --find --show --direct-io=on " + e.v.image, out: testLoop + "\n"},
		}
	}
	isLuks := call{cmd: "cryptsetup isLuks --type luks2 " + testLoop}
	if !luks {
		isLuks.err = exitWith(1)
	}
	return append(loopCalls,
		call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
		isLuks,
	)
}

const luksFormatCmd = "cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --batch-mode --key-file=- " + testLoop

func (e *env) openCall() call {
	return call{cmd: "cryptsetup open --type luks2 --perf-no_read_workqueue --perf-no_write_workqueue --key-file=- " + testLoop + " kura-" + testVolumeID, stdin: testKey}
}

func (e *env) mkfsAndMountCalls(format bool) []call {
	mount := call{cmd: "mount -t xfs -o nodev,nosuid,noatime /dev/mapper/kura-" + testVolumeID + " " + e.staging}
	if !format {
		return []call{mount}
	}
	return []call{{cmd: "mkfs.xfs -q -K -f /dev/mapper/kura-" + testVolumeID}, mount}
}

func TestNodeStageKeyVersions(t *testing.T) {
	tests := []struct {
		name          string
		marker        bool
		storedVersion string
		luks          bool
		active        int
		wantRequested []int
		wantStored    string
		wantFormat    bool
	}{
		{
			name:          "first format asks for the active key and records it before luksFormat",
			marker:        true,
			active:        7,
			wantRequested: []int{0},
			wantStored:    "7",
			wantFormat:    true,
		},
		{
			name:          "resumes a format interrupted before luksFormat with the recorded version",
			marker:        true,
			storedVersion: "2",
			active:        7,
			wantRequested: []int{2},
			wantStored:    "2",
			wantFormat:    true,
		},
		{
			name:          "resumes a format interrupted after luksFormat with the recorded version",
			marker:        true,
			storedVersion: "2",
			luks:          true,
			active:        7,
			wantRequested: []int{2},
			wantStored:    "2",
			wantFormat:    true,
		},
		{
			name:          "reopens after a reboot with the recorded version",
			storedVersion: "4\n",
			luks:          true,
			active:        7,
			wantRequested: []int{4},
			wantStored:    "4\n",
		},
		{
			name:          "records the active version for a LUKS volume without a key version file",
			luks:          true,
			active:        3,
			wantRequested: []int{0},
			wantStored:    "3",
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newEnv(t)
			e.keys.active = tt.active
			e.writeImage(mib)
			if tt.marker {
				e.writeMarker()
			}
			if tt.storedVersion != "" {
				e.writeKeyVersion(tt.storedVersion)
			}
			e.runner.expect(e.formatCalls(true, tt.luks)...)
			if !tt.luks {
				e.runner.expect(call{cmd: luksFormatCmd, stdin: testKey, effect: func() {
					if got := e.keyVersionFile(); got != tt.wantStored {
						t.Errorf("key version file at luksFormat = %q, want %q", got, tt.wantStored)
					}
				}})
			}
			e.runner.expect(e.openCall())
			e.runner.expect(e.mkfsAndMountCalls(tt.wantFormat)...)

			if _, err := e.d.NodeStageVolume(context.Background(), e.stageRequest()); err != nil {
				t.Fatal(err)
			}
			if fmt.Sprint(e.keys.requested) != fmt.Sprint(tt.wantRequested) {
				t.Fatalf("requested key versions %v, want %v", e.keys.requested, tt.wantRequested)
			}
			if got := e.keyVersionFile(); got != tt.wantStored {
				t.Fatalf("key version file = %q, want %q", got, tt.wantStored)
			}
			if e.exists(e.v.marker) || e.exists(e.v.keyVersionTemp) {
				t.Fatal("marker or temporary key version file left behind")
			}
			e.keys.assertZeroed(t)
		})
	}
}

func TestNodeStageRefusesMalformedKeyVersion(t *testing.T) {
	for _, content := range []string{"", "0", "-1", "abc", "01", "1 ", "1\n\n", "9999999999"} {
		t.Run(fmt.Sprintf("%q", content), func(t *testing.T) {
			e := newEnv(t)
			e.writeImage(mib)
			e.writeKeyVersion(content)
			e.runner.expect(e.formatCalls(true, true)...)
			_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
			requireCode(t, err, codes.FailedPrecondition)
			if len(e.keys.requested) != 0 {
				t.Fatal("key fetched despite a malformed key version file")
			}
		})
	}
}

func TestNodeStageRefusesSymlinkedKeyVersion(t *testing.T) {
	e := newEnv(t)
	e.writeImage(mib)
	target := filepath.Join(e.dir, "elsewhere")
	if err := os.WriteFile(target, []byte("1"), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(target, e.v.keyVersion); err != nil {
		t.Fatal(err)
	}
	e.runner.expect(e.formatCalls(true, true)...)
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.FailedPrecondition)
}

func TestNodeStageFailsOnKeyVersionMismatch(t *testing.T) {
	e := newEnv(t)
	e.writeImage(mib)
	e.writeKeyVersion("2")
	e.keys.err = status.Error(codes.Internal, "key service returned key_version 3, requested 2")
	e.runner.expect(e.formatCalls(true, true)...)
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.Internal)
	if fmt.Sprint(e.keys.requested) != "[2]" {
		t.Fatalf("requested key versions %v", e.keys.requested)
	}
}

func TestNodeStageReusesOpenMapping(t *testing.T) {
	e := newEnv(t)
	e.writeImage(mib)
	e.runner.expect(
		call{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"},
		call{cmd: "cryptsetup status kura-" + testVolumeID, out: "/dev/mapper/kura-" + testVolumeID + " is active.\n  type:    LUKS2\n  device:  " + testLoop + "\n  loop:    " + e.v.image + "\n"},
		call{cmd: "mount -t xfs -o nodev,nosuid,noatime /dev/mapper/kura-" + testVolumeID + " " + e.staging},
	)
	if _, err := e.d.NodeStageVolume(context.Background(), e.stageRequest()); err != nil {
		t.Fatal(err)
	}
	if len(e.keys.issued) != 0 {
		t.Fatal("an open mapping needs no key")
	}
}

func TestNodeStageRejectsMappingOnAnotherDevice(t *testing.T) {
	e := newEnv(t)
	e.writeImage(mib)
	e.runner.expect(
		call{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"},
		call{cmd: "cryptsetup status kura-" + testVolumeID, out: "  device:  /dev/loop9\n"},
	)
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.FailedPrecondition)
}

func TestNodeStageIsIdempotentWhenMounted(t *testing.T) {
	tests := []struct {
		name  string
		mount Mount
	}{
		{"by mapper path", Mount{MajorMinor: "252:3", FSType: "xfs", Source: "/dev/mapper/kura-" + testVolumeID}},
		{"by device number", Mount{MajorMinor: "252:3", FSType: "xfs", Source: "/dev/dm-3"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newEnv(t)
			e.writeImage(mib)
			e.host.devices[e.v.mapperPath()] = "252:3"
			tt.mount.MountPoint = e.staging
			e.mounts.add(tt.mount)
			if _, err := e.d.NodeStageVolume(context.Background(), e.stageRequest()); err != nil {
				t.Fatal(err)
			}
			if len(e.keys.issued) != 0 {
				t.Fatal("key fetched for an already staged volume")
			}
		})
	}
}

func TestNodeStageRejectsForeignMount(t *testing.T) {
	e := newEnv(t)
	e.writeImage(mib)
	e.mounts.add(Mount{MajorMinor: "8:1", MountPoint: e.staging, FSType: "ext4", Source: "/dev/sda1"})
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.FailedPrecondition)
}

func TestNodeStageRefusesToFormatWithoutMarker(t *testing.T) {
	e := newEnv(t)
	e.writeImage(mib)
	e.runner.expect(
		call{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"},
		call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
		call{cmd: "cryptsetup isLuks --type luks2 " + testLoop, err: exitWith(1)},
	)
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.FailedPrecondition)
	if len(e.keys.issued) != 0 {
		t.Fatal("key fetched for a volume that cannot be opened")
	}
}

func TestNodeStageFailsOnUnexpectedLUKSProbeError(t *testing.T) {
	e := newEnv(t)
	e.writeImage(mib)
	e.writeMarker()
	e.runner.expect(
		call{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"},
		call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
		call{cmd: "cryptsetup isLuks --type luks2 " + testLoop, err: exitWith(4)},
	)
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.Internal)
}

func TestNodeStagePropagatesKeyErrors(t *testing.T) {
	e := newEnv(t)
	e.writeImage(mib)
	e.keys.err = status.Error(codes.PermissionDenied, "volume belongs to another node")
	e.runner.expect(
		call{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"},
		call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
		call{cmd: "cryptsetup isLuks --type luks2 " + testLoop},
	)
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.PermissionDenied)
}

func TestNodeStageMissingVolume(t *testing.T) {
	e := newEnv(t)
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.NotFound)
}

func TestNodeUnstage(t *testing.T) {
	tests := []struct {
		name  string
		setup func(e *env)
	}{
		{
			name: "tears down mount, mapping and loop",
			setup: func(e *env) {
				e.mounts.add(e.volumeMount(e.staging))
				e.runner.expect(
					call{cmd: "umount " + e.staging, effect: func() { e.mounts.remove(e.staging) }},
					call{cmd: "cryptsetup status kura-" + testVolumeID, out: "  device:  " + testLoop + "\n"},
					call{cmd: "cryptsetup close kura-" + testVolumeID},
					call{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"},
					call{cmd: "losetup -d " + testLoop},
				)
			},
		},
		{
			name: "is idempotent once torn down",
			setup: func(e *env) {
				e.runner.expect(
					call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
					call{cmd: "losetup --noheadings --output NAME -j " + e.v.image},
				)
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newEnv(t)
			e.writeImage(mib)
			tt.setup(e)
			if _, err := e.d.NodeUnstageVolume(context.Background(), &csi.NodeUnstageVolumeRequest{VolumeId: testVolumeID, StagingTargetPath: e.staging}); err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestNodePublish(t *testing.T) {
	tests := []struct {
		name     string
		readonly bool
		setup    func(e *env, target string)
		wantCode codes.Code
	}{
		{
			name: "bind mounts the staged volume",
			setup: func(e *env, target string) {
				e.mounts.add(e.volumeMount(e.staging))
				e.runner.expect(call{cmd: "mount -o bind,nodev,nosuid " + e.staging + " " + target})
			},
		},
		{
			name:     "honours readonly",
			readonly: true,
			setup: func(e *env, target string) {
				e.mounts.add(e.volumeMount(e.staging))
				e.runner.expect(call{cmd: "mount -o bind,nodev,nosuid,ro " + e.staging + " " + target})
			},
		},
		{
			name: "is idempotent when already published",
			setup: func(e *env, target string) {
				e.mounts.add(e.volumeMount(e.staging))
				e.mounts.add(e.volumeMount(target))
			},
		},
		{
			name:     "requires the volume to be staged",
			setup:    func(*env, string) {},
			wantCode: codes.FailedPrecondition,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newEnv(t)
			target := filepath.Join(e.dir, "pods", "volume", "mount")
			tt.setup(e, target)
			_, err := e.d.NodePublishVolume(context.Background(), &csi.NodePublishVolumeRequest{
				VolumeId: testVolumeID, StagingTargetPath: e.staging, TargetPath: target, VolumeCapability: rwo, Readonly: tt.readonly,
			})
			requireCode(t, err, tt.wantCode)
		})
	}
}

func TestNodeUnpublish(t *testing.T) {
	for _, mounted := range []bool{true, false} {
		t.Run(map[bool]string{true: "mounted", false: "not mounted"}[mounted], func(t *testing.T) {
			e := newEnv(t)
			target := filepath.Join(e.dir, "target")
			if err := os.Mkdir(target, 0o750); err != nil {
				t.Fatal(err)
			}
			if mounted {
				e.mounts.add(e.volumeMount(target))
				e.runner.expect(call{cmd: "umount " + target, effect: func() { e.mounts.remove(target) }})
			}
			if _, err := e.d.NodeUnpublishVolume(context.Background(), &csi.NodeUnpublishVolumeRequest{VolumeId: testVolumeID, TargetPath: target}); err != nil {
				t.Fatal(err)
			}
			if e.exists(target) {
				t.Fatal("target path not removed")
			}
		})
	}
}

func TestDeleteVolume(t *testing.T) {
	tests := []struct {
		name      string
		setup     func(e *env)
		wantCode  codes.Code
		wantImage bool
	}{
		{
			name: "erases the LUKS header before removing the volume",
			setup: func(e *env) {
				e.writeImage(mib)
				e.writeMarker()
				e.writeKeyVersion("1")
				if err := os.WriteFile(e.v.keyVersionTemp, []byte("2"), 0o600); err != nil {
					t.Fatal(err)
				}
				e.runner.expect(
					call{cmd: "losetup --noheadings --output NAME -j " + e.v.image},
					call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
					call{cmd: "cryptsetup isLuks --type luks2 " + e.v.image},
					call{cmd: "cryptsetup erase --batch-mode " + e.v.image},
				)
			},
		},
		{
			name: "skips cryptsetup erase for a never staged volume",
			setup: func(e *env) {
				e.writeImage(mib)
				e.writeMarker()
				e.runner.expect(
					call{cmd: "losetup --noheadings --output NAME -j " + e.v.image},
					call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
					call{cmd: "cryptsetup isLuks --type luks2 " + e.v.image, err: exitWith(1)},
				)
			},
		},
		{
			name: "refuses while a loop device is attached",
			setup: func(e *env) {
				e.writeImage(mib)
				e.runner.expect(call{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"})
			},
			wantCode:  codes.FailedPrecondition,
			wantImage: true,
		},
		{
			name: "refuses while the mapping is open",
			setup: func(e *env) {
				e.writeImage(mib)
				e.runner.expect(
					call{cmd: "losetup --noheadings --output NAME -j " + e.v.image},
					call{cmd: "cryptsetup status kura-" + testVolumeID, out: "  device:  " + testLoop + "\n"},
				)
			},
			wantCode:  codes.FailedPrecondition,
			wantImage: true,
		},
		{
			name:  "succeeds for a volume this node does not have",
			setup: func(*env) {},
		},
		{
			name: "cleans up leftovers of an interrupted create",
			setup: func(e *env) {
				e.writeMarker()
				if err := os.WriteFile(e.v.temp, nil, 0o600); err != nil {
					t.Fatal(err)
				}
			},
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newEnv(t)
			tt.setup(e)
			_, err := e.d.DeleteVolume(context.Background(), &csi.DeleteVolumeRequest{VolumeId: testVolumeID})
			requireCode(t, err, tt.wantCode)
			if e.exists(e.v.image) != tt.wantImage {
				t.Fatalf("image exists = %v, want %v", e.exists(e.v.image), tt.wantImage)
			}
			if err == nil {
				for _, path := range []string{e.v.marker, e.v.temp, e.v.keyVersion, e.v.keyVersionTemp, e.v.lock} {
					if e.exists(path) {
						t.Fatalf("%s left behind", path)
					}
				}
			}
		})
	}
}

func TestWipeHeader(t *testing.T) {
	tests := []struct {
		name string
		size int64
	}{
		{"larger than the header area", 40 * mib},
		{"smaller than the header area", 4096},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "volume.img")
			if err := os.WriteFile(path, bytes.Repeat([]byte{0xff}, int(tt.size)), 0o600); err != nil {
				t.Fatal(err)
			}
			if err := wipeHeader(path); err != nil {
				t.Fatal(err)
			}
			data, err := os.ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if int64(len(data)) != tt.size {
				t.Fatalf("size changed to %d", len(data))
			}
			wiped := min(tt.size, headerWipeBytes)
			if !bytes.Equal(data[:wiped], make([]byte, wiped)) {
				t.Fatal("header area not zeroed")
			}
			if !bytes.Equal(data[wiped:], bytes.Repeat([]byte{0xff}, int(tt.size-wiped))) {
				t.Fatal("data past the header area was modified")
			}
		})
	}
}

func TestNodeGetVolumeStats(t *testing.T) {
	e := newEnv(t)
	e.mounts.add(e.volumeMount("/target"))
	e.host.stats = FSStats{TotalBytes: 100, AvailableBytes: 60, UsedBytes: 40, TotalInodes: 10, AvailableInodes: 7, UsedInodes: 3}
	resp, err := e.d.NodeGetVolumeStats(context.Background(), &csi.NodeGetVolumeStatsRequest{VolumeId: testVolumeID, VolumePath: "/target"})
	if err != nil {
		t.Fatal(err)
	}
	if got := resp.Usage[0]; got.Unit != csi.VolumeUsage_BYTES || got.Total != 100 || got.Available != 60 || got.Used != 40 {
		t.Fatalf("bytes usage = %v", got)
	}
	if got := resp.Usage[1]; got.Unit != csi.VolumeUsage_INODES || got.Total != 10 || got.Available != 7 || got.Used != 3 {
		t.Fatalf("inode usage = %v", got)
	}

	_, err = e.d.NodeGetVolumeStats(context.Background(), &csi.NodeGetVolumeStatsRequest{VolumeId: testVolumeID, VolumePath: "/elsewhere"})
	requireCode(t, err, codes.NotFound)
}

func TestLockAbortsWhileAnotherOperationRuns(t *testing.T) {
	e := newEnv(t)
	unlock, err := e.d.lockVolume(context.Background(), e.v)
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	_, err = e.d.NodeUnstageVolume(ctx, &csi.NodeUnstageVolumeRequest{VolumeId: testVolumeID, StagingTargetPath: e.staging})
	requireCode(t, err, codes.Aborted)
}

func TestNodeGetInfoAdvertisesTopology(t *testing.T) {
	e := newEnv(t)
	resp, err := e.d.NodeGetInfo(context.Background(), &csi.NodeGetInfoRequest{})
	if err != nil {
		t.Fatal(err)
	}
	if resp.NodeId != testNode || resp.AccessibleTopology.Segments[TopologyKey] != testNode {
		t.Fatalf("unexpected node info %v", resp)
	}
}

func TestParseMountInfo(t *testing.T) {
	input := strings.Join([]string{
		"36 35 98:0 /mnt1 /mnt2 rw,noatime master:1 - ext3 /dev/root rw,errors=continue",
		`120 30 252:3 / /var/lib/kubelet/plugins/kubernetes.io/csi/kura-volumes.tuist.dev/abc/global\040mount rw,nosuid,nodev,noatime shared:80 - xfs /dev/mapper/kura-` + testVolumeID + " rw,attr2",
		"121 30 0:50 / /run rw - tmpfs tmpfs rw",
	}, "\n")
	mounts, err := ParseMountInfo(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	want := []Mount{
		{MajorMinor: "98:0", MountPoint: "/mnt2", FSType: "ext3", Source: "/dev/root"},
		{MajorMinor: "252:3", MountPoint: "/var/lib/kubelet/plugins/kubernetes.io/csi/kura-volumes.tuist.dev/abc/global mount", FSType: "xfs", Source: "/dev/mapper/kura-" + testVolumeID},
		{MajorMinor: "0:50", MountPoint: "/run", FSType: "tmpfs", Source: "tmpfs"},
	}
	if len(mounts) != len(want) {
		t.Fatalf("got %d mounts", len(mounts))
	}
	for i := range want {
		if mounts[i] != want[i] {
			t.Errorf("mount %d = %+v, want %+v", i, mounts[i], want[i])
		}
	}
	if _, err := ParseMountInfo(strings.NewReader("garbage line")); err == nil {
		t.Fatal("malformed line accepted")
	}
}
