package linux

import "fmt"

// By default a Kata Pod's container rootfs is an overlayfs snapshot on the host
// that virtiofsd shares into the guest, so every open and stat of the compiler,
// its headers and the libraries it loads is a FUSE round trip to the host. On a
// 4 vCPU staging VM a Redis `make -j5` took 35.4 s that way and 24.8 s when the
// rootfs was a devmapper thin device the guest mounts as ext4 over virtio-blk,
// which is the 22.6 to 23.8 s other providers reach on the same CPUs. Warm reads
// of the toolchain's headers went from about 0.25 s to 0.05 s.
//
// KataBlockRootfs points the kata-qemu handler, and only it, at containerd's
// devmapper snapshotter: runc Pods on the same box keep overlayfs. The thin pool
// sits on two preallocated loop files under /data, so it needs no partition of
// its own and the host cannot overcommit /data under it. A fresh join sets it up
// here; a box that joined without it is converted in place on the Ready path,
// drained first because containerd must restart to load the snapshotter
// (kata_block_rootfs_inplace.go).
//
// The kubelet pulls a runner image into overlayfs unless the Pod carries the
// io.containerd.cri.runtime-handler annotation; containerd then unpacks it into
// devmapper when it first creates a container from it on that box
// (internal/cri/opts.WithNewSnapshot in containerd 2.2), so both work, the
// annotation only saves the second copy and the first start's unpack.
const (
	kataDevmapperDir          = "/data/kata-devmapper"
	kataDevmapperPool         = "tuist-kata-pool"
	kataDevmapperScript       = "/usr/local/sbin/tuist-kata-devmapper"
	kataDevmapperUnitPath     = "/etc/systemd/system/tuist-kata-devmapper.service"
	kataBlockRootfsDropInPath = "/opt/kata/share/defaults/kata-containers/config.d/50-tuist-block-rootfs.toml"
)

// Kata's stock qemu configuration (3.30 and 4.4) sets disable_block_device_use = true,
// which makes the shim share even a block-backed rootfs over virtiofs, and
// block_device_driver = "virtio-scsi". virtio-blk is what the staging
// measurements used.
//
// The cache lines change what the guest's flushes cost. By default QEMU opens
// the thin device through the host page cache and turns every guest flush into
// an fsync of it, which ends at /data's md RAID1 and takes 5 to 16 ms: the
// runner's apt-get install took 13.3 s to unpack and configure, against about
// 1 s over virtiofs, which never passed flushes down, and fsync ran at 33 to 59
// iops. noflush drops the guest's flushes and direct opens the device with
// O_DIRECT, so writes skip a second copy in the host page cache: apt took
// 1.2 s, fsync ran at 6k to 11k iops and sequential writes went from about
// 0.9 GB/s to 2.6 to 4.9 GB/s. A host crash can lose writes the guest thought
// were durable, which only matters to a container that outlives the box, and
// none does: the rootfs is gone with the job.
const kataBlockRootfsDropIn = `[hypervisor.qemu]
disable_block_device_use = false
block_device_driver = "virtio-blk"
block_device_cache_set = true
block_device_cache_direct = true
block_device_cache_noflush = true
`

// The pool takes a quarter of /data's free space at first boot, at most 400
// GiB, and refuses to come up with less than 60 GiB: the 2 GiB runner image
// alone used about 6 GiB of the pool once unpacked. It has to leave room for
// the runner cache volume, which the cache-volumes agent preallocates on the
// same disk after the box joins (200 GB plus 40 GB of headroom on staging):
// half of /data's free space left a staging RISE-M with 168 GB, and the agent's
// provisioning failed. Data blocks are 64 KiB (128
// sectors) with block zeroing off, as the prototype ran; 2 GiB of metadata is
// several times what thin_metadata_size asks for at this size. The pool still
// frees blocks it is told to discard, but no_discard_passdown keeps it from
// punching holes in the preallocated data file.
//
// The script is the unit's ExecStart and runs before containerd on every boot.
// The first run creates and preallocates the files and zeroes the metadata
// header, which is how a new pool starts; later runs reattach the loops and
// thin_check the metadata before reactivating it. The marker is written only
// once the pool exists, and containerd cannot have written to the pool before
// the unit finished, so a crash before it just formats again.
const kataDevmapperSetupScript = `#!/usr/bin/env bash
# Written by cluster-api-provider-tuist: brings up the Kata devmapper thin pool.
set -euo pipefail
dir=` + kataDevmapperDir + `
pool=` + kataDevmapperPool + `
if dmsetup info "$pool" > /dev/null 2>&1; then
  exit 0
fi
modprobe dm_thin_pool
if [ ! -e "$dir/data" ] || [ ! -e "$dir/metadata" ]; then
  rm -f "$dir/initialized" "$dir/data" "$dir/metadata"
  install -d -m 0700 "$dir" "$dir/containerd"
  avail=$(df --output=avail -B1 "$dir" | tail -1)
  size=$(( avail / 4 / 1073741824 ))
  [ "$size" -le 400 ] || size=400
  if [ "$size" -lt 60 ]; then
    echo "tuist: $dir has room for a ${size} GiB pool; the Kata devmapper pool needs 60 GiB." >&2
    exit 1
  fi
  fallocate -l 2G "$dir/metadata.new"
  fallocate -l "${size}G" "$dir/data.new"
  mv "$dir/data.new" "$dir/data"
  mv "$dir/metadata.new" "$dir/metadata"
fi
attach() {
  local dev
  dev=$(losetup -j "$1" -n -O NAME | head -n 1)
  [ -n "$dev" ] || dev=$(losetup -f --show --direct-io=on "$1")
  echo "$dev"
}
meta=$(attach "$dir/metadata")
data=$(attach "$dir/data")
if [ -e "$dir/initialized" ]; then
  thin_check "$meta"
else
  dd if=/dev/zero of="$meta" bs=4096 count=1 conv=fsync status=none
fi
dmsetup create "$pool" --table "0 $(blockdev --getsz "$data") thin-pool $meta $data 128 32768 2 skip_block_zeroing no_discard_passdown"
touch "$dir/initialized"
`

// WantedBy rather than RequiredBy: if the pool cannot come up, containerd still
// starts and runc Pods keep working, and only kata-qemu containers fail to
// create, because the devmapper plugin did not load.
const kataDevmapperUnit = `[Unit]
Description=Tuist Kata devmapper thin pool
Before=containerd.service
RequiresMountsFor=` + kataDevmapperDir + `

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=` + kataDevmapperScript + `

[Install]
WantedBy=containerd.service
`

// base_image_size is the size of every container's ext4 rootfs, image
// included. The thin devices only use the blocks they write, so it is a
// per-container ceiling, not a reservation; the pool is the limit they share.
// Today a job's rootfs writes are only bounded by /data, and 20 GB (what the
// prototype ran) would also cap the filesystem at about 1.3M inodes, close to
// the ~888k files the server Seed job's ClickHouse keeps on the rootfs.
//
// containerd config default already emits an empty devmapper section, so the
// values are set inside it rather than appended (a second table of the same
// name would stop containerd parsing its config). discard_blocks stays false:
// the pool's blocks are reused inside the preallocated file, and discarding
// would punch holes in it that the rest of /data could then fill.
var kataDevmapperContainerdConfig = fmt.Sprintf(`/^[[:space:]]*\[plugins\.'io\.containerd\.snapshotter\.v1\.devmapper'\]/,/^[[:space:]]*\[/{
s#^\([[:space:]]*\)root_path = .*#\1root_path = '%s/containerd'#
s#^\([[:space:]]*\)pool_name = .*#\1pool_name = '%s'#
s#^\([[:space:]]*\)base_image_size = .*#\1base_image_size = '100GB'#
}`, kataDevmapperDir, kataDevmapperPool)

// kataBlockRootfsSetup runs inside kataSetup, before bootstrap restarts
// containerd, so the pool exists by the time containerd loads the snapshotter.
func kataBlockRootfsSetup(sudo string) string {
	return fmt.Sprintf(`%[1]sbash -s <<'TUIST_KATA_BLOCK_ROOTFS'
set -euo pipefail
if ! mountpoint -q /data || [ "$(findmnt -no SOURCE /data)" = "$(findmnt -no SOURCE /)" ]; then
  echo "tuist: the Kata devmapper pool needs /data on its own disk." >&2
  exit 1
fi
install -d /usr/local/sbin
cat > %[2]s <<'TUIST_KATA_DEVMAPPER_SCRIPT'
%[3]sTUIST_KATA_DEVMAPPER_SCRIPT
chmod 0755 %[2]s
cat > %[4]s <<'TUIST_KATA_DEVMAPPER_UNIT'
%[5]sTUIST_KATA_DEVMAPPER_UNIT
systemctl daemon-reload
systemctl enable tuist-kata-devmapper.service
systemctl start tuist-kata-devmapper.service
dmsetup status %[6]s | grep -q thin-pool
sed -i "$(cat <<'TUIST_KATA_DEVMAPPER_SED'
%[7]s
TUIST_KATA_DEVMAPPER_SED
)" /etc/containerd/config.toml
grep -q "^[[:space:]]*pool_name = '%[6]s'" /etc/containerd/config.toml || { echo "tuist: could not configure containerd's devmapper snapshotter" >&2; exit 1; }
install -d %[8]s
cat > %[9]s <<'TUIST_KATA_BLOCK_ROOTFS_DROPIN'
%[10]sTUIST_KATA_BLOCK_ROOTFS_DROPIN
TUIST_KATA_BLOCK_ROOTFS
`, sudo, kataDevmapperScript, kataDevmapperSetupScript, kataDevmapperUnitPath, kataDevmapperUnit,
		kataDevmapperPool, kataDevmapperContainerdConfig,
		"/opt/kata/share/defaults/kata-containers/config.d", kataBlockRootfsDropInPath, kataBlockRootfsDropIn)
}

// kataHandlerSnapshotter is the line kataSetup adds to the kata-qemu handler
// block so CRI creates that handler's containers on devmapper.
func kataHandlerSnapshotter(blockRootfs bool) string {
	if !blockRootfs {
		return ""
	}
	return "snapshotter = \"devmapper\"\n"
}
