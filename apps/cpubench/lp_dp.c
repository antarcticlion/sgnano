// Linpack の倍精度（double）の殻（2026-11-20）。中身は lp_body.inc。double の四則と sqrt などは SDK が RP2350 の DCP へ回す
#define DP
#define LP_FN bench_lp_dp
#define LP_FN_EX bench_lp_dp_ex
#define LP_UNUSED_MAIN linpack_main_dp
#include "lp_body.inc"
