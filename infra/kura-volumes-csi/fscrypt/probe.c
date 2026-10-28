// Disposable-VM test helper. Use kernel ABI headers rather than parsing quota CLI output.
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/fs.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/quota.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <unistd.h>

static void fail(const char *s) { perror(s); exit(1); }
// Test confinement only. Production needs an independently qualified node/pod
// profile or user-namespace contract; dropping capabilities alone is insufficient.
static void confine(void) {
#if defined(__x86_64__)
  const unsigned int arch = AUDIT_ARCH_X86_64;
#elif defined(__aarch64__)
  const unsigned int arch = AUDIT_ARCH_AARCH64;
#else
#error Unsupported qualification architecture
#endif
  struct sock_filter code[] = {
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, arch, 1, 0),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
    BPF_JUMP(BPF_JMP | BPF_JGE | BPF_K, 0x40000000, 0, 1), // reject x32 ABI
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_ioctl, 0, 7),
    BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, args[1])),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, FS_IOC_FSSETXATTR, 4, 0),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, FS_IOC_SETFLAGS, 3, 0),
    BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, _IOW('f', 2, int), 2, 0),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM),
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
  };
  struct sock_fprog program = {.len = sizeof(code)/sizeof(code[0]), .filter = code};
  if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) || prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program)) fail("seccomp");
}
int main(int argc, char **argv) {
  if (argc < 3) return 2;
  if (!strcmp(argv[1], "confined")) {
    confine();
    execvp(argv[2], argv+2);
    fail("exec");
  } else if (!strcmp(argv[1], "get") && argc == 4) {
    struct dqblk q = {0};
    if (quotactl(QCMD(Q_GETQUOTA, PRJQUOTA), argv[2], atoi(argv[3]), (void *)&q)) fail("getquota");
    printf("{\"used\":%llu,\"hard\":%llu,\"inodes\":%llu,\"inode_hard\":%llu}\n",
           (unsigned long long)q.dqb_curspace, (unsigned long long)q.dqb_bhardlimit * 1024,
           (unsigned long long)q.dqb_curinodes, (unsigned long long)q.dqb_ihardlimit);
  } else if (!strcmp(argv[1], "set") && argc == 6) {
    struct dqblk q = {0};
    q.dqb_bhardlimit = q.dqb_bsoftlimit = strtoull(argv[4], NULL, 10) / 1024;
    q.dqb_ihardlimit = q.dqb_isoftlimit = strtoull(argv[5], NULL, 10);
    if (!q.dqb_bhardlimit || !q.dqb_ihardlimit) return 2;
    q.dqb_valid = QIF_LIMITS;
    if (quotactl(QCMD(Q_SETQUOTA, PRJQUOTA), argv[2], atoi(argv[3]), (void *)&q)) fail("setquota");
  } else if (!strcmp(argv[1], "project") && argc == 4) {
    int fd = open(argv[2], O_RDONLY | O_DIRECTORY | O_NOFOLLOW);
    if (fd < 0) fail("open");
    struct fsxattr a = {0};
    if (ioctl(fd, FS_IOC_FSGETXATTR, &a)) fail("getxattr");
    a.fsx_projid = atoi(argv[3]);
    a.fsx_xflags |= FS_XFLAG_PROJINHERIT;
    if (ioctl(fd, FS_IOC_FSSETXATTR, &a)) fail("setxattr");
    close(fd);
  } else if (!strcmp(argv[1], "space") && argc == 3) {
    struct statvfs s;
    if (statvfs(argv[2], &s)) fail("statvfs");
    printf("{\"available\":%llu,\"total\":%llu,\"free_inodes\":%llu}\n",
           (unsigned long long)s.f_bavail * s.f_frsize,
           (unsigned long long)s.f_blocks * s.f_frsize, (unsigned long long)s.f_favail);
  } else if (!strcmp(argv[1], "mmap") && argc == 3) {
    int fd = open(argv[2], O_RDONLY);
    if (fd < 0) fail("open");
    struct stat s;
    if (fstat(fd, &s) || s.st_size < 1) fail("stat");
    void *m = mmap(NULL, s.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
    if (m == MAP_FAILED) fail("mmap");
    char b[4096];
    for (off_t p = 0; p < s.st_size; p += sizeof(b)) {
      size_t n = s.st_size-p < (off_t)sizeof(b) ? s.st_size-p : (off_t)sizeof(b);
      if (pread(fd, b, n, p) != (ssize_t)n || memcmp(b, (char *)m+p, n)) return 1;
    }
    munmap(m, s.st_size);
    close(fd);
  } else return 2;
  return 0;
}
