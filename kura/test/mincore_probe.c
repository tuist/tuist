/*
 * Reproducer for the mmap page-cache-residency check kura uses to gate mmap
 * serving (src/mmap.rs `mapping_is_resident`): write a file, fsync it, map it
 * MAP_PRIVATE/PROT_READ, and ask mincore(2) whether the pages are resident.
 *
 * The kura mmap tests assert "freshly written region should be page-cache
 * resident", which holds on a native filesystem but not necessarily on a
 * virtio-fs-backed mount (e.g. inside a Kata Containers microVM). This probe
 * prints residency twice per directory:
 *   - "fresh"       : right after write+fsync+mmap, before touching any page
 *   - "after_touch" : after reading one byte from every page (faulting them in)
 *
 * If "fresh" reports non-resident but "after_touch" reports resident, the data
 * is in memory and it is mincore's page-cache reporting that differs by
 * filesystem -- exactly what disables kura's mmap fast path on such a mount.
 *
 * Build:  cc -O2 test/mincore_probe.c -o mincore_probe
 * Run:    ./mincore_probe <dir>
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

static size_t count_resident(const unsigned char *vec, size_t pages) {
    size_t resident = 0;
    for (size_t i = 0; i < pages; i++) {
        if (vec[i] & 1) {
            resident++;
        }
    }
    return resident;
}

int main(int argc, char **argv) {
    const char *dir = argc > 1 ? argv[1] : "/tmp";
    char path[4096];
    snprintf(path, sizeof path, "%s/.mincore_probe.bin", dir);

    size_t len = 256 * 1024; /* several pages */
    unsigned char *data = malloc(len);
    memset(data, 0xAB, len);

    int fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0644);
    if (fd < 0) {
        printf("open_failed=%s\n", strerror(errno));
        free(data);
        return 0;
    }
    if (write(fd, data, len) != (ssize_t)len) {
        printf("write_failed=%s\n", strerror(errno));
        close(fd);
        free(data);
        return 0;
    }
    fsync(fd);

    long page_size = sysconf(_SC_PAGESIZE);
    size_t pages = (len + (size_t)page_size - 1) / (size_t)page_size;

    void *addr = mmap(NULL, len, PROT_READ, MAP_PRIVATE, fd, 0);
    if (addr == MAP_FAILED) {
        printf("mmap_failed=%s\n", strerror(errno));
        close(fd);
        unlink(path);
        free(data);
        return 0;
    }

    unsigned char *vec = calloc(pages, 1);
    int rc_fresh = mincore(addr, len, vec);
    size_t resident_fresh = count_resident(vec, pages);

    /* Fault every page in with a volatile read. */
    volatile unsigned char sink = 0;
    for (size_t off = 0; off < len; off += (size_t)page_size) {
        sink ^= ((const volatile unsigned char *)addr)[off];
    }
    (void)sink;

    memset(vec, 0, pages);
    int rc_touched = mincore(addr, len, vec);
    size_t resident_touched = count_resident(vec, pages);

    printf("pages=%zu | fresh: rc=%d resident=%zu/%zu | after_touch: rc=%d resident=%zu/%zu\n",
           pages, rc_fresh, resident_fresh, pages, rc_touched, resident_touched, pages);

    munmap(addr, len);
    free(vec);
    free(data);
    close(fd);
    unlink(path);
    return 0;
}
