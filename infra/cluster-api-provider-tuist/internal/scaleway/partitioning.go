package scaleway

import (
	"errors"
	"fmt"
	"strings"

	baremetal "github.com/scaleway/scaleway-sdk-go/api/baremetal/v1"
	"github.com/scaleway/scaleway-sdk-go/scw"
)

const (
	// DataMountPoint is the separate filesystem every Kura cache directory lives
	// on. The self-join binds the local-path StorageClass root and the kubelet
	// root onto it, so a cache PV is a directory on THIS filesystem rather than
	// on root.
	DataMountPoint = "/data"

	// rootPartitionBytes caps / so the rest of the disk can become /data. The
	// node keeps almost nothing on root: the self-join relocates containerd's
	// image store and bind-mounts the kubelet root onto /data, so this holds the
	// base OS and its logs.
	rootPartitionBytes = 64 * 1024 * 1024 * 1024

	// dataPartitionFloorBytes is the smallest /data worth installing. Below it
	// the box cannot hold a meaningful cache, and carving the partition anyway
	// would produce a node that joins and then wedges on ENOSPC instead of
	// failing where an operator can see it.
	dataPartitionFloorBytes = 64 * 1024 * 1024 * 1024
)

// PlanSchema turns an offer's default partitioning schema into one that carries
// a separate XFS /data, by taking space from the partition backing /.
//
// Why /data has to exist at install time: a Kura cache PV is a local-path
// DIRECTORY, and a directory has no size. Nothing in Kubernetes bounds what one
// account's instance writes, so one instance filling the box crosses kubelet's
// eviction line and takes down every tenant on it. XFS project quotas are the
// only real boundary, and they need an XFS filesystem mounted with prjquota that
// is not the root filesystem. Partitioning cannot change in place, so a box that
// comes up without /data cannot grow one without another wipe.
//
// It transforms the provider's own default rather than composing a layout from
// scratch: the default already encodes what this offer's disks are called, how
// many there are, and whether the OS is mirrored across them. Composing one
// blind would mean guessing all three. Callers should still put the result
// through ValidatePartitioningSchema, which checks it against the real offer
// without touching a box.
//
// A default that already mounts /data is left in place and only forced to XFS,
// the same minimal override the Dedibox path makes, since the shape is already
// right and only the filesystem stops it carrying quotas.
func PlanSchema(def *baremetal.Schema) (*baremetal.Schema, error) {
	if def == nil || len(def.Disks) == 0 || len(def.Filesystems) == 0 {
		return nil, errors.New("empty default partitioning schema: refusing to install without a separate /data")
	}
	if def.Zfs != nil && len(def.Zfs.Pools) > 0 {
		return nil, errors.New("default partitioning schema is ZFS-backed, which this planner does not model")
	}

	planned := cloneSchema(def)

	if fs := filesystemAt(planned, DataMountPoint); fs != nil {
		fs.Format = baremetal.SchemaFilesystemFormatXfs
		return planned, nil
	}

	root := filesystemAt(planned, "/")
	if root == nil {
		return nil, errors.New("default partitioning schema mounts no root filesystem")
	}

	// Root sits either directly on a partition or on a RAID array assembled from
	// one partition per disk. Either way the partitions backing it are the ones
	// with space to give, so both cases reduce to the same list.
	backing := []string{root.Device}
	rootRaid := raidNamed(planned, root.Device)
	if rootRaid != nil {
		backing = rootRaid.Devices
	}
	if len(backing) == 0 {
		return nil, fmt.Errorf("root device %q is backed by no partitions", root.Device)
	}

	added := make([]string, 0, len(backing))
	for _, device := range backing {
		disk, part := partitionNamed(planned, device)
		if disk == nil {
			return nil, fmt.Errorf("root is backed by %q, which is not a partition of any disk in the schema", device)
		}
		if uint64(part.Size) <= rootPartitionBytes+dataPartitionFloorBytes {
			return nil, fmt.Errorf("partition %s is %d bytes, too small to give /data a usable share after a %d byte root",
				device, part.Size, uint64(rootPartitionBytes))
		}

		dataSize := uint64(part.Size) - rootPartitionBytes
		part.Size = scw.Size(rootPartitionBytes)

		// A partition that will become a RAID member is labelled raid, not data:
		// the label describes what the partition holds, and what it holds is half
		// of an array. Only an unmirrored /data is labelled data directly.
		label := baremetal.SchemaPartitionLabelData
		if rootRaid != nil {
			label = baremetal.SchemaPartitionLabelRaid
		}
		number := nextPartitionNumber(disk)
		dataDevice, err := partitionDevice(disk, number, device)
		if err != nil {
			return nil, err
		}
		disk.Partitions = append(disk.Partitions, &baremetal.SchemaPartition{
			Label:  label,
			Number: number,
			Size:   scw.Size(dataSize),
		})
		added = append(added, dataDevice)
	}

	dataDevice := added[0]
	if rootRaid != nil {
		// Mirror /data the same way the default mirrors root. Anything else would
		// make a disk loss cost the cache but not the OS, or the reverse, for no
		// reason the hardware justifies.
		name, err := nextRaidName(planned)
		if err != nil {
			return nil, err
		}
		planned.Raids = append(planned.Raids, &baremetal.SchemaRAID{
			Name:    name,
			Level:   rootRaid.Level,
			Devices: added,
		})
		dataDevice = name
	}

	planned.Filesystems = append(planned.Filesystems, &baremetal.SchemaFilesystem{
		Device:     dataDevice,
		Format:     baremetal.SchemaFilesystemFormatXfs,
		Mountpoint: DataMountPoint,
	})
	return planned, nil
}

func filesystemAt(s *baremetal.Schema, mountpoint string) *baremetal.SchemaFilesystem {
	for _, fs := range s.Filesystems {
		if fs != nil && fs.Mountpoint == mountpoint {
			return fs
		}
	}
	return nil
}

func raidNamed(s *baremetal.Schema, name string) *baremetal.SchemaRAID {
	for _, raid := range s.Raids {
		if raid != nil && raid.Name == name {
			return raid
		}
	}
	return nil
}

// partitionNamed finds the disk and partition a device path refers to, matching
// on the naming the schema itself uses rather than on a reconstructed path.
func partitionNamed(s *baremetal.Schema, device string) (*baremetal.SchemaDisk, *baremetal.SchemaPartition) {
	for _, disk := range s.Disks {
		if disk == nil || !strings.HasPrefix(device, disk.Device) {
			continue
		}
		for _, part := range disk.Partitions {
			if part == nil {
				continue
			}
			if candidate, err := partitionDevice(disk, part.Number, device); err == nil && candidate == device {
				return disk, part
			}
		}
	}
	return nil, nil
}

// partitionDevice renders the device path for a partition number on a disk,
// deriving the separator from a path the schema already uses for that disk
// rather than guessing between the two conventions (`/dev/nvme0n1p3` and
// `/dev/sda3`). Guessing wrong produces a schema that names a device which does
// not exist, which the API would either reject or, worse, accept.
func partitionDevice(disk *baremetal.SchemaDisk, number uint32, example string) (string, error) {
	if !strings.HasPrefix(example, disk.Device) {
		return "", fmt.Errorf("device %q is not a partition of disk %q", example, disk.Device)
	}
	suffix := strings.TrimPrefix(example, disk.Device)
	separator := strings.TrimRight(suffix, "0123456789")
	if separator == suffix {
		return "", fmt.Errorf("device %q does not end in a partition number", example)
	}
	return fmt.Sprintf("%s%s%d", disk.Device, separator, number), nil
}

func nextPartitionNumber(disk *baremetal.SchemaDisk) uint32 {
	var highest uint32
	for _, part := range disk.Partitions {
		if part != nil && part.Number > highest {
			highest = part.Number
		}
	}
	return highest + 1
}

// nextRaidName picks an unused array name in the same series the default uses,
// so a schema whose arrays are /dev/md0 and /dev/md1 gets /dev/md2 rather than a
// name from a different convention.
func nextRaidName(s *baremetal.Schema) (string, error) {
	if len(s.Raids) == 0 || s.Raids[0] == nil {
		return "", errors.New("cannot derive a RAID name from a schema with no arrays")
	}
	prefix := strings.TrimRight(s.Raids[0].Name, "0123456789")
	if prefix == s.Raids[0].Name {
		return "", fmt.Errorf("RAID name %q does not end in a number", s.Raids[0].Name)
	}
	for suffix := 0; suffix < len(s.Raids)+1; suffix++ {
		candidate := fmt.Sprintf("%s%d", prefix, suffix)
		if raidNamed(s, candidate) == nil {
			return candidate, nil
		}
	}
	return "", errors.New("no free RAID name")
}

// cloneSchema deep-copies the parts PlanSchema mutates, so a caller that keeps
// the default around (to log it, or to compare) still holds the provider's
// answer rather than a half-edited copy of it.
func cloneSchema(s *baremetal.Schema) *baremetal.Schema {
	out := &baremetal.Schema{Zfs: s.Zfs}
	for _, disk := range s.Disks {
		if disk == nil {
			continue
		}
		clone := &baremetal.SchemaDisk{Device: disk.Device}
		for _, part := range disk.Partitions {
			if part == nil {
				continue
			}
			copied := *part
			clone.Partitions = append(clone.Partitions, &copied)
		}
		out.Disks = append(out.Disks, clone)
	}
	for _, raid := range s.Raids {
		if raid == nil {
			continue
		}
		copied := *raid
		copied.Devices = append([]string(nil), raid.Devices...)
		out.Raids = append(out.Raids, &copied)
	}
	for _, fs := range s.Filesystems {
		if fs == nil {
			continue
		}
		copied := *fs
		out.Filesystems = append(out.Filesystems, &copied)
	}
	return out
}
