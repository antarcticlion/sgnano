# SPEC_gfx: FB のプリミティブ描画の強化（2026-11-13、ユーザー指示）

画面モード 2・3・4（FB の RGB555 / CLUT8 / CLUT4）と 7（320x200x8 のビットマップ）へ、Windows の GDI に倣った
描画の一揃いを足す。**下回りは 1 つのライブラリ `src/gfx/`**（C、ホストでも組める）にまとめ、SGX ABI 5.3 と
3 言語（mruby・MicroPython・SG BASIC）の `Machine` は薄い口でそれを呼ぶ。

ベジェ曲線は、あとで **PDF / PostScript / TrueType** の描画に使えるよう、**パス**（moveto / lineto / 2 次・3 次ベジェ /
閉じる）・**変換行列**（PostScript の CTM と同じ 6 個の値）・**塗りの規則**（nonzero / even-odd）・**アンチエイリアス**を
土台に置く。図形（楕円・扇形・角丸長方形など）もすべて、内部ではパスを作って同じ塗り・線の道を通る。

## 1. 面（surface）と描画の状態（DC）

- **面** `gfx_surface_t`: 先頭・幅・高さ・1 行のバイト数・形式。形式は
  `GFX_FMT_RGB555`（ネイティブの画素、2 バイト）・`GFX_FMT_CLUT8`（1 バイト）・`GFX_FMT_CLUT4`（1 バイトに 2 画素、上位ニブルが左）。
  CLUT の面はパレット（ネイティブの 16 ビット色の並び）を指せる（RGB の画像を近い色の番号へ直すとき・アンチエイリアスで混ぜるときに使う）。
- 描く先は 3 種類:
  - **FB**: いまの書き込みページ（640x480。形式はモード 2 = RGB555・3 = CLUT8・4 = CLUT4）
  - **ビットマップ**: モード 7 の 320x200x8（表示している面。後ろの面があればそれも）
  - **画像**（`gfx_image_t`）: PSRAM に持つ面。新しく作るか、ファイル（PNG / JPEG / GIF / TIFF）から読む。BitBlt の元にも先にもなる
- **DC**（`gfx_dc_t`）: 描く先ごとに 1 つ持つ状態。
  - **ペン**: 色・幅（1〜64）・線の種類（実線・破線・点線・一点鎖線・二点鎖線・なし）・端の形（丸・四角・平ら）・つなぎ目（丸・とがり・面取り）
  - **ブラシ**: 色・種類（塗り・なし・ハッチ 6 種: 横・縦・右上がり・右下がり・十字・斜め十字）
  - **背景のモード**（透明 / 不透明）と背景色: 破線のすき間・ハッチのすき間・文字の背景に使う
  - **ROP2**（描くときの演算）: 上書き・XOR・OR・AND・NOT（先を反転）・ペンの色の反転で上書き
  - **今の位置**（MoveTo / LineTo）
  - **切り抜きの長方形**（既定は面の全体）
  - **変換行列**（a b c d e f。点 (x, y) は (a*x + c*y + e, b*x + d*y + f) へ。既定は単位行列）。**パスの座標にだけ効く**
    （図形の関数は画面の画素の座標をそのまま使う。GDI の互換のため）
  - **アンチエイリアス**（オン / オフ。既定はオフ）。RGB555 の面では端を色の割合で混ぜる（ROP が上書きのとき）。CLUT の面と、
    上書きでない ROP では、画素の半分より多く覆うときだけ塗る（混ぜた色をパレットから探さない）
  - **塗りの規則**（nonzero / even-odd）。多角形とパスの塗りに使う
  - **文字**: フォント・文字の色・揃え（左 / 中央 / 右 x 上 / ベースライン / 下）・文字間
- **色**は、その面の色の値そのもの（RGB555 はネイティブの画素 = `Machine.rgb` の値、CLUT は色の番号）。

## 2. 線と曲線（ペンで描く）

| GDI | gfx | 説明 |
|---|---|---|
| MoveToEx / LineTo | `gfx_move_to` / `gfx_line_to` | 今の位置から線を引き、今の位置を進める |
| （線） | `gfx_line(x0,y0,x1,y1)` | 2 点の線（今の位置は変えない） |
| Polyline / PolylineTo | `gfx_polyline(pts, n)` / `gfx_polyline_to` | 点を順に結ぶ |
| PolyBezier / PolyBezierTo | `gfx_poly_bezier(pts, n)` / `gfx_poly_bezier_to` | 3 次ベジェ。点の数は 1 + 3k（始点 + 制御点 2 つ + 終点を k 回） |
| Arc / ArcTo | `gfx_arc(l,t,r,b, xs,ys,xe,ye)` / `gfx_arc_to` | 外接する長方形の楕円の弧。始点・終点は中心から (xs,ys)・(xe,ye) へ向かう線との交わり。向きは反時計回り（GDI の既定） |
| AngleArc | `gfx_angle_arc(x,y,r, start, sweep)` | 中心と半径・始まりの角度と広がり（度の 1/16 単位の整数。PostScript の `arc` と同じ考え方） |

- 幅 1 の実線は、曲線を折れ線にしてから画素の中心を通る線で描く（ブレゼンハム。端点は両方描く）。
- 幅 2 以上は、線を多角形に広げてから塗る（端・つなぎ目の形はペンの設定）。破線の模様は幅に比例して伸ばす。
- 曲線を折れ線にする細かさは、**誤差 0.2 画素**（変換のあとの画面の上で）。

## 3. 閉じた図形（輪郭はペン、中はブラシ）

| GDI | gfx | 説明 |
|---|---|---|
| Rectangle | `gfx_rectangle(l,t,r,b)` | 右と下は含まない（GDI と同じ）。中を塗ってから輪郭 |
| RoundRect | `gfx_round_rect(l,t,r,b, ew,eh)` | 角の楕円の幅・高さ |
| Ellipse | `gfx_ellipse(l,t,r,b)` | 外接する長方形 |
| Polygon / PolyPolygon | `gfx_polygon(pts, n)` / `gfx_poly_polygon(pts, counts, nc)` | 閉じた多角形（複数の輪は、穴を含む図形。文字の形と同じ） |
| Pie | `gfx_pie(l,t,r,b, xs,ys,xe,ye)` | 弧と、中心から両端への 2 本の線 |
| Chord | `gfx_chord(l,t,r,b, xs,ys,xe,ye)` | 弧と、両端を結ぶ弦 |

- 塗りは画素の中心が図形の内側にあるかで決める（アンチエイリアスがオフのとき）。隣り合う多角形は、すき間も重なりもなく塗り分ける
  （左上の規則: 画素の中心がちょうど辺の上なら、左と上の辺の側だけ塗る）。

## 4. パス（PDF / PostScript / TrueType の土台）

| 関数 | 説明 |
|---|---|
| `gfx_path_begin` / `gfx_path_end` | GDI の BeginPath / EndPath。間に呼んだ線・図形は描かずにパスへ足す |
| `gfx_path_move_to(x,y)` / `line_to` / `quad_to(cx,cy,x,y)` / `cubic_to(c1x,c1y,c2x,c2y,x,y)` / `close` | 座標は **1/256 画素の整数**（24.8 の固定小数点）。変換行列を通してから面へ |
| `gfx_path_arc(cx,cy,r, a0, a1)` | PostScript の `arc`（角度は 1/16 度） |
| `gfx_path_fill` / `gfx_path_stroke` / `gfx_path_fill_stroke` | 塗る（塗りの規則とブラシ）・線（ペン）・両方。描いたらパスは空にする |
| `gfx_set_matrix(a,b,c,d,e,f)` / `gfx_get_matrix` / `gfx_concat_matrix` | 変換行列（各値は 16.16 の固定小数点の整数。e, f は 24.8 の画素） |

- 2 次ベジェは TrueType の輪郭、3 次は PostScript / PDF / CFF の輪郭にそのまま使える。
- 言語の側では、座標は小数でもよい（Ruby・Python は Float を受けて 24.8 に直す。BASIC は数そのもの）。

## 5. ビットマップ

| GDI | gfx | 説明 |
|---|---|---|
| BitBlt | `gfx_bitblt(dst, dx,dy,w,h, src, sx,sy, rop)` | 面から面へ。ROP: SRCCOPY・SRCPAINT（OR）・SRCAND・SRCINVERT（XOR）・NOTSRCCOPY・DSTINVERT・BLACKNESS・WHITENESS |
| TransparentBlt | `gfx_transparent_blt(..., key)` | 透明色（元の値）を飛ばす |
| StretchBlt | `gfx_stretch_blt(dst, dx,dy,dw,dh, src, sx,sy,sw,sh, rop, key)` | 拡大・縮小（いちばん近い画素）。幅・高さが負なら裏返す |
| SetDIBitsToDevice / StretchDIBits | `gfx_draw_dib(dst, dx,dy,dw,dh, bits, fmt, w,h, stride, palette, sx,sy,sw,sh, rop)` | メモリの画素（RGB888・RGBA8888・RGB565・RGB555・GRAY8・INDEX8 + パレット・INDEX4・INDEX1）を、先の形式に直して描く |
| （画像） | `gfx_image_new(w,h,fmt)` / `gfx_image_load(path)` / `gfx_image_free` | ファイルは **PNG・JPEG・GIF（最初の絵）・TIFF**。読んだ画像は RGB555（CLUT8 の FB へは近い色の番号に直す） |

- 形式の違う面どうしの BitBlt は、元を先の形式に直す（RGB555 -> CLUT は近い色の番号、CLUT -> RGB555 は元のパレット）。
- RGBA の α は、先の面の色と混ぜる（RGB555 の面だけ。CLUT の面では α が半分以上を塗る）。

## 6. 文字

| GDI | gfx | 説明 |
|---|---|---|
| CreateFont / SelectObject | `gfx_font(face, height, weight, flags, escapement)` | 字の形は**フォント ROM**（16 ドット、半角 8 / 全角 16）か **8x8**（ASCII）。height は画素の高さ（16 の倍数でなければ一番近い倍率で拡大・縮小）。太字・斜体・下線・取り消し線、向きは 0 / 90 / 180 / 270 度 |
| TextOut | `gfx_text_out(x,y, utf8, len)` | 揃え（SetTextAlign）に従って置く |
| ExtTextOut | `gfx_ext_text_out(x,y, opt, rect, utf8, len, dx)` | ETO_OPAQUE（長方形を背景色で塗る）・ETO_CLIPPED（長方形で切る）・dx（字ごとの送り） |
| DrawText | `gfx_draw_text(utf8, len, rect, flags)` | 長方形の中に、改行・折り返し・揃え。DT_LEFT / CENTER / RIGHT・TOP / VCENTER / BOTTOM・WORDBREAK・SINGLELINE・NOCLIP・CALCRECT（大きさを測るだけ）。戻り値は書いた高さ |
| GetTextExtentPoint32 | `gfx_text_extent(utf8, len, &w, &h)` | 大きさを測る |

- 字の形の出し方は**フォントの種類ごとの口**（`gfx_font_ops_t`: 字の送りと、1 字を描く関数）にしてある。あとで TrueType を足すときは、
  字の輪郭（2 次ベジェ）をパスにして塗る種類を足す（アンチエイリアスもそのまま効く）。

## 7. SGX ABI 5.3

関数の表の末尾に `gfx_*` を足す（5.2 のプログラムはそのまま動く）。描く先は**面の番号**で選ぶ:
`SGX_GFX_FB`（0、いまの書き込みページ）・`SGX_GFX_BITMAP`（1、モード 7 の表示している面）・`SGX_GFX_BITMAP_BACK`（2、後ろの面）・
`gfx_image_new` / `gfx_image_load` が返す番号（16 から）。状態は面の番号ごとに持つ。プログラムが終わると画像は返す。
点の並びは `int32_t` の (x, y) の対の配列。パスの座標は 24.8 の固定小数点。

## 8. 3 言語

`Machine.fb`（FrameBuffer）・`Machine.bitmap`（Bitmap）・`Machine::Image`（新しい）に同じメソッドを足す。名前は Ruby の
snake_case を基本に、`docs/machine_api.md` の決まり（Python は同じ名前、BASIC は `_` を取り、FB は `Machine` に直接、
ビットマップは `Bm`、画像は `Img` で番号を先頭の引数に）。点の並びは配列（BASIC は数の配列）。

## 9. 進め方

1. `src/gfx/` の芯: 面・DC・画素の書き方（ROP・切り抜き）・パスと平らにする・塗り（nonzero / even-odd、アンチエイリアス）・
   線（幅 1・幅広・破線）。ホスト試験 `scripts/test_gfx.py`（`scripts/host_gfx/`）で、塗りの面積・すき間の無さ・対称・切り抜きを確かめる
2. 図形（2・3 節）
3. ビットマップと画像（5 節）。JPEG と GIF は stb_image（パブリックドメイン / MIT、JPEG と GIF だけ組む）、TIFF は自前
   （無圧縮・PackBits・LZW・Deflate（miniz）、ストリップ、8 ビットの RGB / グレー / パレット / 1 ビット）
4. 文字（6 節）
5. SGX ABI 5.3・3 言語の口・`docs/machine_api.md`・`samples/machine_api/api.*`
6. 見本: `samples/ruby/gfxdemo.rb`・`samples/python/gfxdemo.py`・`samples/basic/gfxdemo.bas`・`apps/gfxdemo`（SGX）
