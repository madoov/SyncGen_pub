// =============================================================
// 設定メニュー (ボタン操作 → 各設定値)
//
//  番号 ラベル     内容                          範囲 / 選択肢
//   0  DOTCLK    ドットクロック目標 [Hz]          1,000,000 〜 45,000,000
//   1  MEAS      ドットクロック実測 [Hz]          (表示のみ)
//   2  H ACTIVE  水平表示ドット                   8 〜 2000
//   3  H FP      水平フロントポーチ               1 〜 512
//   4  H SYNC    水平同期幅                       1 〜 512
//   5  H BP      水平バックポーチ                 1 〜 1024
//   6  V ACTIVE  垂直表示ライン                   1 〜 2048
//   7  V FP      垂直フロントポーチ               1 〜 256
//   8  V SYNC    垂直同期幅                       1 〜 64
//   9  V BP      垂直バックポーチ                 1 〜 512
//  10  HS POL    水平同期の極性                   POS / NEG
//  11  VS POL    垂直同期の極性                   POS / NEG
//  12  SYNC      同期の出し方                     SEP / OR / XOR / EQ (SEP から OR / XOR にすると SYNC LV を LOW に。
//                EQ にする・EQ からほかにするときは VS OFS を 0 に。2026-11-13)
//  13  SYNC LV   同期 (HSYNC・VSYNC) の電圧        TTL / LOW 0.6V (75Ω 入力のモニタ用)。初期値 LOW
//  14  VS OFS    VSYNC の切り替え位置 [ドット]    0〜4095 (HSYNC の始まりから。H 合計 - 1 で止まる。2026-11-05)
//      EQ FORM   SYNC = EQ のときは同じ欄が EQ の形 (2026-11-13。VSYNC のピンは止まっていて位置は効かないため)
//                表示 " E 4 8 6": 半ラインずれ (E なし / O あり)、等化パルスの幅 (同期幅の k/8)、切れ込みの幅 (m/8)、
//                等化パルスの数 (6 / 7)。STEP で変える欄を順に移り、UP / DOWN で変える。ビットの並びは vga_timing.v
//  15  SCAN      走査                             PROG / INTER (インターレース。2026-10-23、H TOTAL と V TOTAL を
//                1 行にまとめて空けた)。インターレースでは V ACTIVE がフレームのライン数、V FP / SYNC / BP がフィールドのライン数
//  16  TOTAL     水平総ドット / 垂直総ライン       (表示のみ。"TOTAL   858/ 525" のように 1 行で。
//                インターレースの V はフレームのライン数 = 2 × ((V ACTIVE + 1) / 2 + FP + SYNC + BP) + 1)
//  17  FREQ      水平 / 垂直周波数 (例 15.98k 62.42) (表示のみ。2026-11-05 に H FREQ / V FREQ を 1 行に)
//  18  PATTERN   テストパターン                   BARS / GRAD / GRID / WHITE / XHATCH / DOTS / ASPECT /
//                                                   BAR75 / RAMP / MBURST (10 種類、4 ビット。2026-11-14 に MOVE H / V を外して詰めた)
//  19  PRESET    内蔵プリセット (選ぶと 0,2〜12 と NAME を一括設定)  42 種類 (表は make_menu_rom.py → preset.hex、2026-11-12。64 個まで、2026-11-17。2026-11-18 に並べ替え、2026-11-19 に 18 MB-S1・19 / 20 FM-16β・21 / 22 FP-1100・40 TAITO F3・41 MAPPY)
//  20  TV OUT    テレビ出力 (コンポジット・S 端子) の方式  OFF / NTSC / NTSC FIX / NTSC443 / N443 FIX / PAL / PAL FIX /
//                PAL-M / PALM FIX / PAL-N / PALN FIX / PAL60 / PL60 FIX (13 種類)
//                (2026-10-22、AUTOTRIM の代わり。Si5351A では補正が要らないので AUTOTRIM は削除)
//                - SEL で決定したとき、OFF から方式を選んだ、または 525 ライン系 ⇔ 625 ライン系が変わったら、標準のタイミング
//                  (プリセット NTSC240P / PAL 288P) を作業中の値に入れる。そのあとも変更はできる
//                - OFF 以外: HS POL / VS POL / VS OFS / SYNC / SYNC LV はテレビ出力に効かないので変更不可 (表示は ----)
//                - FIX: 水平・垂直の周波数を標準に保つ。DOTCLK = H 合計 × 標準の水平周波数
//                  (525 ライン系 4.5MHz / 286 = 15734.27Hz、625 ライン系 15625Hz)、V BP = 262 / 312 - (V ACTIVE + FP + SYNC)。
//                  DOTCLK と V BP は変更不可 (自動で変わる。ラベルは *DOTAUTO / *VBPAUTO)。
//                  DOTCLK は 1〜48MHz で頭打ち (H 合計 64〜3050 の範囲で標準の周波数になる)
//  21  SLOT n    ユーザープリセットの番号 1〜8    (値の欄にそのスロットの名前)
//  22  NAME      保存するときの名前 (8文字)       SEL で編集 → UP/DOWN で文字、STEP で次の桁
//  23  LOAD      SEL で SLOT から読み込み          PUSH+ / EMPTY / LOADED / ERROR / BUSY
//  24  SAVE      SEL で SLOT へ保存 (名前も)       PUSH+ / SAVED / ERROR / BUSY
//  25  APPLY     SEL で確定 (STEP 長押しでも可)     OK / CHANGED / WAIT
//  26  MODE      遅延測定 (範囲) / キャプチャ (2026-11-07、LAG AREA から)  LAG FULL / LAG TOP / LAG CENT / LAG BOT /
//                CAP SELF (CAP IN) / CAP RAW。LAG のときは選んでいる間、画面に範囲を白で出す。SEL で決定したときに切り替わる。
//                入力 / 出力は基板の切り替えスイッチ S2 だけで決める (2026-11-21 の仕様変更。メニューの CAP IN (値 5) はなくした)。
//                S2 が IN なら入力モード (出力を止めて J5 から受ける。MODE が LAG でも出力は止まる)、キャプチャの値 4 は CAP IN と表示。
//                S2 が OUT なら CAP SELF (出力モードのまま自分の出力を受ける、折り返しの確かめ)
//    MODE が LAG のとき:
//  27  LAG RUN   SEL で遅延測定を開始、測定中にもう一度 SEL で中止   PUSH+ / CAL / RUN / DONE / LOW SIG / NO VIDEO / NO LIGHT / NOISE / STOP
//  28  LAG AVG   映像が出てから光るまで 平均 [ms, 小数2桁]  (表示のみ)
//  29  LAG MIN   同 最小                          (表示のみ)
//  30  LAG MAX   同 最大                          (表示のみ)
//  31  (LAG では使わない。CMD AVG は 2026-11-21 に外した)
//    MODE が CAP のとき (キャプチャ、2026-11-07。解像度は作業中の H ACTIVE / V ACTIVE を使う):
//  27  CAP RUN   SEL でしきい値を合わせて BLANK MEAS を開始、もう一度 SEL で終わり (cap_ctrl)
//                PUSH+ / THR / RUN / DONE / NO SYNC / ERROR / NO MEAS / NO EDGE / BAD HTOT / H NEG / V NEG
//  28  ACTIVE    推定に使う解像度 = 作業中の H ACTIVE / V ACTIVE ("ACTIVE  640/ 480"。No.2 / No.6 と同じ値)
//                SEL で値を変える状態へ。STEP で x1 → x10 → x100 → (H と V を切り替え) x1 …。変えている方が点滅
//  29  C.TOT   推定した H 合計 / V 合計 ("C.TOT 800/ 525"。インターレースの V はフレーム) (表示のみ)
//  30  C.DOT   推定したドットクロック [Hz]    (表示のみ。測定中は途中の推定)
//  31  COPY      SEL で推定を作業中の値へ (DONE のときだけ)   PUSH+ / COPIED / NO DATA
//                DOTCLK・H FP / SYNC / BP・V FP / SYNC / BP・極性・SYNC・VS OFS・SCAN を入れ、TV OUT を OFF、
//                (作業中の SYNC が EQ で測った形式が OR なら、SYNC と VS OFS の欄 (EQ FORM) はそのまま。2026-11-13)
//                名前を CAPTURE にする (H / V ACTIVE・SYNC LV・パターンはそのまま)。確定が要ればカーソルを APPLY へ
//
//  表示 (2026-11-07): 変更できない項目 (表示のみの項目と TV OUT で変更不可の項目) は OLED で項目名の頭に * (rd_ro)
//
//  操作 (2026-10-17 変更):
//    項目を選ぶ状態 (edit = 0): UP / DOWN で項目を移る (選んだ項目はラベルを反転)。
//      SEL で決定 → 値を変える項目なら「値を変える状態」へ。LOAD / SAVE / APPLY / LAG RUN はその場で実行。
//    値を変える状態 (edit = 1、値が点滅): UP / DOWN で値を変え、SEL で決定して項目を選ぶ状態に戻る。
//      NAME は STEP で次の桁。表示のみの項目は SEL を押しても何もしない。
//    STEP 短押し: 増減幅、STEP 長押し: APPLY (どちらの状態でも)
//    SEL 長押し (2026-11-05): 値を変える状態なら決定して出て、カーソルを APPLY へ移して確定 (どちらの状態でも)
//    PRESET を選んで決定・LOAD したときは、確定が要ればカーソルを APPLY へ移す (手で値を変えたときは移らない)
//
//  変更の確定:
//    DOTCLK・タイミング・極性・同期 (SYNC LV を含む)・TV OUT の変更 (PRESET / LOAD を含む) は、すぐには
//    出力に反映しない。APPLY で確定すると、出力停止 → ドットクロック切替・補正 →
//    タイミング反映 → 出力再開 の順に切り替える。
// =============================================================
module settings #(
    parameter integer SHARED        = 0,             // 1: 割り算器をトップで共有 (2026-11-14)
    parameter integer PUB_CYCLES    = 5_000_000,     // 100ms
    parameter integer SETTLE_CYCLES = 150_000_000,   // 3秒
    parameter integer CLK_HZ        = 50_000_000,
    parameter         PRESET_FILE   = "preset.hex"   // 内蔵プリセットの表 (tools/make_menu_rom.py)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        b_next_in, b_prev_in, b_up_in, b_dn_in, b_step_in, b_apply_in,
    input  wire [26:0] ro_meas, ro_hfreq, ro_vfreq,
    // 表示用
    output reg  [5:0]  cur,              // 選んでいる項目 (0〜31)。bit5 = 1 は階層メニューの行 (下の grp の説明、2026-11-20)
    output reg  [4:0]  menu_pos,         // 表示: カーソルの行の位置 (グループの中の何番目か)
    output reg  [4:0]  menu_cnt,         // 表示: グループの行の数
    output reg         edit,             // 1 = 値を変える状態 (表示で値を点滅)
    output reg  [26:0] step_val,
    input  wire [4:0]  rd_pos,           // 表示が読む行の位置 → rd_code (次のクロック) → rd_val など
    output reg  [5:0]  rd_code,
    output reg  [26:0] rd_val,
    output reg  [1:0]  rd_kind,           // 0:数値 1:選択肢 2:数値(小数2桁) 3:文字列
    output reg  [63:0] rd_text,           // kind 3 の文字列 (8文字, 先頭が上位)
    output reg  [3:0]  rd_cursor,         // kind 3 で反転する桁 (8 = なし)
    output wire        rd_lock,           // 1 = TV OUT のため変更できない (選択肢は ----、数値はラベルを AUTO に)
    output wire        rd_mv,             // 1 = 電圧 [mV、小数 2 桁] として表示 (LOW SIG のときの LAG MIN / MAX)
    output wire        rd_ro,             // 1 = 変更できない項目 (表示だけ、または TV OUT で変更不可)。項目名の頭に * (2026-11-07)
    output reg  [1:0]  rd_q,              // キャプチャ: 推定した値 (AUTO から) の印 ? を数字の後ろに。[0] H (または 1 つの値)、[1] V (2026-11-15)
    output reg  [1:0]  rd_auto,           // キャプチャの ACTIVE: AUTO と表示する。[0] H、[1] V (2026-11-15)
    output wire [3:0]  slot_no,           // 表示用 1〜8
    // vga_timing へ
    output reg  [11:0] cfg_h_active, cfg_h_fp, cfg_h_sync, cfg_h_bp,
    output reg  [11:0] cfg_v_active, cfg_v_fp, cfg_v_sync, cfg_v_bp,
    output reg         cfg_hs_neg, cfg_vs_neg,
    output reg  [11:0] cfg_vs_ofs,        // VSYNC の切り替え位置 (HSYNC の始まりからのドット数、VS OFS)
    output reg  [1:0]  cfg_csync,
    output reg         cfg_sync_lv,      // 同期の電圧 0 = TTL (キャプチャ版の基板で High 約 3.3V)、1 = LOW (75Ω 入力で約 0.6V、初期値)。APPLY で確定
    output reg  [2:0]  cfg_tv_mode,      // テレビ出力の方式 (0 = OFF。tv_encoder の表)。APPLY で確定
    output reg         cfg_interlace,    // 1 = インターレース (SCAN)。APPLY で確定
    output reg         cfg_toggle,
    // その他
    output wire [3:0]  pattern,
    output reg  [26:0] dot_target,
    output reg         dot_upd,
    input  wire        osc_settled,
    output reg         out_en,
    output wire        pending,
    output wire        pend_m,            // 1 行目の * と APPLY の CHANGED: pending + 波形を読んだ・記録したがまだ APPLY していない (wpl、2026-11-26)
    // ユーザープリセット (preset_store)
    output reg          st_save,
    output reg          st_load,
    output wire [2:0]   st_slot,
    output wire [2:0]   st_wslot,          // RAW SAVE / LOAD のスロット (No.29 RAW SLOT、0〜7。2026-11-20)
    output wire [255:0] pk_data,
    input  wire         ld_we,         // LOAD: preset_store から 1 バイトずつ (byte 1〜30、2026-11-13)
    input  wire [4:0]   ld_idx,
    input  wire [7:0]   ld_byte,
    input  wire [7:0]   st_valid,
    input  wire [63:0]  st_name,           // st_slot のスロットの名前 (preset_store のメモリから、1 クロック遅れ)
    input  wire         st_busy,
    input  wire         st_ok,
    input  wire         st_err,
    // 遅延測定 (lag_meas)
    output wire [1:0]   lag_area,
    output wire         lag_sel,           // LAG AREA を選んでいる (範囲を表示する)
    output reg          lag_start,
    output reg          lag_stop,
    input  wire [3:0]   lag_status,
    input  wire [26:0]  lag_avg, lag_min, lag_max,
    // キャプチャ (cap_ctrl / cap_est。e_* は cap_clk 側の値をそのまま読む: DONE のあとは変わらない。測定中の表示は途中の値)
    output wire         cap_en,            // MODE = CAP SELF / CAP IN (決定した値)
    input  wire         cap_sw,            // 切り替えスイッチ S2 が IN (トップで同期化済み。MODE の表示だけに使う。2026-11-08)
    input  wire         cap_clash,         // 出力のぶつかりを見つけて出力を止めた (cap_clash、APPLY で消える。2026-11-08)
    output reg          cap_sel,           // CAP RUN で SEL (1 クロック)
    // 波形コピー (MODE = CAP RAW、2026-11-13。wav_rec / wav_play)
    output wire         wav_en,            // MODE = CAP RAW (決定した値)
    output reg          wav_rec_tgl,       // RAW REC で SEL (反転)
    output reg          wav_play,          // RAW PLAY = ON
    input  wire [2:0]   wav_stat,          // wav_rec の状態 (トップで同期化済み)
    input  wire [11:0]  wav_lines,         // 記録のライン数 / 項目の数 (済みのあとは変わらない)
    input  wire [10:0]  wav_ent,           // 圧縮した語数 (wav_store、2026-11-13)
    output reg          st_wav,            // st_save / st_load が波形のスロット (RAW SAVE / LOAD、2026-11-13)
    input  wire [3:0]   cap_status,
    input  wire [7:0]   cap_rr,            // 推定の H 合計の端数 (cap_ctrl の rr、2026-11-09)
    input  wire         cap_rrv,
    input  wire [11:0]  e_ha, e_va,        // 推定に使った解像度 (cap_est、2026-11-10)
    input  wire [2:0]   e_err,
    input  wire [26:0]  e_dot,
    input  wire [11:0]  e_ht, e_hf, e_hs, e_hb, e_vt, e_vf, e_vs, e_vb, e_vo,
    input  wire         e_il, e_hneg, e_vneg,
    input  wire [1:0]   e_cs,
    output wire [11:0]  cap_ha, cap_va,    // 推定に使う解像度 (作業中の H / V ACTIVE)
    // 割り算器の共有 (2026-11-14、容量削減): SHARED = 1 ならトップの udiv_share を使う (0 なら自前の udiv。単体のテスト用)
    output wire         sd_start,
    output wire [46:0]  sd_num,
    output wire [29:0]  sd_den,
    input  wire [46:0]  sd_quo,
    input  wire [29:0]  sd_rem,
    input  wire         sd_done
);
    localparam N = 32;
    localparam I_DOT=0, I_MEAS=1, I_HA=2, I_HF=3, I_HS=4, I_HB=5, I_VA=6, I_VF=7,
               I_VS=8, I_VB=9, I_HPOL=10, I_VPOL=11, I_SYNC=12, I_SLV=13, I_VOFS=14,
               I_SCAN=15, I_TOT=16, I_HFRQ=17, I_PAT=18, I_PRE=19, I_TV=20,   // 2026-11-12: VS OFS / SCAN / TOTAL / FRQ を SYNC LV の後へ
               I_SLOT=21, I_NAME=22, I_LOAD=23, I_SAVE=24, I_APPLY=25,
               I_MODE=26, I_LRUN=27, I_LAVG=28, I_LMIN=29, I_LMAX=30, I_LCMD=31;
    localparam NPRE = 42;

    // ---- APPLY の状態。APPLY の間はボタンを受け付けない (2026-11-27 容量削減: APPLY を始めたときの作業中の値の写し ap_* を
    //      なくし、確定のときに作業中の値 vr[] を直接出す。途中で値が変わって出力が混ざらないように) ----
    localparam A_IDLE = 3'd0, A_MUTE = 3'd1, A_OSC = 3'd2, A_PUB = 3'd3, A_RUN = 3'd4;
    reg [2:0]  ast;
    wire       b_ok    = (ast == A_IDLE);
    wire       b_next  = b_next_in  && b_ok, b_prev = b_prev_in && b_ok, b_up = b_up_in && b_ok,
               b_dn    = b_dn_in    && b_ok, b_step = b_step_in && b_ok, b_apply = b_apply_in && b_ok;

    reg [26:0] v [0:31];          // 作業中の値 (書き込みはここ、読むときは下の vr[] を使う)
    // ---- 項目ごとに使うビット (2026-11-07、容量削減) ----
    //   読み出しはすべて vr[] = v[] の使うビットだけ。使わないビットの FF は読む先がなくなり合成で消える
    //   (以前は 32 項目 × 27 ビットの FF と、そこから選ぶ回路があった)。値を持たない項目 (MEAS・FREQ・TOTAL・
    //   NAME・LOAD・SAVE・APPLY・LAG の結果) は 0。V FP / SYNC / BP は保存の形式では 16 ビットだが、cfg_* と同じ 12 ビットにする
    function [26:0] vmask(input integer i);
        case (i)
            I_DOT:                                   vmask = 27'h7FFFFFF;
            I_HA, I_HF, I_HS, I_HB, I_VA, I_VF, I_VS, I_VB, I_VOFS: vmask = 27'hFFF;
            I_HPOL, I_VPOL, I_SLV, I_SCAN:           vmask = 27'h1;
            I_SYNC:                                  vmask = 27'h3;
            I_MODE:                                  vmask = 27'h7;
            I_PAT, I_TV, I_SLOT, I_LMIN:             vmask = 27'hF;   // I_LMIN: CAP RAW の RAW SLOT (2026-11-20)
            I_PRE:                                   vmask = 27'h3F;   // 0〜63 (2026-11-17 に 32 個から 64 個へ)
            default:                                 vmask = 27'h0;
        endcase
    endfunction
    wire [26:0] vr [0:31];
    genvar gi;
    generate for (gi = 0; gi < 32; gi = gi + 1) begin : g_vr
        assign vr[gi] = v[gi] & vmask(gi);
    end endgenerate
    // ---- キャプチャ (2026-11-07) ----
    reg [1:0]  cp_code;           // COPY の表示: 0 PUSH+ / 1 COPIED / 2 NO DATA / 3 RANGE NG (2026-11-22)
    reg [2:0]  cp_cnt;            // COPY: TV OUT を OFF にしてから (FIX の自動の値が消えてから) 数えて写す
    // COPY で写せない推定 (2026-11-22): 写すときに値を変えると測ったタイミング (H / V 合計・周波数) が変わるので、変えずに断る。
    //   同期の幅 0、項目の上限 (vmax) 超え、DOTCLK が 1〜48MHz の外。FP / BP の 0 はそのまま写す (vga_timing は 0 でよい)。
    //   e_* は DONE のあと変わらないので、毎クロックのレジスタで比べておく
    reg        cp_rng;
    always @(posedge clk)
        cp_rng <= (e_hs == 12'd0) || (e_vs == 12'd0) ||
                  (e_hf > 12'd512) || (e_hs > 12'd512) || (e_hb > 12'd1024) ||
                  (e_vf > 12'd256) || (e_vs > 12'd64) || (e_vb > 12'd512) ||
                  (e_dot > 27'd48_000_000) || (e_dot < 27'd1_000_000);
    reg        acv;               // ACTIVE (No.28) で変える方: 0 = H ACTIVE、1 = V ACTIVE
    reg [1:0]  eqf;               // EQ FORM (No.14、SYNC = EQ) で変える欄: 0 半ラインずれ / 1 等化パルスの幅 / 2 切れ込みの幅 / 3 数
    reg        au_h, au_v;        // ACTIVE の AUTO (2026-11-10): 1 なら推定に 0 を渡す (cap_est が V は測った値、H は 4/3 × V の暫定)。
                                  //   値を変える状態で最小の値から DOWN で AUTO、UP で戻る (作業中の H / V ACTIVE は変えない)
    reg [11:0] ah_k, av_k;        // ACTIVE の H / V を変え始めたときの値 (2026-11-20): AUTO にしたら作業中の値をこれに戻す
                                  //   (最小の値 1 まで下げてから AUTO にするので、戻さないと V ACTIVE = 1 が残り、APPLY・SAVE に入っていた)
    wire       act_cur = cap_en && (cur == I_LAVG);    // カーソルが ACTIVE (キャプチャ)
    // ---- 階層メニュー (2026-11-20、ユーザーの依頼) ----
    //   grp 0 = 最初の画面 (3 行: SYNC SET/PATTERN、LAG CHECK、SYNC CAPTURE)、1 = SYNC SET/PATTERN、2 = LAG CHECK、3 = SYNC CAPTURE。
    //   1〜3 の先頭の行は << BACK (最初の画面へ)。行 (位置) ⇔ 項目の対応は gmap / gpos の表。cur の bit5 = 1 は項目ではない行
    //   (cur[1:0] = 0 BACK / 1〜3 最初の画面の行 = 入るグループの番号)。
    //     1: BACK、No.0〜25 (DOTCLK 〜 APPLY)               27 行
    //     2: BACK、No.26 MODE (LAG の 4 つ)、No.27〜30        6 行 (No.31 CMD AVG は 2026-11-21 に外した)
    //     3: BACK、No.26 MODE (CAP SELF / IN / RAW)、No.27〜31、No.25 APPLY   8 行
    //   カーソルを今のグループにない項目へ移したとき (APPLY へ移す・ぶつかりなど) は、その項目のグループへ移る
    reg  [1:0] grp;
    function [5:0] gmap(input [1:0] g, input [4:0] p);
        case (g)
        2'd0:    gmap = {1'b1, 5'd1 + p};
        2'd1:    gmap = (p == 5'd0) ? 6'h20 : {1'b0, p - 5'd1};
        default: gmap = (p == 5'd0) ? 6'h20 : (p == 5'd7) ? 6'd25 : {1'b0, 5'd25 + p};   // 1 → 26 MODE、2〜6 → 27〜31、7 → APPLY
        endcase
    endfunction
    function [4:0] gcnt(input [1:0] g);
        gcnt = (g == 2'd0) ? 5'd3 : (g == 2'd1) ? 5'd27 : (g == 2'd2) ? 5'd6 : 5'd8;
    endfunction
    function [5:0] gpos(input [1:0] g, input [5:0] c);   // bit5 = 1: このグループにない
        if (c[5])        gpos = (g == 2'd0) ? ((c[1:0] == 2'd0) ? 6'h20 : {4'd0, c[1:0] - 2'd1}) : ((c[1:0] == 2'd0) ? 6'd0 : 6'h20);
        else if (g == 2'd1) gpos = (c <= 6'd25) ? c + 6'd1 : 6'h20;
        else if (g == 2'd0) gpos = 6'h20;
        else             gpos = (c >= 6'd26) ? c - 6'd25 : (c == 6'd25 && g == 2'd3) ? 6'd7 : 6'h20;
    endfunction
    reg  [5:0] gp_r;              // カーソルの位置 (毎クロック gpos から)
    reg  [4:0] nav_p;             // UP / DOWN で移る位置 (次のクロックで cur へ)
    reg        nav_go;
    wire [4:0] rd_item = rd_code[4:0];
    always @(posedge clk) begin
        gp_r     <= gpos(grp, cur);
        menu_pos <= gp_r[4:0];
        menu_cnt <= gcnt(grp);
        rd_code  <= gmap(grp, rd_pos);
    end
    reg        act_ok;            // ACTIVE を決定した (2026-11-15): MODE をキャプチャにしたら 0 にしてカーソルを ACTIVE へ。
                                  //   0 の間は CAP RUN を SET ACT (変更不可の *) にして始めない。ACTIVE を決定したら 1、カーソルを CAP RUN へ
    reg        qa_h, qa_v;        // CAP RUN を始めたときの AUTO (推定した値に ? を付ける)
    reg        cpd;               // キャプチャの COPY をした (2026-11-20)。CAP RAW の RAW REC は、これがなく確定済みでもないとき NEED CAP
                                  //   (先に CAP RUN → COPY → APPLY を勧める。SEL で記録はできる)。CAP RUN を始めた・LOAD・PRESET で消す
    reg        cs3_p;             // 前のクロックで CAP RUN が DONE (DONE になったらカーソルを COPY へ)
    reg [63:0] wname;             // 保存するときの名前
    reg [2:0]  cpos;              // 名前の編集桁

    // ---- 範囲 ----
    function [26:0] vmin(input [4:0] i);
        case (i)
            I_DOT: vmin = 27'd1_000_000;
            I_VOFS: vmin = 27'd0;
            I_HA:  vmin = 27'd8;
            I_VF:  vmin = 27'd0;    // V FP は 0 から (FM-16β の CRTC は表示の直後に垂直同期、2026-11-19)
            I_HF, I_HB, I_VB: vmin = 27'd0;   // H FP / H BP / V BP も 0 から (2026-11-22、COPY が測った 0 をそのまま入れるので)
            default: vmin = 27'd1;
        endcase
    endfunction
    function [26:0] vmax(input [4:0] i);
        case (i)
            I_DOT: vmax = 27'd48_000_000;   // 2026-11-17 に 45 → 48MHz (PC-98 ハイレゾ 47.8MHz)
            I_HA:  vmax = 27'd2000;
            I_SLOT, I_LMIN: vmax = 27'd8;
            I_HF, I_HS, I_VB: vmax = 27'd512;
            I_HB:  vmax = 27'd1024;
            I_VA:  vmax = 27'd2048;
            I_VF:  vmax = 27'd256;
            I_VS:  vmax = 27'd64;
            I_VOFS: vmax = 27'd4095;
            default: vmax = 27'd1;
        endcase
    endfunction
    function [6:0] n_enum(input [4:0] i);   // 選択肢の数 (プリセットは 64 個までなので 7 ビット)
        case (i)
            I_HPOL, I_VPOL, I_SLV, I_SCAN: n_enum = 5'd2;
            I_TV:   n_enum = 5'd13;
            I_SYNC: n_enum = 5'd4;   // SEP / OR / XOR / EQ (2026-11-12)
            I_PAT:  n_enum = 5'd10;
            I_MODE: n_enum = 5'd7;   // LAG FULL / TOP / CENT / BOT / CAP SELF / CAP IN / CAP RAW (2026-11-13)
            I_PRE:  n_enum = NPRE;
            default: n_enum = 5'd0;
        endcase
    endfunction
    // ---- TV OUT の選択肢の番号 → 方式 (tv_encoder の番号) と FIX ----
    //   0 OFF、1 NTSC、2 NTSC FIX、3 NTSC443、4 N443 FIX、5 PAL、6 PAL FIX、… 12 PL60 FIX
    function [2:0] tvm(input [3:0] t);
        tvm = (t == 4'd0) ? 3'd0 : (t + 4'd1) >> 1;
    endfunction
    function tvfix(input [3:0] t);
        tvfix = (t != 4'd0) && !t[0];
    endfunction
    function tv625(input [3:0] t);                     // 625 ライン系 (PAL / PAL-N)
        tv625 = (tvm(t) == 3'd3) || (tvm(t) == 3'd5);
    endfunction
    function is_ro(input [4:0] i);
        is_ro = (i == I_MEAS) || (i == I_HFRQ) || (i == I_TOT) || (i == I_LOAD) ||
                (i == I_SAVE) || (i == I_APPLY) || (i == I_NAME) || (i >= I_LRUN);
    endfunction

    // ---- 内蔵プリセット (資料・実測例をもとにした参考値) ----
    //   No 名前      機種                         ドット      H 表/FP/同/BP    V 表/FP/同/BP  極性 同期 電圧
    //    0 NTSC240P テレビ出力用 525 ライン系のプログレッシブ (ITU-R BT.601 の 13.5MHz、H 858 = 15.734kHz、
    //               V 262 = 60.05Hz。ファミコン・メガドライブなどの 240p と同じ形)
    //                                           13.5MHz    720/16/62/60     240/4/3/15    N/N SEP
    //    1 PAL 288P テレビ出力用 625 ライン系のプログレッシブ (H 864 = 15.625kHz、V 312 = 50.08Hz)
    //                                           13.5MHz    720/12/64/68     288/2/3/19    N/N SEP
    //    2 NTSC480I テレビ出力用 525 ライン系のインターレース (H 858 = 15.734kHz、V 525 = 59.94Hz のフィールド)。
    //               V の FP / SYNC / BP はフィールドのライン数 (240 + 3 + 3 + 16 = 262、フレーム 2 × 262 + 1 = 525)
    //                                           13.5MHz    720/16/62/60     480/3/3/16    N/N SEP  INTER
    //    3 PAL 576I テレビ出力用 625 ライン系のインターレース (H 864、V 625 = 50Hz のフィールド。288 + 3 + 3 + 18 = 312。
    //               FP を 3 にして、垂直同期の前の等化パルス 6 個が表示のあるラインにかからないようにする)
    //                                           13.5MHz    720/12/64/68     576/3/3/18    N/N SEP  INTER
    //    4 MSX      MSX (TMS9918) 256x192       5.369318MHz 256/23/26/37    192/27/3/40   N/N XOR LOW
    //    5 FAMICOM  ファミコン (NES) 256x240     5.369318MHz 256/20/25/40    240/5/3/14    N/N XOR LOW
    //    6 MSX2 192 MSX2 (V9938) 256x192 60Hz   10.738635MHz 512/43/50/79 192/28/3/39   N/N EQ  LOW
    //               (MSX2 の 5 個・X1 40・PC98 GDC の根拠は make_menu_rom.py の PRESETS の注記)
    //    7 MSX2 212 MSX2 (V9938) 256x212 60Hz   10.738635MHz 512/43/50/79 212/18/3/29   N/N EQ  LOW
    //    8 MSX2 424 MSX2 (V9938) 512x424 インターレース 10.738635MHz 512/43/50/79 424/18/3/29 N/N EQ LOW INTER
    //    9 MSX2P192 MSX2 (V9938) 256x192 50Hz   10.738635MHz 512/43/50/79 192/52/3/66   N/N EQ  LOW
    //   10 MSX2P212 MSX2 (V9938) 256x212 50Hz   10.738635MHz 512/43/50/79 212/42/3/56   N/N EQ  LOW
    //   11 MD H40   メガドライブ 320x224        6.711647MHz 320/28/32/47    224/11/3/24   N/N XOR TTL
    //   12 PC80/88L PC-8001 / PC-8801 の 15kHz 640x200 (2026-10-31 実機の値に。以前は PC-88 LO の名前で 200 ライン系の代表値)
    //               H 合計 896・V 合計 260 = 15.98kHz / 61.46Hz (MAME の pc8001 / pc8801 の画面設定と同じ)。
    //               FP・同期・BP と同期の出し方は PC-8001 の回路図 (I/O 別冊『PC-8001 活用研究』の VIDEO) から (2026-11-05):
    //                 HSYNC = μPD3301 の HRTC の始まりから 10〜18 文字目 (IC66 + IC59)、
    //                 VSYNC = VRTC の始まりから HRTC の終わりを数えて 16〜23 本目 (IC60 + IC68)、どちらも負極性。
    //                 RGB 端子には HSYNC / VSYNC が別々に出る (コンポジット映像の同期は IC34 の XOR)。
    //                 VSYNC はラインの頭で切り替わる。PC-8801 (初代) の回路図も同じ作り (COLOR CONTROL の IC61 / IC62)。
    //                 このプリセットは SYNC LV = TTL・VS OFS も入れる (pfix、2026-11-05)。
    //                 回路図のピンの読みに不確かなところがあり、H は 1〜2 文字ずれる可能性がある
    //               実測に合わせた (2026-11-05、retropc.net の PC-8801FA の測定記事、80x25 の画面):
    //                 赤の表示 44.59µs (640)、表示の終わり → HSYNC 4.53µs (FP 64 = 8 文字)、HSYNC 4.48µs (64)、
    //                 HSYNC の終わり → 表示 9.067µs (BP 128 = 16 文字)。VSYNC 499.86µs (8 ライン)、
    //                 1 フレーム 16.003ms = 256 ライン (62.4Hz。μPD3301 で 25 行 + 帰線 7 行 × 8 ライン。80x20 の画面では
    //                 (20 + 6) × 10 = 260 ライン)。V の FP 16 は回路図の読み (垂直帰線の 16 ライン目から)。負極性 TTL。
    //                 HSYNC と VSYNC の立ち下がりのずれは実測 11.8µs (168 ドット)。VSYNC は表示の始まりより 3 文字前
    //                 (CRTC のラインの頭。表示は映像の回路で遅れる) で切り替わる → VS OFS 168
    //                                           14.31818MHz 640/64/64/128   200/16/8/32   N/N SEP
    //   13 PC-88 HI PC-8801 24kHz 640x400       21.0526MHz 640/64/64/80     400/8/2/38    N/N SEP
    //               (21.0526MHz = mkIISR の 42.1052MHz ÷ 2、回路図で確認。初代 PC-8801 の回路図では 20MHz の水晶。
    //               同期は H / V 別々の TTL (回路図で確認)。初代は VSYNC をラインの頭で切り替える (mkIISR は
    //               ゲートアレイの中で不明)。このプリセットは SYNC LV = TTL・VS OFS 120 (同期 + BP 144 から 3 文字前とした推定) も入れる (pfix)。
    //               FP / 同期 / BP は MAME の値)
    //   14 X1       X1 / X1turbo の 15kHz 640x200 (80 桁)。14.31818MHz (8 ドット / 文字。X1 は 28.636MHz ÷ 2、
    //               X1turbo は 42.9545MHz ÷ 3。どちらも回路図で確認 2026-11-05)、
    //               CRTC (HD46505) R0 = 111 (H 合計 112 文字 = 896)、R2 = 89 (同期 712 ドットから)、R3 = 38h (H 8 文字、V 3 ライン)、
    //               R4 = 31・R5 = 2 (V 合計 32 × 8 + 2 = 258)、R7 = 28 (同期 224 ライン目から)
    //               → 15.98kHz / 61.94Hz (実機の測定 約 62Hz と合う)
    //               同期の出し方は回路図で確認 (2026-11-05。X1 = CZ-800C の I/O 掲載の回路図、X1turbo = CZ-851/852C):
    //                 HD46505 の HSYNC / VSYNC (正極性) → ラッチ (X1: IC45 LS273 → IC44 S374、X1turbo: IC37 LS273) →
    //                 7406 / LS06 (反転のオープンコレクタ、1kΩ で 5V へ) → RGB 端子の H / V 別々 = SEP、N/N、TTL。
    //                 H と V は同じラッチを通るので、VSYNC はラインの頭で切り替わる。
    //                 このプリセットは SYNC LV = TTL・VS OFS (同期 + BP = ラインの頭) も入れる (pfix、2026-11-05)。
    //                 CRTC の値 (FP / 同期 / BP) はソフト (IPL) が書くもので、回路図からは分からない
    //                                           14.31818MHz 640/72/64/120   200/24/3/31   N/N SEP
    //   15 X1 40    X1 の 15kHz 320x200 (40 桁) 7.15909MHz  320/40/32/56     200/24/3/31   N/N SEP TTL (VS OFS 88)
    //   16 X1TURBO  X1turbo の 24kHz 640x400 (高解像度)。42.954545MHz ÷ 2 = 21.47727MHz、CRTC R0 = 107 (864)、R2 = 89 (712)、
    //               R3 = 88h (H 8 文字、V 8 ライン)、R4 = 27・R9 = 15 (V 合計 28 × 16 = 448)、R7 = 26 (同期 416 ライン目から)
    //               → 24.86kHz / 55.49Hz。42.9545MHz (X3) と、同期の出し方 (SEP、N/N、TTL) は 14 X1 と同じく回路図で確認。
    //               X1turbo の 15kHz は 14 X1 と同じ
    //                                           21.47727MHz 640/72/64/88    400/16/8/24   N/N SEP
    //   17 FM-7     FM-7 / FM-77 の 640x200。16.128MHz、H 合計 1024・V 合計 262 = 15.75kHz / 60.11Hz
    //               (MAME の fm7 の画面設定と同じ)。FP・同期・BP の分け方と同期の出し方は推定
    //                                           16.128MHz  640/96/80/208    200/22/3/37   N/N XOR TTL
    //   18 MB-S1    日立 MB-S1 の 80 桁 640x200 (2026-11-19)。16.128MHz (32.256MHz ÷ 2、MAME の bml3 と同じ)、
    //               H / V はユーザー提供の CRTC (HD6845) の値 → 15.75kHz / 60.11Hz。同期の出し方は資料がなく推定 (SEP・N/N)。
    //               CRTC の VSYNC はラインの頭 (表示の始まり) で切り替わるので VS OFS = 同期 + BP = 264 も入れる (pfix = 2。SYNC LV は入れない)
    //                                           16.128MHz  640/120/80/184   200/24/8/30   N/N SEP  (VS OFS 264)
    //   19 FM16B200 富士通 FM-16β の 200 ライン 640x200 (2026-11-19、ユーザー提供の CRTC の値)。H 合計 1024 なので 15.75kHz と見て
    //               16.128MHz (FM-7 と同じ。資料で未確認) → 60.11Hz。V FP 0 (表示の直後に垂直同期)。同期の出し方は推定 (SEP・N/N)、
    //               VS OFS = 同期 + BP = 224 (CRTC の VSYNC はラインの頭)
    //                                           16.128MHz  640/160/64/160   200/0/16/46   N/N SEP  (VS OFS 224)
    //   20 FM16B400 FM-16β の 400 ライン 640x400。21.0526MHz、H 合計 864 = 24.37kHz、V 合計 440 = 55.38Hz
    //               (Common Source Code Project の fm16beta と同じ)。同期の出し方は推定、VS OFS = 同期 + BP = 160
    //                                           21.0526MHz 640/64/64/96     400/0/16/24   N/N SEP  (VS OFS 160)
    //   21 FP11 40  カシオ FP-1100 の 40 桁 320x200 (2026-11-19、ユーザー提供の推定値)。CRTC は HD6845S でソフトが書く。
    //               80 桁 15.9744MHz (MAME の MAIN_CLOCK) の ÷ 2、H 合計 512 → 15.60kHz、V 合計 261 → 59.77Hz (CSP の fp1100 と同じ)。
    //               同期の出し方は推定 (SEP・N/N)、VS OFS = 同期 + BP = 128 (pfix = 2)
    //                                           7.9872MHz  320/64/40/88     200/24/3/34   N/N SEP  (VS OFS 128)
    //   22 FP11 80  FP-1100 の 80 桁 640x200。15.9744MHz、VS OFS 256
    //                                           15.9744MHz 640/128/80/176   200/24/3/34   N/N SEP  (VS OFS 256)
    //   23 PC-98    PC-9801 24kHz 640x400       21.0526MHz 640/64/64/80     400/7/8/25    N/N SEP
    //   24 PC98 GDC μPD7220A に PC-9801F の ROM の設定  21.0526MHz 640/80/64/64  400/7/8/25    N/N SEP
    //   25 PC98HR   PC-98 ハイレゾ (XA / XL / XL2 / RL・98 ハイレゾボード) の 32.84kHz インターレース (2026-11-17)。
    //               テクニカルデータブック HARDWARE 編 (1993) p.351: H 30.45µs、HDISP 23.41 / HFP 2.34 / HS 1.76 / HBP 2.93µs、
    //               V はフィールド 410.5H (80Hz)、VDISP 375H、VFP 8 / 8.5H、VS 5H、VBP 22.5 / 22H。47.8MHz のためドットクロックの
    //               上限を 48MHz に上げた。50kHz のノンインターレース (H98 と同じ) は 70MHz 前後で範囲外
    //                                           47.81504MHz 1120/112/84/140 750/8/5/22   N/N SEP  INTER
    //   26 X68K768H X68000 31kHz 768x512        34.776MHz  768/72/120/144   512/15/6/35   N/N SEP
    //   27 X68K512H X68000 31kHz 512x512        23.184MHz  512/48/80/96     512/15/6/35   N/N SEP
    //               (69.552MHz 発振器を 1/2・1/3 に分周した実際のドットクロック。
    //                CRTC R00〜R08 = IOCS 標準値: 768 は $89,$0E,$1C,$7C,$237,$05,$28,$228
    //                512 は $5B,$09,$11,$51,$237,$05,$28,$228 → H 31.50kHz / V 55.46Hz)
    //               H の表示は CRTC の R02 + 5 文字目から R03 + 5 文字目まで (R02 / R03 から 4 文字遅れて出る、2026-11-17)。
    //                根拠: スプライトの表示開始 = R02 + 4 (Seafy 氏「X68000 CRTC の設定資料」、実機で確かめた設定例) と、
    //                640x480 (CRTMOD $13) の R01 / R02 / R03 がこの読み方で VGA の 96 / 48 / 16 にちょうど合うこと。
    //                前は R02 + 1 文字目からと読んで FP が 32 ドット多く BP が 32 ドット少なかった (768: 104/120/112、512: 80/80/64)
    //   28 X68K384H X68000 31kHz 384x256 (ラインを 2 回ずつ。モード番号なし、HRL = 1 で 69.552MHz/4)
    //                                           17.388MHz  384/40/56/72     512/15/6/35   N/N SEP
    //   29 X68K256H X68000 31kHz 256x256 (CRTMOD $02、ラインを 2 回ずつ。69.552MHz/6)
    //                                           11.592MHz  256/24/40/48     512/15/6/35   N/N SEP
    //   30 X68K640H X68000 31kHz 640x480 (CRTMOD $13、Compact XVI 以降。50.35MHz/2。H は VGA と同じ、V は FP 11 / BP 32)
    //                                           25.175MHz  640/16/96/48     480/11/2/32   N/N SEP
    //   31 X68K24K  X68000 24kHz 1024x424 (CRTMOD $11。69.552MHz/2 → 24.70kHz / 53.12Hz)
    //                                           34.776MHz  1024/96/128/160  424/8/8/25    N/N SEP
    //   32 X68K24KI X68000 24kHz 1024x848 (CRTMOD $12、$11 のインターレース。V はフィールドの値)
    //                                           34.776MHz  1024/96/128/160  848/8/8/25    N/N SEP  INTER
    //   33 X68K15K  X68000 15kHz 256x256 (CRTMOD $03、見えるのは 240 ライン。38.864MHz/8)
    //                                           4.858MHz   256/8/16/24      240/3/3/14    N/N SEP
    //               (28〜34 は 2026-11-17。値は XEiJ の CRTC.java の CRTMOD の表の R00〜R07 を 26 / 27 と同じ読み方 (表示は R02 + 5 文字目から) で。
    //                15kHz の V 同期は R05 = $0002 → 3 ライン (表の注記の 2-1 ではなく値から)。
    //                インターレースのフィールドのライン数 (こちらは 1 フィールドおきに 1 ライン多い) が実機と同じかは未確認)
    //   34 X68K15KI X68000 15kHz 512x512 (CRTMOD $01、インターレースで見えるのは 480 ライン。38.864MHz/4)
    //                                           9.716MHz   512/16/32/48     480/3/3/14    N/N SEP  INTER
    //   35 VGA60    PC/AT VGA 640x480@60        25.175MHz  640/16/96/48     480/10/2/33   N/N SEP
    //   36 VGA70    PC/AT VGA 640x400@70        25.175MHz  640/16/96/48     400/12/2/35   N/P SEP
    //   37 MAC 128K Macintosh 128K 512x342      15.6672MHz 512/14/128/50    342/4/4/20    N/N SEP
    //   38 AMIGA    Amiga NTSC 320x200          7.15909MHz 320/32/34/69     200/21/3/38   N/N XOR TTL
    //   39 C64      Commodore 64 NTSC 418x235   8.181816MHz 418/20/38/44    235/10/3/15   N/N XOR LOW
    //   40 TAITO F3 タイトー F3 基板 320x232 (2026-11-19)。26.686MHz ÷ 4、H 432・V 262 (MAME の taito_f3) → 15.44kHz / 58.94Hz。
    //               同期は EQ の F3 の形 (EQ FORM ` O 4 4 7` = 0x890、capture_plan.md 14.18)。FP / 同期 / BP の分け方は推定
    //                                           6.6715MHz  320/36/32/44     232/5/3/22    N/N EQ TTL (EQ FORM 0x890)
    //   41 MAPPY    ナムコのマッピー / スーパーパックマン / ドルアーガの塔 などの基板 288x224 (2026-11-19)。18.432MHz ÷ 3、
    //               H 384・V 264 (MAME の mappy) → 16.00kHz / 60.61Hz。H / V の FP / 同期 / BP はユーザー提供の実測 (HSYNC 424〜455・VSYNC 504〜511)、
    //               V はライン = H の同期の始まりで進むので VS OFS 0。複合同期は XOR (ユーザーの指定)
    //                                           6.144MHz   288/24/32/40     224/8/8/24    N/N XOR TTL
    //   PC-9801 (24kHz) は 23 PC-98、PC-8801 の 24kHz は 13 PC-88 HI (どちらも MAME の画面設定と同じ値)
    //   (SCAN はプリセットを選ぶと 2 / 3 / 8 / 25 / 32 / 34 で INTER、ほかは PROG になる)
    //   電圧 (SYNC LV): 複合同期 (XOR) のプリセットは、実機の同期のつなぎ方に合わせて入れる (2026-10-31)。
    //     TTL: FM-7 (TTL の同期)、メガドライブ (2 の CSYNC 端子は TTL。初代国内版は映像から取るので LOW 相当)、
    //          Amiga (23 ピンの CSYNC は TTL)
    //     LOW: MSX (MSX2 の RGB21 = 映像と同じ 75Ω の低いレベル)、ファミコン・C64 (RGB 出力はなく同期は映像の中)
    //     PC-88 HI / PC80/88L / X1 / X1TURBO は SEP だが TTL (回路図で確認。VSYNC の位置 VS OFS も入れる。pfix)
    //     そのほかの別々の同期 (SEP) のプリセットは SYNC LV を PRESET を選び始める前の値のままにする
    // 値の表は tools/make_menu_rom.py の PRESETS (2026-11-12 に preset() / pname() / pfix() の LUT の表から移した。容量削減)。
    //   rtl/preset.hex: アドレス = プリセット番号 × 32 + 項目 (I_* と同じ番号。1 = pfix、16 / 17 = 名前)、1 語 32 ビット
    //   pfix: bit0 = SYNC LV を表の値にする (複合同期と、回路図で確かめた PC-88 HI / PC80/88L / X1 / X1TURBO / X1 40 = TTL)、
    //         bit1 = VS OFS を表の値にする (PC80/88L 168 = PC-8801FA の実測、PC-88 HI 120 = 推定、X1 184・X1TURBO 152・X1 40 88 =
    //         HD46505 のラインの頭)。0 の項目は PRESET を選び始める前の値に戻す (送る途中で通ったプリセットの値を残さない)
    //   選んだとき (と TV OUT の標準タイミング) は pl_* の順番で 1 項目ずつ読んで v[] に書く (pfix → DOTCLK → H / V … → 名前、約 20 クロック)
    reg [31:0] prom [0:2047];          // 64 個 × 32 語 (2026-11-17 に 32 個から広げた)
    initial $readmemh(PRESET_FILE, prom);
    reg [31:0] prom_q;
    reg        pl_run, pl_tv, pl_dv;  // 読んでいる / TV OUT の標準タイミング (0〜12 と名前だけ) / prom_q が有効
    reg [5:0]  pl_p;                  // プリセット番号 (0〜63)
    reg [4:0]  pl_k, pl_kd;           // 読む項目 / prom_q の項目
    reg [1:0]  pl_fx;                 // 読んだ pfix
    always @(posedge clk) prom_q <= prom[{pl_p, pl_k}];

    // ---- 名前に使う文字 (空白 A-Z 0-9 - + . / _) ----
    function [7:0] cnext(input [7:0] c);
        if (c == " ") cnext = "A";
        else if (c >= "A" && c < "Z") cnext = c + 8'd1;
        else if (c == "Z") cnext = "0";
        else if (c >= "0" && c < "9") cnext = c + 8'd1;
        else if (c == "9") cnext = "-";
        else if (c == "-") cnext = "+";
        else if (c == "+") cnext = ".";
        else if (c == ".") cnext = "/";
        else if (c == "/") cnext = "_";
        else cnext = " ";
    endfunction
    function [7:0] cprev(input [7:0] c);
        if (c == "A") cprev = " ";
        else if (c > "A" && c <= "Z") cprev = c - 8'd1;
        else if (c == "0") cprev = "Z";
        else if (c > "0" && c <= "9") cprev = c - 8'd1;
        else if (c == "-") cprev = "9";
        else if (c == "+") cprev = "-";
        else if (c == ".") cprev = "+";
        else if (c == "/") cprev = ".";
        else if (c == "_") cprev = "/";
        else cprev = "_";
    endfunction

    // ---- 増減幅 ----
    //   DOTCLK は 1k → 10k → 100k → 1M → 100 → 1k (2026-11-06 に 100 を追加。sidx = 4 は DOTCLK だけ)
    //   ほかは 1 → 10 → 100 → 1000 (DOTCLK の 100 のまま項目を移ったときは 1000 で、次は 1)
    reg [2:0] sidx;
    always @(*) begin
        if (cur == I_SLOT)
            step_val = 1;
        else if (cur == I_DOT)
            case (sidx) 3'd0: step_val = 1_000; 3'd1: step_val = 10_000;
                        3'd2: step_val = 100_000; 3'd3: step_val = 1_000_000; default: step_val = 100; endcase
        else
            case (sidx) 3'd0: step_val = 1; 3'd1: step_val = 10;
                        3'd2: step_val = 100; default: step_val = 1000; endcase
    end

    // 合計 (表示用)。めったに変わらないのでレジスタに入れる (足し算 3 つを 1 クロックに続けない)
    //   インターレースの V はフィールドの表示ライン数 (V ACTIVE + 1) / 2 で数え、フレームは 2 倍 + 1
    //   表示 (No.16) は H 合計 × 10000 + V 合計 (10000 = 8192 + 1024 + 512 + 256 + 16 を足し算で、段ごとにレジスタ)
    //   幅は値の範囲から (2026-11-07): 各項目は 12 ビット (LOAD でも 4095 まで) なので、H 合計は 14 ビット、
    //   V のフレームは 15 ビットで足りる
    reg  [13:0] hsum1, hsum2, vsum1, vsum2, htot, vtot_f, vavs;
    reg  [11:0] vah;
    reg  [14:0] vtot;
    //   同じ形の表示 H × 10000 + V をキャプチャの ACTIVE (No.28、H / V ACTIVE) と C.TOT (No.29、推定の合計) でも使う。
    //   掛け算の足し算は 1 組を 8 クロックずつ順に使い回し、結果をそれぞれのレジスタに取る (2026-11-07)
    reg  [26:0] tt1, tt2, tt3, tot_disp, act_disp, ctot_disp, fq_disp;
    reg  [13:0] fq_h, fq_v;        // 周波数の表示 (No.17): H [10Hz] / V [0.01Hz]、どちらも 9999 まで (下の周波数の計算で書く)
    reg  [4:0]  tq;                // bit4:3 = 今の組 (0 TOTAL / 1 ACTIVE / 2 C.TOT / 3 FREQ)、bit2:0 = 組の中のクロック
    reg  [13:0] tq_h;
    reg  [14:0] tq_v;
    always @(posedge clk) begin
        vah   <= vr[I_SCAN][0] ? ((vr[I_VA] + 27'd1) >> 1) : vr[I_VA];
        hsum1 <= vr[I_HA] + vr[I_HF]; hsum2 <= vr[I_HS] + vr[I_HB]; htot <= hsum1 + hsum2;
        vsum1 <= vah + vr[I_VF]; vsum2 <= vr[I_VS] + vr[I_VB]; vtot_f <= vsum1 + vsum2;
        vtot  <= vr[I_SCAN][0] ? {vtot_f, 1'b1} : {1'b0, vtot_f};
        tq    <= rst ? 5'd0 : tq + 5'd1;
        case (tq[4:3])
        2'd0:    begin tq_h <= htot;               tq_v <= vtot; end
        2'd1:    begin tq_h <= {2'd0, au_h ? e_ha : cap_ha}; tq_v <= {3'd0, au_v ? e_va : cap_va}; end   // AUTO の側は推定に使った値 (表示は AUTO か ?)
        2'd2:    begin tq_h <= {2'd0, e_ht};       tq_v <= e_il ? {2'd0, e_vt, 1'b1} : {3'd0, e_vt}; end
        default: begin tq_h <= fq_h;   tq_v <= {1'b0, fq_v}; end   // 周波数 (2026-11-20 から。前は WAV の情報 LN/WRD)
        endcase
        tt1   <= {tq_h, 13'd0} + {3'd0, tq_h, 10'd0};
        tt2   <= {4'd0, tq_h, 9'd0} + {5'd0, tq_h, 8'd0} + {9'd0, tq_h, 4'd0};
        tt3   <= tt1 + tt2;
        if (tq[2:0] == 3'd7) begin                 // 組を変えてから 4 クロック以上たっている
            case (tq[4:3])
            2'd0:    tot_disp  <= tt3 + tq_v;
            2'd1:    act_disp  <= tt3 + tq_v;
            2'd2:    ctot_disp <= tt3 + tq_v;
            default: fq_disp   <= tt3 + tq_v;
            endcase
        end
    end

    // 周波数 (No.17、2026-11-05 に H FREQ / V FREQ を 1 行に): H [10Hz] × 10000 + V [0.01Hz]
    //   H [Hz] ÷ 10 は udiv で数十クロックかけて (1024 クロックごとに。割り算器は共有なので間を空ける、2026-11-14)。
    //   どちらも 9999 で止める (99.99kHz / 99.99Hz)
    reg  [9:0]  fq_t;
    wire [46:0] fq_q;
    wire [29:0] fq_r;
    wire        fq_done;
    generate if (SHARED) begin : g_sd
        assign fq_q = sd_quo; assign fq_r = sd_rem; assign fq_done = sd_done;
    end else begin : g_sd_l
        udiv #(.NW(47), .DW(30)) u_fq (.clk(clk), .start(fq_t == 10'd0), .num({20'd0, ro_hfreq}), .den(30'd10),
                                       .quo(fq_q), .rem(fq_r), .done(fq_done));
    end endgenerate
    assign sd_start = (fq_t == 10'd0); assign sd_num = {20'd0, ro_hfreq}; assign sd_den = 30'd10;
    //   H × 10000 + V は合計の表示と同じ足し算の組 (上の tq の 4 組目) で作る (2026-11-20、前は専用の足し算 4 つ)
    always @(posedge clk) begin
        fq_t <= rst ? 10'd1 : fq_t + 10'd1;
        if (fq_done) fq_h <= (fq_q > 47'd9999) ? 14'd9999 : fq_q[13:0];
        fq_v <= (ro_vfreq > 27'd9999) ? 14'd9999 : ro_vfreq[13:0];
    end

    // ---- TV OUT 中に変更できない項目 ----
    //   lk_vga: OFF 以外ではテレビに効かない項目 (HS POL / VS POL / VS OFS / SYNC / SYNC LV)
    //   lk_fix: FIX では自動で決まる項目 (DOTCLK / V BP)。V BP はフィールドで 262 / 312 ライン (インターレースは
    //           フレーム 525 / 625) になるように決める
    //   どちらも決定した TV OUT (tv_cmt) で決める。TV OUT の値を変えている途中 (選択肢を送っている間) は前のまま
    reg [3:0] tv_cmt = 4'd0;
    reg lk_vga = 1'b0, lk_fix = 1'b0, fx_625 = 1'b0, eq_w = 1'b0;
    always @(posedge clk) begin
        if (!(edit && cur == I_TV)) tv_cmt <= vr[I_TV][3:0];
        lk_vga <= (tv_cmt != 4'd0);
        eq_w   <= (vr[I_SYNC][1:0] == 2'd3);   // 作業中の SYNC = EQ: No.14 は EQ FORM (2026-11-13)
        lk_fix <= tvfix(tv_cmt);
        fx_625 <= tv625(tv_cmt);
    end
    function locked(input [4:0] i);
        locked = (lk_vga && (i == I_HPOL || i == I_VPOL || i == I_VOFS || i == I_SYNC || i == I_SLV)) ||
                 (lk_fix && (i == I_DOT || i == I_VB));
    endfunction

    // ---- FIX: DOTCLK = H 合計 × 標準の水平周波数 (逐次の掛け算、1 クロックに 1 ビット) ----
    //   K = 水平周波数 × 2^16 (525 ライン系 4.5MHz / 286 × 2^16、625 ライン系 15625 × 2^16。どちらも 30 ビット)
    //   DOTCLK = (H 合計 × K + 2^15) / 2^16 を 1〜48MHz に収める。いつも回しておき、FIX のときだけ使う
    //   2026-11-20 容量削減: K を固定して積を右へずらす形に (cap_est と同じ)。乗数 (H 合計 13 ビット) は積のレジスタの下位に入れ、
    //   毎クロック下位 1 ビットを見て上位 30 ビットに K を足し (31 ビットの足し算)、全体を 1 ビット右へ。13 回で 43 ビットの積
    //   (前は 44 ビットの K を左へずらして 44 ビットに足していた)
    localparam [29:0] K525 = 30'd1031160839, K625 = 30'd1024000000;
    reg [42:0] macc = 43'd0;
    reg [3:0]  mcnt = 4'd0;
    reg        mrun = 1'b0;
    reg [27:0] fx_raw = 28'd0;
    reg [26:0] fx_dot = 27'd13_500_000;
    wire [30:0] m_sum = {1'b0, macc[42:13]} + (macc[0] ? {1'b0, fx_625 ? K625 : K525} : 31'd0);
    always @(posedge clk) begin
        if (!mrun) begin
            macc <= {30'd0, (htot > 27'd8191) ? 13'h1FFF : htot[12:0]}; mcnt <= 4'd0; mrun <= 1'b1;
        end else if (mcnt == 4'd13) begin
            fx_raw <= {1'b0, macc[42:16]} + macc[15]; mrun <= 1'b0;
        end else begin
            macc <= {m_sum, macc[12:1]}; mcnt <= mcnt + 4'd1;
        end
        fx_dot <= (fx_raw > 28'd48_000_000) ? 27'd48_000_000 :
                  (fx_raw < 28'd1_000_000)  ? 27'd1_000_000  : fx_raw[26:0];
    end
    // FIX の V BP = 262 / 312 - (V ACTIVE + FP + SYNC) (足りなければ 1)
    reg [26:0] fx_vb = 27'd15;
    always @(posedge clk) begin
        vavs  <= vsum1 + vr[I_VS];
        fx_vb <= (vavs + 27'd1 > (fx_625 ? 27'd312 : 27'd262)) ? 27'd1 : (fx_625 ? 27'd312 : 27'd262) - vavs;
    end

    // ---- ユーザープリセット ----
    assign st_slot = vr[I_SLOT][2:0] - 3'd1;
    assign st_wslot = vr[I_LMIN][2:0] - 3'd1;
    assign slot_no = vr[I_SLOT][3:0];
    reg  [1:0] msg_op;        // 0 なし 1 LOAD 2 SAVE
    reg        msg_ok, msg_w; // msg_w: 波形のスロットの結果 (RAW SAVE / LOAD に出す)
    wire [63:0] slot_name = st_valid[st_slot] ? st_name : "(EMPTY) ";
    // 表示コード
    wire [26:0] load_code = st_busy ? 4 : (msg_op == 2'd1 && !msg_w) ? (msg_ok ? 2 : 3) : st_valid[st_slot] ? 0 : 1;
    wire [26:0] save_code = st_busy ? 4 : (msg_op == 2'd2 && !msg_w) ? (msg_ok ? 2 : 3) : 0;
    wire [26:0] wload_code = st_busy ? 4 : (msg_op == 2'd1 && msg_w) ? (msg_ok ? 2 : 3) : 0;   // RAW LOAD (スロットは No.29 RAW SLOT の番号)
    wire [26:0] wsave_code = st_busy ? 4 : (msg_op == 2'd2 && msg_w) ? (msg_ok ? 2 : 3) : 0;

    // 名前 8文字 ↔ EEPROM の byte23〜30 (先頭の文字が byte23)
    function [63:0] rev8(input [63:0] x);
        integer k;
        for (k = 0; k < 8; k = k + 1) rev8[k*8 +: 8] = x[(7-k)*8 +: 8];
    endfunction
    // フラグ (byte22): bit7・bit5:4 = 以前のパターン (2026-11-14 に保存をやめた。0 を書き、読むときは無視する。LOAD してもパターンは変わらない)
    //                 bit6 = 以前の AUTOTRIM (今は使わない。0 を書き、読むときは無視する)
    // VS OFS (12 ビット、2026-11-05 追加) は H SYNC・H BP・V ACTIVE の上位 4 ビット (使っていない) に下から 4 ビットずつ。
    //   以前の保存は 0 (HSYNC の始まり) として読む。この 3 項目は下位 12 ビットだけ読む
    // byte5 の bit7 (DOTCLK の bit31、使っていない) = 1 で同期の電圧 TTL (2026-10 追加。0 = LOW なので、以前の保存は LOW として読む)
    // byte5 の bit3〜5 (DOTCLK の bit27〜29) = TV OUT の方式 (2026-10-22 追加。以前の保存は 0 = OFF として読む)
    // byte5 の bit6 (DOTCLK の bit30) = TV OUT の FIX (2026-10-23 追加。以前の保存は 0)
    // byte9 の bit7 (H FP の bit15、使っていない) = SCAN (1 = INTER。2026-10-23 追加。以前の保存は PROG)。H FP は下位 12 ビットだけ読む
    // byte7 の bit7 (H ACTIVE の bit15) = 以前のパターンの bit3 (2026-11-14 に保存をやめた。0 を書き、無視する)。H ACTIVE は下位 12 ビットだけ読む
    wire [7:0] flags = {4'd0, vr[I_SYNC][1:0], vr[I_VPOL][0], vr[I_HPOL][0]};
    assign pk_data = {8'd0, rev8(wname), flags,
                      vr[I_VB][15:0], vr[I_VS][15:0], vr[I_VF][15:0], {vr[I_VOFS][11:8], vr[I_VA][11:0]},
                      {vr[I_VOFS][7:4], vr[I_HB][11:0]}, {vr[I_VOFS][3:0], vr[I_HS][11:0]}, {vr[I_SCAN][0], 3'd0, vr[I_HF][11:0]}, {4'd0, vr[I_HA][11:0]},
                      ~vr[I_SLV][0], tvfix(vr[I_TV][3:0]), tvm(vr[I_TV][3:0]), vr[I_DOT], 8'h01, 8'h00};
    // LOAD の受け取り (2026-11-13、容量削減): byte 1〜30 が 1 バイトずつ来る。下位バイト・DOTCLK の下位などは
    //   ld_t に取っておき、上位バイトが来たときに項目へ書く。byte 1 (形式) が 0x01 でなければ書かない (ld_ok)
    reg  [23:0] ld_t;              // [7:0] 直前のバイト、[23:8] DOTCLK の byte 2・3 / VS OFS の下位 8 ビット
    reg         ld_ok;             // 形式が合う
    wire        ld_end = ld_we && ld_ok && (ld_idx == 5'd30);   // 最後のバイト (このあと値がそろう)

    // ---- 確定 ----
    assign pending = (vr[I_DOT] != dot_target) ||
                     (vr[I_HA] != cfg_h_active) || (vr[I_HF] != cfg_h_fp) || (vr[I_HS] != cfg_h_sync) || (vr[I_HB] != cfg_h_bp) ||
                     (vr[I_VA] != cfg_v_active) || (vr[I_VF] != cfg_v_fp) || (vr[I_VS] != cfg_v_sync) || (vr[I_VB] != cfg_v_bp) ||
                     (vr[I_HPOL][0] != cfg_hs_neg) || (vr[I_VPOL][0] != cfg_vs_neg) || (vr[I_VOFS][11:0] != cfg_vs_ofs) || (vr[I_SYNC][1:0] != cfg_csync) ||
                     (vr[I_SLV][0] != cfg_sync_lv) || (tvm(vr[I_TV][3:0]) != cfg_tv_mode) ||
                     (vr[I_SCAN][0] != cfg_interlace);
    // RAW LOAD・RAW REC のあと、APPLY (で RAW PLAY が ON になる) までは出力に反映されていないので、* と CHANGED を出す (2026-11-26 ユーザーの依頼)
    reg         wpl;              // 波形の APPLY 待ち (下の波形コピーの always で作る)
    assign pend_m = pending || wpl;
    reg [31:0] at;
    reg        boot_apply, force_osc;
    reg        pmod;              // PRESET の欄を (CUSTOM) に (下の ed_chg の説明、2026-11-18)
    // APPLY を始めたときの作業中の値 (この一式で最後まで処理する。2026-10-26 修正:
    //   以前はクロックの安定待ちの間の LOAD・編集が、あとで出すタイミングに混ざっていた)
    reg        osc_fail;          // 前の APPLY でドットクロックが目標に合わないまま時間切れ
                                  //   (次の APPLY は同じ設定でもクロックを書き直して実測を確かめ、合ったときだけ消す)
    // 同期の電圧を LOW から TTL に上げる APPLY は確かめてから (2026-11-17、回路を守るため):
    //   今の出力が LOW (cfg_sync_lv = 1) で作業中の値が TTL のとき、1 回目の APPLY では確定せず、APPLY の行に
    //   TTL OK? を出す (ttl_ok)。もう一度 APPLY (SEL / STEP 長押し / SEL 長押し) で確定する。カーソルが APPLY から
    //   離れる・値を変える状態に入る・TTL に上げる変更でなくなる、のどれかで取り消し。電源投入時の APPLY は確かめない (初期値は LOW)
    wire        ttl_up = !vr[I_SLV][0] && cfg_sync_lv;
    reg         ttl_ok;
    wire [26:0] apply_code = (ast != A_IDLE) ? 2 : cap_clash ? 4 : ttl_ok ? 5 : osc_fail ? 3 : pend_m ? 1 : 0;   // 4 = CLASH (ぶつかりで出力を止めた)、5 = TTL OK?
    reg         lp_apply;          // SEL 長押しの確定 (1 クロック。下の always で作る)
    //   LOAD・保存 (st_busy)・プリセットの読み込み (pl_run) の途中は始めない (作業中の値がそろってから。ap_* をなくしたので、2026-11-27)
    wire        apply_raw  = (b_apply || lp_apply || (b_next && !edit && cur == I_APPLY) || boot_apply) && !st_busy && !pl_run;
    wire        apply_req  = apply_raw && (!ttl_up || ttl_ok || boot_apply);
    wire        ttl_ask    = apply_raw && ttl_up && !ttl_ok && !boot_apply && ast == A_IDLE;

    // 測定中 (THR / RUN) は ACTIVE を変えられない (2026-11-10。推定はその回の始めに取り込んだ解像度で行い、e_ha / e_va で返る)
    wire       cmeas = cap_en && (cap_status == 4'd1 || cap_status == 4'd2);

    // ---- 読み出し ----
    wire eq_txt = (rd_item == I_VOFS) && eq_w && !lk_vga;   // EQ FORM の表示 (TV OUT で変更不可のときは今までどおり)
    always @(*) begin
        rd_text = 64'd0; rd_cursor = 4'd8;
        case (rd_item)
            I_MEAS: rd_val = ro_meas;
            I_HFRQ: rd_val = fq_disp;
            I_TOT:  rd_val = tot_disp;
            I_LOAD: rd_val = load_code;
            I_SAVE: rd_val = save_code;
            I_APPLY: rd_val = apply_code;
            I_LRUN: rd_val = wav_en ? {wav_lines, wav_stat == 3'd4, 11'd0, (wav_stat == 3'd0 && !(cpd && !pending)) ? 3'd6 : wav_stat} :   // 6 = NEED CAP   // RAW REC: [26:15] ライン数、[14] 添える (DONE のとき)
                             !cap_en ? lag_status : !act_ok ? 27'd12 :   // 12 = SET ACT (ACTIVE を決定するまで。2026-11-15)
                             {10'd0, cap_rrv && (cap_status == 4'd2 || cap_status == 4'd3), cap_rr, 4'd0, cap_status};
                    // CAP RUN: [3:0] 状態、[15:8] 推定の端数、[16] 端数を添える (RUN / DONE のとき)
            I_LAVG: rd_val = wav_en ? {26'd0, wav_play} : cap_en ? act_disp : lag_avg;   // RAW PLAY: OFF / ON
            I_LMIN: rd_val = wav_en ? vr[I_LMIN] : cap_en ? ctot_disp : lag_min;         // RAW SLOT (1〜8、2026-11-20)
            I_LMAX: rd_val = wav_en ? wsave_code : cap_en ? e_dot : lag_max;               // RAW SAVE / LOAD (2026-11-13)
            I_LCMD: rd_val = wav_en ? wload_code : cap_en ? {25'd0, cp_code} : 27'd0;   // LAG では使わない (CMD AVG は 2026-11-21 に外した)
            I_MODE: rd_val = vr[I_MODE] + {26'd0, (vr[I_MODE][2:0] == 3'd4) && cap_sw};   // CAP SELF でもスイッチが IN なら CAP IN と表示
            I_PRE:  rd_val = pmod ? 27'd63 : vr[I_PRE];   // プリセットから値を変えた・LOAD した: (CUSTOM) (2026-11-18)
            default: rd_val = vr[rd_item];
        endcase
        if (rd_item == I_SLOT) rd_text = slot_name;
        if (rd_item == I_NAME) begin rd_text = wname; rd_cursor = (cur == I_NAME && edit) ? {1'b0, cpos} : 4'd8; end
        if (rd_item == I_LAVG) rd_cursor = {3'd0, acv};          // ACTIVE: 値を変えている方 (0 = H、1 = V)
        // 推定の印 (2026-11-15): AUTO にした側は、DONE までは AUTO、DONE のあとは推定に使った値 + ?。
        //   C.TOT の H 合計・C.DOT は H を AUTO で推定したとき (途中の結果も) ?。V 合計は測った値なので付けない
        rd_q = 2'd0; rd_auto = 2'd0;
        if (cap_en && rd_item == I_LAVG) begin
            rd_q    = {au_v && qa_v && cap_status == 4'd3, au_h && qa_h && cap_status == 4'd3};
            rd_auto = {au_v && !(qa_v && cap_status == 4'd3), au_h && !(qa_h && cap_status == 4'd3)};
        end
        if (cap_en && (rd_item == I_LMIN || rd_item == I_LMAX))
            rd_q = {1'b0, qa_h && (cap_status == 4'd2 || cap_status == 4'd3)};
        if (eq_txt) begin                                         // EQ FORM: " E 4 8 6" (変えている欄を反転)
            rd_text = {" ", vr[I_VOFS][11] ? "O" : "E", " ", 8'h31 + {5'd0, vr[I_VOFS][10:8] ^ 3'd3}, " ",
                       8'h31 + {5'd0, vr[I_VOFS][7:5] ^ 3'd7}, " ", vr[I_VOFS][4] ? "7" : "6"};
            rd_cursor = (cur == I_VOFS && edit) ? {1'b0, eqf, 1'b1} : 4'd8;
        end
        rd_kind = (wav_en && rd_item >= I_LRUN) ? ((rd_item == I_LMIN) ? 2'd0 : 2'd1) :   // WAV: RAW SLOT は数字、ほかは選択肢
                  (rd_item == I_SLOT || rd_item == I_NAME || eq_txt) ? 2'd3 :
                  (n_enum(rd_item) != 0 || rd_item == I_LOAD || rd_item == I_SAVE ||
                   rd_item == I_APPLY || rd_item == I_LRUN || (cap_en && rd_item == I_LCMD)) ? 2'd1 :
                  (rd_item >= I_LAVG && !cap_en) ? 2'd2 : 2'd0;
    end

    assign rd_lock = locked(rd_item);
    // 変更できない項目: 表示だけ (MEAS・FREQ・TOTAL・LAG の結果・C.TOT / C.DOT) と TV OUT で変更不可のもの
    //   (SEL で実行する LOAD / SAVE / APPLY / LAG RUN / CAP RUN / COPY は含めない)
    assign rd_ro   = locked(rd_item) || (rd_item == I_MEAS) || (rd_item == I_HFRQ) || (rd_item == I_TOT) ||
                     (wav_en ? 1'b0 :
                      cap_en ? (rd_item == I_LMIN || rd_item == I_LMAX || (rd_item == I_LAVG && cmeas) || (rd_item == I_LRUN && !act_ok)) :
                               (rd_item >= I_LAVG));   // ACTIVE は測定中だけ *、CAP RUN は ACTIVE を決定するまで *
    assign rd_mv   = (rd_item == I_LMIN || rd_item == I_LMAX) && (lag_status == 4'd4) && !cap_en && !wav_en;
    assign pattern = vr[I_PAT][3:0];
    assign lag_area = vr[I_MODE][1:0];
    assign lag_sel  = (cur == I_MODE) && !vr[I_MODE][2];   // LAG の範囲を選んでいる (キャプチャの選択肢では出さない)
    // MODE は決定した値で切り替える (選択肢を送っている途中の CAP IN で出力を止めない)
    reg [2:0] md = 3'd2;
    always @(posedge clk) if (rst) md <= 3'd2; else if (!(edit && cur == I_MODE)) md <= vr[I_MODE][2:0];
    assign cap_en = md[2] && !md[1];             // CAP SELF / CAP IN (表示はスイッチに合わせる)
    assign wav_en = (md == 3'd6);                // CAP RAW (波形コピー。No.27〜31 が RAW REC / PLAY / SLOT / SAVE / LOAD)
    assign cap_ha = au_h ? 12'd0 : vr[I_HA][11:0];
    assign cap_va = au_v ? 12'd0 : vr[I_VA][11:0];
    // 遅延測定の開始・中止 (APPLY で出力が止まるときも中止する)
    wire lag_busy = (lag_status == 4'd1) || (lag_status == 4'd2);
    reg         ap_d, wpq;        // APPLY の終わりの検出、RAW LOAD → APPLY → RAW PLAY ON (2026-11-21)
    reg  [1:0]  wrq;              // RAW REC の DONE 待ち: 1 = 押した、2 = 記録が始まった (DONE でなくなった)。DONE になったら wpl (2026-11-26)
    always @(posedge clk) begin
        // LAG RUN で SEL: 待機中なら開始、測定中 (CAL / RUN) なら中止
        lag_start <= !rst && b_next && !edit && cur == I_LRUN && !lag_busy && !cap_en && !wav_en;
        lag_stop  <= !rst && ((b_next && !edit && cur == I_LRUN && lag_busy) || apply_req || ((cap_en || wav_en) && lag_busy));
        // 波形コピー: RAW REC で SEL → 記録 (再生は止める)。CAP RAW でなくなったら止める
        //   RAW PLAY はほかの選択肢と同じく SEL で値を変える状態 (反転) に入り、UP / DOWN で済みの記録があれば ON / OFF、SEL で出る
        //   (2026-11-21。前は SEL ですぐ切り替わり、反転しなかった)
        //   RAW LOAD が成功したら、そのあとの APPLY が済んだところで RAW PLAY を ON にする (wpq: LOAD 中、wpl: APPLY 待ち。2026-11-21)
        ap_d <= (ast != A_IDLE);
        //   RAW REC が DONE になったときも、APPLY を押すと RAW PLAY を ON にする (それまで * と CHANGED。2026-11-26)
        if (rst) begin wav_rec_tgl <= 1'b0; wav_play <= 1'b0; wpq <= 1'b0; wpl <= 1'b0; wrq <= 2'd0; end
        else begin
            if (b_next && !edit && wav_en && cur == I_LCMD && !st_busy && (wav_stat == 3'd0 || wav_stat >= 3'd4)) wpq <= 1'b1;
            else if (st_ok || st_err) wpq <= 1'b0;
            if (b_next && !edit && cur == I_LRUN && wav_en && !st_busy) wrq <= 2'd1;
            else if (!wav_en || wpq) wrq <= 2'd0;
            else if (wrq == 2'd1 && wav_stat != 3'd4) wrq <= 2'd2;
            else if (wrq == 2'd2 && wav_stat == 3'd4) wrq <= 2'd0;
            if ((st_ok || st_err) && wpq) wpl <= st_ok;
            else if (wrq == 2'd2 && wav_stat == 3'd4) wpl <= 1'b1;
            else if ((ap_d && ast == A_IDLE && !osc_fail) || !wav_en || wav_play || (b_next && !edit && cur == I_LRUN)) wpl <= 1'b0;   // CLK ERR の APPLY では残す (再試行で ON に。2026-11-27)
            // REC は EEPROM の読み書き中は始めない (cm を preset_store が使っている。2026-11-14)
            if (b_next && !edit && cur == I_LRUN && wav_en && !st_busy) begin wav_rec_tgl <= ~wav_rec_tgl; wav_play <= 1'b0; end
            else if (!wav_en || wav_stat != 3'd4) wav_play <= 1'b0;
            else if (edit && cur == I_LAVG && (b_up || b_dn)) wav_play <= !wav_play;
            else if (ap_d && ast == A_IDLE && wpl && !osc_fail) wav_play <= 1'b1;
        end
        cap_sel   <= !rst && b_next && !edit && cur == I_LRUN && cap_en && act_ok;
    end

    // TV OUT を決定したときに入れる標準タイミングのプリセット番号
    //   P_TV = NTSC240P の番号。続けて PAL 288P / NTSC480I / PAL 576I (make_menu_rom.py が表の並びと照合する。
    //   2026-11-17 に X68000 のプリセットを 7 個足して 13 → 20、2026-11-18 の並べ替えで先頭の 0 に)
    localparam [4:0] P_TV = 5'd0;
    wire [4:0] tv_std = P_TV + {3'd0, vr[I_SCAN][0], tv625(vr[I_TV][3:0])};   // +0 NTSC240P、+1 PAL 288P、+2 NTSC480I、+3 PAL 576I

    // ---- 値の変更 ----
    // タイミング: 32 項目からの v[cur] の選択・範囲・増減幅は cur / sidx が変わったときだけ変わるので、
    // 毎クロックレジスタに入れておく (ボタンの操作は tick ごとなので 1 クロック遅れても問題ない)。
    // 新しい値 nv もいったんレジスタ (nv_r) に入れ、次のクロックで v[] / プリセット / 名前に書き込む。
    reg  [26:0] cv, mn, mx, sv;
    reg  [6:0]  ne;
    reg         ro, eqc, mdc, mdl;
    //   ACTIVE (No.28、キャプチャ) は H ACTIVE / V ACTIVE (acv) を変える
    wire [4:0]  ecur = act_cur ? (acv ? I_VA : I_HA) : cur[4:0];
    //   AUTO で推定した値 (表示 536?) が出ている側は、UP / DOWN でその値から増減する (2026-11-20。AUTO はやめる)
    wire        aq_c = act_cur && cap_status == 4'd3 && (acv ? (au_v && qa_v) : (au_h && qa_h));
    always @(posedge clk) begin
        cv <= aq_c ? {15'd0, acv ? e_va : e_ha} : vr[ecur]; mn <= vmin(ecur); mx <= vmax(ecur); ne <= n_enum(ecur); ro <= (is_ro(ecur) && !(wav_en && (ecur == I_LMIN || ecur == I_LAVG))) || locked(ecur) || (act_cur && cmeas); sv <= step_val;   // CAP RAW の RAW SLOT・RAW PLAY は変えられる
        eqc <= (ecur == I_VOFS) && eq_w;   // EQ FORM: 欄ごとに変える
        mdc <= (ecur == I_MODE); mdl <= (grp != 2'd3);   // MODE はグループの選択肢の中で回す (LAG CHECK: 0〜3、SYNC CAPTURE: 4〜6)
    end
    // EQ FORM の欄の値: 等化パルス k - 1 = bit10:8 ^ 3、切れ込み m - 1 = bit7:5 ^ 7 (どちらも 0〜7 で止める)
    wire [2:0]  eq_k = cv[10:8] ^ 3'd3, eq_m = cv[7:5] ^ 3'd7;
    wire [2:0]  eq_kn = b_up ? ((eq_k == 3'd7) ? eq_k : eq_k + 3'd1) : ((eq_k == 3'd0) ? eq_k : eq_k - 3'd1);
    wire [2:0]  eq_mn = b_up ? ((eq_m == 3'd7) ? eq_m : eq_m + 3'd1) : ((eq_m == 3'd0) ? eq_m : eq_m - 3'd1);
    reg  [26:0] nv;
    always @(*) begin
        if (eqc) begin
            case (eqf)
            2'd0:    nv = {15'd0, ~cv[11], cv[10:0]};
            2'd1:    nv = {15'd0, cv[11], eq_kn ^ 3'd3, cv[7:0]};
            2'd2:    nv = {15'd0, cv[11:8], eq_mn ^ 3'd7, cv[4:0]};
            default: nv = {15'd0, cv[11:5], ~cv[4], cv[3:0]};
            endcase
        end else if (mdc) begin
            if (mdl)       nv = {25'd0, b_up ? cv[1:0] + 2'd1 : cv[1:0] - 2'd1};
            //   SYNC CAPTURE は CAP (4、表示はスイッチ S2 に合わせて CAP SELF / CAP IN) と CAP RAW (6) の 2 つ。
            //   入力 / 出力はスイッチだけで切り替える (2026-11-21 の仕様変更。メニューの CAP IN (5) はなくした)
            else           nv = (cv[2:0] == 3'd4) ? 27'd6 : 27'd4;
        end else if (ne != 0) begin
            if (b_up) nv = (cv == ne - 1) ? 27'd0 : cv + 27'd1;
            else      nv = (cv == 27'd0) ? ne - 1 : cv - 27'd1;
        end else begin
            if (b_up) nv = (cv + sv > mx) ? mx : cv + sv;
            else      nv = (cv < mn + sv) ? mn : cv - sv;
        end
    end
    wire [7:0] cch = wname[(7 - cpos) * 8 +: 8];
    // 書き込みの 1 段目 (nv と書き込む項目を保持)
    reg  [26:0] nv_r;
    reg  [4:0]  wcur;
    reg         wr_go;
    always @(posedge clk) begin
        nv_r  <= nv;
        wcur  <= ecur;
        wr_go <= !rst && edit && (b_up || b_dn) && !ro && !(act_cur && !aq_c && ((acv ? au_v : au_h) || (b_dn && cv == mn)));   // AUTO の間・AUTO に入るときは値を変えない (推定した値が出ていれば変える)
    end


    // 確定 (APPLY) が要るようになったら、カーソルを APPLY の項目へ移す (2026-10-30 追加、2026-11-05 変更)
    //   PRESET を選んで決定したとき、または LOAD で読み込んだとき (起動時の自動読み込みは除く)。
    //   手で値を変えたときは移らない (確定は APPLY で SEL、SEL 長押し、STEP 長押し)。
    //   値が入るのを待ってから (数クロック後に) pending を見る
    reg        ed_chg;            // 値を変える状態の間に値を変えた
    // pmod (2026-11-18): 作業中の値が、PRESET の欄のプリセットの値ではなくなった (PRESET の欄を (CUSTOM) と表示して混同を防ぐ)。
    //   立てる: プリセットが入れる項目 (DOTCLK・H / V・極性・SYNC・SYNC LV・VS OFS / EQ FORM・SCAN) を手で変えた、
    //           LOAD した (電源投入時のスロット 1 の自動読み込みも)、キャプチャの COPY。
    //   消す:   PRESET でプリセットを選んだ、TV OUT で標準タイミングを入れた
    reg [1:0]  sync_e;            // 値を変える状態に入ったときの SYNC (SEP から複合同期にしたかを見る)
    reg        slv_e;             // 値を変える状態に入ったときの SYNC LV (PRESET を送る途中で変わった分を戻す)
    reg [11:0] vo_e;              // 値を変える状態に入ったときの VS OFS (同上)
    reg [2:0]  jmp_cnt;           // 0 以外: 数えたあとで pending なら APPLY へ
    reg [2:0]  lp_cnt;            // SEL 長押し: 0 以外: 数えたあとで APPLY へ移って確定 (2026-11-05)
    reg        cx_p;              // 前のクロックの cap_clash (ぶつかったらカーソルを APPLY へ)

    integer i;
    always @(posedge clk) begin
        dot_upd <= 1'b0; st_save <= 1'b0; st_load <= 1'b0;
        if (rst) begin
            cur <= 6'h21; grp <= 2'd0; nav_go <= 1'b0; edit <= 1'b0;   // 電源投入時は最初の画面 (SYNC SET/PATTERN の行)
            sidx <= 3'd0; cpos <= 3'd0; acv <= 1'b0; eqf <= 2'd0; au_h <= 1'b0; au_v <= 1'b0;
            act_ok <= 1'b0; qa_h <= 1'b0; qa_v <= 1'b0; cpd <= 1'b0; cs3_p <= 1'b0;
            st_wav <= 1'b0; msg_w <= 1'b0;
            // 電源投入時はプリセット 0 の NTSC240P (2026-11-18、前は VGA60)。スロット 1 に保存があれば、そのあと読み込んで確定する
            v[I_DOT] <= 27'd13_500_000;
            v[I_HA] <= 720; v[I_HF] <= 16; v[I_HS] <= 62; v[I_HB] <= 60;
            v[I_VA] <= 240; v[I_VF] <= 4;  v[I_VS] <= 3;  v[I_VB] <= 15;
            v[I_HPOL] <= 1; v[I_VPOL] <= 1; v[I_SYNC] <= 0;
            pl_run <= 1'b0; pl_dv <= 1'b0; pl_k <= 5'd0;
            v[I_SCAN] <= 0;
            v[I_SLV] <= 1; v[I_VOFS] <= 0; v[I_PAT] <= 0; v[I_PRE] <= 0; v[I_TV] <= 0; v[I_SLOT] <= 1; v[I_LMIN] <= 1; v[I_MODE] <= 2;
            wname <= "USER    ";
            msg_op <= 2'd0; cfg_toggle <= 1'b0;
            dot_target <= 27'd13_500_000;
            cfg_h_active <= 720; cfg_h_fp <= 16; cfg_h_sync <= 62; cfg_h_bp <= 60;
            cfg_v_active <= 240; cfg_v_fp <= 4;  cfg_v_sync <= 3;  cfg_v_bp <= 15;
            cfg_hs_neg <= 1'b1; cfg_vs_neg <= 1'b1; cfg_vs_ofs <= 12'd0; cfg_csync <= 2'd0; cfg_sync_lv <= 1'b1; cfg_tv_mode <= 3'd0; cfg_interlace <= 1'b0;
            out_en <= 1'b0; ast <= A_IDLE; at <= 0; osc_fail <= 1'b0;
            boot_apply <= 1'b1; force_osc <= 1'b1; ttl_ok <= 1'b0;
            cp_code <= 2'd0; cp_cnt <= 3'd0;
            ed_chg <= 1'b0; pmod <= 1'b0; jmp_cnt <= 3'd0; lp_cnt <= 3'd0; lp_apply <= 1'b0; sync_e <= 2'd0; slv_e <= 1'b1; vo_e <= 12'd0;
        end else begin
            // 項目の移動 (項目を選ぶ状態で UP = 上の項目、DOWN = 下の項目)
            //   グループの中の位置で動かし (一番下の次は一番上)、次のクロックで位置 → 項目 (下の nav_go)
            nav_go <= 1'b0;
            if (nav_go) cur <= gmap(grp, nav_p);
            if (!edit && b_up) begin nav_p <= (gp_r[4:0] == 5'd0) ? menu_cnt - 5'd1 : gp_r[4:0] - 5'd1; nav_go <= 1'b1; msg_op <= 2'd0; cp_code <= 2'd0; end
            if (!edit && b_dn) begin nav_p <= (gp_r[4:0] == menu_cnt - 5'd1) ? 5'd0 : gp_r[4:0] + 5'd1; nav_go <= 1'b1; msg_op <= 2'd0; cp_code <= 2'd0; end
            // 階層メニューの行で SEL: BACK は最初の画面へ (カーソルは出てきたグループの行)、最初の画面の行はそのグループへ。
            //   MODE はグループに合わせる: SYNC SET / LAG CHECK に入るときキャプチャなら LAG CENT に (出力を止める CAP IN・再生をやめる)、
            //   SYNC CAPTURE に入るとき LAG なら CAP SELF にして ACTIVE へ (MODE をキャプチャに決定したときと同じ)
            if (b_next && !edit && cur[5]) begin
                if (cur[1:0] == 2'd0) begin grp <= 2'd0; cur <= {4'b1000, grp}; end
                else begin
                    grp <= cur[1:0];
                    if (cur[1:0] == 2'd3) begin
                        if (!md[2]) begin v[I_MODE] <= 27'd4; act_ok <= 1'b0; cur <= I_LAVG; end
                        else cur <= I_MODE;
                    end else begin
                        if (md[2]) v[I_MODE] <= 27'd2;
                        cur <= (cur[1:0] == 2'd1) ? I_DOT : I_MODE;
                    end
                end
            end
            // カーソルが今のグループにない項目へ移ったら、その項目のグループへ (APPLY へ移す・ぶつかりなど)
            if (gp_r[5] && !cur[5]) grp <= (cur <= 6'd25) ? 2'd1 : md[2] ? 2'd3 : 2'd2;
            // SEL: 決定 (値を変える状態に入る / 出る)。
            // SEL 長押し (2026-11-05): 値を変える状態なら出て (決定)、APPLY へ移って確定する。
            //   決定で入る値 (TV OUT の標準タイミング・SYNC LV・FIX の計算) を待ってから (数クロック後に) 確定する
            // ACTIVE (キャプチャ、2026-11-20 ユーザーの依頼): SEL で H ACTIVE → もう一度 SEL で V ACTIVE → もう一度 SEL で決定して出る
            //   (前は STEP の x100 の次で H / V を切り替えていた。STEP は増減幅だけ)
            // EQ FORM (2026-11-23 ユーザーの依頼): SEL で欄を決定して次の欄へ (半ラインずれ → 等化パルスの幅 → 切れ込みの幅 → 数)、
            //   最後の欄で SEL を押すと決定して出る (前は STEP で欄を移っていた)。入るときは最初の欄から
            if (b_next) begin
                if (edit && act_cur && !acv) begin acv <= 1'b1; av_k <= vr[I_VA][11:0]; end   // H → V で増減幅は変えない (2026-11-20)
                else if (edit && cur == I_VOFS && eq_w && eqf != 2'd3) eqf <= eqf + 2'd1;
                else if (edit) edit <= 1'b0;
                else if ((!ro || cur == I_NAME) && !cur[5]) begin edit <= 1'b1; eqf <= 2'd0; if (act_cur) begin acv <= 1'b0; sidx <= 3'd0; ah_k <= vr[I_HA][11:0]; end end   // ACTIVE に入るときは x1
            end
            if (b_prev && edit) edit <= 1'b0;
            // キャプチャの解像度を促す (2026-11-15): MODE をキャプチャ (CAP SELF / CAP IN) に決定したらカーソルを ACTIVE へ。
            //   ACTIVE を決定したら (値はそのままでも) CAP RUN へ。決定するまで CAP RUN は SET ACT で、SEL は ACTIVE へ戻す
            if (edit && (b_next || b_prev) && cur == I_MODE && vr[I_MODE][2:1] == 2'b10 && !cap_en) begin act_ok <= 1'b0; cur <= I_LAVG; end
            if (edit && act_cur && ((b_next && acv) || b_prev)) begin act_ok <= 1'b1; cur <= I_LRUN; end   // V の SEL か長押しで決定
            if (b_next && !edit && cur == I_LRUN && cap_en && !act_ok) cur <= I_LAVG;
            if (b_next && !edit && cur == I_LRUN && cap_en && act_ok && !cmeas) begin qa_h <= au_h; qa_v <= au_v; cpd <= 1'b0; end
            // CAP RUN が DONE になったら、カーソルを COPY へ (COPY のあとは APPLY へ。2026-11-20)
            cs3_p <= cap_en && (cap_status == 4'd3);
            if (cap_en && cap_status == 4'd3 && !cs3_p && cur == I_LRUN && !edit) cur <= I_LCMD;
            // MODE を CAP RAW に決定したら RAW REC へ (2026-11-20)
            if (edit && (b_next || b_prev) && cur == I_MODE && vr[I_MODE][2:0] == 3'd6 && !wav_en) cur <= I_LRUN;
            lp_apply <= 1'b0;
            if (b_prev) lp_cnt <= 3'd4;
            if (lp_cnt != 3'd0) begin
                lp_cnt <= lp_cnt - 3'd1;
                if (lp_cnt == 3'd1) begin
                    if (pl_run || st_busy) lp_cnt <= 3'd1;                 // プリセットの読み込みが終わるまで待つ (2026-11-27)
                    else begin cur <= I_APPLY; lp_apply <= 1'b1; end
                end
            end
            // PRESET・LOAD で確定が要るようになったら APPLY へ (手で値を変えたときは移らない。2026-11-05)
            if (!edit && b_next) begin ed_chg <= 1'b0; sync_e <= vr[I_SYNC][1:0]; slv_e <= vr[I_SLV][0]; vo_e <= vr[I_VOFS][11:0]; end   // 値を変える状態に入る
            // SYNC を SEP から複合同期 (OR / XOR) に決定したら、同期の電圧を LOW (0.6V) にする (2026-10-30)
            //   複合同期は 75Ω 入力の RGB モニタ (CSYNC 入力) へつなぐことが多いため。そのあと SYNC LV を
            //   TTL に上げるのは自由 (OR ⇔ XOR の切り替えでは下げ直さない)
            if (edit && (b_next || b_prev) && cur == I_SYNC && sync_e == 2'd0 && vr[I_SYNC][1:0] != 2'd0)
                v[I_SLV] <= 27'd1;
            // EQ にした・EQ からほかにしたら VS OFS を 0 に (EQ では同じ欄が EQ の形。2026-11-13)
            if (edit && (b_next || b_prev) && cur == I_SYNC && ((sync_e == 2'd3) != (vr[I_SYNC][1:0] == 2'd3)))
                v[I_VOFS] <= 27'd0;
            if (wr_go) ed_chg <= 1'b1;
            if (edit && b_next && ed_chg && cur == I_PRE) jmp_cnt <= 3'd4;
            if (ld_end && !boot_apply) jmp_cnt <= 3'd4;
            if (ld_end) begin pmod <= 1'b1; cpd <= 1'b0; end   // LOAD (電源投入時の自動読み込みも) は (CUSTOM)
            cx_p <= cap_clash;
            if (cap_clash && !cx_p && !edit) cur <= I_APPLY;
            // TTL に上げる APPLY の確かめ (上の ttl_up / ttl_ask)。取り消しを先に書き、確かめの開始 (カーソルを APPLY へ) を後に
            if (ttl_ok && (!ttl_up || cur != I_APPLY || edit || apply_req)) ttl_ok <= 1'b0;
            if (ttl_ask) begin ttl_ok <= 1'b1; cur <= I_APPLY; end
            if (jmp_cnt != 3'd0) begin
                jmp_cnt <= jmp_cnt - 3'd1;
                if (jmp_cnt == 3'd1 && pend_m && !edit) cur <= I_APPLY;
            end
            // STEP: 名前の欄では「次の桁」、それ以外は増減幅
            if (b_step) begin
                if (cur == I_NAME) cpos <= cpos + 3'd1;
                else if (cur == I_VOFS && eq_w) ;                        // EQ FORM: STEP は使わない (欄は SEL で移る)
                else if (act_cur && sidx >= 3'd2) sidx <= 3'd0;                          // ACTIVE: x1 → x10 → x100 → x1
                else if (sidx == 3'd3 && cur == I_DOT) sidx <= 3'd4;
                else if (sidx >= 3'd3) sidx <= 3'd0;
                else sidx <= sidx + 3'd1;
            end
            // ACTIVE の AUTO: 最小の値で DOWN → AUTO (作業中の値は変え始めたときの値に戻す)、AUTO で UP → 戻る (その値が出る)
            if (act_cur && edit && !ro && b_dn && cv == mn && !aq_c) begin
                if (acv) begin au_v <= 1'b1; v[I_VA] <= {15'd0, av_k}; end
                else     begin au_h <= 1'b1; v[I_HA] <= {15'd0, ah_k}; end
            end
            if (act_cur && edit && !ro && (b_up || (b_dn && aq_c))) begin if (acv) au_v <= 1'b0; else au_h <= 1'b0; end   // 推定した値からは DOWN でも
            // 名前の編集
            if (cur == I_NAME && edit && (b_up || b_dn))
                wname[(7 - cpos) * 8 +: 8] <= b_up ? cnext(cch) : cprev(cch);
            // 保存 / 読み出し
            if (b_next && !edit && cur == I_SAVE && !st_busy) begin st_save <= 1'b1; st_wav <= 1'b0; msg_op <= 2'd0; end
            if (b_next && !edit && cur == I_LOAD && !st_busy) begin st_load <= 1'b1; st_wav <= 1'b0; msg_op <= 2'd0; end
            // 波形 (CAP RAW の No.30 RAW SAVE / No.31 RAW LOAD、スロットは SLOT の番号)。SAVE は済みの記録があるときだけ
            if (b_next && !edit && wav_en && cur == I_LMAX && !st_busy && wav_stat == 3'd4) begin st_save <= 1'b1; st_wav <= 1'b1; msg_op <= 2'd0; end
            //   LOAD は記録・変換・圧縮の途中 (状態 1〜3) には始めない (cm の書き込みが重なる。2026-11-14)
            if (b_next && !edit && wav_en && cur == I_LCMD && !st_busy && (wav_stat == 3'd0 || wav_stat >= 3'd4)) begin st_load <= 1'b1; st_wav <= 1'b1; msg_op <= 2'd0; end
            if (edit && (b_up || b_dn) && cur == I_SLOT) msg_op <= 2'd0;
            if (st_ok || st_err) begin msg_op <= (cur == I_SAVE || cur == I_LMAX) ? 2'd2 : 2'd1; msg_ok <= st_ok; msg_w <= st_wav; end
            // FIX: DOTCLK と V BP を自動で合わせる (このあとの読み込み・値の変更が同じクロックにあればそちらが優先)
            if (lk_fix && vr[I_DOT] != fx_dot) v[I_DOT] <= fx_dot;
            if (lk_fix && vr[I_VB] != fx_vb)   v[I_VB]  <= fx_vb;
            // 読み込み (作業中の値と名前)
            if (ld_we) begin
                ld_t[7:0] <= ld_byte;
                if (ld_idx == 5'd1) ld_ok <= (ld_byte == 8'h01);
                if (ld_ok) case (ld_idx)
                5'd3:  ld_t[23:8] <= {ld_byte, ld_t[7:0]};                           // DOTCLK の byte 2・3
                5'd5:  begin
                    v[I_DOT] <= {ld_byte[2:0], ld_t[7:0], ld_t[23:8]};                // byte 5・4・3・2
                    v[I_SLV] <= !ld_byte[7];
                    // TV OUT: 方式 m と FIX f から選択肢の番号 (m * 2 - 1 + f)。範囲外は OFF
                    v[I_TV] <= (ld_byte[5:3] == 3'd0 || ld_byte[5:3] == 3'd7) ? 27'd0 :
                               {23'd0, ld_byte[5:3], 1'b0} - 27'd1 + ld_byte[6];
                end
                5'd7:  v[I_HA] <= {15'd0, ld_byte[3:0], ld_t[7:0]};
                5'd9:  begin v[I_HF] <= {15'd0, ld_byte[3:0], ld_t[7:0]}; v[I_SCAN] <= ld_byte[7]; end
                5'd11: begin v[I_HS] <= {15'd0, ld_byte[3:0], ld_t[7:0]}; ld_t[11:8]  <= ld_byte[7:4]; end   // VS OFS の上位 4 ビットはそれぞれ
                5'd13: begin v[I_HB] <= {15'd0, ld_byte[3:0], ld_t[7:0]}; ld_t[15:12] <= ld_byte[7:4]; end
                5'd15: begin v[I_VA] <= {15'd0, ld_byte[3:0], ld_t[7:0]}; v[I_VOFS] <= {15'd0, ld_byte[7:4], ld_t[15:8]}; end
                5'd17: v[I_VF] <= {11'd0, ld_byte, ld_t[7:0]};
                5'd19: v[I_VS] <= {11'd0, ld_byte, ld_t[7:0]};
                5'd21: v[I_VB] <= {11'd0, ld_byte, ld_t[7:0]};
                5'd22: begin v[I_HPOL] <= ld_byte[0]; v[I_VPOL] <= ld_byte[1]; v[I_SYNC] <= ld_byte[3:2]; end   // パターンは読まない (2026-11-14)
                5'd23, 5'd24, 5'd25, 5'd26, 5'd27, 5'd28, 5'd29, 5'd30:
                       wname <= {wname[55:0], ld_byte};                              // byte 23 が先頭の文字
                default: ;
                endcase
            end
            // COPY (キャプチャの推定を作業中の値へ。DONE のときだけ。e_* は DONE のあと変わらない)
            if (b_next && !edit && cur == I_LCMD && cap_en) begin
                // DONE で、推定に使った解像度 (cap_est の e_ha / e_va) と作業中の ACTIVE が同じときだけ (2026-11-07 / 11-10 修正)
                //   AUTO の側は比べない (推定に使った値を写す。2026-11-10)
                if (cap_status == 4'd3 && cap_ha == (au_h ? 12'd0 : e_ha) && cap_va == (au_v ? 12'd0 : e_va)) begin
                    if (cp_rng) cp_code <= 2'd3;                   // RANGE NG (2026-11-22)
                    else begin v[I_TV] <= 27'd0; cp_cnt <= 3'd4; end
                end else cp_code <= 2'd2;
            end
            if (cp_cnt != 3'd0) begin
                cp_cnt <= cp_cnt - 3'd1;
                if (cp_cnt == 3'd1) begin
                    v[I_DOT] <= e_dot;                                     // 範囲は cp_rng で確かめた (2026-11-22、前は 1〜48MHz に丸めていた)
                    v[I_HA] <= {15'd0, e_ha}; v[I_VA] <= {15'd0, e_va};   // AUTO のときは推定に使った値 (手で入れたときは同じ値)
                    // FP / BP の 0 もそのまま (2026-11-22、前は 1 にして H / V 合計が 1 増えていた。V FP は 2026-11-19 から)
                    v[I_HF] <= {15'd0, e_hf}; v[I_HS] <= {15'd0, e_hs}; v[I_HB] <= {15'd0, e_hb};
                    v[I_VF] <= {15'd0, e_vf}; v[I_VS] <= {15'd0, e_vs}; v[I_VB] <= {15'd0, e_vb};
                    v[I_HPOL] <= e_hneg; v[I_VPOL] <= e_vneg; v[I_SCAN] <= e_il;
                    // 作業中の SYNC が EQ で、測った形式が OR (キャプチャは EQ を OR と測る) なら SYNC と EQ FORM はそのまま (2026-11-13)
                    if (!(vr[I_SYNC][1:0] == 2'd3 && e_cs == 2'd1)) begin v[I_SYNC] <= e_cs; v[I_VOFS] <= {15'd0, e_vo}; end
                    wname <= "CAPTURE "; cp_code <= 2'd1; jmp_cnt <= 3'd4; pmod <= 1'b1; cpd <= 1'b1;
                end
            end
            // 値の変更
            if (wr_go) begin                    // 書き込みの 2 段目
                v[wcur] <= nv_r;
                if (wcur <= I_SCAN && wcur != I_MEAS) pmod <= 1'b1;   // プリセットが入れる項目を手で変えた
                if (wcur == I_PRE) begin         // 表を読み始める (下の pl_*)
                    pmod <= 1'b0; cpd <= 1'b0;
                    pl_run <= 1'b1; pl_tv <= 1'b0; pl_p <= nv_r[5:0]; pl_k <= 5'd1; pl_dv <= 1'b0;
                end
            end
            // TV OUT を SEL で決定したとき: OFF から方式を選んだ、または 525 ⇔ 625 ライン系が変わったら標準のタイミングを入れる
            //   (選択肢を送っている途中の方式では入れない。tv_cmt は決定前の値)
            //   SCAN が INTER なら 480i / 576i、PROG なら 240p / 288p
            if (edit && cur == I_TV && (b_next || b_prev) && vr[I_TV][3:0] != 4'd0 &&
                (tv_cmt == 4'd0 || tv625(tv_cmt) != tv625(vr[I_TV][3:0]))) begin
                pl_run <= 1'b1; pl_tv <= 1'b1; pl_p <= {1'b0, tv_std}; pl_k <= 5'd1; pl_dv <= 1'b0;
                v[I_PRE] <= {22'd0, tv_std}; pmod <= 1'b0;
            end
            // 内蔵プリセットの表を 1 項目ずつ読んで書く (項目の順 1 → 0 → 2 … 17。prom_q は 1 クロック遅れ)
            //   同期の電圧・VSYNC の位置は、実機に合わせるプリセット (pfix) だけ入れ、ほかは PRESET を選び始める前の値に戻す。
            //   TV OUT の標準タイミングでは 0〜12 と名前だけ
            if (pl_run) begin
                pl_kd <= pl_k; pl_dv <= 1'b1;
                pl_k  <= (pl_k == 5'd1) ? 5'd0 : (pl_k == 5'd0) ? 5'd2 : pl_k + 5'd1;
                if (pl_k == 5'd17) pl_run <= 1'b0;
            end else pl_dv <= 1'b0;
            if (pl_dv) begin
                case (pl_kd)
                5'd1:  pl_fx <= prom_q[1:0];
                5'd13: if (!pl_tv) v[I_SLV]  <= pl_fx[0] ? {26'd0, prom_q[0]} : {26'd0, slv_e};
                5'd14: if (!pl_tv) v[I_VOFS] <= pl_fx[1] ? {15'd0, prom_q[11:0]} :
                                                ((sync_e == 2'd3) != (vr[I_SYNC][1:0] == 2'd3)) ? 27'd0 : {15'd0, vo_e};   // EQ の出入りでは 0
                5'd15: if (!pl_tv) v[I_SCAN] <= {26'd0, prom_q[0]};
                5'd16: wname[63:32] <= prom_q;
                5'd17: wname[31:0]  <= prom_q;
                5'd0:  v[I_DOT]  <= {prom_q[26:0]};
                5'd2:  v[I_HA]   <= {15'd0, prom_q[11:0]};
                5'd3:  v[I_HF]   <= {15'd0, prom_q[11:0]};
                5'd4:  v[I_HS]   <= {15'd0, prom_q[11:0]};
                5'd5:  v[I_HB]   <= {15'd0, prom_q[11:0]};
                5'd6:  v[I_VA]   <= {15'd0, prom_q[11:0]};
                5'd7:  v[I_VF]   <= {15'd0, prom_q[11:0]};
                5'd8:  v[I_VS]   <= {15'd0, prom_q[11:0]};
                5'd9:  v[I_VB]   <= {15'd0, prom_q[11:0]};
                5'd10: v[I_HPOL] <= {26'd0, prom_q[0]};
                5'd11: v[I_VPOL] <= {26'd0, prom_q[0]};
                5'd12: v[I_SYNC] <= {25'd0, prom_q[1:0]};
                default: ;
                endcase
            end

            // ---- 確定 ----
            case (ast)
            A_IDLE: if (apply_req) begin
                boot_apply <= 1'b0; out_en <= 1'b0; at <= 0; ast <= A_MUTE;
                if (osc_fail) force_osc <= 1'b1;            // 前回失敗: 同じ周波数でも書き直して確かめる (2026-10-26 修正)
            end
            //   APPLY の間はボタンを受け付けず、LOAD・プリセットの読み込みも始まらないので、作業中の値 vr[] は変わらない
            A_MUTE: if (at == PUB_CYCLES) begin
                at <= 0;
                if (force_osc || vr[I_DOT] != dot_target) begin
                    dot_target <= vr[I_DOT]; dot_upd <= 1'b1; force_osc <= 1'b0; ast <= A_OSC;
                end else ast <= A_PUB;
            end else at <= at + 1;
            A_OSC: begin
                at <= at + 1;
                // osc_settled = 実測が目標に合った。合わないまま時間切れなら CLK ERR を出す (出力は再開する)
                if ((at > 32'd1000 && osc_settled) || at == SETTLE_CYCLES) begin
                    at <= 0; ast <= A_PUB;
                    osc_fail <= !(at > 32'd1000 && osc_settled);
                end
            end
            A_PUB: begin
                cfg_h_active <= vr[I_HA]; cfg_h_fp <= vr[I_HF]; cfg_h_sync <= vr[I_HS]; cfg_h_bp <= vr[I_HB];
                cfg_v_active <= vr[I_VA]; cfg_v_fp <= vr[I_VF]; cfg_v_sync <= vr[I_VS]; cfg_v_bp <= vr[I_VB];
                cfg_hs_neg <= vr[I_HPOL][0]; cfg_vs_neg <= vr[I_VPOL][0]; cfg_vs_ofs <= vr[I_VOFS][11:0]; cfg_csync <= vr[I_SYNC][1:0];
                cfg_sync_lv <= vr[I_SLV][0];
                cfg_tv_mode <= tvm(vr[I_TV][3:0]);
                cfg_interlace <= vr[I_SCAN][0];
                cfg_toggle <= ~cfg_toggle;
                at <= 0; ast <= A_RUN;
            end
            A_RUN: if (at == PUB_CYCLES) begin out_en <= 1'b1; ast <= A_IDLE; end
                   else at <= at + 1;
            default: ast <= A_IDLE;
            endcase
        end
    end
endmodule
