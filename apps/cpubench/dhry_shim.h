// Dhrystone 2.1（third_party/dhrystone、手を入れていない元の版）を SGX で組むときに -include で先に読ませる宣言（2026-11-20）。
// 組み方は apps/CMakeLists.txt: -std=gnu89（K&R の書き方のまま）・-DTIME と、main / scanf / printf / malloc / time を
// bench_dhry.c のつなぎへ名前を替える。時間は Dhrystone の中では測らず、外側（cpubench.c）が sgx->us() で測る
#include <string.h>
char *dhry_malloc();
int   dhry_scanf(const char *fmt, ...);
int   dhry_printf(const char *fmt, ...);
long  dhry_time();
