package driver

import (
	"context"
	"path/filepath"
	"testing"
	"time"

	"github.com/container-storage-interface/spec/lib/go/csi"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// A stage waiting on the key service holds only its volume: pool-wide
// observation, admission and deletion of other volumes continue.
func TestStageWaitingOnKeysDoesNotHoldThePool(t *testing.T) {
	e := newEnv(t)
	e.d.thin.Pool = "tenants"
	e.writeImage(mib)
	e.keys.fetching, e.keys.release = make(chan struct{}), make(chan struct{})
	e.keys.err = status.Error(codes.Unavailable, "key service down")
	e.runner.expect(
		call{cmd: "losetup --noheadings --output NAME -j " + e.v.image, out: testLoop + "\n"},
		call{cmd: "cryptsetup status kura-" + testVolumeID, err: exitWith(4)},
		call{cmd: "cryptsetup isLuks --type luks2 " + testLoop},
	)
	staged := make(chan error, 1)
	go func() {
		_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
		staged <- err
	}()
	<-e.keys.fetching

	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	unlock, err := e.d.lockPool(ctx)
	if err != nil {
		close(e.keys.release)
		t.Fatalf("pool lock blocked by a stage waiting on keys: %v", err)
	}
	unlock()

	// The volume itself stays serialized.
	short, cancelShort := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancelShort()
	_, err = e.d.NodeUnstageVolume(short, &csi.NodeUnstageVolumeRequest{VolumeId: testVolumeID, StagingTargetPath: e.staging})
	requireCode(t, err, codes.Aborted)

	close(e.keys.release)
	requireCode(t, <-staged, codes.Unavailable)
}

// Pool administration (observation, grants, admission) must not stall node
// cleanup of unrelated volumes.
func TestNodeCallsDoNotWaitForThePool(t *testing.T) {
	e := newEnv(t)
	e.d.thin.Pool = "tenants"
	unlock, err := e.d.lockPool(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	target := filepath.Join(e.dir, "target")
	if _, err := e.d.NodeUnpublishVolume(ctx, &csi.NodeUnpublishVolumeRequest{VolumeId: testVolumeID, TargetPath: target}); err != nil {
		t.Fatalf("unpublish waited for the pool: %v", err)
	}
}

// Controller lifecycle keeps the documented pool-then-volume order.
func TestControllerCallsStillTakeThePool(t *testing.T) {
	e := newEnv(t)
	e.d.thin.Pool = "tenants"
	unlock, err := e.d.lockPool(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	defer unlock()
	ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
	defer cancel()
	_, err = e.d.DeleteVolume(ctx, &csi.DeleteVolumeRequest{VolumeId: testVolumeID})
	requireCode(t, err, codes.Aborted)
}

// A key-service outage during a volume's first stage leaves it exactly as
// created: no key version, no LUKS header, marker intact. The retry formats it.
func TestFirstStageSurvivesAKeyServiceOutage(t *testing.T) {
	e := newEnv(t)
	e.keys.active = 5
	e.writeImage(mib)
	e.writeMarker()
	e.keys.err = status.Error(codes.Unavailable, "key service down")
	e.runner.expect(e.formatCalls(true, false)...)
	_, err := e.d.NodeStageVolume(context.Background(), e.stageRequest())
	requireCode(t, err, codes.Unavailable)
	if e.exists(e.v.keyVersion) || !e.exists(e.v.marker) {
		t.Fatal("a failed key fetch changed the volume's format state")
	}

	e.keys.err = nil
	e.runner.expect(e.formatCalls(false, false)...)
	e.runner.expect(call{cmd: luksFormatCmd, stdin: testKey}, e.openCall())
	e.runner.expect(e.mkfsAndMountCalls(true)...)
	if _, err := e.d.NodeStageVolume(context.Background(), e.stageRequest()); err != nil {
		t.Fatal(err)
	}
	if got := e.keyVersionFile(); got != "5" {
		t.Fatalf("key version = %q, want 5", got)
	}
	e.keys.assertZeroed(t)
}
