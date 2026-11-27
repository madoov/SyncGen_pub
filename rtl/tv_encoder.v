// =============================================================
// テレビ出力 (コンポジット CVBS + S 端子 Y / C) のエンコーダ
//
//   クロック
//     dclk : ドットクロック (vga_timing / vga_pattern / vga_osd と同じ)  … 1 ライン分のバッファに書く
//     clk  : 50MHz                                                       … 設定 (方式・ドットクロックの比)
//     tclk : 27MHz (Si5351A CLK1、15 番)                                  … 読み出し・変調・DAC
//
//   方式 (mode、settings の TV OUT。APPLY で確定)
//     0 OFF      : DAC はすべて 0
//     1 NTSC     : 3.579545MHz、バースト 180°、セットアップなし (日本の NTSC-J と同じ黒 = ブランキング)
//     2 NTSC443  : NTSC と同じ変調で 4.433619MHz
//     3 PAL      : 4.433619MHz、V をラインごとに反転、バースト ±135°、同期 300mV
//     4 PAL-M    : 3.575612MHz、PAL と同じ変調 (同期は 525 ライン系の 40IRE)
//     5 PAL-N    : 3.582056MHz、PAL と同じ変調・同期
//     6 PAL60    : 4.433619MHz、PAL と同じ変調 (同期は 525 ライン系の 40IRE)
//     (7 は SECAM 用に空けてある。今は OFF と同じ)
//
//   テレビ用のパターン (pattern、settings の PATTERN。作業中の値がそのまま効く)
//     7 BAR75  : 75% のカラーバー (白・黄・シアン・緑・マゼンタ・赤・青・黒) を Y / U / V の定数で正確に出す
//     8 RAMP   : 黒 → 白の横の階調を DAC の 1 段ごとに (136 段) なめらかに
//     9 MBURST: 8 区画 = 白 / 0.5・1・2・3・4・5MHz の Y の正弦波 (50% を中心に ±40%) / 黒。色はなし
//     どれも OSD の画素 (vga_osd の osd_o) はバッファの絵のまま出すので、OSD はテレビにも重なる。
//     ほかのパターンは VGA と同じ RGB 4 ビットの絵。区画の境目は表示幅の k/8
//     0 SMPTE  : 位置は VGA と同じ絵 (バッファ) のまま、色の値 (SMPTE に出てくる 12 色) を 8 ビットの正確な
//                Y / U / V に置き換える (2026-11-27): 75% の 7 本・黒・100% の白・-I / +Q (黒の上に 40 IRE p-p)・
//                PLUGE の +4 IRE、vga_osd の sub_o の画素は -4 IRE (黒 = ブランキングの 5 段下)。
//                色の値はビットの一部だけで見分ける (SMPTE の 12 色の中でだけ正しい)。パラメータ SMPTE = 0 で今までの RGB
//
//   映像のタイミングは VGA 出力と同じ (H / V の表示・FP・同期・BP の設定がそのまま効く)。
//   同期は H と V の複合同期で、Y / CVBS の下向きの段差として入れる (極性・SEP/OR/XOR・SYNC LV は関係しない)。
//   垂直同期のラインは、H の同期の位置で始まり、次のラインの H の同期の手前 (同期幅ぶん) まで続く
//   長いパルスにする (切れ込みの立ち下がりの位置が H と同じなので、垂直同期の間も H がずれない)。等化パルスは入れない。
//   インターレース (vga_timing の cfg_interlace) では、vga_timing がラインごとに渡す 2 か所の同期の種類
//   (slot_a = ラインの途中 M、slot_b = H の同期の位置 S) から、半ライン単位の等化パルス (同期幅の半分) と
//   切れ込み入りの垂直同期 (半ライン - 同期幅の広いパルス) を作る。片方のフィールドは垂直同期が半ラインずれる。
//
//   しくみ
//     ドットクロック側: vga_osd の出力 (RGB 各 4 ビット、OSD を含む) の表示期間を 2 ライン分のバッファに交互に書く。
//       表示幅が 1024 ドットより大きいときは 1 ドットおきに書く (テレビの解像度ではこれで足りる)。
//       ラインの先頭 (x = 0) でトグルを反転し、そのラインの情報 (垂直同期か、表示があるか、書くバンク) を渡す。
//     27MHz 側: トグルを受けたら、1 つ前のライン (書き終わったバンク) を再生する (全体が 1 ライン遅れる)。
//       ライン中の位置 p [ドット] は、毎クロック R = ドットクロック / 27MHz を足して求める (固定小数点、小数 20 ビット)。
//       ラインの区切りは毎回ドットクロック側の合図に合わせ直すので、R の誤差はたまらない。
//       合図の受け取りで ±1 クロック (37ns) ずれることがある (13.5MHz のようにちょうど割り切れるときはずれない)。
//     変調: Y = 0.299R + 0.587G + 0.114B、U = 0.492 (B - Y)、V = 0.877 (R - Y)。
//       U / V は 4 点の平均で帯域を少し絞り、C = U sin(ωt) + V cos(ωt) (PAL 系は V の符号をラインごとに反転)。
//       副搬送波は 32 ビットの DDS (27MHz で 0.006Hz 刻み)。バーストは同期の始まりから 5.4µs 後に 9 サイクル
//       (3.58MHz 系) / 10 サイクル (4.43MHz 系)。CVBS = Y + C も中で足す。
//
//   DAC の値 (8 ビット R-2R → 680Ω → THS7314 で 2 倍 → 75Ω で半分。1 段 約 5.24mV、相手の 75Ω の端で)
//     同期の先 6 (525 ライン系 40IRE) / 2 (625 ライン系 300mV)、ブランキング = 黒 60、白 196 (60 + 136)
//     C (S 端子) は 128 を中心に振る。バーストは 20IRE 相当 (±27)
//
//   遅れ: 27MHz 側で約 10 クロック (同期・バースト・画素とも同じだけ遅らせてそろえる)。
//         出力は I/O のレジスタで 1 クロック増える (Interface Designer で register、出力クロック = tv_clk)
//   タイミング: 掛け算は U / V と sin / cos の 2 つだけ (前後をレジスタで区切った乗算器)。
//         定数の掛け算 (RGB → YUV) は 4 ビットの値なので足し算になる。R の割り算は 50MHz 側で逐次 (udiv)
// =============================================================
module tv_encoder #(
    parameter integer SHARED = 0,       // 1: 割り算器をトップで共有 (2026-11-14)
    parameter integer SMPTE  = 1        // 1: パターン 0 (SMPTE) の色をテレビ用に正確にする (0 は tb_tv の 8 本のバー用)
)(
    // ---- ドットクロック側 ----
    input  wire        dclk,
    input  wire        de,            // vga_timing (遅れ 0)
    input  wire [11:0] x,             // vga_timing (遅れ 0)
    input  wire [1:0]  slot_a,        // vga_timing: ラインの途中 M の同期の種類 (0 なし / 2 等化 / 3 広い半ライン、遅れ 0)
    input  wire [2:0]  slot_b,        // vga_timing: H の同期の位置 S の種類 (1 H / 2 等化 / 3 広い半ライン / 4 広い 1 ライン)
    input  wire [11:0] h_mid,         // 表示の始まりから M まで (H の同期の始まり - 1 ライン / 2)
    input  wire        out_on,        // vga_timing: 出力中 (APPLY の切り替え中は 0)
    input  wire [11:0] h_active,      // vga_timing の今の設定 (フレームの区切りでだけ変わる)
    input  wire [11:0] h_sync_s,      // 表示の始まりから同期の始まりまで (表示 + FP)
    input  wire [11:0] h_sync_e,      // 表示の始まりから同期の終わりまで (表示 + FP + 同期)
    input  wire [3:0]  r_in, g_in, b_in,   // vga_osd の出力 (遅れ 4)
    input  wire        osd_in,        // vga_osd: この画素は OSD (r_in などと同じ遅れ)
    input  wire        sub_in,        // vga_osd: 黒より下の画素 (SMPTE の PLUGE の -4%、r_in などと同じ遅れ)
    // ---- 50MHz 側 ----
    input  wire        clk,
    input  wire [26:0] dot_hz,        // 確定したドットクロック [Hz]
    input  wire [2:0]  mode,          // 確定した方式
    input  wire [11:0] ha_cfg,        // 確定した H の表示ドット数 (RAMP の傾き)
    input  wire [3:0]  pattern,       // パターン (別クロックから入れてよい。遅延測定中は 0 にして渡す)
    // ---- 27MHz 側 ----
    input  wire        tclk,
    output reg  [7:0]  y_o,           // S 端子の Y (ピンへ)
    output reg  [7:0]  c_o,           // S 端子の C
    output reg  [7:0]  cvbs_o,        // コンポジット
    // 割り算器の共有 (2026-11-14、容量削減): SHARED = 1 ならトップの udiv_share を使う (0 なら自前の udiv。単体のテスト用)
    output wire        sd_start,
    output wire [46:0] sd_num,
    output wire [29:0] sd_den,
    input  wire [46:0] sd_quo,
    input  wire [29:0] sd_rem,
    input  wire        sd_done,
    // 割り算器の共有 (2026-11-14、容量削減): SHARED = 1 ならトップの udiv_share を使う (0 なら自前の udiv。単体のテスト用)
    output wire        sk_start,
    output wire [46:0] sk_num,
    output wire [29:0] sk_den,
    input  wire [46:0] sk_quo,
    input  wire [29:0] sk_rem,
    input  wire        sk_done
);
    localparam integer TV_HZ = 27_000_000;
    // DAC の値
    localparam [7:0] LV_BLANK = 8'd60, LV_SYNC525 = 8'd6, LV_SYNC625 = 8'd2, LV_CMID = 8'd128;
    // バースト (27MHz のクロック数、同期の始まりから)
    localparam [8:0] BURST_S = 9'd146, BURST_L358 = 9'd68, BURST_L443 = 9'd61;
    // バーストの U / V (U / V の 64 倍の単位。U64 / 64 が DAC の段数)
    localparam signed [13:0] BU_NTSC = -14'sd1728;                     // -U 方向に 27 段
    localparam signed [13:0] BU_PAL  = -14'sd1313, BV_PAL = 14'sd1313; // (-U ± V) / √2 方向に 29 段

    // =========================================================
    // ドットクロック側: ラインの書き込み
    // =========================================================
    reg [13:0] lbuf [0:2047];         // {バンク, 位置[9:0]} → {黒より下, OSD, R, G, B}

    reg        bank = 1'b0;           // いま書いているバンク
    reg        ev_tgl = 1'b0;         // ラインの先頭ごとに反転
    reg        ev_act = 1'b0, ev_bank = 1'b0;   // そのラインの情報 (次の先頭まで変わらない)
    reg [1:0]  ev_a = 2'd0;
    reg [2:0]  ev_b = 3'd1;
    reg        dec = 1'b0;            // 1 ドットおきに書く
    always @(posedge dclk) begin
        dec <= (h_active > 12'd1024);
        if (out_on && x == 12'd0) begin
            bank    <= ~bank;
            ev_bank <= ~bank;
            ev_a    <= slot_a;
            ev_b    <= slot_b;
            ev_act  <= de;            // 先頭で de = 1 なら表示のあるライン
            ev_tgl  <= ~ev_tgl;
        end
    end

    // RGB は x / de より 4 クロック遅れて来るので、de とバンクも 4 クロック遅らせる
    //   バンクは x = 0 のクロックで反転するので、その画素 (ラインの先頭) から新しいバンクにする
    //   (反転前の bank を取り込むと、先頭の画素だけ 1 つ前のラインのバンクに書かれる。2026-10-25 修正)
    reg [3:0]  de_d = 4'd0;
    reg [3:0]  bk_d = 4'd0;
    reg [10:0] wpos = 11'd0;
    wire       bank_px = (out_on && x == 12'd0) ? ~bank : bank;
    always @(posedge dclk) begin
        de_d <= {de_d[2:0], de};
        bk_d <= {bk_d[2:0], bank_px};
        if (!de_d[3]) wpos <= 11'd0;
        else          wpos <= wpos + 11'd1;
        if (de_d[3] && (!dec || !wpos[0]) && (dec || !wpos[10]))
            lbuf[{bk_d[3], dec ? wpos[10:1] : wpos[9:0]}] <= {sub_in, osd_in, r_in, g_in, b_in};
    end

    // =========================================================
    // 50MHz 側: R = ドットクロック / 27MHz (小数 20 ビット) と
    //           RAMP の傾き K = 136 * 2^14 / 表示ドット数 を計算して渡す
    // =========================================================
    //   SHARED のときは R (sd) と K (sk) を別々に頼む。K の方が番号が小さい (先に終わる) ようにトップでつなぐ
    reg         d_start = 1'b0;
    reg [11:0] last_ha = 12'd0;
    reg [26:0] last_hz = 27'd0;
    wire [46:0] d_quo, k_quo;
    wire [29:0] d_rem, k_rem;
    wire        d_done, k_done;
    generate if (SHARED) begin : g_sd
        assign d_quo = sd_quo; assign d_rem = sd_rem; assign d_done = sd_done;
        assign k_quo = sk_quo; assign k_rem = sk_rem; assign k_done = sk_done;
    end else begin : g_sd_l
        udiv #(.NW(47), .DW(30)) u_div (.clk(clk), .start(d_start), .num({last_hz, 20'd0}), .den({5'd0, TV_HZ[24:0]}),
                                        .quo(d_quo), .rem(d_rem), .done(d_done));
        udiv #(.NW(47), .DW(30)) u_kdiv (.clk(clk), .start(d_start), .num(47'd2228224), .den({18'd0, last_ha}),
                                         .quo(k_quo), .rem(k_rem), .done(k_done));
    end endgenerate
    assign sd_start = d_start; assign sd_num = {last_hz, 20'd0}; assign sd_den = {5'd0, TV_HZ[24:0]};
    assign sk_start = d_start; assign sk_num = 47'd2228224;      assign sk_den = {18'd0, last_ha};
    reg [2:0]  last_mode = 3'd0;
    reg [17:0] cf_k = 18'd0;          // K (表示ドット数 9 以上で 18 ビットに収まる)
    reg        d_busy = 1'b0, cf_tgl = 1'b0;
    reg [21:0] cf_r = 22'd0;          // R (整数 2 ビット + 小数 20 ビット)
    reg [2:0]  cf_mode = 3'd0;
    always @(posedge clk) begin
        d_start <= 1'b0;
        if (!d_busy && (dot_hz != last_hz || mode != last_mode || ha_cfg != last_ha)) begin
            last_hz <= dot_hz; last_mode <= mode; last_ha <= ha_cfg; d_start <= 1'b1; d_busy <= 1'b1;
        end
        // K は R より先に終わる (自前は 47 クロックで同時、共有は番号が小さい方が先)。K を先に入れ、R でトグル
        if (k_done) cf_k <= (k_quo[46:18] != 29'd0) ? 18'h3FFFF : k_quo[17:0];
        if (d_done) begin
            cf_r <= d_quo[21:0]; cf_mode <= last_mode; cf_tgl <= ~cf_tgl; d_busy <= 1'b0;
        end
    end

    // =========================================================
    // 27MHz 側
    // =========================================================
    // ---- 設定の受け取り (めったに変わらない) ----
    (* async_reg = "true" *) reg [2:0] cf_s = 3'd0;
    reg [21:0] r_inc = 22'd0;
    reg [17:0] rk = 18'd0;
    reg [2:0]  md = 3'd0;
    reg        pal = 1'b0, sc443 = 1'b0, l625 = 1'b0;
    reg [31:0] dds_inc = 32'd0;
    reg [7:0]  lv_sync = LV_SYNC525;
    reg [8:0]  burst_e = 9'd0;
    always @(posedge tclk) begin
        cf_s <= {cf_s[1:0], cf_tgl};
        if (cf_s[2] ^ cf_s[1]) begin r_inc <= cf_r; md <= cf_mode; rk <= cf_k; end
        pal     <= (md >= 3'd3) && (md <= 3'd6);
        sc443   <= (md == 3'd2) || (md == 3'd3) || (md == 3'd6);
        l625    <= (md == 3'd3) || (md == 3'd5);
        lv_sync <= l625 ? LV_SYNC625 : LV_SYNC525;
        burst_e <= BURST_S + (sc443 ? BURST_L443 : BURST_L358);
        case (md)                                   // 副搬送波 / 27MHz * 2^32
            3'd1:       dds_inc <= 32'd569408543;   // NTSC    3.579545MHz
            3'd2, 3'd3,
            3'd6:       dds_inc <= 32'd705268427;   // 4.433619MHz
            3'd4:       dds_inc <= 32'd568782819;   // PAL-M   3.575612MHz
            3'd5:       dds_inc <= 32'd569807942;   // PAL-N   3.582056MHz
            default:    dds_inc <= 32'd0;
        endcase
    end
    wire tv_on = (md != 3'd0) && (md != 3'd7);

    // ---- パターンの受け取り: 2 回続けて同じ値なら採用 (複数ビットが同時に変わる途中を拾わない) ----
    (* async_reg = "true" *) reg [3:0] pt_s1 = 4'd0, pt_s2 = 4'd0;
    reg [3:0] pt_s3 = 4'd0;
    reg [1:0] npat = 2'd0;            // 0 = バッファの絵、1 = BAR75、2 = RAMP、3 = MBURST
    reg       smp = 1'b0;             // 1 = SMPTE (バッファの絵の色を置き換える)
    always @(posedge tclk) begin
        pt_s1 <= pattern; pt_s2 <= pt_s1; pt_s3 <= pt_s2;
        if (pt_s2 == pt_s3) begin
            npat <= (pt_s3 == 4'd7) ? 2'd1 : (pt_s3 == 4'd8) ? 2'd2 : (pt_s3 == 4'd9) ? 2'd3 : 2'd0;
            smp  <= (SMPTE != 0) && (pt_s3 == 4'd0);
        end
    end

    // ---- ラインの合図の受け取り ----
    (* async_reg = "true" *) reg [2:0] ev_s = 3'd0;
    wire ev = ev_s[2] ^ ev_s[1];
    reg        nx_act = 1'b0, nx_bank = 1'b0;   // 受け取ったライン (次に再生する)
    reg        pl_act = 1'b0, pl_bank = 1'b0;   // 再生中のライン
    reg [1:0]  nx_a = 2'd0, pl_a = 2'd0;        // 同期の種類 (M の位置)
    reg [2:0]  nx_b = 3'd1, pl_b = 3'd1, pv_b = 3'd1;   // 同期の種類 (S の位置。pv_b は 1 つ前に再生したライン)
    reg        vsw = 1'b0;                                    // PAL の V の反転
    reg [11:0] t_ha = 12'd0, t_ss = 12'd0, t_se = 12'd0, t_bs = 12'd0;
    reg [11:0] t_m = 12'd0, t_mw = 12'd0, t_me = 12'd0, t_s2 = 12'd0;   // M、M - 同期幅、M + 同期幅/2、S + 同期幅/2
    reg        t_dec = 1'b0;
    reg [33:0] p = 34'd0;             // ライン中の位置 [ドット] (整数 14 ビット + 小数 20 ビット)
    reg [12:0] tc = 13'd0;            // 合図からのクロック数 (合図が来なくなったら止める)
    reg        run = 1'b0;
    reg [8:0]  tb = 9'h1FF;           // 同期の始まりからのクロック数 (バースト用)
    wire [13:0] pi = p[33:20];
    always @(posedge tclk) begin
        ev_s <= {ev_s[1:0], ev_tgl};
        if (ev) begin
            // 1 つ前のライン (書き終わっている) を再生する
            pl_act <= nx_act; pl_bank <= nx_bank; pl_a <= nx_a; pl_b <= nx_b; pv_b <= pl_b;
            nx_act <= ev_act; nx_bank <= ev_bank; nx_a <= ev_a; nx_b <= ev_b;
            vsw   <= ~vsw;
            t_ha  <= h_active; t_ss <= h_sync_s; t_se <= h_sync_e; t_dec <= dec;
            t_bs  <= (h_sync_s > (h_sync_e - h_sync_s)) ? h_sync_s - (h_sync_e - h_sync_s) : 12'd0;
            t_m   <= h_mid;
            t_mw  <= (h_mid > (h_sync_e - h_sync_s)) ? h_mid - (h_sync_e - h_sync_s) : 12'd0;
            t_me  <= h_mid + ((h_sync_e - h_sync_s) >> 1);
            t_s2  <= h_sync_s + ((h_sync_e - h_sync_s) >> 1);
            p   <= 34'd0;
            tc  <= 13'd0;
            run <= 1'b1;
        end else begin
            p <= p + {12'd0, r_inc};
            if (tc == 13'h1FFF) run <= 1'b0;          // 約 300µs 合図がない (出力停止中)
            else tc <= tc + 13'd1;
        end
    end

    // ---- 区画の境目 (表示幅の k/8。t_ha はラインの先頭でだけ変わる) ----
    reg [11:0] sb1 = 0, sb2 = 0, sb3 = 0, sb4 = 0, sb5 = 0, sb6 = 0, sb7 = 0;
    reg [14:0] ha3 = 0, ha5 = 0, ha7 = 0;
    always @(posedge tclk) begin
        ha3 <= {3'd0, t_ha} + {2'd0, t_ha, 1'b0};
        ha5 <= {3'd0, t_ha} + {1'b0, t_ha, 2'd0};
        ha7 <= {t_ha, 3'd0} - {3'd0, t_ha};
        sb1 <= {3'd0, t_ha[11:3]}; sb2 <= {2'd0, t_ha[11:2]}; sb4 <= {1'd0, t_ha[11:1]};
        sb3 <= ha3[14:3]; sb5 <= ha5[14:3]; sb6 <= ha3[14:2]; sb7 <= ha7[14:3];
    end
    wire [2:0] seg = (pi >= {2'd0, sb7}) ? 3'd7 : (pi >= {2'd0, sb6}) ? 3'd6 :
                     (pi >= {2'd0, sb5}) ? 3'd5 : (pi >= {2'd0, sb4}) ? 3'd4 :
                     (pi >= {2'd0, sb3}) ? 3'd3 : (pi >= {2'd0, sb2}) ? 3'd2 :
                     (pi >= {2'd0, sb1}) ? 3'd1 : 3'd0;

    // ---- 1 段目: 位置から同期・表示・バーストを決める ----
    wire in_act = pl_act && (pi < {2'd0, t_ha});
    //   1 つ前のラインの S から続く広いパルス (pv_b) / M から半ライン (pl_a) / S から (pl_b) の 3 つの重ね合わせ
    wire sy_tail = ((pv_b == 3'd4) && (pi < {2'd0, t_bs})) || ((pv_b == 3'd3) && (pi < {2'd0, t_mw}));
    wire sy_a = (pi >= {2'd0, t_m}) && (pi < {2'd0, t_ss}) &&
                (((pl_a == 2'd2) && (pi < {2'd0, t_me})) || ((pl_a == 2'd3) && (pi < {2'd0, t_bs})));
    wire sy_b = (pi >= {2'd0, t_ss}) &&
                (((pl_b == 3'd1) && (pi < {2'd0, t_se})) || ((pl_b == 3'd2) && (pi < {2'd0, t_s2})) || (pl_b >= 3'd3));
    wire in_sync = sy_tail || sy_a || sy_b;
    reg        f1_act = 1'b0, f1_sync = 1'b0, f1_burst = 1'b0, f1_run = 1'b0, f1_sw = 1'b0;
    reg        sync_d = 1'b0;
    reg [10:0] raddr = 11'd0;
    reg [2:0]  f1_seg = 3'd0;
    reg [11:0] f1_pi = 12'd0;
    always @(posedge tclk) begin
        f1_seg   <= seg;
        f1_pi    <= pi[11:0];
        sync_d <= in_sync;
        if (in_sync && !sync_d) tb <= 9'd0;           // 同期の始まり
        else if (tb != 9'h1FF) tb <= tb + 9'd1;
        f1_run   <= run;
        f1_act   <= run && in_act;
        f1_sync  <= run && in_sync;
        // バーストは S の普通の同期のあと。垂直同期の次のライン (プログレッシブ) と、次の M に同期があるときは出さない
        f1_burst <= run && !in_sync && !in_act && (pl_b == 3'd1) && (pv_b != 3'd4) && (nx_a == 2'd0) &&
                    (tb >= BURST_S) && (tb < burst_e);
        f1_sw    <= pal && vsw;
        raddr    <= {pl_bank, t_dec ? pi[10:1] : pi[9:0]};
    end

    // ---- 2 段目: バッファを読む。RAMP の掛け算、MBURST の正弦波 ----
    reg [13:0] px = 14'd0;
    reg        f2_act = 1'b0, f2_sync = 1'b0, f2_burst = 1'b0, f2_run = 1'b0, f2_sw = 1'b0;
    reg [2:0]  f2_seg = 3'd0;
    reg [29:0] rmul = 30'd0;          // 位置 * K (RAMP の Y64 の 256 倍)
    reg [31:0] mph = 32'd0, minc = 32'd0;   // MBURST の DDS
    reg signed [7:0] msn = 8'sd0;
    always @(posedge tclk) begin
        px <= lbuf[raddr];
        {f2_act, f2_sync, f2_burst, f2_run, f2_sw} <= {f1_act, f1_sync, f1_burst, f1_run, f1_sw};
        f2_seg <= f1_seg;
        rmul   <= f1_pi * rk;
        case (f1_seg)                                 // 周波数 / 27MHz * 2^32
            3'd1:    minc <= 32'd79536431;            // 0.5MHz
            3'd2:    minc <= 32'd159072863;           // 1MHz
            3'd3:    minc <= 32'd318145726;           // 2MHz
            3'd4:    minc <= 32'd477218588;           // 3MHz
            3'd5:    minc <= 32'd636291451;           // 4MHz
            3'd6:    minc <= 32'd795364314;           // 5MHz
            default: minc <= 32'd0;
        endcase
        mph <= (f1_seg == 3'd0) ? 32'd0 : mph + minc; // 区画 1 は sin(0) から始まる
        msn <= sine(mph[31:24]);
    end

    // ---- 3 段目: RGB → Y / U / V (64 倍。Y64 / 64 が DAC の段数、0〜135) ----
    wire [3:0] pr = px[11:8], pg = px[7:4], pb = px[3:0];
    wire       nat = (npat != 2'd0) && !px[12];       // テレビ用のパターンを出す (OSD の画素以外)
    wire [13:0] ramp = (rmul[29:8] > 22'd8704) ? 14'd8704 : rmul[21:8];
    wire signed [13:0] mbv = 14'sd4352 + (msn <<< 4) + (msn <<< 3) + (msn <<< 1) + msn;   // 50% ± 27 * sin
    // SMPTE の色の番号 (VGA の RGB の値から。75% の 7 本は bit3 で、ほかは数ビットで見分ける)
    //   0〜6 = 75% の 7 本 (BBB / BB0 / 0BB / 0B0 / B0B / B00 / 00B)、7 黒、8 100% の白 (FFF)、9 -I (024)、10 +Q (306)、11 +4 IRE (111)
    wire       s_bar = pr[3] | pg[3] | pb[3];
    wire [3:0] sidx  = s_bar ? (pr[2] ? 4'd8 : {1'b0, ~pg[3], ~pr[3], ~pb[3]}) :
                       pg[1] ? 4'd9 : pr[1] ? 4'd10 : pr[0] ? 4'd11 : 4'd7;
    wire       sm_px = f2_act && smp && !px[12];          // SMPTE の画素 (OSD の画素以外)
    wire [3:0] bidx  = smp ? sidx : {1'b0, f2_seg};
    // 75% のカラーバー: 白・黄・シアン・緑・マゼンタ・赤・青・黒 (Y64 / U64 / V64、136 * 64 * 0.75 = 6528 が白)
    //   SMPTE の 8〜11: 100% の白 = 8704。-I / +Q は黒の上に振幅 20 IRE = 27.2 段 (×64 = 1741) を
    //   -I = 303°、+Q = 33° (U から) の向きに。+4 IRE = 8704 × 0.04 = 348
    reg [13:0] by64; reg signed [13:0] bu64, bv64;
    always @(*) begin
        case (bidx)
            4'd0: begin by64 = 14'd6528; bu64 =  14'sd0;    bv64 =  14'sd0;    end
            4'd1: begin by64 = 14'd5784; bu64 = -14'sd2846; bv64 =  14'sd653;  end
            4'd2: begin by64 = 14'd4576; bu64 =  14'sd960;  bv64 = -14'sd4013; end
            4'd3: begin by64 = 14'd3832; bu64 = -14'sd1885; bv64 = -14'sd3361; end
            4'd4: begin by64 = 14'd2696; bu64 =  14'sd1885; bv64 =  14'sd3361; end
            4'd5: begin by64 = 14'd1952; bu64 = -14'sd960;  bv64 =  14'sd4013; end
            4'd6: begin by64 = 14'd744;  bu64 =  14'sd2846; bv64 = -14'sd653;  end
            4'd8: begin by64 = 14'd8704; bu64 =  14'sd0;    bv64 =  14'sd0;    end
            4'd9: begin by64 = 14'd0;    bu64 =  14'sd948;  bv64 = -14'sd1460; end
            4'd10: begin by64 = 14'd0;   bu64 =  14'sd1460; bv64 =  14'sd948;  end
            4'd11: begin by64 = 14'd348; bu64 =  14'sd0;    bv64 =  14'sd0;    end
            default: begin by64 = 14'd0; bu64 =  14'sd0;    bv64 =  14'sd0;    end
        endcase
    end
    reg  [13:0]        y64 = 14'd0;
    reg  signed [13:0] u64 = 14'sd0, v64 = 14'sd0;
    reg        f3_act = 1'b0, f3_sync = 1'b0, f3_burst = 1'b0, f3_run = 1'b0, f3_sw = 1'b0;
    reg        f3_sub = 1'b0;         // 黒より下 (-4 IRE) の画素
    always @(posedge tclk) begin
        f3_sub <= sm_px && px[13];
        if (sm_px) begin
            y64 <= by64; u64 <= bu64; v64 <= bv64;
        end else if (f2_act && nat) begin
            case (npat)
                2'd1:    begin y64 <= by64; u64 <= bu64; v64 <= bv64; end
                2'd2:    begin y64 <= ramp; u64 <= 14'sd0; v64 <= 14'sd0; end
                default: begin
                    y64 <= (f2_seg == 3'd0) ? 14'd8704 : (f2_seg == 3'd7) ? 14'd0 : mbv;
                    u64 <= 14'sd0; v64 <= 14'sd0;
                end
            endcase
        end else if (f2_act) begin
            y64 <= 14'd173 * pr + 14'd340 * pg + 14'd66 * pb;
            u64 <= $signed({1'b0, 14'd253 * pb}) - $signed({1'b0, 14'd85 * pr}) - $signed({1'b0, 14'd168 * pg});
            v64 <= $signed({1'b0, 14'd357 * pr}) - $signed({1'b0, 14'd299 * pg}) - $signed({1'b0, 14'd58 * pb});
        end else begin
            y64 <= 14'd0; u64 <= 14'sd0; v64 <= 14'sd0;
        end
        {f3_act, f3_sync, f3_burst, f3_run, f3_sw} <= {f2_act, f2_sync, f2_burst, f2_run, f2_sw};
    end

    // ---- 4 段目: U / V を 4 点で平均 (Y は 2 クロック遅らせて中央にそろえる)、バーストを入れる ----
    //   Y は y64 → y4a → y4b → y5 と 3 段なので、表示・同期などの印も f4 のあとに 1 段 (f4d) 足して
    //   5 段目で Y とそろえる (2026-10-25 修正。以前は印が 1 クロック早く、表示の先頭に黒が 1 サンプル入っていた)。
    //   U / V の 4 点平均の中心と Y のずれは 0.5 サンプル (18ns) だけ
    reg signed [13:0] u1 = 0, u2 = 0, u3 = 0, v1 = 0, v2 = 0, v3 = 0;
    reg signed [15:0] us_a = 0, us_b = 0, vs_a = 0, vs_b = 0;
    reg [13:0]        y4a = 0, y4b = 0;
    reg        f4_act = 1'b0, f4_sync = 1'b0, f4_burst = 1'b0, f4_run = 1'b0, f4_sw = 1'b0;
    reg        f4d_act = 1'b0, f4d_sync = 1'b0, f4d_burst = 1'b0, f4d_run = 1'b0, f4d_sw = 1'b0;
    reg        f4_sub = 1'b0, f4d_sub = 1'b0;
    always @(posedge tclk) begin
        u1 <= u64; u2 <= u1; u3 <= u2;
        v1 <= v64; v2 <= v1; v3 <= v2;
        us_a <= u64 + u1; us_b <= u2 + u3;             // 2 つずつ足してから (1 クロックの足し算を短く)
        vs_a <= v64 + v1; vs_b <= v2 + v3;
        y4a <= y64; y4b <= y4a;
        {f4_act, f4_sync, f4_burst, f4_run, f4_sw} <= {f3_act, f3_sync, f3_burst, f3_run, f3_sw};
        {f4d_act, f4d_sync, f4d_burst, f4d_run, f4d_sw} <= {f4_act, f4_sync, f4_burst, f4_run, f4_sw};
        f4_sub <= f3_sub; f4d_sub <= f4_sub;
    end
    reg signed [13:0] uf = 0, vf = 0;
    reg [13:0]        y5 = 0;
    reg        f5_act = 1'b0, f5_sync = 1'b0, f5_run = 1'b0, f5_c = 1'b0, f5_sub = 1'b0;
    always @(posedge tclk) begin
        if (f4d_burst) begin
            // バーストはラインの終わり (同期のあと) にあり、そのあとの表示は次のラインなので、
            // PAL の V の向きは次のライン (今の反対) に合わせる: 次が反転しないなら 135°、反転するなら 225°
            uf <= pal ? BU_PAL : BU_NTSC;
            vf <= pal ? (f4d_sw ? BV_PAL : -BV_PAL) : 14'sd0;
        end else begin
            uf <= (us_a + us_b) >>> 2;
            vf <= f4d_sw ? -((vs_a + vs_b) >>> 2) : ((vs_a + vs_b) >>> 2);
        end
        y5 <= y4b;
        f5_act <= f4d_act; f5_sync <= f4d_sync; f5_run <= f4d_run; f5_sub <= f4d_sub;
        f5_c   <= f4d_burst || f4d_act;
    end

    // ---- 副搬送波 (DDS) と sin / cos ----
    reg [31:0] ph = 32'd0;
    always @(posedge tclk) ph <= ph + dds_inc;
    // 1/4 周期の表: round(127 * sin((k + 0.5) * 2π / 256))、k = 0〜63
    function [6:0] qsin(input [5:0] k);
        reg [6:0] s;
        begin
            case (k)
            6'd0: s = 7'd2; 6'd1: s = 7'd5; 6'd2: s = 7'd8; 6'd3: s = 7'd11; 6'd4: s = 7'd14; 6'd5: s = 7'd17; 6'd6: s = 7'd20; 6'd7: s = 7'd23;
            6'd8: s = 7'd26; 6'd9: s = 7'd29; 6'd10: s = 7'd32; 6'd11: s = 7'd35; 6'd12: s = 7'd38; 6'd13: s = 7'd41; 6'd14: s = 7'd44; 6'd15: s = 7'd47;
            6'd16: s = 7'd50; 6'd17: s = 7'd53; 6'd18: s = 7'd56; 6'd19: s = 7'd58; 6'd20: s = 7'd61; 6'd21: s = 7'd64; 6'd22: s = 7'd67; 6'd23: s = 7'd69;
            6'd24: s = 7'd72; 6'd25: s = 7'd74; 6'd26: s = 7'd77; 6'd27: s = 7'd79; 6'd28: s = 7'd82; 6'd29: s = 7'd84; 6'd30: s = 7'd86; 6'd31: s = 7'd89;
            6'd32: s = 7'd91; 6'd33: s = 7'd93; 6'd34: s = 7'd95; 6'd35: s = 7'd97; 6'd36: s = 7'd99; 6'd37: s = 7'd101; 6'd38: s = 7'd103; 6'd39: s = 7'd105;
            6'd40: s = 7'd106; 6'd41: s = 7'd108; 6'd42: s = 7'd110; 6'd43: s = 7'd111; 6'd44: s = 7'd113; 6'd45: s = 7'd114; 6'd46: s = 7'd115; 6'd47: s = 7'd117;
            6'd48: s = 7'd118; 6'd49: s = 7'd119; 6'd50: s = 7'd120; 6'd51: s = 7'd121; 6'd52: s = 7'd122; 6'd53: s = 7'd123; 6'd54: s = 7'd124; 6'd55: s = 7'd124;
            6'd56: s = 7'd125; 6'd57: s = 7'd125; 6'd58: s = 7'd126; 6'd59: s = 7'd126; 6'd60: s = 7'd127; 6'd61: s = 7'd127; 6'd62: s = 7'd127; default: s = 7'd127;
            endcase
            qsin = s;
        end
    endfunction
    function signed [7:0] sine(input [7:0] a);       // 1 周 = 256
        reg [6:0] m;
        begin
            m = qsin(a[6] ? ~a[5:0] : a[5:0]);
            sine = a[7] ? -$signed({1'b0, m}) : $signed({1'b0, m});
        end
    endfunction
    reg signed [7:0] sn = 0, cs = 0;
    always @(posedge tclk) begin
        sn <= sine(ph[31:24]);
        cs <= sine(ph[31:24] + 8'd64);
    end

    // ---- 6 段目: 掛け算 (前後をレジスタで区切る) ----
    reg signed [21:0] mu = 0, mv = 0;
    reg [13:0] y6 = 0;
    reg        f6_act = 1'b0, f6_sync = 1'b0, f6_run = 1'b0, f6_c = 1'b0, f6_sub = 1'b0;
    always @(posedge tclk) begin
        mu <= uf * sn;
        mv <= vf * cs;
        y6 <= y5;
        f6_act <= f5_act; f6_sync <= f5_sync; f6_run <= f5_run; f6_c <= f5_c; f6_sub <= f5_sub;
    end

    // ---- 7 段目: C の段数と Y の値 ----
    reg signed [9:0] ch = 0;
    reg [7:0]  ylv = 8'd0;
    reg        f7_run = 1'b0;
    wire signed [22:0] msum = mu + mv;
    always @(posedge tclk) begin
        ch     <= f6_c ? msum[22:13] : 10'sd0;            // 64 * 128 = 8192 で割る
        //   -4 IRE = 136 × 0.04 = 5.4 段 → 5 段 (+4 IRE も 348 / 64 → 5 段で対称)
        ylv    <= f6_sync ? lv_sync : f6_sub ? LV_BLANK - 8'd5 : f6_act ? LV_BLANK + y6[13:6] : LV_BLANK;
        f7_run <= f6_run;
    end

    // ---- 8 段目: 出力 (ピンの I/O レジスタの手前) ----
    wire signed [10:0] cv = $signed({3'b000, ylv}) + ch;
    wire signed [10:0] cc = $signed(11'sd128) + ch;
    always @(posedge tclk) begin
        if (!tv_on) begin
            y_o <= 8'd0; c_o <= 8'd0; cvbs_o <= 8'd0;
        end else if (!f7_run) begin                       // ドットクロック側が止まっている: 黒・同期なし
            y_o <= LV_BLANK; c_o <= LV_CMID; cvbs_o <= LV_BLANK;
        end else begin
            y_o    <= ylv;
            c_o    <= (cc < 0) ? 8'd0 : (cc > 255) ? 8'd255 : cc[7:0];
            cvbs_o <= (cv < 0) ? 8'd0 : (cv > 255) ? 8'd255 : cv[7:0];
        end
    end
endmodule
