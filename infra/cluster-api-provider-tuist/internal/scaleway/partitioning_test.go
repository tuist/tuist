package scaleway

import (
	"testing"

	baremetal "github.com/scaleway/scaleway-sdk-go/api/baremetal/v1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

const terabyte = 1024 * 1024 * 1024 * 1024

// mirroredDefaultSchema is the shape the cache offer reports: two NVMe disks,
// each with an EFI partition and a RAID member, root mirrored across them.
func mirroredDefaultSchema() *baremetal.Schema {
	disk := func(device string) *baremetal.SchemaDisk {
		return &baremetal.SchemaDisk{
			Device: device,
			Partitions: []*baremetal.SchemaPartition{
				{Label: baremetal.SchemaPartitionLabelUefi, Number: 1, Size: scw.Size(512 * 1024 * 1024)},
				{Label: baremetal.SchemaPartitionLabelRaid, Number: 2, Size: scw.Size(2 * terabyte)},
			},
		}
	}
	return &baremetal.Schema{
		Disks: []*baremetal.SchemaDisk{disk("/dev/nvme0n1"), disk("/dev/nvme1n1")},
		Raids: []*baremetal.SchemaRAID{{
			Name:    "/dev/md0",
			Level:   baremetal.SchemaRAIDLevelRaidLevel1,
			Devices: []string{"/dev/nvme0n1p2", "/dev/nvme1n1p2"},
		}},
		Filesystems: []*baremetal.SchemaFilesystem{
			{Device: "/dev/nvme0n1p1", Format: baremetal.SchemaFilesystemFormatFat32, Mountpoint: "/boot/efi"},
			{Device: "/dev/md0", Format: baremetal.SchemaFilesystemFormatExt4, Mountpoint: "/"},
		},
	}
}

// singleDiskDefaultSchema is the unmirrored shape: one disk, root straight on a
// partition with no array in the way.
func singleDiskDefaultSchema() *baremetal.Schema {
	return &baremetal.Schema{
		Disks: []*baremetal.SchemaDisk{{
			Device: "/dev/sda",
			Partitions: []*baremetal.SchemaPartition{
				{Label: baremetal.SchemaPartitionLabelUefi, Number: 1, Size: scw.Size(512 * 1024 * 1024)},
				{Label: baremetal.SchemaPartitionLabelRoot, Number: 2, Size: scw.Size(2 * terabyte)},
			},
		}},
		Filesystems: []*baremetal.SchemaFilesystem{
			{Device: "/dev/sda1", Format: baremetal.SchemaFilesystemFormatFat32, Mountpoint: "/boot/efi"},
			{Device: "/dev/sda2", Format: baremetal.SchemaFilesystemFormatExt4, Mountpoint: "/"},
		},
	}
}

// The mirrored shape: /data must come out of root's space, be XFS, and be
// mirrored the same way root is. Anything else makes a disk loss cost the cache
// but not the OS, or the reverse.
func TestPlanSchemaCarvesAMirroredXFSData(t *testing.T) {
	planned, err := PlanSchema(mirroredDefaultSchema())
	if err != nil {
		t.Fatalf("PlanSchema: %v", err)
	}

	data := filesystemAt(planned, DataMountPoint)
	if data == nil {
		t.Fatalf("no /data filesystem planned: %+v", planned.Filesystems)
	}
	if data.Format != baremetal.SchemaFilesystemFormatXfs {
		t.Fatalf("/data format = %q, want xfs (project quotas are the only per-account boundary)", data.Format)
	}

	raid := raidNamed(planned, data.Device)
	if raid == nil {
		t.Fatalf("/data device %q is not a RAID array; root is mirrored so /data must be too", data.Device)
	}
	if raid.Level != baremetal.SchemaRAIDLevelRaidLevel1 {
		t.Fatalf("/data raid level = %q, want the same mirror root uses", raid.Level)
	}
	if raid.Name == "/dev/md0" {
		t.Fatal("/data reused the root array name")
	}
	if len(raid.Devices) != 2 {
		t.Fatalf("/data array spans %d devices, want one per disk: %+v", len(raid.Devices), raid.Devices)
	}

	// The new members have to be real partitions of the disks, named the way the
	// schema already names partitions on them.
	for _, device := range raid.Devices {
		disk, part := partitionNamed(planned, device)
		if disk == nil {
			t.Fatalf("array member %q is not a partition of any disk in the schema", device)
		}
		if part.Label != baremetal.SchemaPartitionLabelRaid {
			t.Fatalf("array member %q label = %q, want raid", device, part.Label)
		}
	}

	// Root gives up the space rather than the schema inventing it.
	_, rootPart := partitionNamed(planned, "/dev/nvme0n1p2")
	if uint64(rootPart.Size) != rootPartitionBytes {
		t.Fatalf("root partition = %d bytes, want it capped at %d", rootPart.Size, uint64(rootPartitionBytes))
	}
	_, dataPart := partitionNamed(planned, raid.Devices[0])
	if want := uint64(2*terabyte) - rootPartitionBytes; uint64(dataPart.Size) != want {
		t.Fatalf("/data partition = %d bytes, want the %d root left over", dataPart.Size, want)
	}
}

// The unmirrored shape has no array to copy, so /data goes straight onto its own
// partition rather than growing a single-member array around it.
func TestPlanSchemaHandlesASingleDisk(t *testing.T) {
	planned, err := PlanSchema(singleDiskDefaultSchema())
	if err != nil {
		t.Fatalf("PlanSchema: %v", err)
	}
	data := filesystemAt(planned, DataMountPoint)
	if data == nil || data.Format != baremetal.SchemaFilesystemFormatXfs {
		t.Fatalf("/data = %+v, want an xfs filesystem", data)
	}
	if len(planned.Raids) != 0 {
		t.Fatalf("planned %d arrays for a single-disk box: %+v", len(planned.Raids), planned.Raids)
	}
	disk, part := partitionNamed(planned, data.Device)
	if disk == nil {
		t.Fatalf("/data device %q is not a partition of the disk", data.Device)
	}
	if part.Label != baremetal.SchemaPartitionLabelData {
		t.Fatalf("/data partition label = %q, want data", part.Label)
	}
}

// A default that already mounts /data only needs its filesystem forced, the same
// minimal override the Dedibox path makes. Re-carving it would take space from a
// root that has already given some up.
func TestPlanSchemaOnlyReformatsAnExistingData(t *testing.T) {
	def := singleDiskDefaultSchema()
	def.Disks[0].Partitions = append(def.Disks[0].Partitions,
		&baremetal.SchemaPartition{Label: baremetal.SchemaPartitionLabelData, Number: 3, Size: scw.Size(terabyte)})
	def.Filesystems = append(def.Filesystems,
		&baremetal.SchemaFilesystem{Device: "/dev/sda3", Format: baremetal.SchemaFilesystemFormatExt4, Mountpoint: DataMountPoint})

	planned, err := PlanSchema(def)
	if err != nil {
		t.Fatalf("PlanSchema: %v", err)
	}
	if got := filesystemAt(planned, DataMountPoint); got.Format != baremetal.SchemaFilesystemFormatXfs {
		t.Fatalf("/data format = %q, want xfs", got.Format)
	}
	if _, rootPart := partitionNamed(planned, "/dev/sda2"); uint64(rootPart.Size) != uint64(2*terabyte) {
		t.Fatalf("root partition = %d bytes, want it untouched", rootPart.Size)
	}
}

// Planning must not mutate the provider's answer, so a caller that logs or
// compares against the default still holds what the API actually returned.
func TestPlanSchemaLeavesTheDefaultAlone(t *testing.T) {
	def := mirroredDefaultSchema()
	if _, err := PlanSchema(def); err != nil {
		t.Fatalf("PlanSchema: %v", err)
	}
	if got := len(def.Disks[0].Partitions); got != 2 {
		t.Fatalf("default disk grew to %d partitions; planning mutated its input", got)
	}
	if got := len(def.Filesystems); got != 2 {
		t.Fatalf("default grew to %d filesystems; planning mutated its input", got)
	}
}

// Refusing beats installing a layout that cannot carry quotas: a box that comes
// up without a usable /data needs another wipe to get one.
func TestPlanSchemaRefusesUnusableDefaults(t *testing.T) {
	if _, err := PlanSchema(nil); err == nil {
		t.Fatal("expected an error for a nil schema")
	}
	if _, err := PlanSchema(&baremetal.Schema{}); err == nil {
		t.Fatal("expected an error for an empty schema")
	}

	noRoot := singleDiskDefaultSchema()
	noRoot.Filesystems = noRoot.Filesystems[:1]
	if _, err := PlanSchema(noRoot); err == nil {
		t.Fatal("expected an error when nothing mounts root")
	}

	// A disk with no room for a meaningful cache after the root cap.
	tiny := singleDiskDefaultSchema()
	tiny.Disks[0].Partitions[1].Size = scw.Size(rootPartitionBytes + 1)
	if _, err := PlanSchema(tiny); err == nil {
		t.Fatal("expected an error when the disk cannot give /data a usable share")
	}
}

// Partition device naming differs between NVMe and SCSI, and a wrong guess names
// a device that does not exist. It is derived from what the schema already uses
// rather than assumed.
func TestPartitionDeviceFollowsTheSchemasOwnNaming(t *testing.T) {
	nvme := &baremetal.SchemaDisk{Device: "/dev/nvme0n1"}
	if got, err := partitionDevice(nvme, 3, "/dev/nvme0n1p2"); err != nil || got != "/dev/nvme0n1p3" {
		t.Fatalf("partitionDevice(nvme) = %q, %v; want /dev/nvme0n1p3", got, err)
	}
	scsi := &baremetal.SchemaDisk{Device: "/dev/sda"}
	if got, err := partitionDevice(scsi, 3, "/dev/sda2"); err != nil || got != "/dev/sda3" {
		t.Fatalf("partitionDevice(scsi) = %q, %v; want /dev/sda3", got, err)
	}
	if _, err := partitionDevice(scsi, 3, "/dev/sda"); err == nil {
		t.Fatal("expected an error for an example that names no partition")
	}
}
