// Linpack の単精度（float）の殻（2026-11-20）。中身は lp_body.inc
#define SP
#define LP_FN bench_lp_sp
#define LP_UNUSED_MAIN linpack_main_sp
#include "lp_body.inc"
