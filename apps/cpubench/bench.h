// 計測の部品（cpubench、2026-11-20。2026-11-24 に両コア対応）: 計算の本体は third_party の元の版をそのまま組む
#pragma once
#include <stdbool.h>
#include <stdint.h>

// Dhrystone 2.1: runs 回まわす（1 回 = 1 Dhrystone）。pool = レコード 2 つの置き場（BENCH_DHRY_POOL バイト。SRAM か PSRAM）
// bench_dhry_runs は Core 1 用、bench_dhry0_runs は Core 0 用の独立インスタンス（同時実行可能）
#define BENCH_DHRY_POOL 512u
void bench_dhry_runs(int runs, void *pool);
void bench_dhry0_runs(int runs, void *pool);

// Linpack（Menninger 版、n = 100）: rolled と unrolled を 1 回ずつ解く。浮動小数点の演算の数を返し、dgefa + dgesl にかかった時間（µs）を
// *us に足す。now は µs の時計。配列は lda = n + 1 = 101 に詰める（2026-11-20、ユーザー指示: SRAM に置く。元の lda = 200 では
// 単精度 160KB・倍精度 320KB で SRAM に入らない。解く大きさと演算の数は同じ）
// _ex 版は rolled と unrolled の間で *stop を確認して早期終了できる（再入可能・両コア同時実行可能）
typedef uint64_t (*bench_clock_fn)(void);
double bench_lp_sp(void *work, bench_clock_fn now, uint64_t *us);   // 単精度（float）
double bench_lp_dp(void *work, bench_clock_fn now, uint64_t *us);   // 倍精度（double）
double bench_lp_sp_ex(void *work, bench_clock_fn now, uint64_t *us, const volatile bool *stop);
double bench_lp_dp_ex(void *work, bench_clock_fn now, uint64_t *us, const volatile bool *stop);
#define BENCH_LP_N        100
#define BENCH_LP_LDA      (BENCH_LP_N + 1)
#define BENCH_LP_WORK(sz) ((uint32_t)(BENCH_LP_LDA * BENCH_LP_N + BENCH_LP_N) * (sz) + BENCH_LP_N * 4u + 64u)
#define BENCH_LP_WORK_SP  BENCH_LP_WORK(4u)
#define BENCH_LP_WORK_DP  BENCH_LP_WORK(8u)
