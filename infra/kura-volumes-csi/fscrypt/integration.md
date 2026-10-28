# Integration gates for the shared encrypted filesystem experiment

This is the proposed integration contract for the experiment in [README.md](README.md).
No fscrypt CSI backend or StorageClass is implemented. The deployed candidate
still uses its existing LUKS layouts. Passing the primitive experiment is a
decision gate for implementation, not merge or enrollment approval.

## Scope and storage boundary

Keep encryption in #14152 and fairness policy in #14825. A possible new layout
would use one physically backed ext4 filesystem per node, with a separate
fscrypt v2 directory policy and project quota for each CSI volume. It need not
use thin LVM. A shared, fully backed LV can hold ext4 where a node already has a
VG, provided it is newly allocated and does not displace existing data.

Logical ceilings are policy limits, not preallocated files or partitions. Grant
changes change kernel quotas without resizing the filesystem. Closing/deleting
files makes blocks reusable inside the same filesystem without device TRIM.
SSD discard is a separate maintenance operation; neither its success nor file
deletion can substitute for verified quota and filesystem observations.

The confidentiality boundary changes: fscrypt protects contents and filenames,
but exposes sizes, timestamps, permissions, extended attributes and allocation
patterns. It does not authenticate stored data or isolate an unlocked directory
from a privileged host. Do not describe this as identical to per-volume LUKS.
See the [kernel's threat model](https://docs.kernel.org/filesystems/fscrypt.html).

## Key custody and lifecycle

Preserve the existing OpenBao-backed tenant-share provider, caller/node/PVC
ownership checks and sealed key-delivery transport. Changing the local
encryption mechanism does not require changing the wrapping service.

The experiment uses independent random 64-byte fscrypt keys in memory. It does
not implement production key persistence. Before implementation, specify a
versioned, domain-separated fscrypt key/envelope format, its ownership binding,
crash-safe publication, recovery and retirement procedure. Never zero-pad or
repeat the current 32-byte LUKS passphrase to obtain a 64-byte key. Do not reuse
the same raw key for LUKS and fscrypt.

Deletion requires its own explicit security contract. Deterministically
re-deriving a key after deleting a directory is not cryptographic erasure.
Deleting a wrapped-key file on a journaled filesystem also does not prove that
every recoverable copy disappeared. Do not carry over the LUKS-header erasure
claim without an independently validated design, including backups. Retain
authorization revocation, active-mount checks and incomplete-cleanup records.

Key removal may leave keys in use by open files. A CSI unstage must check mount
and key-removal status and preserve a retryable record. An absent key after a
cold remount is a fail-closed case, not permission to create a plaintext tree.
Permanent OpenBao custody, durable audit delivery and matching database/key
restore remain the separate gates in [key-management.md](../security/key-management.md).

## One owner for enforcement and accounting

CSI must own creation, policy assignment, key installation, mounting, quotas,
reclamation and deletion. The allocator supplies desired grants through CSI's
serialized node-local interface. It must not invoke `quotactl` or alter projects
independently on a CSI-owned filesystem.

Persist the CSI volume ID, filesystem UUID, project ID, policy identifier,
key/envelope version, capacity mode and lifecycle state. Do not reuse a project
ID until all associated inodes and open-deleted allocations are gone. Keep the
pod UID and budget generation as separate fencing fields: replacing a pod does
not replace the volume, and an old pod's lease cannot authorize new operations.

Admission must reserve floors and committed grants, not sum logical ceilings.
For each project charge at least `max(allocated bytes, committed hard quota)`;
charge retained, terminating and partially created/deleted volumes too. Include
non-tenant consumption, pending increases, inode limits and physical reserves.
Read failures or incomplete inventory must prevent new admission and increases.
This equation applies to this shared filesystem, not thin-pool mappings.

Define one versioned conversion between useful cache bytes and whole-project
quota bytes, including workspace and metadata. #14825 currently uses whole
quota bytes; the existing thin API adds workspace to cache grants. Passing the
same number through both APIs would double-count or omit overhead.

Reserve accounting needs real pressure tests before deployment, including many
small files, metadata growth and writes in flight during observation. Restrict
unmanaged writers; a sampled free-space percentage is not a hard exhaustion
bound. During an allocator outage, existing hard quotas remain enforced and
expired runtime leases stop new cache writes. Growth requires fresh serialized
observations; unverified reclaimed bytes cannot fund another grant.

The VM adapter exercises unchanged #14825 policy through `Backend.Read` and
`Backend.SetLimit`. It has a deliberately complete two-volume inventory. A
production adapter still needs CSI discovery, exact ownership verification,
capacity conversion and pod-incarnation fencing. This test is not evidence
that the inventory or admission transaction is already implemented.

## Runtime confinement

A non-root file owner in the initial user namespace can change project IDs or
clear inheritance. Dropping capabilities alone is insufficient. Qualify a
production user-namespace or seccomp contract and refuse workload publication
when that contract is absent. Account for both legacy mutation ioctls and the
Linux 6.17 `file_setattr` syscall; the test helper explicitly covers both.
The harness filter is test code, not a Kubernetes profile installation.

Only expose the assigned directory to the pod. Ensure all persistent cache,
temporary/staging and index data is below its encrypted tree. Validate ordinary
runtime operation, restarts and attempted quota escape under the actual pod
configuration and supported host kernels.

## Migration, validation and rollout

XFS cannot be converted to ext4 in place. Existing thick or thin encrypted
volumes also cannot simply be relabeled as encrypted directories. Prepare new
ext4 landing capacity, create new encrypted claims, backfill and verify them,
then use the existing catch-up and endpoint-handoff protocol. Keep the source
until handoff and deletion safeguards permit retirement. A populated VG is not
spare capacity for a new shared filesystem.

Preserve account enrollment and source-node pacing, starting with the Tuist
account after qualification. Pod-by-pod handoff can use prepared capacity;
reformatting a node requires evacuating its existing data first. A single-host
region needs external landing capacity. Do not promise a migration without
spare capacity or a filesystem switch triggered by an ordinary pod restart.

Before merge, qualify the real CSI/key-service/OpenBao path on staging with
restart, outage, concurrency, retained-volume and pressure cases; repeat
benchmarks against the production-style shared-XFS control on the same host.
Rehearse interrupted migration and rollback. Rollback disables new enrollment
while retaining the driver and key providers needed to reopen existing volumes.
Recalculate capacity and memory results for the final layout: earlier shared-XFS
and thin results cannot establish ext4/fscrypt fleet savings.
