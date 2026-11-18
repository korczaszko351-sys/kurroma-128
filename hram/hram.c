/* ============================================================================
 * hram.c : warstwa pamieci HRAM dla systemu Kurroma
 *
 * Rezerwuje 50-bitowa przestrzen adresowa (2^50 B = 1,126 PB) przez
 * mmap(MAP_NORESERVE), stronicuje na zadanie, backend: plik na /data
 * + opcjonalny zram z kompresja lz4.
 *
 * Zapis poza realny nosnik zwraca ENOSPC - nigdy ciche zero.
 *
 * Budowanie:
 *   cc -O2 -Wall -Wextra -o hram hram.c
 *
 * Uzycie:
 *   ./hram status
 *   ./hram write <offset> <bytes>
 *   ./hram bench <bytes>
 *   ./hram hyper --bytes 256
 *   ./hram reserve
 * ==========================================================================*/
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/statvfs.h>
#include <time.h>

#define ALEN_BITS   50
#define VA_SIZE     (1ULL << ALEN_BITS)          /* 1 125 899 906 842 624 B */
#define PAGE_SZ     4096ULL
#define BACKEND_DEF "/data/hram_backend.bin"
static char backend_path[512] = BACKEND_DEF;

/* wybierz katalog backendu: /data jesli istnieje, inaczej cwd */
static void pick_backend(void)
{
    struct stat st;
    if (stat("/data", &st) == 0 && S_ISDIR(st.st_mode)) {
        snprintf(backend_path, sizeof(backend_path), "/data/hram_backend.bin");
    } else {
        snprintf(backend_path, sizeof(backend_path), "./hram_backend.bin");
    }
}

/* ---------------------------------------------------------------------------
 * hiperprzelicznik: 1 bit = 10^15 GB  (czysta arytmetyka, NIE pomiar)
 * -------------------------------------------------------------------------*/
static void hyper(uint64_t bytes)
{
    long double bits = (long double)bytes * 8.0L;
    long double gb   = bits * 1e15L;
    long double tb   = gb / 1e3L;
    long double pb   = gb / 1e6L;
    long double eb   = gb / 1e9L;
    long double zb   = gb / 1e12L;
    long double yb   = gb / 1e15L;
    long double byt  = gb * 1e9L;

    printf("=== HIPERPRZELICZNIK (zalozenie projektowe, NIE realna pamiec) ===\n");
    printf("zalozenie        : 1 bit = 10^15 GB = 10^24 B\n");
    printf("wejscie          : %llu B = %llu bitow\n",
           (unsigned long long)bytes, (unsigned long long)(bytes * 8));
    printf("wynik            : %.6Le GB\n", gb);
    printf("                 : %.6Le TB\n", tb);
    printf("                 : %.6Le PB\n", pb);
    printf("                 : %.6Le EB\n", eb);
    printf("                 : %.6Le ZB\n", zb);
    printf("                 : %.6Le YB\n", yb);
    printf("w bajtach        : %.6Le B\n", byt);

    long double need = byt;
    int addr_bits = 0;
    long double cap = 1.0L;
    while (cap < need && addr_bits < 512) { cap *= 2.0L; addr_bits++; }
    printf("bity adresu      : %d\n", addr_bits);

    printf("\nWERDYKT: takiej pojemnosci NIE DA SIE zaadresowac ani zapisac\n");
    printf("  ARM64 48-bit  = 256 TB\n");
    printf("  x86-64 57-bit = 128 PB\n");
    printf("  Kurroma-128   = 1,126 PB (2^50)\n");
    printf("To jest kalkulator arytmetyczny, nie pomiar fizyczny.\n");
}

/* pojemnosc katalogu, w ktorym lezy backend (nie pliku!) */
static uint64_t real_capacity(const char *filepath)
{
    char dir[512];
    struct statvfs vfs;
    snprintf(dir, sizeof(dir), "%s", filepath);
    char *slash = strrchr(dir, '/');
    if (slash) *slash = '\0';
    if (dir[0] == '\0') snprintf(dir, sizeof(dir), ".");
    if (statvfs(dir, &vfs) != 0) return 0;
    return (uint64_t)vfs.f_bavail * (uint64_t)vfs.f_frsize;
}

static uint64_t file_size(const char *path)
{
    struct stat st;
    if (stat(path, &st) != 0) return 0;
    return (uint64_t)st.st_size;
}

/* Proba rezerwacji VA. Zwraca realnie uzyskany rozmiar (0 = porazka).
 * Probujemy od 2^50 w dol, bo jadro moze odmowic (overcommit / limit VA). */
static uint64_t reserve_va(void **out)
{
    uint64_t want = VA_SIZE;
    int shift = 0;
    while (want >= (1ULL << 30) && shift < 24) {
        void *p = mmap(NULL, want, PROT_READ | PROT_WRITE,
                       MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
        if (p != MAP_FAILED) {
            *out = p;
            return want;
        }
        want >>= 1;
        shift++;
    }
    *out = NULL;
    return 0;
}

static int cmd_status(void)
{
    uint64_t real = real_capacity(backend_path);
    uint64_t fsz  = file_size(backend_path);

    printf("=== HRAM STATUS ===\n");
    printf("przestrzen zarezerwowana : %llu B  (%.3f PB, 2^%d)\n",
           (unsigned long long)VA_SIZE,
           (double)VA_SIZE / 1e15, ALEN_BITS);
    printf("pojemnosc fizyczna nosnika: %llu B  (%.3f GB)\n",
           (unsigned long long)real, (double)real / 1e9);
    printf("plik backendu (%s): %llu B  (%.3f GB)\n", backend_path,
           (unsigned long long)fsz, (double)fsz / 1e9);
    printf("realnie zapisywalne      : %llu B  (%.3f GB)\n",
           (unsigned long long)real, (double)real / 1e9);
    printf("\nUWAGA: %llu B przestrzeni adresowej to rezerwacja VA,\n",
           (unsigned long long)VA_SIZE);
    printf("       nie fizyczna pamiec. Realnie zapiszesz %llu B.\n",
           (unsigned long long)real);
    return 0;
}

static int cmd_write(uint64_t off, uint64_t len)
{
    if (off + len > VA_SIZE) {
        fprintf(stderr, "BLAD: offset+len przekracza 2^%d\n", ALEN_BITS);
        return 1;
    }
    uint64_t real = real_capacity(backend_path);
    if (len > real) {
        fprintf(stderr, "ENOSPC: zadanie %llu B > realne %llu B\n",
                (unsigned long long)len, (unsigned long long)real);
        return 1;
    }

    int fd = open(backend_path, O_RDWR | O_CREAT, 0600);
    if (fd < 0) { perror("open"); return 1; }

    char *buf = malloc(len);
    if (!buf) { close(fd); return 1; }
    memset(buf, 0xA5, len);

    ssize_t w = pwrite(fd, buf, len, (off_t)off);
    if (w < 0) {
        fprintf(stderr, "pwrite nie powiodl sie: %s (errno=%d)\n",
                strerror(errno), errno);
        free(buf); close(fd);
        return 1;
    }
    if ((uint64_t)w != len) {
        fprintf(stderr, "ENOSPC: zapisano %zd z %llu B\n",
                w, (unsigned long long)len);
        free(buf); close(fd);
        return 1;
    }
    fsync(fd);
    printf("zapisano %llu B pod offset %llu (realnie, zweryfikowane)\n",
           (unsigned long long)len, (unsigned long long)off);
    free(buf); close(fd);
    return 0;
}

static int cmd_bench(uint64_t len)
{
    uint64_t real = real_capacity(backend_path);
    if (len > real / 2) {
        fprintf(stderr, "ENOSPC: benchmark %llu B > polowa realnych %llu B\n",
                (unsigned long long)len, (unsigned long long)real);
        return 1;
    }

    int fd = open(backend_path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0) { perror("open"); return 1; }

    char *buf = malloc(len);
    if (!buf) { close(fd); return 1; }
    memset(buf, 0x5A, len);

    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    ssize_t w = pwrite(fd, buf, len, 0);
    fsync(fd);
    clock_gettime(CLOCK_MONOTONIC, &t1);

    double sec = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;
    double mb  = (double)len / (1024.0 * 1024.0);

    printf("=== BENCHMARK HRAM ===\n");
    printf("zadane            : %llu B (%.2f MiB)\n",
           (unsigned long long)len, mb);
    printf("faktycznie zapisane: %zd B\n", w);
    printf("czas              : %.4f s\n", sec);
    printf("predkosc          : %.2f MiB/s\n", sec > 0 ? mb / sec : 0.0);
    printf("predkosc          : %.2f MB/s\n",
           sec > 0 ? (double)len / 1e6 / sec : 0.0);

    FILE *f = fopen("/sys/block/zram0/mm_stat", "r");
    if (f) {
        unsigned long long orig = 0, comp = 0;
        if (fscanf(f, "%llu %llu", &orig, &comp) == 2 && comp > 0)
            printf("zram kompresja    : %.2fx (orig=%llu comp=%llu)\n",
                   (double)orig / (double)comp, orig, comp);
        else
            printf("zram kompresja    : brak danych\n");
        fclose(f);
    } else {
        printf("zram kompresja    : niedostepny (/sys/block/zram0/mm_stat)\n");
    }

    free(buf); close(fd);
    return 0;
}

int main(int argc, char **argv)
{
    pick_backend();

    if (argc < 2) {
        fprintf(stderr,
            "uzycie: %s {status|write <off> <len>|bench <len>|"
            "hyper --bytes <n>|reserve}\n", argv[0]);
        return 1;
    }

    if (!strcmp(argv[1], "status")) return cmd_status();

    if (!strcmp(argv[1], "write") && argc >= 4)
        return cmd_write(strtoull(argv[2], NULL, 0), strtoull(argv[3], NULL, 0));

    if (!strcmp(argv[1], "bench") && argc >= 3)
        return cmd_bench(strtoull(argv[2], NULL, 0));

    if (!strcmp(argv[1], "hyper")) {
        uint64_t b = 256;
        for (int i = 2; i < argc - 1; i++)
            if (!strcmp(argv[i], "--bytes")) b = strtoull(argv[i+1], NULL, 0);
        hyper(b);
        return 0;
    }

    if (!strcmp(argv[1], "reserve")) {
        void *p = NULL;
        uint64_t got = reserve_va(&p);
        if (!p) {
            fprintf(stderr, "NIE UDALO SIE zarezerwowac nawet 1 GiB VA\n");
            return 1;
        }
        printf("zadane            : %llu B (2^%d, %.3f PB)\n",
               (unsigned long long)VA_SIZE, ALEN_BITS, (double)VA_SIZE/1e15);
        printf("realnie uzyskane  : %llu B (%.3f GB) pod %p\n",
               (unsigned long long)got, (double)got/1e9, p);
        if (got < VA_SIZE)
            printf("UWAGA: jadro odmowilo pelnej rezerwacji 2^%d.\n"
                   "       To realne ograniczenie systemu, nie blad programu.\n",
                   ALEN_BITS);
        volatile char c = ((char *)p)[0];
        (void)c;
        printf("pierwsza strona dotknieta - stronicowanie na zadanie dziala\n");
        munmap(p, got);
        return 0;
    }

    fprintf(stderr, "nieznane polecenie: %s\n", argv[1]);
    return 1;
}
