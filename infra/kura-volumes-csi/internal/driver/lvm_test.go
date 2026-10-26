package driver

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strconv"
	"testing"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
)

const testVolumeGroup = "kuravg"

// newLVMEnv is an env whose driver has a volume group, with its device links
// under a temporary directory instead of /dev.
func newLVMEnv(t *testing.T) *env {
	t.Helper()
	e := newEnv(t, func(c *Config) { c.VolumeGroup = testVolumeGroup })
	e.d.devDir = filepath.Join(e.dir, "dev")
	if err := os.MkdirAll(filepath.Join(e.d.devDir, testVolumeGroup), 0o755); err != nil {
		t.Fatal(err)
	}
	return e
}

func (e *env) lvPath() string { return e.d.lvPath(e.v) }

func lvmCmd(command, args string) string {
	return command + " --config " + lvmConfig + " " + args
}

func (e *env) lvsCall(size int64) call {
	c := call{cmd: lvmCmd("lvs", "--noheadings --nosuffix --units b -o lv_size "+testVolumeGroup+"/"+testVolumeID)}
	if size < 0 {
		c.err = exitWith(lvmNotFound)
	} else {
		c.out = "  " + strconv.FormatInt(size, 10) + "\n"
	}
	return c
}

func vgsCall(free int64) call {
	c := call{cmd: lvmCmd("vgs", "--noheadings --nosuffix --units b -o vg_free "+testVolumeGroup)}
	if free < 0 {
		c.err = exitWith(lvmNotFound)
	} else {
		c.out = "  " + strconv.FormatInt(free, 10) + "\n"
	}
	return c
}

func (e *env) activateCalls() []call {
	lv := testVolumeGroup + "/" + testVolumeID
	return []call{
		{cmd: lvmCmd("lvchange", "--activate y "+lv)},
		{cmd: lvmCmd("vgmknodes", lv)},
	}
}

func TestCreateVolumeOnVolumeGroup(t *testing.T) {
	tests := []struct {
		name       string
		setup      func(e *env)
		required   int64
		wantCode   codes.Code
		wantMarker bool
	}{
		{
			name: "creates a logical volume after marking it unformatted",
			setup: func(e *env) {
				e.runner.expect(
					e.lvsCall(-1),
					vgsCall(1<<30),
					call{
						cmd: lvmCmd("lvcreate", "--yes --wipesignatures y --zero y --size 2097152b --name "+testVolumeID+" "+testVolumeGroup),
						effect: func() {
							if !e.exists(e.v.marker) {
								t.Error("lvcreate ran before the unformatted marker was written")
							}
						},
					},
				)
			},
			required:   mib + 1,
			wantMarker: true,
		},
		{
			name:     "is idempotent for an existing logical volume rounded up to whole extents",
			setup:    func(e *env) { e.runner.expect(e.lvsCall(4 * mib)) },
			required: 2 * mib,
		},
		{
			name:     "rejects an existing logical volume smaller than requested",
			setup:    func(e *env) { e.runner.expect(e.lvsCall(mib)) },
			required: 2 * mib,
			wantCode: codes.AlreadyExists,
		},
		{
			name:     "fails when the volume group has no room",
			setup:    func(e *env) { e.runner.expect(e.lvsCall(-1), vgsCall(mib)) },
			required: 2 * mib,
			wantCode: codes.ResourceExhausted,
		},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newLVMEnv(t)
			tt.setup(e)
			_, err := e.d.CreateVolume(context.Background(), createRequest(tt.required))
			requireCode(t, err, tt.wantCode)
			if got := e.exists(e.v.marker); got != tt.wantMarker {
				t.Errorf("marker exists = %v, want %v", got, tt.wantMarker)
			}
			if e.exists(e.v.image) {
				t.Error("a backing file was created on a node with a volume group")
			}
		})
	}
}

func TestCreateVolumeKeepsBackingFilesWithoutTheVolumeGroup(t *testing.T) {
	e := newLVMEnv(t)
	e.runner.expect(
		e.lvsCall(-1),
		vgsCall(-1),
		call{cmd: "fallocate -l 1048576 " + e.v.temp, effect: func() { _ = os.Truncate(e.v.temp, mib) }},
	)
	_, err := e.d.CreateVolume(context.Background(), createRequest(mib))
	requireCode(t, err, codes.OK)
	if !e.exists(e.v.image) {
		t.Fatal("backing file was not created")
	}
}

func TestNodeStageFormatsLogicalVolume(t *testing.T) {
	e := newLVMEnv(t)
	e.keys.active = 3
	e.writeMarker()
	device := e.lvPath()
	e.runner.expect(e.lvsCall(2 * mib))
	e.runner.expect(e.activateCalls()...)
	e.runner.expect(
		call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
		call{cmd: "cryptsetup isLuks --type luks2 " + device, err: exitWith(1)},
		call{cmd: "cryptsetup luksFormat --type luks2 --cipher aes-xts-plain64 --key-size 512 --pbkdf pbkdf2 --pbkdf-force-iterations 1000 --batch-mode --key-file=- " + device, stdin: testKey},
		call{cmd: "cryptsetup open --type luks2 --key-file=- " + device + " kura-" + testVolumeID, stdin: testKey},
	)
	e.runner.expect(e.mkfsAndMountCalls(true)...)

	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.OK)
	if e.exists(e.v.marker) {
		t.Error("unformatted marker survived the format")
	}
	if got := e.keyVersionFile(); got != "3" {
		t.Errorf("key version = %q, want 3", got)
	}
	e.keys.assertZeroed(t)
}

func TestNodeStageReusesMappingOnLogicalVolume(t *testing.T) {
	e := newLVMEnv(t)
	e.writeKeyVersion("1")
	// cryptsetup names the backing device by its /dev/mapper node.
	e.host.devices[e.lvPath()] = "252:9"
	e.host.devices["/dev/mapper/kuravg-pvc--0b5a7f7e"] = "252:9"
	e.runner.expect(e.lvsCall(2 * mib))
	e.runner.expect(e.activateCalls()...)
	e.runner.expect(call{cmd: "cryptsetup status kura-" + testVolumeID, out: "  device:  /dev/mapper/kuravg-pvc--0b5a7f7e\n"})
	e.runner.expect(e.mkfsAndMountCalls(false)...)

	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.OK)
	if len(e.keys.requested) != 0 {
		t.Errorf("fetched a key for an already open mapping")
	}
}

func TestDeleteVolumeRemovesLogicalVolume(t *testing.T) {
	e := newLVMEnv(t)
	e.writeKeyVersion("1")
	device := e.lvPath()
	header := bytes.Repeat([]byte{0xab}, int(2*mib))
	if err := os.WriteFile(device, header, 0o600); err != nil {
		t.Fatal(err)
	}
	e.runner.expect(
		e.lvsCall(2*mib),
		call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
	)
	e.runner.expect(e.activateCalls()...)
	e.runner.expect(
		call{cmd: "cryptsetup isLuks --type luks2 " + device},
		call{cmd: "cryptsetup erase --batch-mode " + device},
		call{cmd: lvmCmd("lvremove", "--yes "+testVolumeGroup+"/"+testVolumeID), effect: func() {
			data, err := os.ReadFile(device)
			if err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(data, make([]byte, len(data))) {
				t.Error("lvremove ran before the volume header was zeroed")
			}
		}},
	)

	_, err := e.d.DeleteVolume(context.Background(), &csi.DeleteVolumeRequest{VolumeId: testVolumeID})
	requireCode(t, err, codes.OK)
	if e.exists(e.v.keyVersion) || e.exists(e.v.lock) {
		t.Error("volume state files survived the delete")
	}
}

func TestDeleteVolumeRefusesOpenLogicalVolume(t *testing.T) {
	e := newLVMEnv(t)
	e.runner.expect(
		e.lvsCall(2*mib),
		call{cmd: "cryptsetup status kura-" + testVolumeID, out: "  device:  " + e.lvPath() + "\n"},
	)
	_, err := e.d.DeleteVolume(context.Background(), &csi.DeleteVolumeRequest{VolumeId: testVolumeID})
	requireCode(t, err, codes.FailedPrecondition)
}

func TestNewRejectsInvalidVolumeGroup(t *testing.T) {
	e := newEnv(t)
	for _, name := range []string{"-vg", "vg/sub", "vg name"} {
		cfg := Config{NodeID: testNode, StateDir: e.dir, VolumeGroup: name, Keys: e.keys, Runner: e.runner, Mounts: e.mounts, Host: e.host}
		if _, err := New(cfg); err == nil {
			t.Errorf("New accepted volume group %q", name)
		}
	}
}

func plainCreateRequest(required int64) *csi.CreateVolumeRequest {
	r := createRequest(required)
	r.Parameters = map[string]string{encryptionParameter: encryptionNone}
	return r
}

func (e *env) plainStageRequest() *csi.NodeStageVolumeRequest {
	r := e.stageRequest()
	r.VolumeContext = map[string]string{encryptionParameter: encryptionNone}
	return r
}

func TestCreatePlainVolume(t *testing.T) {
	e := newLVMEnv(t)
	e.runner.expect(
		e.lvsCall(-1),
		vgsCall(1<<30),
		call{cmd: lvmCmd("lvcreate", "--yes --wipesignatures y --zero y --size 1048576b --name "+testVolumeID+" "+testVolumeGroup)},
	)
	resp, err := e.d.CreateVolume(context.Background(), plainCreateRequest(mib))
	requireCode(t, err, codes.OK)
	if got := resp.GetVolume().GetVolumeContext()[encryptionParameter]; got != encryptionNone {
		t.Errorf("volume context encryption = %q, want %q", got, encryptionNone)
	}
}

func TestCreatePlainVolumeNeedsTheVolumeGroup(t *testing.T) {
	e := newLVMEnv(t)
	e.runner.expect(e.lvsCall(-1), vgsCall(-1))
	_, err := e.d.CreateVolume(context.Background(), plainCreateRequest(mib))
	requireCode(t, err, codes.ResourceExhausted)
	if e.exists(e.v.image) || e.exists(e.v.temp) {
		t.Error("a backing file was created for an unencrypted volume")
	}
}

func TestCreateVolumeRejectsUnknownEncryption(t *testing.T) {
	e := newLVMEnv(t)
	r := createRequest(mib)
	r.Parameters = map[string]string{encryptionParameter: "aes"}
	_, err := e.d.CreateVolume(context.Background(), r)
	requireCode(t, err, codes.InvalidArgument)
}

func TestCreateEncryptedVolumeReportsItsEncryption(t *testing.T) {
	e := newLVMEnv(t)
	e.runner.expect(e.lvsCall(2 * mib))
	resp, err := e.d.CreateVolume(context.Background(), createRequest(mib))
	requireCode(t, err, codes.OK)
	if got := resp.GetVolume().GetVolumeContext()[encryptionParameter]; got != encryptionLUKS2 {
		t.Errorf("volume context encryption = %q, want %q", got, encryptionLUKS2)
	}
}

func TestNodeStagePlainVolume(t *testing.T) {
	tests := []struct {
		name     string
		marker   bool
		luks     bool
		wantCode codes.Code
		wantMkfs bool
	}{
		{name: "formats a new volume without a key", marker: true, wantMkfs: true},
		{name: "mounts a formatted volume without a key"},
		{name: "refuses a LUKS volume", luks: true, wantCode: codes.FailedPrecondition},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			e := newLVMEnv(t)
			device := e.lvPath()
			if tt.marker {
				e.writeMarker()
			}
			e.runner.expect(e.lvsCall(2 * mib))
			e.runner.expect(e.activateCalls()...)
			if tt.wantMkfs {
				e.runner.expect(call{cmd: "mkfs.xfs -q -K -f " + device})
			} else {
				isLuks := call{cmd: "cryptsetup isLuks --type luks2 " + device}
				if !tt.luks {
					isLuks.err = exitWith(1)
				}
				e.runner.expect(isLuks)
			}
			if tt.wantCode == codes.OK {
				e.runner.expect(call{cmd: "mount -t xfs -o nodev,nosuid,noatime " + device + " " + e.staging})
			}
			_, err := e.d.NodeStageVolume(context.Background(), e.plainStageRequest())
			requireCode(t, err, tt.wantCode)
			if len(e.keys.requested) != 0 {
				t.Errorf("fetched a key for an unencrypted volume")
			}
			if tt.marker && e.exists(e.v.marker) {
				t.Error("unformatted marker survived the format")
			}
		})
	}
}

func TestNodeStagePlainVolumeRefusesABackingFile(t *testing.T) {
	e := newLVMEnv(t)
	e.writeImage(mib)
	e.runner.expect(e.lvsCall(-1))
	_, err := e.d.NodeStageVolume(context.Background(), e.plainStageRequest())
	requireCode(t, err, codes.FailedPrecondition)
}

func TestNodePublishRecognisesAPlainVolumeStaging(t *testing.T) {
	e := newLVMEnv(t)
	e.host.devices[e.lvPath()] = "252:9"
	e.mounts.add(Mount{MajorMinor: "252:9", MountPoint: e.staging, FSType: "xfs", Source: "/dev/mapper/kuravg-pvc--0b5a7f7e"})
	target := filepath.Join(e.dir, "target")
	e.runner.expect(call{cmd: "mount -o bind,nodev,nosuid " + e.staging + " " + target})
	_, err := e.d.NodePublishVolume(context.Background(), &csi.NodePublishVolumeRequest{
		VolumeId: testVolumeID, StagingTargetPath: e.staging, TargetPath: target, VolumeCapability: rwo,
	})
	requireCode(t, err, codes.OK)
}

func TestKuraDiskCapacityExcludesOtherVolumes(t *testing.T) {
	e := newLVMEnv(t)
	e.runner.expect(
		call{cmd: lvmCmd("vgs", "--noheadings --nosuffix --units b -o vg_size "+testVolumeGroup), out: "  1000000\n"},
		call{cmd: lvmCmd("lvs", "--noheadings --nosuffix --units b --separator , -o lv_name,lv_size "+testVolumeGroup),
			out: "  data,300000\n  " + testVolumeID + ",200000\n"},
	)
	capacity, ok, err := e.d.KuraDiskCapacity(context.Background())
	if err != nil || !ok {
		t.Fatalf("ok = %v, err = %v", ok, err)
	}
	// Kura's own volumes stay counted: they are what the room is for.
	if capacity != 700000 {
		t.Errorf("capacity = %d, want 700000", capacity)
	}
}

func TestKuraDiskCapacityWithoutTheVolumeGroup(t *testing.T) {
	e := newLVMEnv(t)
	e.runner.expect(call{cmd: lvmCmd("vgs", "--noheadings --nosuffix --units b -o vg_size "+testVolumeGroup), err: exitWith(lvmNotFound)})
	if _, ok, err := e.d.KuraDiskCapacity(context.Background()); ok || err != nil {
		t.Fatalf("ok = %v, err = %v; want false, nil", ok, err)
	}
}
