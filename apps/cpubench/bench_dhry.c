// Dhrystone 2.1 のつなぎ（2026-11-20）。元の main（dhry_main に名前を替えたもの）を、決めた回数で 1 回ずつ呼ぶ。
// 元の main は回数を scanf で読み、レコードを 2 つ malloc し、結果を printf で出すので、それぞれをここで受ける:
//   scanf  -> いま頼んでいる回数を返す / malloc -> 呼ぶたびに頭から使い回す静的な置き場（漏らさない） / printf・time -> 何もしない
#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>
#include "bench.h"

int dhry_main();                         // third_party/dhrystone/dhry_1.c の main（-Dmain=dhry_main）

static int      want_runs;
static uint8_t *pool;                    // Rec_Type 2 つ（1 つ 60 バイトほど）。置き場（SRAM / PSRAM）は呼び手が渡す（2026-11-20）
static unsigned pool_used;

char *dhry_malloc(size_t n) {
    n = (n + 7u) & ~(size_t)7u;
    if (!pool || pool_used + n > BENCH_DHRY_POOL) return NULL;
    char *p = (char *)pool + pool_used;
    pool_used += n;
    return p;
}
int dhry_scanf(const char *fmt, ...) {
    (void)fmt;
    va_list ap; va_start(ap, fmt);
    int *p = va_arg(ap, int *);
    va_end(ap);
    *p = want_runs;
    return 1;
}
int dhry_printf(const char *fmt, ...) { (void)fmt; return 0; }
long dhry_time(long *t) { if (t) *t = 0; return 0; }

void bench_dhry_runs(int runs, void *pool_mem) {
    want_runs = runs;
    pool = (uint8_t *)pool_mem;
    pool_used = 0;
    dhry_main();
}
