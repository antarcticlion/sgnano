// Linpack の殻の共通の中身（lp_sp.c / lp_dp.c が SP / DP を決めてから読み込む。2026-11-20）。
// 元の linpack.c（third_party/linpack、Menninger 版）を同じ翻訳単位に読み込み、その static な関数（matgen・dgefa・dgesl）をそのまま呼ぶ。
// 元の linpack() と同じく n = 100 を rolled と unrolled で 1 回ずつ解き、時間は dgefa + dgesl だけを足す。演算の数は 2/3·n^3 + 2·n^2（1 回あたり）。
// 配列は lda = n + 1 に詰める（元は lda = 200。SRAM に置くため、bench.h）
#define main LP_UNUSED_MAIN                 // 元の main（大きさを標準入力から読む）は使わない
#include "third_party/linpack/linpack.c"
#undef main
#include <stdint.h>
#include "bench.h"

double LP_FN(void *work, bench_clock_fn now, uint64_t *us) {
    const int lda = BENCH_LP_LDA, n = BENCH_LP_N;
    REAL *a = (REAL *)work, *b = a + (long)lda * n, norma;
    int *ipvt = (int *)&b[n], info;
    const double ops = (2.0 * n * n * n) / 3.0 + 2.0 * n * n;
    for (int roll = 1; roll >= 0; roll--) {
        matgen(a, lda, n, b, &norma);
        const uint64_t t0 = now();
        dgefa(a, lda, n, ipvt, &info, roll);
        dgesl(a, lda, n, ipvt, b, 0, roll);
        *us += now() - t0;
    }
    return 2.0 * ops;
}
