#define _GNU_SOURCE
#include <dlfcn.h>
#include <execinfo.h>
#include <fcntl.h>
#include <link.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

#define DEPTH 28
#define ROW (DEPTH + 1)
#define MAGIC 0x50524f4653414d50ULL

static uint64_t *rows;
static size_t cap;
static atomic_size_t used;
static long period_ns;
static uint64_t load_base;
static const char *out_path;
static atomic_int dumped;

struct start {
    void *(*fn)(void *);
    void *arg;
};

static void on_prof(int sig, siginfo_t *si, void *uc)
{
    void *frames[DEPTH + 2];
    size_t i = atomic_fetch_add(&used, 1);
    int n, keep, j;
    uint64_t *row;
    (void)sig;
    (void)si;
    (void)uc;
    if (i >= cap)
        return;
    n = backtrace(frames, DEPTH + 2);
    keep = n > 2 ? n - 2 : 0;
    if (keep > DEPTH)
        keep = DEPTH;
    row = rows + i * ROW;
    row[0] = (uint64_t)keep;
    for (j = 0; j < keep; j++)
        row[1 + j] = (uint64_t)(uintptr_t)frames[j + 2];
}

static void arm_current_thread(void)
{
    struct sigevent sev;
    struct itimerspec its;
    timer_t t;
    memset(&sev, 0, sizeof sev);
    sev.sigev_notify = SIGEV_THREAD_ID;
    sev.sigev_signo = SIGPROF;
    sev._sigev_un._tid = (int)syscall(SYS_gettid);
    if (timer_create(CLOCK_THREAD_CPUTIME_ID, &sev, &t) != 0)
        return;
    its.it_interval.tv_sec = period_ns / 1000000000L;
    its.it_interval.tv_nsec = period_ns % 1000000000L;
    its.it_value = its.it_interval;
    timer_settime(t, 0, &its, NULL);
}

static void *thread_main(void *p)
{
    struct start s = *(struct start *)p;
    free(p);
    arm_current_thread();
    return s.fn(s.arg);
}

int pthread_create(pthread_t *th, const pthread_attr_t *attr, void *(*fn)(void *), void *arg)
{
    static int (*real)(pthread_t *, const pthread_attr_t *, void *(*)(void *), void *);
    struct start *s;
    if (!real)
        real = dlsym(RTLD_NEXT, "pthread_create");
    s = malloc(sizeof *s);
    s->fn = fn;
    s->arg = arg;
    return real(th, attr, thread_main, s);
}

static void write_all(int fd, const void *buf, size_t len)
{
    const char *p = buf;
    while (len > 0) {
        ssize_t w = write(fd, p, len);
        if (w <= 0)
            return;
        p += w;
        len -= (size_t)w;
    }
}

static void dump(void)
{
    uint64_t hdr[5];
    size_t n = atomic_load(&used);
    int fd;
    if (atomic_exchange(&dumped, 1) || !out_path)
        return;
    if (n > cap)
        n = cap;
    fd = open(out_path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd < 0)
        return;
    hdr[0] = MAGIC;
    hdr[1] = load_base;
    hdr[2] = DEPTH;
    hdr[3] = n;
    hdr[4] = (uint64_t)period_ns;
    write_all(fd, hdr, sizeof hdr);
    write_all(fd, rows, n * ROW * sizeof(uint64_t));
    close(fd);
}

static void on_term(int sig)
{
    dump();
    signal(sig, SIG_DFL);
    raise(sig);
}

static int first_phdr(struct dl_phdr_info *info, size_t size, void *data)
{
    (void)size;
    *(uint64_t *)data = (uint64_t)info->dlpi_addr;
    return 1;
}

__attribute__((constructor)) static void init(void)
{
    struct sigaction sa;
    const char *hz_env = getenv("PROF_HZ");
    const char *cap_env = getenv("PROF_CAP");
    void *warm[4];
    long hz = hz_env ? atol(hz_env) : 20;
    out_path = getenv("PROF_OUT");
    if (hz < 1)
        hz = 1;
    period_ns = 1000000000L / hz;
    cap = cap_env ? (size_t)atol(cap_env) : 3000000;
    rows = mmap(NULL, cap * ROW * sizeof(uint64_t), PROT_READ | PROT_WRITE,
                MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0);
    if (rows == MAP_FAILED)
        return;
    dl_iterate_phdr(first_phdr, &load_base);
    backtrace(warm, 4);
    memset(&sa, 0, sizeof sa);
    sa.sa_sigaction = on_prof;
    sa.sa_flags = SA_SIGINFO | SA_RESTART;
    sigemptyset(&sa.sa_mask);
    sigaction(SIGPROF, &sa, NULL);
    signal(SIGTERM, on_term);
    arm_current_thread();
}

__attribute__((destructor)) static void fini(void)
{
    dump();
}
