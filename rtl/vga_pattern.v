// =============================================================
// テストパターン生成 (RGB 各4bit)
//   pattern = 0 : SMPTE のカラーバー (2026-11-27。前は 8 本のカラーバー)
//                 上 2/3: 75% の 7 本 (白・黄・シアン・緑・マゼンタ・赤・青)
//                 中 1/12: 逆順の帯 (青・黒・マゼンタ・黒・シアン・黒・白)
//                 下 1/4: -I・100% 白・+Q・黒 (バー 5/4 本ずつ)、PLUGE (バー 1/3 本ずつ)、黒
//                 幅は表示幅の 1/84 単位 (バー 12、下の区画 15、PLUGE 4)。75% は 4 ビットなので 11/15 = 73%。
//                 RGB は黒が 0 なので PLUGE の -4% は出せず 0 / 0 / +1 (6.7%)。-I = (0,2,4)、+Q = (3,0,6)
//                 テレビ出力は tv_encoder が色の値から 8 ビットの正確な Y / U / V に置き換え、
//                 PLUGE の -4% の画素は sub_o (黒より下の印) で知らせて -4 IRE を出す (2026-11-27)
//             1 : 階調 (上から R / G / B / 白 の16段階)
//             2 : グリッド (外枠=白、16ドットごとの格子=灰、64 ドットごとは明るい灰、中央十字=赤)。
//                 マスは解像度によらず 16 ドット × 16 ライン (64 × 64 も) なので、映すと機種本来のドットの縦横比が分かる (2026-11-21)
//             3 : 全面白
//             4 : クロスハッチ (黒地に白線、横 16 × 縦 12 マス。コンバーゼンス・直線性)
//             5 : ドット (クロスハッチの交点に 2×2 の白い点。コンバーゼンス・フォーカス)
//             6 : アスペクト (灰の 16×12 マス + 白の外枠・中央十字・中央の正方形・
//                 大きな正方形・四隅の正方形。4:3 の画面に映したとき正方形になる。2026-11-13 に円から変更 (容量削減)。
//                 白の線は 2 ドット・2 ライン (2026-11-21))
//             7 : BAR75 (75% のカラーバー。RGB 4 ビットなので 11/15 = 73%。テレビ出力は 8 ビットで正確な 75%)
//             8 : RAMP (横方向の灰色の階調 16 段。テレビ出力は 8 ビットのなめらかな階調)
//             9 : MBURST (8 区画: 白 / 縦縞 32・16・8・4・2 ドット周期 / 1 ドットの市松 / 黒。
//                 解像度・液晶のクロックと位相の調整。テレビ出力は 0.5〜5MHz のマルチバースト)
//   (動く帯 MOVE H / MOVE V は 2026-11-13〜14 に容量のため外し、番号を詰めた。前は 7 MOVE H / 8 MOVE V / 9〜11)
//   表示ドット数・ライン数が変わっても自動で幅を合わせる
//   16×12 マスは 4:3 の画面に映したとき正方形になる (どの解像度でも)
//   出力は vga_timing より1クロック遅れるので、同期信号も1クロック遅らせて出す
//
//   遅延測定 (lag_mode = 1 のとき、パターンの代わりに出す)
//     黒地に測定範囲 (lag_area 0 = 全面 / 1 = 上 / 2 = 中央 / 3 = 下 の正方形) を白で出す。
//     lag_req はフレームの先頭でだけ取り込む (フレームの途中から光らせない)。
//     lag_shown は測定範囲の中央 (センサーを置く位置) の画素をピンへ出したところで 1 になり、
//     lag_req が 0 になったフレームで 0 に戻る (範囲の中を走査する時間を測定値に入れないため)。
//     正方形は横 3/32・縦 1/8 (横 16 × 縦 12 マスの 1.5 マス。4:3 の画面で正方形)、横は中央。
//     上 / 下は画面の端から高さの 1/16 離す
// =============================================================
module vga_pattern #(
    parameter BARS8 = 0               // 1 で pattern 0 を前の 8 本のカラーバーに (tb_tv の色の確かめ用)
) (
    input  wire        dclk,
    input  wire [3:0]  pattern,       // 別クロック (スイッチなど) から入れてよい
    // vga_timing から
    input  wire        hs_in, vs_in, de, frame_start,
    input  wire [11:0] x, y, h_active, v_active,
    input  wire [11:0] v_total_m1,    // 総ライン数 - 1 (以前の円の先読みに使っていた。今は使わない)
    input  wire        interlace,     // vga_timing: インターレース (1 ラインごとに y が 2 進む。フィールド 1 は y が奇数)
    // 遅延測定 (別クロックから入れてよい)
    input  wire        lag_mode,
    input  wire        lag_req,
    input  wire [1:0]  lag_area,
    output reg         lag_shown,
    // ピンへ
    output reg  [3:0]  r, g, b,
    output reg         hsync_o, vsync_o,
    output reg         sub_o          // SMPTE の PLUGE の -4% (黒より下) の画素 (r / g / b は黒。テレビ出力が使う)
);
    (* async_reg = "true" *) reg [3:0] p1, p2;
    always @(posedge dclk) begin p1 <= pattern; p2 <= p1; end

    // ---- 表示サイズから決まる値 ----
    //   h_active / v_active はフレームの区切りでしか変わらないので、
    //   引き算・比較の片側をレジスタに入れておき、毎クロックの組み合わせ回路を短くする
    //   (変わった直後の 1〜2 クロックは古い値。APPLY 中は出力停止 (de=0) なので影響なし)
    reg  [11:0] stepw_m1, bandh_m1, ha_m1, va_m1, ha_half, va_half;
    always @(posedge dclk) begin
        stepw_m1 <= (h_active[11:4] == 8'd0) ? 12'd0 : {4'd0, h_active[11:4]} - 12'd1;
        bandh_m1 <= (v_active[11:2] == 10'd0) ? 12'd0 : {2'd0, v_active[11:2]} - 12'd1;
        ha_m1    <= h_active - 12'd1;
        va_m1    <= v_active - 12'd1;
        ha_half  <= {1'b0, h_active[11:1]};
        va_half  <= {1'b0, v_active[11:1]};
    end

    // ---- SMPTE: 縦の境目 (2/3 ≒ 1/2 + 1/8 + 1/32 + 1/128 + 1/512、3/4) と横の 1/84 の単位 ----
    reg  [11:0] v23a, v23b, v23, v34;
    always @(posedge dclk) begin
        v23a <= {1'b0, v_active[11:1]} + {3'd0, v_active[11:3]};
        v23b <= {5'd0, v_active[11:5]} + {7'd0, v_active[11:7]} + {9'd0, v_active[11:9]};
        v23  <= v23a + v23b;
        v34  <= {1'b0, v_active[11:1]} + {2'd0, v_active[11:2]};
    end
    //   su = floor(x * 84 / h_active)。sa = x * 84 mod h_active (端数を足していく。1 クロックに 1 単位まで)
    reg  [11:0] sa;
    reg  [6:0]  su;
    wire [12:0] sa_n = {1'b0, sa} + 13'd84;
    wire        sa_w = (sa_n >= {1'b0, h_active});
    always @(posedge dclk) begin
        if (!de) begin
            sa <= 12'd0; su <= 7'd0;
        end else begin
            sa <= sa_w ? sa_n[11:0] - h_active : sa_n[11:0];
            if (sa_w && su != 7'd83) su <= su + 7'd1;
        end
    end

    // ---- 横方向: 表示幅を16分割した段 step (0..15) ----
    reg  [11:0] scnt;
    reg  [3:0]  step;
    // ---- 縦方向: 表示ライン数を4分割した帯 band (0..3) ----
    reg  [11:0] lcnt;
    reg  [1:0]  band;
    reg         de_d;
    reg         ex2 = 1'b0;               // インターレースで 2 回目に進める (表示ラインの終わりの次のクロック)
    always @(posedge dclk) ex2 <= interlace && de_d && !de && (y < v_active);

    always @(posedge dclk) begin
        de_d <= de;
        // step は「今の画素」の値を保持し、使った後に次の画素用へ進める
        if (!de) begin
            scnt <= 12'd0;
            step <= 4'd0;
        end else if (scnt == stepw_m1) begin
            scnt <= 12'd0;
            if (step != 4'd15) step <= step + 4'd1;
        end else
            scnt <= scnt + 12'd1;
        // band は表示ラインの終わりで進め、垂直帰線期間に0へ戻す
        //   インターレース: 1 ラインで y が 2 進むので、次のクロック (ex2) でもう 1 回進める。
        //   フィールド 1 (y が奇数) は y = 1 の値から始める。帰線期間の y は今のフィールドの偶奇なので、
        //   次のフィールド (反対の偶奇) に合わせて !y[0] で決める
        if (y >= v_active) begin
            lcnt <= (interlace && !y[0] && bandh_m1 != 12'd0) ? 12'd1 : 12'd0;
            band <= (interlace && !y[0] && bandh_m1 == 12'd0) ? 2'd1 : 2'd0;
        end else if ((de_d && !de) || ex2) begin
            if (lcnt == bandh_m1) begin
                lcnt <= 12'd0;
                if (band != 2'd3) band <= band + 2'd1;
            end else
                lcnt <= lcnt + 12'd1;
        end
    end

    // ---- 色の決定 ----
    reg [11:0] rgb;
    wire [2:0] bar = step[3:1];
    wire border = (x == 12'd0) || (x == ha_m1) ||
                  (y == 12'd0) || (y == va_m1);
    wire center = (x == ha_half) || (y == va_half);
    wire grid   = (x[3:0] == 4'd0) || (y[3:0] == 4'd0);
    wire grid64 = (x[5:0] == 6'd0) || (y[5:0] == 6'd0);   // 64 ドット × 64 ラインの正方形を目立たせる (2026-11-21)


    // ---- クロスハッチ: 横 16 × 縦 12 マスの線 (割り算を使わず端数を足していく) ----
    //   横: 画素 x で ga = x*16 mod (ha-1)。ga < 16 の画素が縦線 (x = 0 と ha-1 を含む 17 本)
    //   縦: ライン y で gb = y*12 mod (va-1)。gb < 12 のラインが横線 (13 本)
    //   gk / gl は今の画素の左 (今のラインの上) にある線の番号 (0〜16 / 0〜12)
    reg  [11:0] ga, gb;
    reg  [4:0]  gk;
    reg  [3:0]  gl;
    wire [12:0] ga_n = {1'b0, ga} + 13'd16;
    wire        ga_w = (ga_n >= {1'b0, ha_m1});
    wire [12:0] gb_n = {1'b0, gb} + 13'd12;
    wire        gb_w = (gb_n >= {1'b0, va_m1});
    always @(posedge dclk) begin
        if (!de) begin
            ga <= 12'd0; gk <= 5'd0;
        end else begin
            ga <= ga_w ? ga_n[11:0] - ha_m1 : ga_n[11:0];
            if (ga_w) gk <= gk + 5'd1;
        end
        if (y >= v_active) begin                    // 次がフィールド 1 なら y = 1 の値 (12 mod (va-1)) から
            gb <= (interlace && !y[0]) ? ((12'd12 >= va_m1) ? 12'd12 - va_m1 : 12'd12) : 12'd0;
            gl <= (interlace && !y[0] && 12'd12 >= va_m1) ? 4'd1 : 4'd0;
        end else if ((de_d && !de) || ex2) begin
            gb <= gb_w ? gb_n[11:0] - va_m1 : gb_n[11:0];
            if (gb_w) gl <= gl + 4'd1;
        end
    end
    wire hl = (ga < 12'd16);            // 縦線の上
    wire vl = (gb < 12'd12);            // 横線の上
    wire hd = (ga < 12'd32);            // 縦線とその右の 1 画素 (ドット用)
    wire vd = (gb < 12'd24);            // 横線とその下の 1 ライン (ドット用)
    // アスペクトの白い線は 2 ドット・2 ラインの太さ (2026-11-21、ユーザーの依頼。灰の格子は 1 ドットのまま):
    //   線とその右の 1 画素 (下の 1 ライン)。右端・下端の外枠は内側 (左・上) の 1 画素 (1 ライン) を足す
    wire hw = hd || (ga_w && gk == 5'd15);
    wire vw = vd || (gb_w && gl == 4'd11);
    // アスペクトの白い線: 外枠・中央十字・中央の正方形 (横 6〜10 番、縦 4〜8 番の線)
    wire in_h = (gk >= 5'd6) && ((gk < 5'd10) || (gk == 5'd10 && hw));
    wire in_v = (gl >= 4'd4) && ((gl < 4'd8)  || (gl == 4'd8  && vw));
    wire a_white = (hw && (gk == 5'd0 || gk == 5'd16 || gk == 5'd8)) ||
                   (vw && (gl == 4'd0 || gl == 4'd12 || gl == 4'd6)) ||
                   (hw && (gk == 5'd6 || gk == 5'd10) && in_v) ||
                   (vw && (gl == 4'd4 || gl == 4'd8)  && in_h);

    // ---- 正方形 (アスペクト、2026-11-13 に円から変更。容量削減) ----
    //   マスの線 (hl / vl と線の番号 gk / gl) だけで描く。4:3 の画面でマスは正方形なので、正方形に見えれば縦横比が合っている
    //     大きな正方形: 横 2〜14 番・縦 0〜12 番の線 (12 × 12 マス。以前の大きな円の外接)
    //     四隅の正方形: 横 1〜3 / 13〜15 番、縦 1〜3 / 9〜11 番の線 (2 × 2 マス。以前の四隅の円の位置)
    //   (信号は引数で渡す。関数の中からモジュールの信号を読むと、シミュレータが引数の変化でしか計算し直さない)
    function sq(input [4:0] x0, input [4:0] x1, input [3:0] y0, input [3:0] y1,
                input hl_i, input vl_i, input [4:0] gk_i, input [3:0] gl_i);
        sq = (hl_i && (gk_i == x0 || gk_i == x1) && ((gl_i >= y0 && gl_i < y1) || (gl_i == y1 && vl_i))) ||
             (vl_i && (gl_i == y0 || gl_i == y1) && ((gk_i >= x0 && gk_i < x1) || (gk_i == x1 && hl_i)));
    endfunction
    wire circ = sq(5'd2,  5'd14, 4'd0, 4'd12, hw, vw, gk, gl) ||
                sq(5'd1,  5'd3,  4'd1, 4'd3,  hw, vw, gk, gl) || sq(5'd13, 5'd15, 4'd1, 4'd3,  hw, vw, gk, gl) ||
                sq(5'd1,  5'd3,  4'd9, 4'd11, hw, vw, gk, gl) || sq(5'd13, 5'd15, 4'd9, 4'd11, hw, vw, gk, gl);

    // MBURST の区画 (bar = 0〜7): 白 / 縦縞 (周期 32・16・8・4・2 ドット) / 1 ドットの市松 / 黒
    reg mb;
    always @(*) begin
        case (bar)
            3'd0: mb = 1'b1;
            3'd1: mb = x[4];
            3'd2: mb = x[3];
            3'd3: mb = x[2];
            3'd4: mb = x[1];
            3'd5: mb = x[0];
            3'd6: mb = x[0] ^ y[0];
            default: mb = 1'b0;
        endcase
    end

    // SMPTE のバーの番号 (0〜6) と区画
    wire [2:0] sb = (su >= 7'd72) ? 3'd6 : (su >= 7'd60) ? 3'd5 : (su >= 7'd48) ? 3'd4 :
                    (su >= 7'd36) ? 3'd3 : (su >= 7'd24) ? 3'd2 : (su >= 7'd12) ? 3'd1 : 3'd0;
    wire [2:0] sm = 3'd6 - sb;                     // 中段: 偶数番は逆順の色、奇数番は黒
    reg [11:0] smpte;
    always @(*) begin
        if (y < v23)
            smpte = {{4{~sb[1]}}, {4{~sb[2]}}, {4{~sb[0]}}} & 12'hBBB;
        else if (y < v34)
            smpte = sb[0] ? 12'h000 : {{4{~sm[1]}}, {4{~sm[2]}}, {4{~sm[0]}}} & 12'hBBB;
        else if (su < 7'd15) smpte = 12'h024;      // -I
        else if (su < 7'd30) smpte = 12'hFFF;      // 100% 白
        else if (su < 7'd45) smpte = 12'h306;      // +Q
        else if (su < 7'd68) smpte = 12'h000;      // 黒、PLUGE の -4% / 0%
        else if (su < 7'd72) smpte = 12'h111;      // PLUGE の +4%
        else                 smpte = 12'h000;
    end
    wire smpte_sub = (BARS8 == 0) && (p2 == 4'd0) && (y >= v34) && (su >= 7'd60) && (su < 7'd64);

    always @(*) begin
        case (p2)
            4'd0: rgb = (BARS8 != 0) ? {{4{~bar[1]}}, {4{~bar[2]}}, {4{~bar[0]}}} : smpte;
            4'd1: case (band)
                      2'd0: rgb = {step, 4'h0, 4'h0};
                      2'd1: rgb = {4'h0, step, 4'h0};
                      2'd2: rgb = {4'h0, 4'h0, step};
                      default: rgb = {step, step, step};
                  endcase
            4'd2: rgb = border ? 12'hFFF : center ? 12'hF00 : grid64 ? 12'hCCC : grid ? 12'h888 : 12'h000;
            4'd4: rgb = (hl || vl) ? 12'hFFF : 12'h000;
            4'd5: rgb = (hd && vd) ? 12'hFFF : 12'h000;
            4'd6: rgb = (a_white || circ) ? 12'hFFF : (hl || vl) ? 12'h888 : 12'h000;
            4'd7: rgb = {{4{~bar[1]}}, {4{~bar[2]}}, {4{~bar[0]}}} & 12'hBBB;
            4'd8: rgb = {step, step, step};
            4'd9: rgb = mb ? 12'hFFF : 12'h000;
            default: rgb = 12'hFFF;
        endcase
    end

    // ---- 遅延測定の範囲 ----
    (* async_reg = "true" *) reg [1:0] lm_s, lr_s;
    (* async_reg = "true" *) reg [1:0] la1, la2;
    reg  [11:0] sq_w, sq_h, v16, sq_wh, sq_hh, lx0, lx1, ly0, ly1, lcy;
    reg         lact;
    always @(posedge dclk) begin
        lm_s <= {lm_s[0], lag_mode}; lr_s <= {lr_s[0], lag_req};
        la1  <= lag_area; la2 <= la1;
        // 表示サイズと範囲の選択から境界を作る (めったに変わらないので 2 段のレジスタで区切る)
        sq_w  <= {4'd0, h_active[11:4]} + {5'd0, h_active[11:5]};      // 3/32
        sq_h  <= {3'd0, v_active[11:3]};                                // 1/8
        v16   <= {4'd0, v_active[11:4]};                                // 1/16
        sq_wh <= {1'b0, sq_w[11:1]};
        sq_hh <= {1'b0, sq_h[11:1]};
        if (la2 == 2'd0) begin
            lx0 <= 12'd0; lx1 <= h_active; ly0 <= 12'd0; ly1 <= v_active; lcy <= va_half;
        end else begin
            lx0 <= ha_half - sq_wh;
            lx1 <= ha_half - sq_wh + sq_w;
            case (la2)
                2'd1:    begin ly0 <= v16;                   ly1 <= v16 + sq_h;              lcy <= v16 + sq_hh; end
                2'd2:    begin ly0 <= va_half - sq_hh;       ly1 <= va_half - sq_hh + sq_h;  lcy <= va_half; end
                default: begin ly0 <= v_active - v16 - sq_h; ly1 <= v_active - v16;          lcy <= v_active - v16 - sq_hh; end
            endcase
        end
        if (frame_start) lact <= lm_s[1] && lr_s[1];
    end
    wire lag_in = (x >= lx0) && (x < lx1) && (y >= ly0) && (y < ly1);
    wire lag_px = de && lact && lag_in;
    wire lag_mid = (x == ha_half) && (y == lcy);    // 範囲の中央

    always @(posedge dclk) begin
        if (lm_s[1])
            {r, g, b} <= lag_px ? 12'hFFF : 12'h000;
        else
            {r, g, b} <= de ? rgb : 12'h000;  // 帰線期間は必ず黒
        sub_o <= !lm_s[1] && de && smpte_sub;
        if (!lact)       lag_shown <= 1'b0;
        else if (lag_px && lag_mid) lag_shown <= 1'b1;   // 中央の画素と同じクロックで 1
        hsync_o   <= hs_in;
        vsync_o   <= vs_in;
    end
endmodule


// =============================================================
// 使用例トップ: 電源投入時は 640x480@60Hz (ドットクロック 25.175MHz)
//   実際の基板では cfg_* を OLED/エンコーダの設定画面のレジスタにつなぐ
// =============================================================
module vga_demo_top (
    input  wire       dot_clk,      // Si5351A の CLK0 出力 (GPIOL_24_CLK0)
    input  wire       rst_n,
    input  wire [3:0] pattern_sw,
    output wire [3:0] vga_r, vga_g, vga_b,
    output wire       vga_hsync, vga_vsync
);
    wire        hs, vs, de, fs;
    wire [11:0] x, y, ha, va, vtm1;

    vga_timing u_tim (
        .dclk(dot_clk), .rst_n(rst_n),
        .cfg_h_active(12'd640), .cfg_h_fp(12'd16), .cfg_h_sync(12'd96), .cfg_h_bp(12'd48),
        .cfg_v_active(12'd480), .cfg_v_fp(12'd10), .cfg_v_sync(12'd2),  .cfg_v_bp(12'd33),
        .cfg_hs_neg(1'b1), .cfg_vs_neg(1'b1), .cfg_csync(2'd0), .cfg_interlace(1'b0), .cfg_l625(1'b0), .cfg_toggle(1'b0), .out_en(1'b1),
        .hsync_o(hs), .vsync_o(vs), .de(de), .x(x), .y(y), .frame_start(fs),
        .h_active(ha), .v_active(va), .v_total_m1(vtm1)
    );

    vga_pattern u_pat (
        .dclk(dot_clk), .pattern(pattern_sw),
        .hs_in(hs), .vs_in(vs), .de(de), .frame_start(fs),
        .x(x), .y(y), .h_active(ha), .v_active(va), .v_total_m1(vtm1), .interlace(1'b0),
        .lag_mode(1'b0), .lag_req(1'b0), .lag_area(2'd0), .lag_shown(),
        .r(vga_r), .g(vga_g), .b(vga_b),
        .hsync_o(vga_hsync), .vsync_o(vga_vsync)
    );
endmodule
