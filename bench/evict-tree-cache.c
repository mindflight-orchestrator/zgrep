#define _XOPEN_SOURCE 700

#include <errno.h>
#include <fcntl.h>
#include <ftw.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static int evict_file(
    const char *path,
    const struct stat *stat_buffer,
    int type,
    struct FTW *walk
) {
    (void)stat_buffer;
    (void)walk;
    if (type != FTW_F) return 0;

    const int file = open(path, O_RDONLY | O_CLOEXEC);
    if (file < 0) {
        fprintf(stderr, "cache eviction: %s: %s\n", path, strerror(errno));
        return 1;
    }
    const int advice_error = posix_fadvise(file, 0, 0, POSIX_FADV_DONTNEED);
    if (close(file) != 0) {
        fprintf(stderr, "cache eviction: %s: %s\n", path, strerror(errno));
        return 1;
    }
    if (advice_error != 0) {
        fprintf(stderr, "cache eviction: %s: %s\n", path, strerror(advice_error));
        return 1;
    }
    return 0;
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s TREE\n", argv[0]);
        return 2;
    }
    return nftw(argv[1], evict_file, 64, FTW_PHYS) == 0 ? 0 : 1;
}
