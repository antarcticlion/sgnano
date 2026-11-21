// CPU パワーの計測（cpubench.sgx、2026-11-20、ユーザー指示）。
// 画面の負荷（画面モード 0〜7。ローレゾのモードでは歯抜けの BG 2 面と 32x32 のオブジェクト 128 個を並べ、FB のモードは
// 模様を描いた FB を出す。計っている間は動かさない = 表示そのものの負荷）と音の負荷（無し / MP3 / YM2151 + C352 の VGM。2026-11-20 に SegaPCM から C352 へ）を選び、その下で計算の速さを測る:
//   - Dhrystone 2.1（third_party/dhrystone、元の版）: Dhrystones/秒、DMIPS（= VAX MIPS = Dhrystones/秒 / 1757）、DMIPS/MHz
//   - Linpack（third_party/linpack、元の Menninger 版。n = 100）: 単精度 MFLOPS（float、M33 の FPU）・倍精度 MFLOPS（double、DCP）
// 計算はメインより 2 段低い優先度のタスクで回す（描画・音楽・先読みが先に走り、計算は残りの時間で回る = 負荷で削られた分が数字に出る）。
// Dhrystone は「回した数 / 経過時間」、Linpack は元の作法どおり「演算の数 / dgefa + dgesl の時間」。
// 結果は S:/SystemLogs/cpubench.csv に 1 行ずつ書き足し、メニューの下に一覧（負荷なし = モード 0・音なしとの比）を出す。UART のログにも CPUBENCH の行。
// 曲はこのプログラムと同じフォルダの skyward_pulse.vgz（scripts/make_bench_song.py）と skyward_pulse.mp3。引数 -vgm / -mp3 で替えられる
#include "sgx_api.h"
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "bench.h"

extern const sgx_api_t *sgx;            // sgx_crt0.c

#define CSV_PATH   "S:/SystemLogs/cpubench.csv"
#define CSV_MAX    (48u * 1024u)        // これを超えたら古い行から捨てる
#define CPU_MHZ    302.4                // clk_sys（sgnano のファームウェアの既定）
#define BG_TILES   8u
#define N_MODES    8
#define N_MUSIC    3

// 訳（SGX_F_LOCALIZE）。translate の返す文は同じタスクの次の translate までしか持たず、text_puts も中で translate を呼ぶので、
// 自分の置き場（16 個を順に使い回す）へ写して返す（写さずに並べていて、メニューの名前がすべて最後の訳になり、行が前の行の中身で連なった）
static const char *T(const char *en) {
    static char ring[16][120];
    static unsigned at;
    const char *s = sgx->translate ? sgx->translate(en) : NULL;
    char *o = ring[at++ & 15u];
    snprintf(o, sizeof ring[0], "%s", s ? s : en);
    return o;
}

static const char *const MODE_NAME[N_MODES] = {
    "0: no display (sync only)", "1: text", "2: text + RGB555 FB", "3: text + low-res + CLUT8 FB",
    "4: text + low-res + CLUT4 FB", "5: text + low-res", "6: low-res only (320 wide)", "7: text + 320x200 bitmap",
};
static const char *const MUSIC_NAME[N_MUSIC] = { "none", "MP3", "VGM (YM2151 + C352)" };
static const char *const MUSIC_TAG[N_MUSIC] = { "none", "mp3", "vgm" };
static bool mode_has_lr(int m) { return m >= 3 && m <= 6; }
static bool mode_has_text(int m) { return m != 0 && m != 6; }

static char vgm_path[160], mp3_path[160];

// ---- 文字 ----
static void logf_(const char *fmt, ...) {
    char b[240];
    va_list ap; va_start(ap, fmt);
    int n = sgx->vsnprintf(b, sizeof b - 1u, fmt, ap);
    va_end(ap);
    if (n < 0) return;
    if (n > (int)sizeof b - 2) n = (int)sizeof b - 2;
    b[n++] = '\n';
    sgx->log(b, (unsigned)n);
}
static void row_text(unsigned row, uint32_t attr, const char *fmt, ...) {   // 1 行を書き換える（80 桁を埋める）
    char b[200];
    va_list ap; va_start(ap, fmt);
    int n = sgx->vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    if (n < 0) n = 0;
    if (row >= sgx->text_rows()) return;
    const unsigned used = sgx->text_puts(0, row, b, attr);
    for (unsigned x = used; x < 80u; x++) sgx->text_put(x, row, ' ', attr);
}
#define A_NORM  (SGX_T_FG(7) | SGX_T_BG(0))
#define A_DIM   (SGX_T_FG(8) | SGX_T_BG(0))
#define A_HEAD  (SGX_T_FG(0) | SGX_T_BG(6))
#define A_SEL   (SGX_T_FG(0) | SGX_T_BG(7))
#define A_GOOD  (SGX_T_FG(14) | SGX_T_BG(0))
#define A_RUN   (SGX_T_FG(15) | SGX_T_BG(1) | SGX_T_BG_TRANS)

// ---- 画面の負荷 ----
static uint32_t rs = 1;
static uint32_t rnd(void) { rs ^= rs << 13; rs ^= rs >> 17; rs ^= rs << 5; return rs; }

// テスト用アプリ（apps/testapp の mode3〜6）と同じ球のオブジェクト: 真ん中が明るく縁へ暗くなる円を、色の段のパレットで塗る。
// ローレゾ面は小さく（パターン 16KB = 256 タイル）開くので、絵は BG のタイルのすぐ後ろに置く（testapp はタイル 256〜）。
// オブジェクトのパターンはタイル順ではなく 1 枚の絵のまま並べる（testapp の set_pattern と同じ）
#define SPR_64 16u                                      // 64x64 = 64 タイル（16〜79）
#define SPR_32 80u                                      // 32x32 = 16 タイル
#define SPR_16 96u                                      // 16x16 = 4 タイル
#define SPR_8  100u
#define N_OBJ  24                                       // testapp の既定と同じ数（4 つの大きさを順に）
static const uint16_t SPR[4] = { SPR_8, SPR_16, SPR_32, SPR_64 };
static uint8_t *lr_pat;
static uint32_t lr_pat_bytes;
static void set_pattern(unsigned tile, const uint8_t *d, unsigned n) { if (tile * 64u + n <= lr_pat_bytes) memcpy(lr_pat + tile * 64u, d, n); }
static void ramp(int pal, unsigned r, unsigned g, unsigned b) {   // 色 0〜127 を暗いほうから明るいほうへ（testapp と同じ）
    if (pal >= sgx->lr_palettes()) return;
    uint16_t *p = sgx->lr_palette(pal);
    if (!p) return;
    for (unsigned c = 0; c < 128u; c++) p[c] = sgx->rgb(r * 255u / 31u * c / 127u, g * 255u / 31u * c / 127u, b * 255u / 31u * c / 127u);
}
static void disc(unsigned tile, unsigned size) {        // 真ん中が明るく、縁へ暗く、外は透過（testapp と同じ）
    static uint8_t d[64 * 64];
    const int c = (int)size / 2, rr = c * c;
    for (unsigned i = 0; i < size * size; i++) {
        const int x = (int)(i % size) - c, y = (int)(i / size) - c, dd = x * x + y * y;
        d[i] = dd >= rr ? 128 : (uint8_t)(127 - dd * 127 / rr);
    }
    set_pattern(tile, d, size * size);
}
static void lowres_init(void) {
    lr_pat = sgx->lr_pattern(&lr_pat_bytes);
    const int npal = sgx->lr_palettes();
    ramp(0, 12, 14, 18);                                // BG: 落ち着いた青灰
    ramp(1, 31, 31, 31); ramp(2, 8, 31, 12); ramp(3, 31, 22, 6); ramp(4, 10, 18, 31); ramp(5, 31, 10, 10);   // 白・緑・橙・青・赤
    uint8_t t[64];
    for (unsigned k = 0; k < BG_TILES; k++) {           // 歯抜けの BG: タイルの半分ほどが透過（2 面とも合成の手間がかかる）
        for (unsigned y = 0; y < 8u; y++) for (unsigned x = 0; x < 8u; x++)
            t[y * 8u + x] = (((x + y + k) & 3u) < 2u) ? SGX_LR_TRANSPARENT : (uint8_t)(40u + ((k * 16u + x * 4u + y * 3u) & 63u));
        set_pattern(k, t, 64);
    }
    disc(SPR_64, 64); disc(SPR_32, 32); disc(SPR_16, 16); disc(SPR_8, 8);
    for (int p = 0; p < sgx->lr_planes() && p < 2; p++) {
        uint16_t *m = sgx->lr_map(p);
        for (unsigned i = 0; i < SGX_LR_MAP_W * SGX_LR_MAP_H; i++)
            m[i] = (uint16_t)((unsigned)p * 4u + (i * 7u + i / SGX_LR_MAP_W) % 4u);   // パレット 0
    }
    sgx_lr_obj_t *o = sgx->lr_oam();
    memset(o, 0, sizeof(sgx_lr_obj_t) * SGX_LR_OBJS);
    const unsigned npc = npal > 1 ? (unsigned)(npal - 1 < 5 ? npal - 1 : 5) : 1u;
    for (int i = 0; i < N_OBJ; i++) {                   // 画面に散らして置く（動かさない）
        const unsigned k = (unsigned)i % 4u, w = 8u << k;
        o[i].pattern = SPR[k];
        o[i].x = (int16_t)(8 + (i % 6) * 52 + (int)(rnd() % 8u));
        o[i].y = (int16_t)(8 + (i / 6) * 56 + (int)(rnd() % 8u));
        o[i].attr = (uint16_t)(((w - 1u) & 0xFFu) | (k << 8) | (((unsigned)i % 3u) << 10) | SGX_LR_OBJ_SHOW);
        o[i].attr2 = 1u + (unsigned)i % npc;
    }
    sgx_lr_ctrl_t *c = sgx->lr_ctrl();
    c->bg[0] = c->bg[1] = true; c->obj = true;
    c->sx[0] = c->sy[0] = 0; c->sx[1] = 3; c->sy[1] = 5;  // 2 面を少しずらして重ねる（動かさない）
    sgx->lr_commit();
}
static void fb_pattern(int mode) {                      // FB は「出しているだけ」の負荷: 模様を 1 回描いておく
    if (mode == 3) for (int i = 0; i < 256; i++) sgx->fb_palette(i, sgx->rgb((unsigned)i, (unsigned)(i * 3) & 255u, 255u - (unsigned)i));
    for (int y = 0; y < 480; y += 16)
        for (int x = 0; x < 640; x += 40) {
            const unsigned k = (unsigned)(x / 40 + y / 16);
            uint32_t c;
            if (mode == 2) c = sgx->rgb((k * 37u) & 255u, (k * 91u) & 255u, (k * 13u + 128u) & 255u);
            else if (mode == 3) c = k & 255u;
            else c = k & 15u;
            sgx->fb_fill_rect(x, y, 40, 16, c);
        }
}
static void bitmap_pattern(void) {
    for (int i = 0; i < 256; i++) sgx->bm_palette(i, sgx->rgb((unsigned)i, 255u - (unsigned)i, (unsigned)(i * 5) & 255u));
    uint8_t *v = sgx->bm_vram();
    if (!v) return;
    for (unsigned y = 0; y < 200u; y++) for (unsigned x = 0; x < 320u; x++) v[y * 320u + x] = (uint8_t)((x ^ y) + y);
}
static const char *setup_screen(int mode) {
    // ローレゾの絵は 2KB ほどなので、ローレゾ面は小さく（16KB）開く。大きく開くと VGM の合成の区画を借りて、曲が鳴らせなかった（music -9）。
    // 音のありなしで同じ条件にするため、いつもこの印で開く
    // 【2026-11-20 ユーザー指示】ローレゾのモードは全部 BG 1 面で開く（ABI 5.15 の SGX_MODE_LR_ONE_BG。マップの 8KB が空き、ローレゾ面と
    // テキスト面を出したまま倍精度の配列 82KB を SRAM に取れる。2 面では 524 B しか残らず、倍精度の SRAM が n/a だった）
    const char *e = sgx->set_mode(mode_has_lr(mode) ? (mode | SGX_MODE_LR_SMALL | SGX_MODE_LR_ONE_BG) : mode);
    if (e) return e;
    if (mode_has_text(mode)) sgx->text_clear(SGX_T_FG(7) | SGX_T_BG(0) | SGX_T_BG_TRANS);
    if (mode >= 2 && mode <= 4) fb_pattern(mode);
    if (mode_has_lr(mode)) lowres_init();
    if (mode == 7) bitmap_pattern();
    return NULL;
}

// ---- 計算のタスク ----
// 1 つの組み合わせで 6 つを測る: 整数（Dhrystone）・単精度・倍精度（Linpack）を、データの置き場 SRAM と PSRAM のそれぞれで（2026-11-20、
// ユーザー指示）。SRAM のときは、データ（Linpack の配列・Dhrystone のレコード）と計算のタスクのスタックを SRAM に置き、その計測の間だけ取る。
// 取れなければ「測れない」（-1、一覧では n/a）にして、PSRAM の数を入れない。プログラムのコードと Dhrystone のグローバルの配列は、
// どちらでもプログラムの像（PSRAM、キャッシュを通る）にある
enum { JOB_DHRY = 1, JOB_SP, JOB_DP };
enum { MEM_SRAM = 0, MEM_PSRAM = 1 };
#define N_A        (-1.0)
#define TASK_STACK 1024u                       // 実測で最大 604 B（倍精度、浮動小数点のレジスタの退避込み）。2026-11-20 に 2KB -> 1KB（ローレゾ面と
                                                        // 倍精度の配列 82KB を取ると、2KB の塊が残らなかった）。8KB では倍精度の配列 82KB を
                                                        // SRAM に取ったあとスタックの塊が残らなかった（2026-11-20）。2KB はファームの最小
static volatile int c_job;
static volatile bool c_stop, c_fail;
static volatile double c_work;
static volatile uint64_t c_wall_us, c_kernel_us;
static void *c_mem;                                     // この計測のデータの置き場
static void *lp_psram, *dhry_psram;                     // PSRAM の置き場（起動のときに取る）
static uint64_t clock_us(void) { return sgx->us(); }
static void compute_task(void *arg) {
    (void)arg;
    const uint64_t t0 = sgx->us();
    double work = 0;
    uint64_t kus = 0;
    if (!c_mem) { c_fail = true; return; }
    if (c_job == JOB_DHRY) {
        int runs = 2000;
        while (!c_stop) {
            const uint64_t a = sgx->us();
            bench_dhry_runs(runs, c_mem);
            const uint64_t d = sgx->us() - a;
            work += runs;
            c_work = work; c_wall_us = sgx->us() - t0;
            if (d < 20000u && runs < 4000000) runs *= 2;      // 1 回 20ms ほどに（止める頼みに早く応える）
        }
    } else {
        while (!c_stop) {
            work += c_job == JOB_SP ? bench_lp_sp(c_mem, clock_us, &kus) : bench_lp_dp(c_mem, clock_us, &kus);
            c_work = work; c_kernel_us = kus; c_wall_us = sgx->us() - t0;
        }
    }
}

// ---- 1 回の計測 ----
// 値は [MEM_SRAM / MEM_PSRAM]。Dhrystone は Dhrystones/秒、Linpack は MFLOPS。N_A = SRAM が取れず測れない
// na_need / na_largest: SRAM が取れずに測れなかったとき、要った大きさ（データ + スタック）と SRAM の最大の塊（[整数, 単精度, 倍精度]、0 = 測れた）
typedef struct { double dhry[2], sp[2], dp[2]; unsigned mload; uint32_t underrun, fifo; uint32_t na_need[3], na_largest[3]; bool ok; } result_t;
static double dmips_of(double d) { return d < 0 ? N_A : d / 1757.0; }
static unsigned cfg_secs = 5;                 // 1 つの測定の秒数（6 つで合計 30 秒。2026-11-20 ユーザー指示: 以前は 30 秒ずつ）
static volatile bool user_abort;

static bool poll_abort(void) {
    int k;
    while ((k = sgx->key(false)) >= 0) if ((k & 0xFF) == SGX_KEY_ESC) user_abort = true;
    return user_abort || sgx->stop_requested();
}

static uint32_t mload_sum, mload_n;
static void *c_pre;                                     // 組み合わせの初めに取っておいた SRAM の置き場（倍精度の大きさ。無ければ NULL）
static void *c_stk;                                     // 同じく、計算のタスクのスタックの分の置き場（タスクを作る直前に返して、スタックをそこへ入れる）
static uint32_t na_need, na_largest;                    // 直前の run_job が SRAM を取れなかったときの数
static double run_job(int job, int mem, int music, int mode) {
    const uint32_t need = job == JOB_DHRY ? BENCH_DHRY_POOL : job == JOB_SP ? BENCH_LP_WORK_SP : BENCH_LP_WORK_DP;
    const bool sram = mem == MEM_SRAM;
    void *buf;
    na_need = na_largest = 0;
    if (sram) {                                         // SRAM: データとスタックの両方が取れるときだけ測る（取れなければ黙って PSRAM にしない）
        if (c_stk) { sgx->sram_free(c_stk); c_stk = NULL; }   // スタックの分を空ける（2026-11-20: ローレゾ面が残りを使い、2KB が取れなかった）
        if (c_pre && sgx->sram_largest() < TASK_STACK + 128u) {
            // 取っておいた置き場のせいでスタックが取れない（ローレゾ面などが残りを使った）: 返して、計測ごとに取る段取りに戻す（2026-11-20。
            // ローレゾのモードの音なしで、整数も含めて全部 n/a になっていた）
            sgx->sram_free(c_pre); c_pre = NULL;
            logf_("[cpubench] mode %d music %s: no room for the task stack, SRAM work area now per test", mode, MUSIC_TAG[music]);
        }
        buf = c_pre ? c_pre : sgx->sram_alloc(need, 32);   // 取っておいた置き場があればそれを使い回す（2026-11-20）
        const uint32_t largest = sgx->sram_largest();
        if (!buf || largest < TASK_STACK + 128u) {
            na_need = (buf ? 0u : need) + TASK_STACK; na_largest = largest;   // 足りなかったもの（データ + スタック、データが取れていればスタックだけ）
            logf_("CPUBENCH n/a mode=%d music=%s job=%s: no SRAM (need %lu + %u stack, largest %lu)", mode, MUSIC_TAG[music],
                  job == JOB_DHRY ? "dhrystone" : job == JOB_SP ? "sp" : "dp", (unsigned long)need, TASK_STACK, (unsigned long)largest);
            if (buf && buf != c_pre) sgx->sram_free(buf);
            return N_A;
        }
    } else buf = job == JOB_DHRY ? dhry_psram : lp_psram;
    c_job = job; c_mem = buf; c_stop = false; c_fail = false; c_work = 0; c_wall_us = 0; c_kernel_us = 0;
    // 優先度 2（= 11）: 音楽（9）と、MP3 などの先読みのタスク（10）より下。1（= 10）では先読みと同じ優先度になり、眠らずに回る計算が
    // 先読みに順番を回さず、MP3 がデータを待って音の負荷が 246〜379% になった（2026-11-20。VGM は丸ごとメモリに置くので起きなかった）
    sgx_task_t *t = sgx->task_create(compute_task, NULL, TASK_STACK, 2, sram, "cpubench");
    if (!t) { if (sram && buf != c_pre) sgx->sram_free(buf); return N_A; }
    const uint32_t start = sgx->ms();
    uint32_t next = start;
    // 計っている間、画面には何もしない（オブジェクトも BG のスクロールも動かさず、文字も書き換えない。2026-11-20 ユーザー指示:
    // 負荷は「表示そのもの」と音だけ）。メインはフレームを待ってキー（ESC）と音の負荷を見るだけ
    while (sgx->ms() - start < cfg_secs * 1000u && !poll_abort()) {
        sgx->wait_frames(1);
        if ((int32_t)(sgx->ms() - next) >= 0) {
            next += 500u;
            if (music) { sgx_music_info_t mi; sgx->music_info(&mi); mload_sum += mi.load_pct; mload_n++; }
        }
    }
    {                                                   // 計算のタスクのスタックの使った量をログへ（スタックの大きさを決めるため）
        static sgx_task_info_t ti[24];
        const unsigned n = sgx->task_info ? sgx->task_info(ti, 24) : 0u;
        for (unsigned i = 0; i < n; i++)
            if (!strcmp(ti[i].name, "cpubench")) logf_("[cpubench] job %d mem %s: stack used %lu of %lu", job, sram ? "sram" : "psram",
                                                       (unsigned long)(ti[i].stack_size - ti[i].stack_unused), (unsigned long)ti[i].stack_size);
    }
    c_stop = true;
    sgx->task_join(t, 10000000u);
    if (sram && buf != c_pre) sgx->sram_free(buf);
    sgx->wait_frames(3);
    if (c_pre && !c_stk) c_stk = sgx->sram_alloc(TASK_STACK + 128u, 32);   // スタックが返ったら、次の計測のために取り直す
                                                        // 終わったタスクのスタックは、ファームが次に片付けるとき（reap、ほぼ毎フレーム）に返る。
                                                        // すぐ次の計測の SRAM を取りに行くと、前のスタック（SRAM 8KB）がまだ残っていた
    if (c_fail) return N_A;
    // 時間内に 1 回も終わらなかった（重い負荷で計算にほとんど時間が回らない）のは 0。失敗ではない
    if (!c_wall_us || c_work <= 0) return 0.0;
    if (job == JOB_DHRY) return c_work * 1e6 / (double)c_wall_us;
    return c_kernel_us ? c_work / (double)c_kernel_us : 0.0;    // 演算の数 / µs = MFLOPS
}

static void stamp(char *b, size_t n) {                  // 日本時間の yyyy-mm-dd hh:mm
    int64_t s = (int64_t)(sgx->utc_us() / 1000000u) + 9 * 3600;
    int64_t days = s / 86400; int sec = (int)(s % 86400);
    int64_t z = days + 719468, era = (z >= 0 ? z : z - 146096) / 146097;
    unsigned doe = (unsigned)(z - era * 146097), yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int y = (int)(yoe + era * 400); unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100), mp = (5 * doy + 2) / 153;
    unsigned d = doy - (153 * mp + 2) / 5 + 1, m = mp < 10 ? mp + 3 : mp - 9;
    if (m <= 2) y++;
    snprintf(b, n, "%04d-%02u-%02u %02d:%02d", y, m, d, sec / 3600, (sec / 60) % 60);
}

static const char *fv(char *b, size_t n, double v, int prec) {   // 値の文字（N_A は空 = n/a）
    if (v < 0) b[0] = 0; else snprintf(b, n, "%.*f", prec, v);
    return b;
}

// CSV（2 版、2026-11-20）: SRAM と PSRAM のそれぞれの値。測れないものは空。見出しが違う古いファイルは cpubench_v1.csv に写して新しく始める
static const char CSV_HEAD[] = "date,mode,music,secs,dmips_sram,dmips_psram,sp_sram,sp_psram,dp_sram,dp_psram,"
                               "dhrystones_sram,dhrystones_psram,music_load_pct,underrun,fifo_stall\n";
static void csv_append(int mode, int music, const result_t *r) {
    static char buf[CSV_MAX + 512];
    uint32_t got = 0;
    if (sgx->read_file(CSV_PATH, buf, CSV_MAX, &got)) got = 0;
    buf[got] = 0;
    if (got && strncmp(buf, CSV_HEAD, sizeof CSV_HEAD - 1u)) {    // 古い形: 写して残し、新しく始める
        const int e = sgx->write_file("S:/SystemLogs/cpubench_v1.csv", buf, got);
        logf_("[cpubench] the old results went to cpubench_v1.csv (%d)", e);
        got = 0;
    }
    if (!got) { memcpy(buf, CSV_HEAD, sizeof CSV_HEAD - 1u); got = sizeof CSV_HEAD - 1u; }
    while (got > CSV_MAX - 256u) {                      // 古い行（見出しの次）から捨てる
        char *l1 = strchr(buf, '\n'); if (!l1) break;
        char *l2 = strchr(l1 + 1, '\n'); if (!l2) break;
        memmove(l1 + 1, l2 + 1, got - (uint32_t)(l2 + 1 - buf) + 1u);
        got -= (uint32_t)(l2 - l1);
    }
    char d[24], v[10][16]; stamp(d, sizeof d);
    got += (uint32_t)snprintf(buf + got, sizeof buf - got, "%s,%d,%s,%u,%s,%s,%s,%s,%s,%s,%s,%s,%u,%lu,%lu\n", d, mode, MUSIC_TAG[music], cfg_secs,
                              fv(v[0], 16, dmips_of(r->dhry[0]), 1), fv(v[1], 16, dmips_of(r->dhry[1]), 1),
                              fv(v[2], 16, r->sp[0], 2), fv(v[3], 16, r->sp[1], 2), fv(v[4], 16, r->dp[0], 2), fv(v[5], 16, r->dp[1], 2),
                              fv(v[6], 16, r->dhry[0], 0), fv(v[7], 16, r->dhry[1], 0), r->mload, (unsigned long)r->underrun, (unsigned long)r->fifo);
    const int e = sgx->write_file(CSV_PATH, buf, got);
    if (e) logf_("[cpubench] could not write %s (%d %s)", CSV_PATH, e, sgx->strerror(e));
}

static bool music_file_ok(int music) {
    if (!music) return true;
    sgx_stat_t st;
    return sgx->stat(music == 1 ? mp3_path : vgm_path, &st) == 0;
}

static char last_why[120];                              // うまくいかなかった訳（メニューに出す）
static bool measure(int mode, int music, result_t *r) {
    memset(r, 0, sizeof *r);
    last_why[0] = 0;
    // テキスト面を消してから（字の置き場の SRAM を返す。メニューの字が残っていると、ローレゾ面が VGM の合成の区画を借りて曲が鳴らせなかった）、
    // いつもモード 0 を通ってから選んだモードへ（どの組み合わせも同じ状態から。2026-11-20 ユーザー指示）
    sgx->text_clear(A_NORM);
    // 前の組み合わせのローレゾ面・ビットマップも返す（ABI 5.14）。テキスト面もいったん閉じる（2026-11-21: メニューで使った字の行
    // （1 行 1,284 B）が空きの真ん中に 7 つ残り、VGM を鳴らすと SRAM の最大の塊が 26KB に割れて単精度の 42KB が取れなかった。
    // テキストのあるモードは、この後の set_mode でまっさらに開き直す）
    sgx->set_mode(0 | SGX_MODE_CLOSE_PLANES | SGX_MODE_NO_TEXT);
    sgx->wait_frames(10);
    // SRAM の置き場（倍精度の大きさ）を、曲を鳴らす前に取っておき、SRAM の 3 つの計測で使い回す（2026-11-20）。曲を鳴らしたあとに取ると、
    // MP3 を読む受け場（16KB）が VGM の区画の上の空きに入って塊を割り、倍精度の 82KB が取れなかった。持ったままでは曲が鳴らない・
    // 画面モードが開けないとき（VGM の合成の区画やローレゾ面の SRAM がぶつかる）は、返して今までの段取り（計測ごとに取る）でやり直す
    c_pre = sgx->sram_alloc(BENCH_LP_WORK_DP, 32);
    if (music) {                                        // 曲を先に鳴らす（合成の区画を先に取る。あとで開くローレゾ面はそれを借りない）
        int me = sgx->music_play(music == 1 ? mp3_path : vgm_path, SGX_MUSIC_LOOP);
        if (me < 0 && c_pre) {                          // 置き場が VGM の合成の区画を借りていた: 返してもう一度
            sgx->sram_free(c_pre); c_pre = NULL;
            if (c_stk) { sgx->sram_free(c_stk); c_stk = NULL; }
            me = sgx->music_play(music == 1 ? mp3_path : vgm_path, SGX_MUSIC_LOOP);
        }
        if (me < 0) {
            sgx_music_info_t mi; sgx->music_info(&mi);
            snprintf(last_why, sizeof last_why, "%s: %s", T("could not play the music"), mi.error[0] ? mi.error : sgx->strerror(me));
            logf_("CPUBENCH mode=%d music=%s FAILED: music %d %s", mode, MUSIC_TAG[music], me, mi.error);
            return false;
        }
        sgx->sleep_us(1000000);                         // 鳴り始め（読み込み・展開）を測りに入れない
    }
    const char *e = setup_screen(mode);
    if (e && c_pre) {                                   // 置き場がローレゾ面などの SRAM とぶつかった: 返してもう一度
        sgx->sram_free(c_pre); c_pre = NULL;
        if (c_stk) { sgx->sram_free(c_stk); c_stk = NULL; }
        e = setup_screen(mode);
    }
    logf_("[cpubench] mode %d music %s: SRAM work area %s", mode, MUSIC_TAG[music], c_pre ? "taken before the music" : "per test");
    if (c_pre) c_stk = sgx->sram_alloc(TASK_STACK + 128u, 32);   // 画面を開いたあと、スタックの分を取っておく（先に取るとローレゾ面が開けなかった）
    logf_("[cpubench] SRAM largest after the screen: %lu, stack room %s", (unsigned long)sgx->sram_largest(), c_stk ? "kept" : "none");
    if (e) {
        if (music) sgx->music_stop();
        snprintf(last_why, sizeof last_why, "%s: %s", T("could not set the screen mode"), e);
        logf_("CPUBENCH mode=%d music=%s FAILED: %s", mode, MUSIC_TAG[music], e);
        return false;
    }
    if (mode_has_text(mode))                            // 何を計っているかは始める前に 1 回だけ書く（途中では書き換えない）
        row_text(0, A_RUN, " CPUBENCH  %s  |  %s  |  %u s x 6   (ESC: %s)", T(MODE_NAME[mode]), T(MUSIC_NAME[music]), cfg_secs, T("stop"));
    sgx->wait_frames(30);                               // 選んだモードへの切り替えが落ち着いてから計算を始める
    sgx_video_info_t v0, v1;
    sgx->video_info(&v0);
    mload_sum = mload_n = 0;
    double *const slot[3] = { r->dhry, r->sp, r->dp };
    for (int j = 0; j < 3; j++)
        for (int m = 0; m < 2; m++) {
            slot[j][m] = user_abort ? N_A : run_job(JOB_DHRY + j, m, music, mode);
            if (m == MEM_SRAM && slot[j][m] < 0 && !user_abort) { r->na_need[j] = na_need; r->na_largest[j] = na_largest; }
        }
    sgx->video_info(&v1);
    if (music) sgx->music_stop();
    if (c_pre) { sgx->sram_free(c_pre); c_pre = NULL; }
    if (c_stk) { sgx->sram_free(c_stk); c_stk = NULL; }
    r->mload = mload_n ? mload_sum / mload_n : 0;
    r->underrun = v1.underrun - v0.underrun; r->fifo = v1.fifo_stall - v0.fifo_stall;
    r->ok = !user_abort;
    logf_("CPUBENCH mode=%d music=%s secs=%u dmips=%.1f/%.1f sp_mflops=%.2f/%.2f dp_mflops=%.2f/%.2f (sram/psram, -1 = n/a) music_load=%u underrun=%lu fifo_stall=%lu%s",
          mode, MUSIC_TAG[music], cfg_secs, dmips_of(r->dhry[0]), dmips_of(r->dhry[1]), r->sp[0], r->sp[1], r->dp[0], r->dp[1], r->mload,
          (unsigned long)r->underrun, (unsigned long)r->fifo, r->ok ? "" : " (stopped)");
    if (r->ok) csv_append(mode, music, r);
    return r->ok;
}

// CSV の 1 行を項目に分ける（line は書き換える）。数は strtod で読む: newlib-nano の sscanf は %lf を組み込まず、一覧が空になった
enum { F_DATE, F_MODE, F_MUSIC, F_SECS, F_DMS, F_DMP, F_SPS, F_SPP, F_DPS, F_DPP, F_DHS, F_DHP, F_MLOAD, F_UNDER, F_FIFO, F_N };
static bool csv_split(char *line, char *f[F_N]) {
    unsigned n = 0;
    for (char *p = line; n < F_N; ) {
        f[n++] = p;
        char *c = strchr(p, ',');
        if (!c) break;
        *c = 0; p = c + 1;
    }
    return n >= F_DPP + 1u && f[F_DATE][0] >= '0' && f[F_DATE][0] <= '9';
}
static double csv_num(const char *s) { return s[0] ? strtod(s, NULL) : N_A; }
static int csv_music(const char *m) { return !strcmp(m, "mp3") ? 1 : !strcmp(m, "vgm") ? 2 : 0; }

// 負荷なし（モード 0・音なし）の最新の値 [DMIPS S/P, SP S/P, DP S/P]（無ければ N_A）
static void csv_baseline(double b[6]) {
    static char buf[CSV_MAX + 1];
    uint32_t got = 0;
    for (int i = 0; i < 6; i++) b[i] = N_A;
    if (sgx->read_file(CSV_PATH, buf, CSV_MAX, &got)) return;
    buf[got] = 0;
    if (strncmp(buf, CSV_HEAD, sizeof CSV_HEAD - 1u)) return;
    for (char *l = buf; l && *l; ) {
        char *nx = strchr(l, '\n');
        if (nx) *nx = 0;
        char *f[F_N];
        if (csv_split(l, f) && atoi(f[F_MODE]) == 0 && csv_music(f[F_MUSIC]) == 0)
            for (int i = 0; i < 6; i++) b[i] = csv_num(f[F_DMS + i]);
        l = nx ? nx + 1 : NULL;
    }
}
static const char *pct_of(char *o, size_t n, double v, double base) {   // 負荷なしとの比（どちらかが無ければ "-"）
    if (v < 0 || base <= 0) snprintf(o, n, "-"); else snprintf(o, n, "%.0f%%", v * 100.0 / base);
    return o;
}
static const char *num_or_na(char *o, size_t n, double v, int prec) { if (v < 0) snprintf(o, n, "n/a"); else snprintf(o, n, "%.*f", prec, v); return o; }

// SRAM 不足の理由（n/a のとき、要った大きさと SRAM の最大の塊を KB で）。無ければ空
static const char *na_text(char *o, size_t n, const result_t *r) {
    static const char *const nm[3] = { "int", "SP", "DP" };
    size_t k = 0; o[0] = 0;
    for (int j = 0; j < 3 && k + 1 < n; j++)
        if (r->na_need[j]) k += (size_t)snprintf(o + k, n - k, "%s%s: need %lu KB, largest %lu KB", k ? "; " : "", nm[j],
                                                 (unsigned long)((r->na_need[j] + 1023u) / 1024u), (unsigned long)(r->na_largest[j] / 1024u));
    return o;
}

// 大きな文字（縦横倍角: 1 字が 2x2 のセル、1 行 40 字）
#define A_BIG(fg) (SGX_T_FG(fg) | SGX_T_BG(0) | SGX_T_DH | SGX_T_DW)
static void big_text(unsigned row, unsigned col, uint32_t attr, const char *fmt, ...) {
    char b[64];
    va_list ap; va_start(ap, fmt);
    sgx->vsnprintf(b, sizeof b, fmt, ap);
    va_end(ap);
    sgx->text_puts(col, row, b, attr);
}

// 始める前のカウントダウン（3, 2, 1。2026-11-20 ユーザー指示）。false = ESC でやめた
static bool countdown(const char *what) {
    sgx->set_mode(1 | SGX_MODE_CLOSE_PLANES);
    sgx->text_clear(A_NORM);
    row_text(0, A_HEAD, " SGNANO CPU BENCH");
    row_text(4, A_NORM, "  %s", what);
    row_text(6, A_DIM, "  %s", T("The screen may go dark while measuring. The computation is running."));
    row_text(27, A_DIM, "  %s", T("ESC: stop"));
    for (int n = 3; n >= 1; n--) {
        big_text(12, 38, A_BIG(14), "%d", n);
        for (int f = 0; f < 60; f++) { sgx->wait_frames(1); if (poll_abort()) return false; }
    }
    return true;
}

// 結果を大きな文字で（何かキーでメニューへ）。3 行（DMIPS・単精度・倍精度）に SRAM と PSRAM の 2 つの値
static void show_big_result(int mode, int music, const result_t *r) {
    double b[6];
    csv_baseline(b);
    sgx->set_mode(1 | SGX_MODE_CLOSE_PLANES);           // ローレゾ面を返す（返さないと字の置き場が取れず、行が欠けた。ABI 5.14）
    sgx->text_clear(A_NORM);
    row_text(0, A_HEAD, " SGNANO CPU BENCH  --  %s", T("result"));
    row_text(2, A_NORM, "  %s: %s", T("Screen mode"), T(MODE_NAME[mode]));
    row_text(3, A_NORM, "  %s: %s   %s %u%%   %u s x 6", T("Music"), T(MUSIC_NAME[music]), T("music load"), r->mload, cfg_secs);
    row_text(5, A_HEAD, "%22s%-18s%-30s", "", "SRAM", "PSRAM");
    const double v[3][2] = { { dmips_of(r->dhry[0]), dmips_of(r->dhry[1]) }, { r->sp[0], r->sp[1] }, { r->dp[0], r->dp[1] } };
    static const char *const name[3] = { "DMIPS", "SP MF", "DP MF" };
    static const char *const note[3] = { "Dhrystone 2.1 (DMIPS = VAX MIPS)", "Linpack single precision (float, FPU)", "Linpack double precision (double, DCP)" };
    static const int prec[3] = { 1, 2, 2 }, fg[3] = { 15, 14, 10 };
    for (int i = 0; i < 3; i++) {
        char a[16], c[16], p0[8], p1[8];
        big_text(6u + 4u * (unsigned)i, 2, A_BIG(fg[i]), "%-6s%8s %8s", name[i], num_or_na(a, sizeof a, v[i][0], prec[i]), num_or_na(c, sizeof c, v[i][1], prec[i]));
        row_text(8u + 4u * (unsigned)i, A_DIM, "    %-38s %s %s / %s", T(note[i]), T("vs no load"),
                 pct_of(p0, sizeof p0, v[i][0], b[i * 2]), pct_of(p1, sizeof p1, v[i][1], b[i * 2 + 1]));
    }
    row_text(19, A_NORM, "  %s %lu   fifo_stall %lu", T("display: underrun"), (unsigned long)r->underrun, (unsigned long)r->fifo);
    row_text(21, A_DIM, "  %s", T("SRAM = the data and the task stack in SRAM. PSRAM = in PSRAM. The program code is in PSRAM for both."));
    char why[160];
    if (na_text(why, sizeof why, r)[0]) row_text(22, SGX_T_FG(12) | SGX_T_BG(0), "  %s %s", T("n/a = not enough SRAM:"), why);
    row_text(27, A_DIM, "  %s", T("press any key"));
    while (sgx->key(true) < 0 && !sgx->stop_requested()) {}
}

// ---- メニューと結果の一覧 ----
static int sel, cfg_mode = 5, cfg_music = 2;
enum { M_MODE, M_MUSIC, M_SECS, M_RUN, M_ALL, M_CLEAR, M_QUIT, M_N };
static const unsigned SECS_CHOICE[] = { 5, 10, 30, 60 };
#define N_SECS 4u

static void show_results(unsigned top) {
    static char buf[CSV_MAX + 1];
    uint32_t got = 0;
    if (sgx->read_file(CSV_PATH, buf, CSV_MAX, &got)) got = 0;
    buf[got] = 0;
    if (got && strncmp(buf, CSV_HEAD, sizeof CSV_HEAD - 1u)) got = 0, buf[0] = 0;   // 古い形は出さない（次に測ると cpubench_v1.csv へ写す）
    const unsigned rows = sgx->text_rows();
    row_text(top, A_HEAD, " %-16s %-9s %7s %7s  %6s %6s  %6s %6s %5s", T("date"), T("load"), "DMIPS:S", "P", "SP:S", "P", "DP:S", "P", T("vs 0"));
    double b[6];
    csv_baseline(b);
    char *lines[200]; unsigned nl = 0;
    for (char *p = strchr(buf, '\n'); p && nl < 200; p = strchr(p + 1, '\n')) { *p = 0; if (p[1]) lines[nl++] = p + 1; }
    unsigned r = top + 1u;
    for (int i = (int)nl - 1; i >= 0 && r < rows; i--, r++) {
        char *f[F_N];
        if (!csv_split(lines[i], f)) { r--; continue; }
        const int mode = atoi(f[F_MODE]), mi = csv_music(f[F_MUSIC]);
        char load[16], c[6][12], pc[8];
        snprintf(load, sizeof load, "%d/%s", mode, mi == 2 ? "VGM" : mi == 1 ? "MP3" : T("none"));
        for (int k2 = 0; k2 < 6; k2++) num_or_na(c[k2], sizeof c[k2], csv_num(f[F_DMS + k2]), k2 < 2 ? 1 : 2);
        row_text(r, (mode == 0 && mi == 0) ? A_GOOD : A_NORM, " %-16s %-9s %7s %7s  %6s %6s  %6s %6s %5s", f[F_DATE], load,
                 c[0], c[1], c[2], c[3], c[4], c[5], pct_of(pc, sizeof pc, csv_num(f[F_DMS]), b[0]));
    }
    for (; r < rows; r++) row_text(r, A_NORM, "");
    if (!nl) row_text(top + 2u, A_DIM, "   %s", T("no results yet -- choose the load and run"));
}

static void draw_menu(void) {
    row_text(0, A_HEAD, " SGNANO CPU BENCH  --  Dhrystone 2.1 / Linpack (n = 100)  @ %.1f MHz", CPU_MHZ);
    char v[3][100];
    snprintf(v[0], sizeof v[0], "%s", T(MODE_NAME[cfg_mode]));
    snprintf(v[1], sizeof v[1], "%s%s", T(MUSIC_NAME[cfg_music]), music_file_ok(cfg_music) ? "" : T("  (file not found)"));
    snprintf(v[2], sizeof v[2], "%u s x 6", cfg_secs);
    const char *lab[M_N] = { T("Screen mode"), T("Music"), T("Time per test"), T("Run"), T("Run all (8 modes x 3 music)"), T("Clear the results"), T("Quit") };
    for (int i = 0; i < M_N; i++) {
        const uint32_t a = i == sel ? A_SEL : A_NORM;
        if (i < 3) row_text(2u + (unsigned)i, a, "  %-22s < %s >", lab[i], v[i]);
        else row_text(2u + (unsigned)i, a, "  %s", lab[i]);
    }
    // 案内は 1 行目にまとめ、9 行目は空ける（知らせを出すときだけ使う）。結果の一覧は 10 行目から（2026-11-20 ユーザー指示: 3 行増やす）
    row_text(1, A_DIM, "  %s", T("Up/Down/Left/Right: choose  Enter: run  ESC: quit   S = SRAM, P = PSRAM"));
    row_text(9, A_NORM, "");
    show_results(10);
}

static void menu_screen(void) {
    sgx->set_mode(1 | SGX_MODE_CLOSE_PLANES);
    sgx->text_clear(A_NORM);
    draw_menu();
}

static void run_and_show(int mode, int music) {
    result_t r;
    user_abort = false;
    char what[160];
    snprintf(what, sizeof what, "%s  /  %s  /  %u s x 6", T(MODE_NAME[mode]), T(MUSIC_NAME[music]), cfg_secs);
    if (!countdown(what)) { menu_screen(); row_text(9, SGX_T_FG(12) | SGX_T_BG(0), "  %s", T("stopped")); return; }
    const bool ok = measure(mode, music, &r);
    if (ok) show_big_result(mode, music, &r);
    menu_screen();
    if (!ok) row_text(9, SGX_T_FG(12) | SGX_T_BG(0), "  %s", user_abort ? T("stopped") : last_why[0] ? last_why : T("could not run this combination (see the log)"));
}

// 「全部の組み合わせ」の報告を S:/SystemLogs/cpubench_日付_時刻.txt に書く（2026-11-20、ユーザー指示）。読みやすい表で、
// 負荷なし（この回のモード 0・音なし）との比も。n/a が残っていれば頭にその数
typedef struct { int mode, music; bool done; result_t r; } combo_t;
static combo_t combos[N_MODES * N_MUSIC];
static void write_report(void) {
    static char buf[16 * 1024];
    char d[24], name[64]; stamp(d, sizeof d);
    snprintf(name, sizeof name, "S:/SystemLogs/cpubench_%.4s%.2s%.2s_%.2s%.2s.txt", d, d + 5, d + 8, d + 11, d + 14);
    const result_t *base = NULL;
    unsigned na = 0;
    for (unsigned i = 0; i < N_MODES * N_MUSIC; i++) {
        if (!combos[i].done) continue;
        if (combos[i].mode == 0 && combos[i].music == 0) base = &combos[i].r;
        const result_t *r = &combos[i].r;
        for (int m = 0; m < 2; m++) na += (r->dhry[m] < 0) + (r->sp[m] < 0) + (r->dp[m] < 0);
    }
    int n = snprintf(buf, sizeof buf,
        "SGNANO CPU BENCH report  %s\n"
        "clk_sys %.1f MHz, %u s per test, Dhrystone 2.1 (DMIPS = VAX MIPS = Dhrystones/s / 1757), Linpack n = 100 (MFLOPS)\n"
        "S = data and task stack in SRAM, P = in PSRAM (the program code is in PSRAM for both). n/a = not enough SRAM (the line below says how much). %% = against mode 0 with no music.\n"
        "n/a in this run: %u\n\n"
        "%-30s %-5s %8s %8s %8s %8s %8s %8s  %6s %6s %6s  %5s %8s %10s\n",
        d, CPU_MHZ, cfg_secs, na, "screen mode", "music", "DMIPS S", "DMIPS P", "SP S", "SP P", "DP S", "DP P", "DM S%", "SP S%", "DP S%", "load", "underrun", "fifo_stall");
    for (unsigned i = 0; i < N_MODES * N_MUSIC && n > 0 && n < (int)sizeof buf - 200; i++) {
        if (!combos[i].done) continue;
        const result_t *r = &combos[i].r;
        char v[6][12], p[3][8];
        num_or_na(v[0], 12, dmips_of(r->dhry[0]), 1); num_or_na(v[1], 12, dmips_of(r->dhry[1]), 1);
        num_or_na(v[2], 12, r->sp[0], 2); num_or_na(v[3], 12, r->sp[1], 2); num_or_na(v[4], 12, r->dp[0], 2); num_or_na(v[5], 12, r->dp[1], 2);
        pct_of(p[0], 8, dmips_of(r->dhry[0]), base ? dmips_of(base->dhry[0]) : N_A);
        pct_of(p[1], 8, r->sp[0], base ? base->sp[0] : N_A);
        pct_of(p[2], 8, r->dp[0], base ? base->dp[0] : N_A);
        n += snprintf(buf + n, sizeof buf - (size_t)n, "%-30s %-5s %8s %8s %8s %8s %8s %8s  %6s %6s %6s  %4u%% %8lu %10lu\n",
                      MODE_NAME[combos[i].mode], MUSIC_TAG[combos[i].music], v[0], v[1], v[2], v[3], v[4], v[5], p[0], p[1], p[2],
                      r->mload, (unsigned long)r->underrun, (unsigned long)r->fifo);
        char why[160];
        if (na_text(why, sizeof why, r)[0] && n < (int)sizeof buf - 200) n += snprintf(buf + n, sizeof buf - (size_t)n, "    n/a (not enough SRAM): %s\n", why);
    }
    const int e = sgx->write_file(name, buf, (uint32_t)n);
    logf_("[cpubench] report %s (%d bytes, n/a %u): %s", name, n, na, e ? sgx->strerror(e) : "ok");
}

static void run_all(void) {
    user_abort = false;
    unsigned done = 0, skipped = 0;
    memset(combos, 0, sizeof combos);
    if (!countdown(T("Run all (8 modes x 3 music)"))) { menu_screen(); return; }   // カウントダウンは最初の 1 回だけ（組み合わせごとにモード 0 は通る）
    for (int m = 0; m < N_MODES && !user_abort; m++)
        for (int mu = 0; mu < N_MUSIC && !user_abort; mu++) {
            if (!music_file_ok(mu)) { skipped++; continue; }
            combo_t *c = &combos[m * N_MUSIC + mu];
            c->mode = m; c->music = mu;
            if (measure(m, mu, &c->r)) { done++; c->done = true; } else if (!user_abort) skipped++;
        }
    if (done && !user_abort) write_report();
    menu_screen();
    row_text(9, user_abort ? SGX_T_FG(12) | SGX_T_BG(0) : A_GOOD, "  %s: %u  %s: %u%s", T("measured"), done, T("skipped"), skipped,
             user_abort ? T("  (stopped)") : "");
}

int sgx_main(const sgx_api_t *api, int argc, char **argv) {
    (void)api;
    rs = sgx->random_seed() | 1u;
    const char *dir = sgx->program_dir ? sgx->program_dir() : "S:/bin";
    snprintf(vgm_path, sizeof vgm_path, "%s/skyward_pulse.vgz", dir);
    snprintf(mp3_path, sizeof mp3_path, "%s/skyward_pulse.mp3", dir);
    bool go = false;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "-vgm") && i + 1 < argc) snprintf(vgm_path, sizeof vgm_path, "%s", argv[++i]);
        else if (!strcmp(argv[i], "-mp3") && i + 1 < argc) snprintf(mp3_path, sizeof mp3_path, "%s", argv[++i]);
        else if (!strcmp(argv[i], "-m") && i + 1 < argc) cfg_mode = atoi(argv[++i]) % N_MODES;
        else if (!strcmp(argv[i], "-s") && i + 1 < argc) cfg_music = atoi(argv[++i]) % N_MUSIC;
        else if (!strcmp(argv[i], "-t") && i + 1 < argc) cfg_secs = (unsigned)atoi(argv[++i]);
        else if (!strcmp(argv[i], "-go")) go = true;            // 選んだ組み合わせを 1 回測って終わる（試し用）
    }
    if (cfg_secs < 1u) cfg_secs = 1u;
    lp_psram = sgx->psram_alloc(BENCH_LP_WORK_DP, 32);   // PSRAM の置き場（単精度もこれ。倍精度のほうが大きい）
    dhry_psram = sgx->psram_alloc(BENCH_DHRY_POOL, 32);
    if (!lp_psram || !dhry_psram) logf_("[cpubench] no PSRAM for the work areas");
    int rc = 0;
    if (go) { result_t r; user_abort = false; measure(cfg_mode, cfg_music, &r); rc = r.ok ? 0 : 1; goto out; }
    menu_screen();
    for (;;) {
        if (sgx->stop_requested()) break;
        const int k = sgx->key(true);
        if (k < 0) continue;
        const int c = k & 0xFF;
        if (c == SGX_KEY_ESC || c == 'q') break;
        if (c == SGX_KEY_UP) sel = (sel + M_N - 1) % M_N;
        else if (c == SGX_KEY_DOWN) sel = (sel + 1) % M_N;
        else if (c == SGX_KEY_LEFT || c == SGX_KEY_RIGHT) {
            const int d = c == SGX_KEY_RIGHT ? 1 : -1;
            if (sel == M_MODE) cfg_mode = (cfg_mode + N_MODES + d) % N_MODES;
            else if (sel == M_MUSIC) cfg_music = (cfg_music + N_MUSIC + d) % N_MUSIC;
            else if (sel == M_SECS) {
                unsigned i = 0; while (i < N_SECS && SECS_CHOICE[i] != cfg_secs) i++;
                if (i >= N_SECS) i = 0u;
                i = (i + N_SECS + (unsigned)d) % N_SECS; cfg_secs = SECS_CHOICE[i];
            }
        } else if (c == SGX_KEY_ENTER) {
            if (sel == M_RUN) { if (music_file_ok(cfg_music)) { run_and_show(cfg_mode, cfg_music); continue; } }
            else if (sel == M_ALL) { run_all(); continue; }
            else if (sel == M_CLEAR) sgx->remove(CSV_PATH);
            else if (sel == M_QUIT) break;
        }
        draw_menu();
    }
out:
    if (lp_psram) sgx->psram_free(lp_psram);
    if (dhry_psram) sgx->psram_free(dhry_psram);
    return rc;
}
