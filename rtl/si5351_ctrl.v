// =============================================================
// Si5351A (I2C クロックジェネレータ) 周波数制御
//   target_hz (1〜48MHz) を受け取り、PLLA と MultiSynth0 の設定を計算して I2C で書き込む。
//   CLK0 にドットクロックを出す。CLK1 にはテレビ出力用の 27MHz、CLK2 には映像入力 (キャプチャ) のサンプリング用の
//   50MHz を出す (どちらも起動時に 1 回だけ設定。CLK2 は 2026-11-06 追加、ブランチ capture-meas)。
//
//   周波数の作り方 (水晶 XTAL_HZ = 25MHz)
//     f_out = f_vco / D、f_vco = XTAL * (a + b / c)
//     D (MultiSynth0 の分周比) = 900MHz / f を切り捨てて偶数にした整数 (18〜900)
//       → f_vco = f * D は 810〜900MHz (Si5351 の範囲 600〜900MHz に入る)
//     a = f_vco / XTAL の整数部、b / c は端数。c = 2^19 に固定し、b = 端数 * 2^19 (四捨五入)
//       → 周波数の誤差は 1 億分の 1 以下 (残りは水晶の誤差だけ)
//   レジスタの値 (Skyworks AN619)
//     PLLA : P1 = 128*a + floor(128*b/c) - 512 = 128*a + (b >> 12) - 512
//            P2 = 128*b - c*floor(128*b/c)    = 128 * (b & 4095)
//            P3 = c = 2^19
//     MS0  : 整数モード。P1 = 128*D - 512、P2 = 0、P3 = 1。R0 は ÷1
//   CLK1 (テレビ出力用 27MHz、固定)
//     PLLB = 25MHz * 32.4 = 810MHz (a = 32、b / c = 2 / 5 → P1 = 3635、P2 = 1、P3 = 5)
//     MS1  = 30 (整数モード、P1 = 3328) → 27MHz ちょうど
//   CLK2 (キャプチャのサンプリング用 50MHz、固定。基板では CLK2 → 92 番 GCLK の予定)
//     MS2  = 16.2 = 16 + 1/5 (端数モード。P1 = 128*16 + floor(128/5) - 512 = 1561、P2 = 128 - 5*25 = 3、P3 = 5)
//            → 810MHz / 16.2 = 50MHz ちょうど
//
//   書き込みの順番
//     起動時  : 出力を止める (reg 3)、水晶の負荷容量 (reg 183)、CLK0 の電源を切り CLK1 / CLK2 を PLLB・MS1 / MS2 に
//               (reg 16〜18) → PLLB (reg 34〜41) → MS1 (reg 50〜57) → MS2 (reg 58〜65) → PLLB をリセット (reg 177) →
//               CLK1 と CLK2 を出力 (reg 3)
//     目標変更: PLLA (reg 26〜33) → MS0 (reg 42〜49) → CLK0 を MS0 から出す (reg 16) →
//               PLLA だけリセット (reg 177。CLK1 の 27MHz・CLK2 の 50MHz は止めない) → CLK0〜CLK2 を出力 (reg 3)
//   I2C: アドレス 0x60、書き込みのみ (ACK は見ない)。SCL / SDA はオープンドレイン
//        (*_oe = 1 で Low、0 で離す。High は基板のプルアップ)
//   settled: 書き込みのあと、周波数カウンタの測定が 2 回続けて目標の ±0.1% (+ 40Hz) に入ったら 1
//            (Si5351 は計算どおりの周波数が出るので、LTC6903 のような実測による補正はしない。
//             2026-10-26 修正: 以前は測定が 2 回終わっただけで 1 になり、クロックが出ていなくても安定と判定した)
//
//   タイミング: 割り算は逐次 (udiv)、掛け算 f * D は 1 ビットずつの逐次計算
// =============================================================
module si5351_ctrl #(
    parameter integer SHARED = 0,       // 1: 割り算器をトップで共有 (2026-11-14)
    parameter integer XTAL_HZ = 25_000_000,
    parameter [7:0]   XTAL_CL = 8'hD2,       // reg 183: 水晶の負荷容量 10pF (8pF なら 8'h92、6pF なら 8'h52)
    parameter integer I2C_Q   = 34           // I2C の 1 ビットの 1/4 (34 → 約 368kHz)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [26:0] target_hz,
    input  wire        target_upd,     // 目標を変えたとき 1 クロック
    input  wire        meas_valid,     // freq_counter の測定が終わった
    input  wire [26:0] meas_hz,        // その測定値 (クロックが来ないときは 0)
    output reg         scl_oe,         // 1 = SCL を Low に引く
    output reg         sda_oe,         // 1 = SDA を Low に引く
    output reg         settled,
    // 割り算器の共有 (2026-11-14、容量削減): SHARED = 1 ならトップの udiv_share を使う (0 なら自前の udiv。単体のテスト用)
    output wire        sd_start,
    output wire [46:0] sd_num,
    output wire [29:0] sd_den,
    input  wire [46:0] sd_quo,
    input  wire [29:0] sd_rem,
    input  wire        sd_done
);
    localparam [7:0] ADDR_W = 8'hC0;   // 0x60 << 1 | 0 (書き込み)

    // ---------------- 計算 ----------------
    reg         d_start;
    reg  [44:0] d_num;
    reg  [29:0] d_den;
    wire [46:0] d_quo;
    wire [29:0] d_rem;
    wire        d_done;
    generate if (SHARED) begin : g_sd
        assign d_quo = sd_quo; assign d_rem = sd_rem; assign d_done = sd_done;
    end else begin : g_sd_l
        udiv #(.NW(47), .DW(30)) u_div (.clk(clk), .start(d_start), .num({2'd0, d_num}), .den(d_den),
                                        .quo(d_quo), .rem(d_rem), .done(d_done));
    end endgenerate
    assign sd_start = d_start; assign sd_num = {2'd0, d_num}; assign sd_den = d_den;

    localparam C_IDLE = 3'd0, C_D = 3'd1, C_MUL = 3'd2, C_A = 3'd3, C_B = 3'd4, C_P = 3'd5;
    reg  [2:0]  cst;
    reg  [26:0] f;
    reg  [10:0] dd;                // D (偶数、18〜900)
    reg  [29:0] vco;               // f * D
    reg  [38:0] m_acc, m_a;
    reg  [10:0] m_b;
    reg  [3:0]  m_k;
    reg  [6:0]  pa;                // a (32〜36)
    reg  [19:0] pb;                // b (0〜2^19)
    reg  [17:0] pll_p1, ms_p1;
    reg  [19:0] pll_p2;
    reg         calc_done;

    always @(posedge clk) begin
        d_start   <= 1'b0;
        calc_done <= 1'b0;
        if (rst) cst <= C_IDLE;
        else case (cst)
        C_IDLE: ;
        C_D: begin                                   // D = 900MHz / f
            d_num <= 45'd900_000_000; d_den <= {3'd0, f}; d_start <= 1'b1; cst <= C_MUL;
        end
        C_MUL: if (d_done) begin                     // 偶数にそろえて f * D を逐次で
            dd    <= {d_quo[10:1], 1'b0};
            m_acc <= 39'd0; m_a <= {12'd0, f}; m_b <= {d_quo[10:1], 1'b0}; m_k <= 4'd0;
            cst   <= C_A;
        end
        C_A: begin
            if (m_k != 4'd11) begin
                if (m_b[0]) m_acc <= m_acc + m_a;
                m_a <= {m_a[37:0], 1'b0}; m_b <= {1'b0, m_b[10:1]}; m_k <= m_k + 4'd1;
            end else begin                           // a = vco / XTAL
                vco   <= m_acc[29:0];
                d_num <= {15'd0, m_acc[29:0]}; d_den <= XTAL_HZ; d_start <= 1'b1;
                m_k   <= 4'd12; cst <= C_B;
            end
        end
        C_B: if (d_done) begin
            if (m_k == 4'd12) begin                  // b = (端数 * 2^19 + XTAL/2) / XTAL
                pa    <= d_quo[6:0];
                d_num <= {d_rem[25:0], 19'd0} + (XTAL_HZ / 2); d_den <= XTAL_HZ; d_start <= 1'b1;
                m_k   <= 4'd13;
            end else begin
                if (d_quo[19]) begin pa <= pa + 7'd1; pb <= 20'd0; end   // 四捨五入で 2^19 になったら繰り上げ
                else pb <= d_quo[19:0];
                cst <= C_P;
            end
        end
        C_P: begin                                   // レジスタの値
            pll_p1 <= {4'd0, pa, 7'd0} + {11'd0, pb[18:12]} - 18'd512;
            pll_p2 <= {1'b0, pb[11:0], 7'd0};
            ms_p1  <= {dd, 7'd0} - 18'd512;
            calc_done <= 1'b1; cst <= C_IDLE;
        end
        default: cst <= C_IDLE;
        endcase
        if (go_calc) begin f <= target_hz; cst <= C_D; end
    end

    // ---------------- 書き込む内容 ----------------
    //   トランザクション番号 tr: 0〜7 起動時、8〜12 目標変更
    localparam integer P3_PLL = 1 << 19;
    localparam [3:0] T_BOOT_END = 4'd7, T_UPD = 4'd8, T_UPD_END = 4'd12;
    localparam [17:0] PLLB_P1 = 18'd3635;            // 810MHz / 25MHz = 32.4
    localparam [19:0] PLLB_P2 = 20'd1, PLLB_P3 = 20'd5;
    localparam [17:0] MS1_P1  = 18'd3328;            // 128 * 30 - 512
    localparam [17:0] MS2_P1  = 18'd1561;            // 16.2 = 16 + 1/5
    localparam [19:0] MS2_P2  = 20'd3, MS2_P3 = 20'd5;
    function [3:0] tr_len(input [3:0] t);
        case (t)
            4'd2:                     tr_len = 4'd5;    // reg 16〜18
            4'd3, 4'd4, 4'd5, 4'd8, 4'd9: tr_len = 4'd10;   // PLL / MS の 8 バイト
            default:                  tr_len = 4'd3;
        endcase
    endfunction
    reg [7:0] tb;                                    // 送るバイト
    always @(*) begin
        tb = 8'h00;
        if (tk == 4'd0) tb = ADDR_W;
        else case (tr)
        4'd0: tb = (tk == 4'd1) ? 8'd3   : 8'hFF;                      // 出力をすべて止める
        4'd1: tb = (tk == 4'd1) ? 8'd183 : XTAL_CL;                    // 水晶の負荷容量
        4'd2: case (tk)                                                // reg 16〜18
                4'd1: tb = 8'd16;
                4'd3: tb = 8'h6F;          // CLK1: 整数モード・PLLB・MS1・8mA
                4'd4: tb = 8'h2F;          // CLK2: 端数モード・PLLB・MS2・8mA
                default: tb = 8'h80;       // CLK0: 電源を切る
              endcase
        4'd3: case (tk)                                                // PLLB (reg 34〜41)
                4'd1: tb = 8'd34;
                4'd2: tb = PLLB_P3[15:8];  4'd3: tb = PLLB_P3[7:0];
                4'd4: tb = {6'd0, PLLB_P1[17:16]};
                4'd5: tb = PLLB_P1[15:8];  4'd6: tb = PLLB_P1[7:0];
                4'd7: tb = {PLLB_P3[19:16], PLLB_P2[19:16]};
                4'd8: tb = PLLB_P2[15:8];  default: tb = PLLB_P2[7:0];
              endcase
        4'd4: case (tk)                                                // MS1 (reg 50〜57)、P3 = 1、P2 = 0、R1 = ÷1
                4'd1: tb = 8'd50;
                4'd2: tb = 8'h00;          4'd3: tb = 8'h01;
                4'd4: tb = {6'd0, MS1_P1[17:16]};
                4'd5: tb = MS1_P1[15:8];   4'd6: tb = MS1_P1[7:0];
                default: tb = 8'h00;
              endcase
        4'd5: case (tk)                                                // MS2 (reg 58〜65)、端数モード、R2 = ÷1
                4'd1: tb = 8'd58;
                4'd2: tb = MS2_P3[15:8];   4'd3: tb = MS2_P3[7:0];
                4'd4: tb = {6'd0, MS2_P1[17:16]};
                4'd5: tb = MS2_P1[15:8];   4'd6: tb = MS2_P1[7:0];
                4'd7: tb = {MS2_P3[19:16], MS2_P2[19:16]};
                4'd8: tb = MS2_P2[15:8];   default: tb = MS2_P2[7:0];
              endcase
        4'd6: tb = (tk == 4'd1) ? 8'd177 : 8'h80;                      // PLLB をリセット
        4'd7: tb = (tk == 4'd1) ? 8'd3   : 8'hF9;                      // CLK1 と CLK2 を出力
        4'd8: case (tk)                                                // PLLA (reg 26〜33)
                4'd1: tb = 8'd26;
                4'd2: tb = P3_PLL[15:8];   4'd3: tb = P3_PLL[7:0];
                4'd4: tb = {6'd0, pll_p1[17:16]};
                4'd5: tb = pll_p1[15:8];   4'd6: tb = pll_p1[7:0];
                4'd7: tb = {P3_PLL[19:16], pll_p2[19:16]};
                4'd8: tb = pll_p2[15:8];   default: tb = pll_p2[7:0];
              endcase
        4'd9: case (tk)                                                // MS0 (reg 42〜49)、P3 = 1、P2 = 0、R0 = ÷1
                4'd1: tb = 8'd42;
                4'd2: tb = 8'h00;          4'd3: tb = 8'h01;
                4'd4: tb = {6'd0, ms_p1[17:16]};
                4'd5: tb = ms_p1[15:8];    4'd6: tb = ms_p1[7:0];
                default: tb = 8'h00;
              endcase
        4'd10: tb = (tk == 4'd1) ? 8'd16  : 8'h4F;                     // CLK0: 整数モード・PLLA・MS0・8mA
        4'd11: tb = (tk == 4'd1) ? 8'd177 : 8'h20;                     // PLLA だけリセット
        default: tb = (tk == 4'd1) ? 8'd3 : 8'hF8;                     // CLK0〜CLK2 を出力
        endcase
    end

    // ---------------- I2C (書き込みのみ) ----------------
    localparam I_IDLE = 3'd0, I_START = 3'd1, I_BIT = 3'd2, I_STOP = 3'd3, I_GAP = 3'd4;
    reg  [2:0]  ist;
    reg  [1:0]  ph;
    reg  [7:0]  qc;
    reg  [3:0]  tr;
    reg  [3:0]  tk;
    reg  [3:0]  bn;                // 0〜7 データ、8 = ACK
    reg  [7:0]  sh;
    reg         boot, pend, run_upd, prog;   // prog: 一度でも周波数を書き込んだ
    reg  [1:0]  nmeas;
    reg  [1:0]  m_chk = 2'd0;
    reg  [26:0] m_hz = 27'd0, m_tol = 27'd0, m_diff = 27'd0;
    wire        qend = (qc == I2C_Q - 1);
    wire        go_calc = pend && ist == I_IDLE && cst == C_IDLE && !boot && !run_upd;

    always @(posedge clk) begin
        if (rst) begin
            ist <= I_IDLE; scl_oe <= 1'b0; sda_oe <= 1'b0; qc <= 0; ph <= 0;
            boot <= 1'b1; pend <= 1'b0; run_upd <= 1'b0; prog <= 1'b0; tr <= 4'd0; settled <= 1'b0; nmeas <= 2'd0;
        end else begin
            if (target_upd) begin pend <= 1'b1; settled <= 1'b0; end
            if (go_calc) pend <= 1'b0;
            if (calc_done) begin run_upd <= 1'b1; tr <= T_UPD; end
            // 書き込み後、目標に合った測定が 2 回続いたら settled (外れたら数え直す)
            //   m_chk: 測定値を受けたクロックの次で差を、その次で許容幅と比べる (1 クロックの回路を短く)
            m_chk <= {m_chk[0], ist == I_IDLE && prog && !run_upd && !boot && !pend && cst == C_IDLE && !settled && meas_valid};
            if (meas_valid) m_hz <= meas_hz;
            m_tol  <= {10'd0, target_hz[26:10]} + 27'd40;
            m_diff <= (m_hz >= target_hz) ? m_hz - target_hz : target_hz - m_hz;
            if (m_chk[1] && !pend && !run_upd) begin
                if (m_diff <= m_tol) begin
                    if (nmeas == 2'd1) settled <= 1'b1;
                    nmeas <= nmeas + 2'd1;
                end else nmeas <= 2'd0;
            end
            case (ist)
            I_IDLE: if (boot || run_upd) begin
                tk <= 4'd0; ph <= 0; qc <= 0; ist <= I_START;
            end
            I_START: begin                              // SCL High のまま SDA を下げ、次に SCL を下げる
                if (ph == 2'd0) sda_oe <= 1'b1;
                if (ph == 2'd1) scl_oe <= 1'b1;
                if (qend) begin
                    qc <= 0;
                    if (ph == 2'd1) begin ph <= 0; sh <= tb; bn <= 4'd0; ist <= I_BIT; end
                    else ph <= ph + 2'd1;
                end else qc <= qc + 8'd1;
            end
            I_BIT: begin                                // SCL Low で SDA を決め、SCL を上げて下げる
                case (ph)
                    2'd0: sda_oe <= (bn == 4'd8) ? 1'b0 : ~sh[7];
                    2'd1: scl_oe <= 1'b0;
                    2'd3: scl_oe <= 1'b1;
                    default: ;
                endcase
                if (qend) begin
                    qc <= 0; ph <= ph + 2'd1;
                    if (ph == 2'd3) begin
                        if (bn == 4'd8) begin
                            if (tk == tr_len(tr) - 4'd1) begin ph <= 0; ist <= I_STOP; end
                            else begin tk <= tk + 4'd1; bn <= 4'd0; ist <= I_GAP; end   // 次のバイトを tb から取る
                        end else begin sh <= {sh[6:0], 1'b0}; bn <= bn + 4'd1; end
                    end
                end else qc <= qc + 8'd1;
            end
            I_GAP: begin                                // 1 クロック: 次のバイトを読み込む
                sh <= tb; ph <= 0; qc <= 0; ist <= I_BIT;
            end
            I_STOP: begin                               // SDA Low → SCL High → SDA High
                case (ph)
                    2'd0: sda_oe <= 1'b1;
                    2'd1: scl_oe <= 1'b0;
                    2'd2: sda_oe <= 1'b0;
                    default: ;
                endcase
                if (qend) begin
                    qc <= 0; ph <= ph + 2'd1;
                    if (ph == 2'd3) begin               // 1 トランザクション終わり
                        ph <= 0; tk <= 4'd0;
                        if (boot && tr == T_BOOT_END)        begin boot <= 1'b0; ist <= I_IDLE; end
                        else if (run_upd && tr == T_UPD_END) begin run_upd <= 1'b0; prog <= 1'b1; nmeas <= 2'd0; ist <= I_IDLE; end
                        else begin tr <= tr + 4'd1; ist <= I_START; end
                    end
                end else qc <= qc + 8'd1;
            end
            default: ist <= I_IDLE;
            endcase
        end
    end
endmodule
