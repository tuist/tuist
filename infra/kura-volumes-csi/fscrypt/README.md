# Disposable ext4/fscrypt qualification

This is a storage-primitive experiment for #14152, not a CSI implementation,
OpenBao deployment or replacement rollout. The aim is to preserve tenant keys
while letting the later #14825 allocator transfer filesystem quota grants
without thin-pool overcommit or filesystem replacement.

Run `stack_test.rb` only as root in a disposable Linux VM with
`KURA_FSCRYPT_DISPOSABLE_VM=1`. It creates private sparse files and loop devices;
it never accepts an existing block device. Required tools: Ruby, a C compiler,
e2fsprogs, quota support, fscryptctl 1.2.0, xfsprogs, LVM, cryptsetup and fio.
`probe.c` is a test-only wrapper around the kernel's quota/project and mmap APIs.
No generated keys are written to disk or included in reports. Quota writes run
as UID 1000 without capabilities. Failed detach retains backing files.

File ownership without a separate user namespace can permit changing project
IDs and inheritance. The harness records this negative control, then installs
an additional seccomp filter rejecting filesystem project/flag mutation ioctls
for test writers. The same filter is inherited by the benchmark Kura process,
in addition to Docker's normal confinement. This is test code, not a shipped
pod security contract. A production implementation must qualify equivalent
confinement and fail closed when it is missing.

The harness checks distinct fscrypt v2 policies, dynamic kernel quotas, physical
space recovery, held unlinked files, concurrent quota exhaustion, inode limits,
independent key removal, wrong keys, mmap reads and cold remount. Aggregate
logical ceilings exceed the filesystem; a deliberately smaller fixed admission
budget and filesystem reserve remain separate. It is not a fairness allocator.

Benchmarks alternate shared XFS, plain ext4, encrypted ext4, thick LUKS/XFS and
512 KiB thin LUKS/XFS, then reverse the order. All use buffered synchronous I/O
to avoid silently comparing fscrypt's O_DIRECT fallback with actual direct I/O.
The 512 MiB file and eight-second phases are VM mechanism diagnostics, not
hosted NVMe/application measurements or proof of a cold working set. Reclamation
churn includes TRIM for thin; ordinary filesystem block reuse requires no TRIM.

Setting `KURA_FSCRYPT_CACHE_BENCH` to the built `cmd/cache-bench` executable also
runs the pinned Kura runtime in unprivileged Docker containers, with one CPU,
768 MiB memory, 4 GiB cache budget and 2 GiB workspace. It compares shared XFS,
plain ext4, fscrypt and thin LUKS/XFS in forward/reverse order with a new cache
directory each time. Every layout has a 6 GiB project quota. Authenticated,
checksum-checked HTTP workloads include eviction churn and a 1 GiB working set.
The temporary auth token is fixture-only, kept out of artifacts and deleted
with the fixture. This remains VM testing, not Kubernetes/CSI or OpenBao E2E.

`allocator_test.go.fixture` is compiled against the exact #14825 policy revision
`34956ca681a3dc0dc257ee5b4d0d65814bd5f23d` in a separate CI checkout. Set
`KURA_FSCRYPT_ALLOCATOR_TEST` to that test binary to exercise its unchanged
`Agent.Reconcile` against the two encrypted projects. A 10 GiB admission cap
and a 2 GiB physical reserve protect the test. A held 5 GiB donor allocation
blocks the recipient's increase; after closure, the restarted agent transfers
quotas from 6/4 GiB to 4/6 GiB and the recipient writes beyond its old allowance.
The adapter's complete inventory is known only because the filesystem is private
to this test. It is not a deployable inventory or substitute for CSI serialization.

Buffered fio write rates include repeated page-cache overwrites; even with a
final fsync they are not sustained durable device bandwidth. Prefer the actual
Kura workload for this experiment, and hosted staging for a rollout decision.

fscrypt encrypts file contents and filenames, not other filesystem metadata.
Unlocked files still rely on normal host permissions and pod isolation. Keys
for open files can remain in use after a removal request. A successful probe
does not establish live revocation, authenticated encryption, permanent key
custody, crash/power-loss recovery, production capacity safety or performance.
See the [kernel fscrypt contract](https://docs.kernel.org/filesystems/fscrypt.html).
