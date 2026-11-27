// =============================================================
// ビデオ信号ジェネレータ トップ (Trion T20Q144)
//
//   クロック
//     clk50   : 50MHz 発振器 (PLLIN ピン)      … ボタン・OLED・Si5351A 制御・測定
//     dot_clk : Si5351A CLK0 出力 (14 番 GPIOL_25_CLK1) … VGA タイミング・パターン
//     tv_clk  : Si5351A CLK1 出力 27MHz (15 番 GPIOL_24_CLK0) … テレビ出力 (tv_encoder)
//     cap_clk : Si5351A CLK2 出力 50MHz (92 番 GPIOR_125_CLK10 の予定、基板の改版が要る) … 映像入力の測定 (cap_meas)
//
//   操作 (押しボタン 4個、押すと Low)
//     UP / DOWN : 項目を選ぶ (選んだ項目はラベルを反転、長押しで連続)
//     SEL       : 決定。値を変える状態に入る (値が点滅) → UP / DOWN で値を変え、SEL で決定して戻る
//                 LOAD / SAVE / APPLY は SEL で実行
//     STEP      : 増減幅 x1/x10/x100/x1000 (DOTCLK は 1k/10k/100k/1MHz)
//     STEP 長押し: 変更を確定して出力を切り替える (メニューの APPLY でも可)
//     UP+DOWN 同時押し: VGA 出力への情報表示 (OSD) の ON/OFF (電源投入時は OFF)
//                       ドットクロック・H/V のドット数と同期・水平/垂直周波数を画面中央に出す
//
//   テレビ出力 (メニューの TV OUT、APPLY で確定)
//     tv_y[7:0] / tv_c[7:0] (S 端子) と tv_cvbs[7:0] (コンポジット) を 8 ビットの R-2R の DAC へ。VGA と同じ映像・タイミング
//
//   遅延測定 (メニューの MODE = LAG の範囲 / LAG RUN)
//     lag_sens  : 光センサーのコンパレータ出力 (1 = 明るい)
//     lag_thr   : コンパレータのしきい値 (PWM、基板の RC で平滑)
//
//   映像入力の測定 (2026-11-06、ブランチ capture-meas。docs/capture_plan.md の 9 章)
//     cap_vr / cap_vg / cap_vb / cap_hs / cap_vs : 入力 (R / G / B が黒以外 / HSYNC か CSYNC / VSYNC)。DDIO (resync) で cap_clk の両方の端で取る
//       (2026-11-07: R / G / B を合成して 1 つのコンパレータで見ていたのを、色ごとのコンパレータに。合成の RC で右端が遅れるため。
//        中で OR して「黒以外」(vid) にする)
//     cap_tx    : 使わない (High。2026-11-10 に確かめ用の UART (cap_uart) を外した。容量のため)
//     cap_thr / cap_sthr : コンパレータのしきい値 (PWM、cap_thr.v が自動で合わせる)、out_oe_n : 出力モード / 入力モードの切り替え
//     mode_sw   : 入力 / 出力の切り替えスイッチ S2 の状態 (101 番、2026-11-08。S2 が IN なら基板で入力モードに固定される)
//     メニュー (2026-11-07): MODE = CAP SELF (スイッチ IN なら CAP IN と表示) で No.27〜31 がキャプチャの項目 (CAP RUN / ACTIVE / C.TOT / C.DOT / COPY)
//     ピン: 77 cap_vr / 86 cap_vg / 76 cap_vb / 87 cap_hs / 89 cap_vs (入力)、90 cap_tx、92 cap_clk、98 cap_thr、100 out_oe_n、99 cap_sthr (回路図 674245b で 99 / 100 番を入れ替え)
//       101 mode_sw / 102 term_sw (入力、2026-11-08)、103 term_off (出力、終端を切る、2026-11-09)
//       (回路図・基板 8f9dd33。76 / 77 番と色ごとのコンパレータは 8f9dd33 で回路図・基板に入った、schematic_todo.md の AH / AI 節)
// =============================================================
module video_gen_top #(
    // 実機用の値 (シミュレーションでは短くする)
    parameter integer TICK_CYCLES = 50_000,       // ボタン 1ms
    parameter integer MENU_SHOW_MS = 5000,        // ボタンを押してから VGA 出力にメニューを出す時間 [ms] (2026-11-11)
    parameter integer PUB_CYCLES  = 5_000_000,    // 確定時の待ち時間 100ms
    parameter integer SETTLE_CYCLES = 150_000_000, // ドットクロック安定待ちの上限 3秒
    parameter integer DOT_GATE    = 5_000_000,    // ドットクロック測定 0.1秒
    parameter integer DOT_SCALE   = 10,
    parameter integer H_GATE      = 50_000_000,   // 水平周波数測定 1秒
    parameter integer H_SCALE     = 1,
    parameter integer REFRESH     = 2_500_000,    // OLED 表示更新 50ms
    parameter integer OLED_RESET  = 2_500_000,    // OLED: 電源投入後の待ち 50ms (x2)
    parameter integer OLED_I2C_Q  = 34,           // OLED I2C: 1 ビットの 1/4 (34 → 約 368kHz)
    parameter integer LAG_DARK    = 15_000_000,   // 遅延測定: 黒の時間 300ms
    parameter integer LAG_HOLD    = 5_000_000,    // 遅延測定: 光ってから白のままの時間 100ms
    parameter integer LAG_TIMEOUT = 50_000_000,   // 遅延測定: 光を待つ上限 1秒
    parameter integer LAG_SETTLE  = 250_000,      // 遅延測定: しきい値が落ち着くまで 5ms
    parameter integer LAG_WIN     = 2_500_000,    // 遅延測定: 較正で信号を見る時間 50ms
    parameter integer LAG_RUNS_LOG2 = 4,          // 遅延測定: 16 回
    // 映像入力 (キャプチャ)
    parameter integer CAP_VWIN_LOG2 = 21,         // cap_meas: VS の極性・CSYNC の判定 42ms (シミュレーションでは短く)
    parameter integer CAP_SET_LOG2  = 18,         // cap_thr: しきい値を変えてから落ち着くまで 5.2ms
    parameter integer CAP_WIN_LOG2  = 17,         // cap_thr: 1 回の試しで見る時間 2.6ms
    parameter integer CAP_FTO_LOG2  = 22,         // cap_thr: 白の試し (フィールドの区切り 3 回まで) の打ち切り 84ms
    parameter [7:0]   CAP_RCOMP     = 8'd0,       // cap_est: 右端の補正 [1/256 サンプル]。2026-11-20 に 102 (0.4 サンプル、330Ω と入力容量の遅れ) → 0
                                                  //   (映像のしきい値を黒と白の中間にしたので、立ち上がり・立ち下がりの遅れがそろう)
    parameter integer CAP_CLASH_WIN = 14          // cap_clash: 2^14 クロック (328µs) ごとに数え直す (シミュレーションでは短く)
)(
    input  wire       clk50,
    input  wire       rst_n,
    input  wire       dot_clk,
    input  wire       tv_clk,
    input  wire [3:0] btn_n,          // [0]SEL [1]UP [2]DOWN [3]STEP
    // Si5351A (I2C、アドレス 0x60)
    //   オープンドレイン。Efinity の Interface Designer で 141 番 (SCL) / 144 番 (SDA) の GPIO を inout にし、
    //   OUT = osc_scl_out / osc_sda_out (常に 0)、OE = osc_scl_oe / osc_sda_oe につなぐ (IN は使わない)
    //   (OE = 1 で Low、0 で離す。High は基板のプルアップ 4.7kΩ)
    output wire       osc_scl_out,
    output wire       osc_scl_oe,
    output wire       osc_sda_out,
    output wire       osc_sda_oe,
    // OLED (SSD1306 I2C、アドレス 0x3C)
    //   オープンドレイン。Efinity の Interface Designer で 81 / 82 番の GPIO を inout (双方向) にし、
    //   OUT = oled_scl_out / oled_sda_out (常に 0)、OE = oled_scl_oe / oled_sda_oe につなぐ (IN は今は使わない)
    //   (OE = 1 で Low に引く、0 で離す。High はモジュールのプルアップで上がる)
    output wire       oled_scl_out,
    output wire       oled_scl_oe,
    output wire       oled_sda_out,
    output wire       oled_sda_oe,
    // EEPROM (25LC640A, ユーザープリセット保存)
    output wire       ee_cs_n,
    output wire       ee_sck,
    output wire       ee_mosi,
    input  wire       ee_miso,
    // VGA
    //   Efinity の Interface Designer ではバスのピンを 1 本ずつ register にできないので、
    //   RGB は 1 ビットずつのポートにしている (0 が最下位、3 が最上位 = 510Ω 側)。
    //   14 本とも Register Option = register、出力クロック = dot_clk にする (docs/pinout.md)
    output wire       vga_r0, vga_r1, vga_r2, vga_r3,
    output wire       vga_g0, vga_g1, vga_g2, vga_g3,
    output wire       vga_b0, vga_b1, vga_b2, vga_b3,
    output wire       vga_hsync,
    output wire       vga_vsync,
    // 同期 (HSYNC / 複合同期・VSYNC) の電圧の切り替え (メニューの SYNC LV、APPLY で確定)
    //   基板では HSYNC・VSYNC を U8 74AHCT125 (5V) の 2 回路ずつで出している (FPGA 75 番):
    //     HSYNC: 回路 1 → R41 470Ω (いつも)、回路 2 → R42 47Ω (OE = このピン)
    //     VSYNC: 回路 4 → R44 470Ω (いつも)、回路 3 → R43 47Ω (OE = このピン)
    //   (キャプチャの改版では U8 = 74LVC125A (+3V3、電源 OFF で切り離す)、R41 / R44 = 270Ω。TTL の High は 3.3V。schematic_todo.md の AO 節)
    //   0 = TTL: 回路 2 / 3 も出す (約 43Ω、5V の TTL 入力向け)
    //   1 = LOW: 回路 2 / 3 は Hi-Z (470Ω だけ、75Ω 入力で約 0.6V。TTL 入力でもたいてい使える)
    //   初期値は LOW。コンフィグ前もプルアップで 1 (LOW) になる
    output reg        hs_ttl_oe_n,
    // 遅延測定
    input  wire       lag_sens,
    output wire       lag_thr,
    // テレビ出力 (8 ビットの R-2R の DAC。0 が最下位 = はしごの終端の側)
    //   Interface Designer の 8 ビットのバス (tv_y[7:0] など) に合わせる (2026-10-25)。
    //   24 本とも同じ設定 (Register Option = register、出力クロック = tv_clk) なのでバスでよい
    output wire [7:0] tv_y,
    output wire [7:0] tv_c,
    output wire [7:0] tv_cvbs,
    // 映像入力の測定 (Interface Designer: cap_clk は GCLK、ほかの 3 本は DDIO resync の入力で、
    //   立ち上がり側を *_hi、立ち下がり側 (name_ddio_lo) を *_lo、クロックは cap_clk)
    input  wire       cap_clk,
    input  wire       cap_vr_hi, cap_vr_lo,       // R が黒以外 (77 番 GPIOR_154、IC3 TLV3502 A)
    input  wire       cap_vg_hi, cap_vg_lo,       // G (86 番 GPIOR_133、IC3 TLV3502 B)
    input  wire       cap_vb_hi, cap_vb_lo,       // B (76 番 GPIOR_155、IC4 TLV3502 A)
    input  wire       cap_hs_hi,  cap_hs_lo,
    input  wire       cap_vs_hi,  cap_vs_lo,
    output wire       cap_tx,
    output wire       cap_thr,        // VID のコンパレータのしきい値 (PWM、98 番)
    output wire       cap_sthr,       // 同期のコンパレータのしきい値 (PWM、99 番。674245b で 100 番から)
    output reg        out_oe_n,       // 0 = 出力モード、1 = 入力モード (U8 の 1OE / 4OE と終端の MOSFET、100 番 (674245b で 99 番から)、R54 1kΩ 越し。基板で 10kΩ プルアップ)
    input  wire       term_sw,        // 終端の切り替えスイッチ S3 の状態 (/TERM_SW を 102 番で読む。1 = 75Ω の終端あり、2026-11-08。
                                      //   スイッチのない基板では未接続で弱いプルダウン。2026-11-09 から S3 の NO のネット /TERM_SW を読む)
    output reg        term_off,       // 1 = 終端を切る (103 番 GPIOR_104 → Q6 で /TERM_EN を GND に。2026-11-09、schematic_todo.md の AS 節)。
                                      //   基板で R81 100kΩ のプルアップ (コンフィグ前も切る)。入力モードで S3 = 75Ω、HI LEVEL でないときだけ 0
    input  wire       mode_sw         // 入力 / 出力の切り替えスイッチ S2 の状態 (/OUT_OE_N のネットを 101 番で読む。1 = IN、2026-11-08。
                                      //   スイッチのない基板では 101 番は未接続で、Interface Designer の弱いプルダウンで 0)
                                      //   S2 が IN なら /OUT_OE_N は基板でじかに +3V3 (FPGA の 100 番は R54 1kΩ 越し)、/HS_TTL_OE_N もダイオードで High
);
    wire [3:0] vga_r, vga_g, vga_b;
    assign {vga_r3, vga_r2, vga_r1, vga_r0} = vga_r;
    assign {vga_g3, vga_g2, vga_g1, vga_g0} = vga_g;
    assign {vga_b3, vga_b2, vga_b1, vga_b0} = vga_b;

    assign osc_scl_out = 1'b0;
    assign osc_sda_out = 1'b0;
    assign oled_scl_out = 1'b0;
    assign oled_sda_out = 1'b0;

    // ---------- 50MHz 側リセット ----------
    reg [1:0] rs = 2'b11;
    always @(posedge clk50 or negedge rst_n)
        if (!rst_n) rs <= 2'b11; else rs <= {rs[0], 1'b0};
    wire rst = rs[1];

    // ---------- ボタン ----------
    wire b_next, b_prev, b_up, b_dn, b_step, b_apply, b_osd;
    buttons #(.TICK_CYCLES(TICK_CYCLES)) u_btn (
        .clk(clk50), .rst(rst), .btn_n(btn_n),
        .sel_next(b_next), .sel_prev(b_prev), .up(b_up), .dn(b_dn), .step(b_step), .apply(b_apply),
        .osd(b_osd)
    );
    reg osd_en;                       // VGA 出力への情報表示
    always @(posedge clk50)
        if (rst) osd_en <= 1'b1; else if (b_osd) osd_en <= ~osd_en;   // 電源投入時は ON (2026-10-30)
    reg osd_show;                     // 遅延測定の画面を出している間は OSD を消す
    wire lag_mode;
    always @(posedge clk50) osd_show <= osd_en && !lag_mode;
    // メニューを VGA 出力にも出す (2026-11-11): ボタンを押してから MENU_SHOW_MS の間、OLED と同じ 16 文字 x 8 行を OSD の枠の中央に。
    //   遅延測定の画面を出している間は出さない。1ms の刻みはボタンと同じ数え方 (TICK_CYCLES)
    reg [15:0] mtc;                   // 1ms の刻み
    reg [12:0] mshow;                 // 残り [ms]
    reg        menu_show;
    always @(posedge clk50) begin
        mtc <= (rst || mtc == TICK_CYCLES - 1) ? 16'd0 : mtc + 16'd1;
        if (rst) mshow <= 13'd0;
        else if (b_next || b_prev || b_up || b_dn || b_step || b_apply) mshow <= MENU_SHOW_MS;
        else if (mtc == 16'd0 && mshow != 13'd0) mshow <= mshow - 13'd1;
        menu_show <= (mshow != 13'd0) && !lag_mode;
    end

    // ---------- 測定 ----------
    wire [26:0] meas_hz, hfreq, vfreq;
    wire        meas_valid, no_clk;
    freq_counter #(.GATE_CYCLES(DOT_GATE), .SCALE(DOT_SCALE)) u_fc (
        .clk(clk50), .rst(rst), .meas_clk(dot_clk),
        .freq_hz(meas_hz), .valid(meas_valid), .no_signal(no_clk)
    );
    // ---------- 割り算器の共有 (2026-11-14、容量削減) ----------
    //   50MHz 側の割り算を 1 つの udiv で順番に: 0 Si5351A / 1 テレビの K / 2 テレビの R / 3 垂直周波数 / 4 遅延測定 / 5 H 周波数 ÷ 10
    //   (待ちが重なったら番号の小さい方が先。テレビは K を R より先に終える前提で、K を小さい番号に)
    wire [5:0]   ud_start, ud_done;
    wire [281:0] ud_num;            // 47 ビット × 6
    wire [179:0] ud_den;            // 30 ビット × 6
    wire [46:0]  ud_quo;
    wire [29:0]  ud_rem;
    udiv_share #(.N(6), .NW(47), .DW(30)) u_ud (
        .clk(clk50), .start(ud_start), .num(ud_num), .den(ud_den),
        .quo(ud_quo), .rem(ud_rem), .done(ud_done)
    );
    wire line_tgl, frame_tgl;
    sync_meas #(.SHARED(1), .GATE(H_GATE), .SCALE(H_SCALE)) u_sm (
        .clk(clk50), .rst(rst), .line_tgl(line_tgl), .frame_tgl(frame_tgl),
        .hfreq_hz(hfreq), .vfreq_x100(vfreq),
        .sd_start(ud_start[3]), .sd_num(ud_num[3*47 +: 47]), .sd_den(ud_den[3*30 +: 30]),
        .sd_quo(ud_quo), .sd_rem(ud_rem), .sd_done(ud_done[3])
    );

    // ---------- 設定 ----------
    wire [5:0]  cur, rd_code;          // cur の bit5 = 1 は階層メニューの行 (2026-11-20)
    wire [4:0]  rd_pos, menu_pos, menu_cnt;
    wire        menu_edit;
    wire [26:0] step_val, rd_val, dot_target;
    wire [1:0]  rd_kind;
    wire [3:0]  pattern;
    wire [11:0] c_ha, c_hf, c_hs, c_hb, c_va, c_vf, c_vs, c_vb;
    wire        c_hn, c_vn, c_tg, dot_upd;
    wire [11:0] c_vo;              // VSYNC の切り替え位置 (VS OFS)
    wire [1:0]  c_cs;
    wire        c_slv;
    wire [2:0]  c_tv;
    wire        c_il;                 // インターレース (確定値)
    wire        osc_settled, out_en, pending, pend_m;
    wire        st_save, st_load, ld_we, st_busy, st_ok, st_err;
    wire [4:0]  ld_idx;
    wire [7:0]  ld_byte;
    wire [2:0]  st_slot, st_wslot;
    wire [7:0]  st_valid;
    wire [255:0] pk_data;
    wire [63:0]  st_name;
    wire [63:0]  rd_text;
    wire [3:0]   rd_cursor, slot_no;
    wire         rd_lock, rd_mv, rd_ro;
    wire [1:0]   rd_q, rd_auto;          // キャプチャの推定の印 ? と AUTO の表示 (2026-11-15)
    wire [1:0]  lag_area;
    wire        lag_sel, lag_start, lag_stop, lag_active, lag_req, lag_shown;
    wire [3:0]  lag_status;
    wire [26:0] lag_avg, lag_min, lag_max;
    // キャプチャ (メニュー ⇔ cap_ctrl / cap_est)
    wire        cap_en, cap_sel;
    wire        wav_en, wav_rec_tgl, wav_play_s;
    // wav_rec の状態 (cap_clk) を clk50 へ (wav_store が見せる。結果は wav_store が済みのトグルで取り込む)
    (* async_reg = "true" *) reg [2:0] wst_s0, wst_s1;
    reg  [2:0]  wav_rstat_s;
    wire [2:0]  wav_stat_c, wav_stat_s;
    wire [11:0] wav_lines_c, wav_lines_s;
    wire [10:0] wav_ent_c, wav_ent_s;
    wire        wav_rdy_c;
    always @(posedge clk50) begin
        wst_s0 <= wav_stat_c; wst_s1 <= wst_s0; wav_rstat_s <= wst_s1;
    end
    // EEPROM の波形のスロット (preset_store ⇔ wav_store)
    wire        st_wav, st_wv, wcm_we;
    wire [7:0]  wcm_addr, wcm_waddr;
    wire [15:0] wcm_q, wcm_wd;
    wire [10:0] wl_nw;
    wire [11:0] wl_lines;
    wire [1:0]  wl_lv0, wav_slv0;
    // 入力モード = 切り替えスイッチ S2 が IN (/OUT_OE_N のネットを 101 番で読む。スイッチのない基板では 101 番は弱いプルダウンで 0
    //   なので入力モードにならない)。2026-11-21 の仕様変更でメニューの CAP IN はなくし、入力 / 出力はスイッチだけで決める。
    //   FPGA が /OUT_OE_N に出すのはぶつかり (CLASH) のときだけ。S2 が IN で FPGA が 0 を出している間は、1kΩ (R77) に 3.3mA 流れる
    (* async_reg = "true" *) reg [1:0] msw;
    always @(posedge clk50) msw <= {msw[0], mode_sw};
    wire        cap_clash_s;              // ぶつかりの見張り (cap_clash、clk50 にそろえた値)
    // スイッチの向きは /OUT_OE_N のネットで読むので、FPGA が out_oe_n = 1 を出している間 (ぶつかり) は
    //   スイッチが OUT でも 1 に読める。出している間と 0 に戻してから約 1.3µs は読まず、スイッチは OUT とみなす (2026-11-21)
    reg  [5:0]  sw_hold;
    always @(posedge clk50) sw_hold <= out_oe_n ? 6'd0 : (sw_hold == 6'd63) ? sw_hold : sw_hold + 6'd1;
    wire        sw_in  = msw[1] && (sw_hold == 6'd63);
    wire        cap_in = sw_in | cap_clash_s;   // ぶつかったら入力モードと同じく出力を止める
    wire [3:0]  cap_status;
    wire [7:0]  cap_rr;
    wire        cap_rrv;
    wire [11:0] cap_ha, cap_va;
    wire        es_tgl, es_ack;
    wire [2:0]  es_err;
    wire [1:0]  es_bstat;
    wire [15:0] es_nfield;
    wire [11:0] es_ht, es_hf, es_hs, es_hb, es_vf, es_vs, es_vb, es_vt, es_vo;
    wire        es_il, es_hneg, es_vneg;
    wire [1:0]  es_cs;
    wire [26:0] es_dot;
    wire [7:0]  es_frac;
    wire [11:0] es_ha, es_va;           // 推定に使った解像度 (2026-11-10)
    settings #(.SHARED(1), .PUB_CYCLES(PUB_CYCLES), .SETTLE_CYCLES(SETTLE_CYCLES)) u_set (
        .clk(clk50), .rst(rst),
        .b_next_in(b_next), .b_prev_in(b_prev), .b_up_in(b_up), .b_dn_in(b_dn), .b_step_in(b_step), .b_apply_in(b_apply),
        .ro_meas(meas_hz), .ro_hfreq(hfreq), .ro_vfreq(vfreq),
        .cur(cur), .menu_pos(menu_pos), .menu_cnt(menu_cnt), .edit(menu_edit), .step_val(step_val), .rd_pos(rd_pos), .rd_code(rd_code), .rd_val(rd_val), .rd_kind(rd_kind),
        .rd_text(rd_text), .rd_cursor(rd_cursor), .rd_lock(rd_lock), .rd_mv(rd_mv), .rd_q(rd_q), .rd_auto(rd_auto), .rd_ro(rd_ro), .slot_no(slot_no), .st_name(st_name),
        .cfg_h_active(c_ha), .cfg_h_fp(c_hf), .cfg_h_sync(c_hs), .cfg_h_bp(c_hb),
        .cfg_v_active(c_va), .cfg_v_fp(c_vf), .cfg_v_sync(c_vs), .cfg_v_bp(c_vb),
        .cfg_hs_neg(c_hn), .cfg_vs_neg(c_vn), .cfg_vs_ofs(c_vo), .cfg_csync(c_cs), .cfg_sync_lv(c_slv), .cfg_tv_mode(c_tv), .cfg_interlace(c_il), .cfg_toggle(c_tg),
        .pattern(pattern), .dot_target(dot_target), .dot_upd(dot_upd),
        .osc_settled(osc_settled), .out_en(out_en), .pending(pending), .pend_m(pend_m),
        .st_save(st_save), .st_load(st_load), .st_slot(st_slot), .st_wslot(st_wslot), .pk_data(pk_data),
        .ld_we(ld_we), .ld_idx(ld_idx), .ld_byte(ld_byte), .st_valid(st_valid), .st_busy(st_busy),
        .st_ok(st_ok), .st_err(st_err),
        .lag_area(lag_area), .lag_sel(lag_sel), .lag_start(lag_start), .lag_stop(lag_stop),
        .lag_status(lag_status), .lag_avg(lag_avg), .lag_min(lag_min), .lag_max(lag_max),
        .cap_en(cap_en), .cap_sw(sw_in), .cap_clash(cap_clash_s), .cap_sel(cap_sel), .cap_status(cap_status), .cap_rr(cap_rr), .cap_rrv(cap_rrv), .e_ha(es_ha), .e_va(es_va),
        .wav_en(wav_en), .wav_rec_tgl(wav_rec_tgl), .wav_play(wav_play_s), .wav_stat(wav_stat_s), .wav_lines(wav_lines_s), .wav_ent(wav_ent_s), .st_wav(st_wav),
        .e_err(es_err), .e_dot(es_dot), .e_ht(es_ht), .e_hf(es_hf), .e_hs(es_hs), .e_hb(es_hb),
        .e_vt(es_vt), .e_vf(es_vf), .e_vs(es_vs), .e_vb(es_vb), .e_vo(es_vo), .e_il(es_il), .e_hneg(es_hneg), .e_vneg(es_vneg), .e_cs(es_cs),
        .cap_ha(cap_ha), .cap_va(cap_va),
        .sd_start(ud_start[5]), .sd_num(ud_num[5*47 +: 47]), .sd_den(ud_den[5*30 +: 30]),
        .sd_quo(ud_quo), .sd_rem(ud_rem), .sd_done(ud_done[5])
    );

    // ---------- 同期の電圧 (U11 の OE) ----------
    always @(posedge clk50) hs_ttl_oe_n <= rst ? 1'b1 : (c_slv || cap_in);   // 入力モードでは 47Ω の側も止める

    // ---------- 遅延測定 ----------
    //   測定中は画面を黒地 + 測定範囲にする。LAG AREA を選んでいる間は範囲を白で出しておく (センサーの位置合わせ)
    lag_meas #(.SHARED(1), .DARK_CYC(LAG_DARK), .HOLD_CYC(LAG_HOLD), .TIMEOUT(LAG_TIMEOUT),
               .SETTLE(LAG_SETTLE), .WIN(LAG_WIN), .RUNS_LOG2(LAG_RUNS_LOG2)) u_lag (
        .clk(clk50), .rst(rst), .start(lag_start), .stop(lag_stop),
        .shown(lag_shown), .sens_in(lag_sens),
        .active(lag_active), .req(lag_req), .thr_pwm(lag_thr), .status(lag_status),
        .avg_lag(lag_avg), .min_lag(lag_min), .max_lag(lag_max),
        .sd_start(ud_start[4]), .sd_num(ud_num[4*47 +: 47]), .sd_den(ud_den[4*30 +: 30]),
        .sd_quo(ud_quo), .sd_rem(ud_rem), .sd_done(ud_done[4])
    );
    reg lag_mode_r, lag_req_r;
    always @(posedge clk50) begin
        lag_mode_r <= lag_active || lag_sel;
        lag_req_r  <= lag_active ? lag_req : 1'b1;
    end
    assign lag_mode = lag_mode_r;

    // ---------- ユーザープリセット (EEPROM) ----------
    preset_store u_store (
        .clk(clk50), .rst(rst), .save(st_save), .load(st_load), .slot(st_slot), .wslot(st_wslot),
        .cur_data(pk_data), .ld_we(ld_we), .ld_idx(ld_idx), .ld_byte(ld_byte), .valid(st_valid), .name_sel(st_slot), .name_q(st_name),
        .busy(st_busy), .done_ok(st_ok), .done_err(st_err),
        .wav(st_wav), .wv_nw(wav_ent_s), .wv_lines(wav_lines_s), .wv_lv0(wav_slv0), .cm_addr(wcm_addr), .cm_q(wcm_q),
        .cm_we(wcm_we), .cm_waddr(wcm_waddr), .cm_wd(wcm_wd), .wv(st_wv), .wl_nw(wl_nw), .wl_lines(wl_lines), .wl_lv0(wl_lv0),
        .ee_cs_n(ee_cs_n), .ee_sck(ee_sck), .ee_mosi(ee_mosi), .ee_miso(ee_miso)
    );

    // ---------- Si5351A ----------
    //   補正はしない (Si5351A は計算どおりの周波数が出る)。CLK1 には起動時からテレビ出力用の 27MHz を出す
    si5351_ctrl #(.SHARED(1), .I2C_Q(OLED_I2C_Q)) u_osc (
        .clk(clk50), .rst(rst),
        .target_hz(dot_target), .target_upd(dot_upd), .meas_valid(meas_valid), .meas_hz(meas_hz),
        .scl_oe(osc_scl_oe), .sda_oe(osc_sda_oe), .settled(osc_settled),
        .sd_start(ud_start[0]), .sd_num(ud_num[0 +: 47]), .sd_den(ud_den[0 +: 30]),
        .sd_quo(ud_quo), .sd_rem(ud_rem), .sd_done(ud_done[0])
    );

    // ---------- 映像入力の測定 (cap_clk 側) ----------
    //   cap_meas (測定) → cap_blank (BLANK MEAS、表示の端) → cap_est (推定)。推定はトグル + 変わらない値で 50MHz 側へ
    //   (メニュー (settings) が表示・COPY で読み、cap_ctrl が受け取りを返す)。
    //   操作はメニューの CAP RUN → cap_ctrl (50MHz) → cap_thr (しきい値の合わせ込み) → cap_blank の START / END
    //   解像度 (H / V ACTIVE) は作業中の値 (cap_ha / cap_va、50MHz 側の値をそのまま)。cap_est が推定の始めに 2 回続けて
    //   同じ値を取り込んでその一式で計算し、使った値を e_ha / e_va で返す (COPY は作業中の値と一致するときだけ)。
    //   測定中 (THR / RUN) は settings が ACTIVE の変更を止める (2026-11-10)
    // 黒以外 = R / G / B のどれかが黒以外 (DDIO の 2 サンプルごとに OR)
    wire        cap_vid_hi = cap_vr_hi | cap_vg_hi | cap_vb_hi;
    wire        cap_vid_lo = cap_vr_lo | cap_vg_lo | cap_vb_lo;
    wire [7:0]  cap_flags;
    wire [23:0] cap_th;
    wire [19:0] cap_hsw;
    wire [11:0] cap_vt0, cap_vsw;
    wire [15:0] cap_vo0, cap_vo1;
    wire        cap_lnv, cap_lnhasr, cap_lnany, cap_fdv, cap_fdpar, cap_fdok;
    wire [11:0] cap_lnno, cap_fdcnt;
    wire [15:0] cap_lnrise, cap_lnfall;
    cap_meas #(.VWIN_LOG2(CAP_VWIN_LOG2)) u_cap (
        .cclk(cap_clk), .rst_n(rst_n),
        .vid_hi(cap_vid_hi), .vid_lo(cap_vid_lo), .hs_hi(cap_hs_hi), .hs_lo(cap_hs_lo), .vs_hi(cap_vs_hi), .vs_lo(cap_vs_lo),
        .m_th(cap_th), .m_hsw(cap_hsw), .m_vsw(cap_vsw),
        .ln_v(cap_lnv), .ln_no(cap_lnno), .ln_rise(cap_lnrise), .ln_fall(cap_lnfall), .ln_hasr(cap_lnhasr), .ln_any(cap_lnany),
        .fd_v(cap_fdv), .fd_par(cap_fdpar), .fd_cnt(cap_fdcnt), .fd_cnt0(cap_vt0), .fd_vo(cap_vo1), .fd_vo0(cap_vo0),
        .fd_flags(cap_flags), .fd_ok(cap_fdok),
        .w_pa(cap_wpa), .w_pb(cap_wpb), .w_lna(cap_wlna), .w_lnb(cap_wlnb),
        .w_sa(cap_wsa), .w_sb(cap_wsb), .w_ua(cap_wua), .w_ub(cap_wub), .w_csy(cap_wcsy)
    );
    wire [15:0] cap_wpa, cap_wpb;
    wire [11:0] cap_wlna, cap_wlnb;
    wire        cap_wsa, cap_wsb, cap_wua, cap_wub, cap_wcsy;
    // cap_clk 側のリセット (rst_n を同期化)
    reg [1:0] crs = 2'b11;
    always @(posedge cap_clk or negedge rst_n)
        if (!rst_n) crs <= 2'b11; else crs <= {crs[0], 1'b0};
    wire crst = crs[1];
    wire        bl_start, bl_stop, bl_tgl, bl_ack;
    wire [1:0]  bl_stat;
    wire [15:0] bl_nfield, bl_left, bl_right;
    wire [15:0] bl_ln0, bl_ln1, bl_rn0, bl_rn1;
    wire [11:0] bl_top0, bl_bot0, bl_top1, bl_bot1;
    wire [3:0]  bl_found;
    // しきい値の自動の合わせ込み (cap_clk) とキャプチャの操作 (50MHz)
    wire        th_req, th_done, th_ok, th_busy, th_hi, cc_act;
    wire [9:0]  th_s, th_v;
    cap_thr #(.SET_LOG2(CAP_SET_LOG2), .WIN_LOG2(CAP_WIN_LOG2), .FLD_TO_LOG2(CAP_FTO_LOG2)) u_capt (
        .clk(cap_clk), .rst(crst), .req_tgl(th_req),
        .vid_hi(cap_vid_hi), .vid_lo(cap_vid_lo), .hs_hi(cap_hs_hi), .hs_lo(cap_hs_lo), .fd(cap_fdv),
        .inmode(cap_in), .term(term_sw), .hold(cc_act), .busy(th_busy), .hi_lvl(th_hi),
        .sthr(th_s), .vthr(th_v), .done_tgl(th_done), .ok(th_ok)
    );
    cap_ctrl u_capc (
        .clk(clk50), .rst(rst), .en(cap_en), .sel(cap_sel),
        .thr_req(th_req), .thr_done(th_done), .thr_ok(th_ok), .thr_hi(th_hi), .active(cc_act), .bl_start(bl_start), .bl_stop(bl_stop),
        .e_tgl(es_tgl), .e_bstat(es_bstat), .e_err(es_err), .e_frac(es_frac), .rr(cap_rr), .rr_v(cap_rrv), .status(cap_status), .e_ack(es_ack)
    );
    cap_blank u_capb (
        .clk(cap_clk), .rst(crst), .start_tgl(bl_start), .stop_tgl(bl_stop),
        .ln_v(cap_lnv), .ln_no(cap_lnno), .ln_rise(cap_lnrise), .ln_fall(cap_lnfall), .ln_hasr(cap_lnhasr), .ln_any(cap_lnany),
        .fd_v(cap_fdv), .fd_par(cap_fdpar), .fd_cnt(cap_fdcnt), .fd_ok(cap_fdok),
        .res_tgl(bl_tgl), .res_ack(bl_ack), .b_stat(bl_stat), .b_nfield(bl_nfield), .b_left(bl_left), .b_right(bl_right),
        .b_ln0(bl_ln0), .b_ln1(bl_ln1), .b_rn0(bl_rn0), .b_rn1(bl_rn1),
        .b_top0(bl_top0), .b_bot0(bl_bot0), .b_top1(bl_top1), .b_bot1(bl_bot1), .b_found(bl_found)
    );
    cap_est #(.RCOMP(CAP_RCOMP)) u_cape (
        .clk(cap_clk), .rst(crst), .ha(cap_ha), .va(cap_va),
        .m_v(cap_fdv), .m_flags(cap_flags), .m_th(cap_th), .m_hsw(cap_hsw), .m_vt0(cap_vt0), .m_vt1(cap_fdcnt), .m_vsw(cap_vsw),
        .m_vo0(cap_vo0), .m_vo1(cap_vo1),
        .b_tgl(bl_tgl), .b_ack(bl_ack), .b_stat(bl_stat), .b_nfield(bl_nfield), .b_left(bl_left), .b_right(bl_right),
        .b_ln0(bl_ln0), .b_ln1(bl_ln1), .b_rn0(bl_rn0), .b_rn1(bl_rn1), .b_top0(bl_top0), .b_top1(bl_top1), .b_bot0(bl_bot0), .b_bot1(bl_bot1), .b_found(bl_found),
        .e_tgl(es_tgl), .e_ack(es_ack), .e_err(es_err), .e_bstat(es_bstat), .e_nfield(es_nfield),
        .e_ht(es_ht), .e_hf(es_hf), .e_hs(es_hs), .e_hb(es_hb), .e_vf(es_vf), .e_vs(es_vs), .e_vb(es_vb), .e_vt(es_vt), .e_vo(es_vo),
        .e_il(es_il), .e_hneg(es_hneg), .e_vneg(es_vneg), .e_cs(es_cs), .e_dot(es_dot), .e_frac(es_frac), .e_ha(es_ha), .e_va(es_va),
        .x_sel(wdv_sel), .x_start(wdv_go), .x_num(wdv_num), .x_den(wdv_den), .x_quo(wdv_q), .x_done(wdv_done)   // 割り算を wav_rec に貸す
    );
    wire        wdv_sel, wdv_go, wdv_done;
    wire [47:0] wdv_num, wdv_q;
    wire [23:0] wdv_den;
    assign cap_tx = 1'b1;                 // UART は外した (2026-11-10)
    // 出力のぶつかりの見張り (cap_clk)。出力している (out_en で入力モードでない) ときに、受けた同期と自分の同期を比べる。
    //   ぶつかったら APPLY まで出力を止める (APPLY の cfg_toggle で消す)
    wire cap_clash_c;
    cap_clash #(.WIN_LOG2(CAP_CLASH_WIN)) u_capx (
        .clk(cap_clk), .rst(crst), .en(out_en && !cap_in), .busy(th_busy),
        .own_hs(vga_hsync), .own_vs(vga_vsync), .hs_in(cap_hs_hi), .vs_in(cap_vs_hi),
        .clr_tgl(c_tg), .clash(cap_clash_c)
    );
    (* async_reg = "true" *) reg [1:0] cx_s;
    always @(posedge clk50) cx_s <= {cx_s[0], cap_clash_c};
    assign cap_clash_s = cx_s[1];

    // コンパレータのしきい値 (PWM、cap_clk) とモード (スイッチ S2 が IN で入力モード)
    cap_pwm u_cpw_v (.clk(cap_clk), .rst(crst), .duty(th_v), .out(cap_thr));
    cap_pwm u_cpw_s (.clk(cap_clk), .rst(crst), .duty(th_s), .out(cap_sthr));
    always @(posedge clk50) out_oe_n <= rst ? 1'b1 : cap_clash_s;   // ぶつかり (スイッチの IN は基板で 1 になる。メニューの CAP IN は 2026-11-21 になくした)
    // 終端を切る (2026-11-09): 入力モードで S3 = 75Ω のときだけ終端を入れ、cap_thr の見張り・CAP RUN の確かめで HI LEVEL なら切る。
    //   出力モードでは終端のゲートの元 (/OUT_OE_N) が 0 なので、どちらでも入らない (1 にしておく)
    (* async_reg = "true" *) reg [1:0] tsw, thi;
    always @(posedge clk50) begin tsw <= {tsw[0], term_sw}; thi <= {thi[0], th_hi}; end
    always @(posedge clk50) term_off <= rst ? 1'b1 : !(cap_in && tsw[1] && !thi[1]);

    // ---------- OLED ----------
    wire       wr_en;
    wire [6:0] wr_addr;
    wire [7:0] wr_data;
    wire        mcv_start, mcv_done, ocv_start, ocv_done;
    wire [26:0] mcv_in, ocv_in;
    wire [31:0] cv_bcd;
    menu_display #(.REFRESH(REFRESH)) u_menu (
        .clk(clk50), .rst(rst), .mpos(menu_pos), .mcnt(menu_cnt), .edit(menu_edit), .step_val(step_val),
        .rd_pos(rd_pos), .rd_code(rd_code), .rd_val(rd_val), .rd_kind(rd_kind), .pending(pend_m),
        .rd_text(rd_text), .rd_cursor(rd_cursor), .rd_lock(rd_lock), .rd_mv(rd_mv), .rd_q(rd_q), .rd_auto(rd_auto), .rd_ro(rd_ro), .slot_no(slot_no), .cap(cap_en), .wav(wav_en),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .cv_start(mcv_start), .cv_in(mcv_in), .cv_bcd(cv_bcd), .cv_done(mcv_done)
    );
    // 2 進 → 10 進の変換は menu_display と osd_text で 1 つを共有 (2026-11-13、容量削減)
    bcd_share u_bcd (.clk(clk50), .a_start(mcv_start), .a_bin(mcv_in), .a_done(mcv_done),
                     .b_start(ocv_start), .b_bin(ocv_in), .b_done(ocv_done), .bcd(cv_bcd));
    ssd1306_text #(.RESET_CYCLES(OLED_RESET), .I2C_Q(OLED_I2C_Q)) u_oled (
        .clk(clk50), .rst(rst),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .oled_scl_oe(oled_scl_oe), .oled_sda_oe(oled_sda_oe), .frame_done()
    );

    // ---------- VGA (ドットクロック側) ----------
    wire        hs, vs, de, fs;
    wire [11:0] x, y, ha, va, vtm1, hss, hse;
    wire        vsl, oon, ilace;
    wire [1:0]  slot_a;
    wire [2:0]  slot_b;
    wire [11:0] hmid;
    vga_timing u_tim (
        .dclk(dot_clk), .rst_n(rst_n),
        .cfg_h_active(c_ha), .cfg_h_fp(c_hf), .cfg_h_sync(c_hs), .cfg_h_bp(c_hb),
        .cfg_v_active(c_va), .cfg_v_fp(c_vf), .cfg_v_sync(c_vs), .cfg_v_bp(c_vb),
        .cfg_hs_neg(c_hn), .cfg_vs_neg(c_vn), .cfg_vs_ofs(c_vo), .cfg_csync(c_cs), .cfg_interlace(c_il), .cfg_l625(c_tv == 3'd3 || c_tv == 3'd5), .cfg_toggle(c_tg), .out_en(out_en && !cap_in),   // 入力モードでは RGB を 0、同期を止める
        .hsync_o(hs), .vsync_o(vs), .de(de), .x(x), .y(y), .frame_start(fs),
        .h_active(ha), .v_active(va), .v_total_m1(vtm1), .line_tgl(line_tgl), .frame_tgl(frame_tgl),
        .h_sync_s(hss), .h_sync_e(hse), .vs_line(vsl), .out_on(oon),
        .slot_a(slot_a), .slot_b(slot_b), .h_mid(hmid), .h_total(wav_ht), .interlace(ilace), .v_sync_s(vss_pl)
    );
    // ---------- 波形コピー (2026-11-13、MODE = CAP RAW) ----------
    //   wav_rec (cap_clk): 入力の同期を 1 フィールド記録して wav_play のメモリへ。wav_play (dot_clk): ジェネレータの座標で再生。
    //   再生中は vga_pattern へ入れる同期 (hs / vs) を差し替える (以降の遅れ・OSD を今までどおり通す)。極性は確定値
    wire [11:0] vss_pl;
    wire        wav_pw_en;
    wire [10:0] wav_pw_addr;
    wire [24:0] wav_pw_data;
    wire [11:0] wav_ht;                // H 合計 (vga_timing の確定値。変わらない値として cap_clk で読む)
    wav_rec u_wrec (
        .clk(cap_clk), .rst(crst), .rec_tgl(wav_rec_tgl), .ht(wav_ht),
        .w_pa(cap_wpa), .w_pb(cap_wpb), .w_lna(cap_wlna), .w_lnb(cap_wlnb),
        .w_sa(cap_wsa), .w_sb(cap_wsb), .w_ua(cap_wua), .w_ub(cap_wub), .w_csy(cap_wcsy),
        .fd_v(cap_fdv), .fd_par(cap_fdpar), .fd_cnt(cap_fdcnt), .fd_flags(cap_flags), .m_th(cap_th),
        .dv_sel(wdv_sel), .dv_go(wdv_go), .dv_num(wdv_num), .dv_den(wdv_den), .dv_q(wdv_q), .dv_done(wdv_done),
        .stat(wav_stat_c), .n_lines(wav_lines_c), .n_ent(wav_ent_c), .s0(wav_s0_c), .lv0(wav_lv0_c),
        .rdy_tgl(wav_rdy_c), .pw_en(wav_pw_en), .pw_addr(wav_pw_addr), .pw_data(wav_pw_data)
    );
    wire [10:0] wav_s0_c;
    wire [1:0]  wav_lv0_c;
    // wav_store (clk50): 圧縮 (cm) → 再生のメモリへ展開。EEPROM (RAW SAVE / LOAD) は cm を読み書き
    wire        wav_prdy, wav_qw_en;
    wire [10:0] wav_pent, wav_qw_addr;
    wire [24:0] wav_qw_data;
    wav_store u_wst (
        .clk(clk50), .rst(rst), .rec_tgl(wav_rec_tgl), .r_stat(wav_rstat_s), .r_rdy_tgl(wav_rdy_c),
        .r_ent(wav_ent_c), .r_s0(wav_s0_c), .r_lv0(wav_lv0_c), .r_lines(wav_lines_c),
        .wclk(cap_clk), .cw_en(wav_pw_en), .cw_addr(wav_pw_addr), .cw_data(wav_pw_data),
        .ld_beg(st_load && st_wav), .ld_ok(st_ok && st_wv), .ld_err(st_err && st_wv),
        .ld_nw(wl_nw), .ld_lines(wl_lines), .ld_lv0(wl_lv0),
        .e_addr(wcm_addr), .e_q(wcm_q), .e_we(wcm_we), .e_waddr(wcm_waddr), .e_wd(wcm_wd),
        .stat(wav_stat_s), .n_lines(wav_lines_s), .n_words(wav_ent_s), .lv0(wav_slv0),
        .p_rdy_tgl(wav_prdy), .p_ent(wav_pent), .pw_en(wav_qw_en), .pw_addr(wav_qw_addr), .pw_data(wav_qw_data)
    );
    wire        wav_act, wav_phs, wav_pvs;
    wav_play u_wplay (
        .dclk(dot_clk), .en(wav_play_s), .rdy_tgl(wav_prdy), .n_ent(wav_pent), .lv0(wav_slv0),
        .x(x), .y(y), .hs_s(hss), .vs_s(vss_pl), .il(ilace), .wclk(clk50), .pw_en(wav_qw_en), .pw_addr(wav_qw_addr), .pw_data(wav_qw_data),
        .act(wav_act), .hs_lv(wav_phs), .vs_lv(wav_pvs)
    );
    // 再生中は hs / vs を差し替え (正論理 → 確定の極性)。vs は複合同期では止める (c_cs != 0)
    //   出力を止めている間 (APPLY 中・入力モード。vga_timing の out_on = 0) は差し替えず、vga_timing の同期なしのまま (2026-11-14)
    wire wav_sel = wav_act && oon;
    wire hs_p = wav_sel ? (wav_phs ^ c_hn) : hs;
    wire vs_p = wav_sel ? ((c_cs != 2'd0) ? c_vn : (wav_pvs ^ c_vn)) : vs;
    wire [3:0]  pr, pg, pb;
    wire        phs, pvs;
    wire        osd_px, psub, osd_sub;
    vga_pattern u_pat (
        .dclk(dot_clk), .pattern(pattern),
        .hs_in(hs_p), .vs_in(vs_p), .de(de), .frame_start(fs),
        .x(x), .y(y), .h_active(ha), .v_active(va), .v_total_m1(vtm1), .interlace(ilace),
        .lag_mode(lag_mode_r), .lag_req(lag_req_r), .lag_area(lag_area), .lag_shown(lag_shown),
        .r(pr), .g(pg), .b(pb), .hsync_o(phs), .vsync_o(pvs), .sub_o(psub)
    );
    // いま出力している設定と測定値を VGA 出力の中央に重ねる (UP+DOWN 同時押しで ON/OFF)
    wire       ow_en;
    wire [7:0] ow_addr, ow_data;
    osd_text #(.REFRESH(REFRESH)) u_otxt (
        .clk(clk50), .rst(rst),
        .dot_hz(dot_target), .meas_hz(meas_hz),
        .ha(c_ha), .hf(c_hf), .hs(c_hs), .hb(c_hb), .va(c_va), .vf(c_vf), .vs(c_vs), .vb(c_vb),
        .hneg(c_hn), .vneg(c_vn), .csync(c_cs), .sync_lv(c_slv), .ilace(c_il), .hfreq_hz(hfreq), .vfreq_x100(vfreq),
        .wr_en(ow_en), .wr_addr(ow_addr), .wr_data(ow_data),
        .cv_start(ocv_start), .cv_in(ocv_in), .cv_bcd(cv_bcd), .cv_done(ocv_done)
    );
    vga_osd u_osd (
        .wclk(clk50), .wr_en(ow_en), .wr_addr(ow_addr), .wr_data(ow_data),
        .mwr_en(wr_en), .mwr_addr(wr_addr), .mwr_data(wr_data), .menu_en(menu_show),
        .dclk(dot_clk), .osd_en(osd_show),
        .de(de), .x(x), .y(y), .h_active(ha), .v_active(va),
        .r_in(pr), .g_in(pg), .b_in(pb), .hs_in(phs), .vs_in(pvs), .sub_in(psub),
        .r(vga_r), .g(vga_g), .b(vga_b), .hsync_o(vga_hsync), .vsync_o(vga_vsync), .osd_o(osd_px), .sub_o(osd_sub)
    );

    // ---------- テレビ出力 (27MHz 側) ----------
    //   VGA の出力 (OSD を含む) をそのままテレビの形にする。パターン 7〜9 はテレビ用に 8 ビットで作る
    reg  [3:0] tv_pat;                // 遅延測定の画面を出している間はテレビ用のパターンを使わない
    always @(posedge clk50) tv_pat <= lag_mode ? 4'd0 : pattern;
    tv_encoder #(.SHARED(1)) u_tv (
        .dclk(dot_clk), .de(de), .x(x), .slot_a(slot_a), .slot_b(slot_b), .h_mid(hmid), .out_on(oon),
        .h_active(ha), .h_sync_s(hss), .h_sync_e(hse),
        .r_in(vga_r), .g_in(vga_g), .b_in(vga_b), .osd_in(osd_px), .sub_in(osd_sub),
        .clk(clk50), .dot_hz(dot_target), .mode(c_tv), .ha_cfg(c_ha), .pattern(tv_pat),
        .tclk(tv_clk), .y_o(tv_y), .c_o(tv_c), .cvbs_o(tv_cvbs),
        .sk_start(ud_start[1]), .sk_num(ud_num[1*47 +: 47]), .sk_den(ud_den[1*30 +: 30]),
        .sk_quo(ud_quo), .sk_rem(ud_rem), .sk_done(ud_done[1]),
        .sd_start(ud_start[2]), .sd_num(ud_num[2*47 +: 47]), .sd_den(ud_den[2*30 +: 30]),
        .sd_quo(ud_quo), .sd_rem(ud_rem), .sd_done(ud_done[2])
    );
endmodule
