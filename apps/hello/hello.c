// SGX の試しのプログラム（2026-10-24、docs/sgx_abi.md）。端末に書き、画面モード 7 のビットマップに模様を描き、
// 音を鳴らし、自分のフォルダの一覧を出し、ファイルを書いて読み返す。キーで次へ、q で終わる
#include "sgx_api.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

extern const sgx_api_t *sgx;

static void say(const char *s) { sgx->term_write(s, (unsigned)strlen(s)); }

static void list_cb(const sgx_dirent_t *e, void *user) {
    (void)user;
    char b[160];
    snprintf(b, sizeof b, "  %s%.*s  %lu\n", e->is_dir ? "[D] " : "", (int)e->name_len, e->name, (unsigned long)e->size);
    say(b);
}

int sgx_main(const sgx_api_t *api, int argc, char **argv) {
    char b[200];
    snprintf(b, sizeof b, "hello from SGX (ABI %u.%u, table %lu bytes)\n", api->abi_major, api->abi_minor, (unsigned long)api->size);
    say(b);
    for (int i = 0; i < argc; i++) { snprintf(b, sizeof b, "  argv[%d] = %s\n", i, argv[i]); say(b); }
    snprintf(b, sizeof b, "folder %s, PSRAM largest %lu KB, SRAM largest %lu KB\n", api->program_dir(),
             (unsigned long)(api->psram_largest() / 1024u), (unsigned long)(api->sram_largest() / 1024u));
    say(b);
    // malloc（SDK の口）
    char *m = malloc(1000);
    snprintf(b, sizeof b, "malloc(1000) = %p\n", (void *)m);
    say(b);
    free(m);
    // フォルダの一覧
    say("files:\n");
    api->list(api->program_dir(), list_cb, NULL);
    // ファイルを書いて読み返す
    char path[160];
    snprintf(path, sizeof path, "%s/HELLO.TXT", api->program_dir());
    const char *text = "written by hello.sgx\n";
    int e = api->write_file(path, text, (uint32_t)strlen(text));
    char back[64] = { 0 };
    uint32_t got = 0;
    if (!e) e = api->read_file(path, back, sizeof back - 1u, &got);
    snprintf(b, sizeof b, "write and read %s: %s (%lu bytes) %s", path, api->strerror(e), (unsigned long)got, back);
    say(b);
    if (!e) api->remove(path);
    say("press a key for mode 7 (q: quit)\n");
    if (api->key(true) == 'q') return 0;
    // 画面モード 7: 模様と 2 枚の面
    const char *why = api->set_mode(SGX_MODE_TEXT_BM8);
    if (why) { say(why); say("\n"); return 1; }
    for (int i = 0; i < 256; i++) api->bm_palette(i, api->rgb((unsigned)i, (unsigned)(255 - i), (unsigned)((i * 3) & 255)));
    uint8_t *back_fb = api->bm_back();
    api->snd_open();
    api->snd_wave(0, SGX_WAVE_SQUARE);
    api->snd_note_on(0, 69, 100);
    uint32_t t0 = api->ms();
    unsigned frames = 0;
    // cppcheck-suppress [knownConditionTrueFalse, duplicateExpression]   // api->ms() は呼ぶたびに進む（関数の表なので道具は同じ値と見る）
    while (api->ms() - t0 < 3000u) {
        uint8_t *v = back_fb ? back_fb : api->bm_vram();
        const unsigned f = frames++;
        for (unsigned y = 0; y < SGX_BM_H; y++) for (unsigned x = 0; x < SGX_BM_W; x++) v[y * SGX_BM_W + x] = (uint8_t)(x + y + f);
        if (back_fb) api->bm_present(); else api->wait_frames(1);
    }
    api->snd_note_off(0);
    snprintf(b, sizeof b, "%u frames in 3 s (%s)\n", frames, back_fb ? "2 buffers" : "1 buffer");
    api->set_mode(SGX_MODE_TEXT);
    say(b);
    say("done -- press a key\n");
    api->key(true);
    return 0;
}
