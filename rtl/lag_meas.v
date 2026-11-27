// =============================================================
// 表示遅延の測定 (基準 50MHz 側で動作)
//
//   画面の一部 (または全体) を黒 → 白に切り替え、光センサーが光を検出するまでの時間を測る。
//   センサーの信号は基板のコンパレータで 2 値にして入れる (sens_in、1 = 明るい)。
//   コンパレータのしきい値は FPGA の PWM (thr_pwm、10 ビット) を RC で平滑して作る。
//
//   手順 (start で開始、stop で中止)
//     1. 較正: 画面を黒にして、センサー信号の最大値 (しきい値を 2 分探索) を求める。
//              次に測定範囲を白にして同じく最大値を求め、しきい値を 2 つの中間にする
//              (ブラウン管のように光がパルス状でも、窓の間に 1 回でも超えれば「超えた」とする)
//     2. 測定: 黒 (DARK_CYC) → 白にする指示 (req) → 測定範囲の中央の画素を出力 (shown)
//              → センサーが光を検出 (sens) を RUNS 回くり返す
//                 lag = sens - shown  (映像信号が出てから光るまで = 表示機器の遅延)
//     3. 結果: lag の平均・最小・最大を 10µs 単位で出す (12.34ms → 1234。指示から光るまでの CMD AVG は 2026-11-21 に外した)
//
//   LOW SIG のときは、較正で求めた黒と白の電圧を min_lag (黒) / max_lag (白) に 0.01mV 単位で出す (2026-11-06。
//     原因を見分けるため。しきい値の 1 段 = 3.3V × 10k / 43k ÷ 1024 = 0.7495mV ≒ 0.75mV → 段数 × 75。
//     767.25 (しきい値の上限 0.77V) なら 0.77V 以上、0 なら 0V 付近)
//   status: 0 PUSH+ (待機) / 1 CAL / 2 RUN / 3 DONE / 4 LOW SIG (明暗の差が小さい) /
//           5 NO VIDEO (測定範囲が出力されない) / 6 NO LIGHT (光を検出しない) /
//           7 NOISE (黒の間に光を検出) / 8 STOP (中止)
//   shown はドットクロック側の信号 (別クロックから入れてよい)。同期の遅れ 2〜3 クロック (60ns 以下) は無視する
// =============================================================
module lag_meas #(
    parameter integer SHARED = 0,       // 1: 割り算器をトップで共有 (2026-11-14)
    parameter integer CLK_HZ   = 50_000_000,
    parameter integer DARK_CYC = 15_000_000,     // 黒にしておく時間 300ms
    parameter integer HOLD_CYC = 5_000_000,      // 光を検出してから白のままにする時間 100ms
    parameter integer TIMEOUT  = 50_000_000,     // 光を待つ時間の上限 1秒
    parameter integer SETTLE   = 250_000,        // しきい値を変えてから落ち着くまで 5ms
    parameter integer WIN      = 2_500_000,      // 較正で信号を見る時間 50ms (2 フレーム以上)
    parameter integer MIN_DIFF = 16,             // 明暗の差の下限 (PWM の単位、約 12mV)
    parameter integer RUNS_LOG2 = 4              // 測定回数 2^4 = 16 回
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        start,            // 開始 (パルス)
    input  wire        stop,             // 中止 (パルス)
    input  wire        shown,            // 測定範囲の中央の画素を出力した (ドットクロック側)
    input  wire        sens_in,          // コンパレータの出力 (ピン、1 = 明るい)
    output reg         active,           // 測定中 (画面を測定用にする)
    output reg         req,              // 1 = 測定範囲を白にする
    output reg         thr_pwm,          // しきい値の PWM 出力 (ピン)
    output reg  [3:0]  status,
    output reg  [26:0] avg_lag,          // 10µs 単位
    output reg  [26:0] min_lag,
    output reg  [26:0] max_lag,
    // 割り算器の共有 (2026-11-14、容量削減): SHARED = 1 ならトップの udiv_share を使う (0 なら自前の udiv。単体のテスト用)
    output wire        sd_start,
    output wire [46:0] sd_num,
    output wire [29:0] sd_den,
    input  wire [46:0] sd_quo,
    input  wire [29:0] sd_rem,
    input  wire        sd_done
);
    localparam integer RUNS = 1 << RUNS_LOG2;
    localparam integer UNIT = CLK_HZ / 100_000;  // 10µs のクロック数
    localparam [8:0]   UNIT9 = UNIT;
    localparam [31:0]  DARK_CHK = DARK_CYC - WIN;  // ここから先の黒の間は光ってはいけない

    // ---- 入力の同期 ----
    (* async_reg = "true" *) reg [1:0] sh_s, se_s;
    always @(posedge clk) begin sh_s <= {sh_s[0], shown}; se_s <= {se_s[0], sens_in}; end
    wire sh = sh_s[1];
    wire se = se_s[1];

    // ---- しきい値の PWM (10 ビット、約 49kHz) ----
    //   pc は初期値とリセットで 0 にする (2026-10-26 修正。以前は初期値がなく、シミュレーションで X のままだった)
    reg [9:0] thr = 10'd0, pc = 10'd0;
    initial thr_pwm = 1'b0;
    always @(posedge clk) begin
        if (rst) pc <= 10'd0;
        else     pc <= pc + 10'd1;
        thr_pwm <= (pc < thr);
    end

    // ---- 状態機械 ----
    localparam S_IDLE = 4'd0, S_DARK0 = 4'd1, S_SAR_SET = 4'd2, S_SAR_WIN = 4'd3,
               S_WHITE0 = 4'd4, S_THR = 4'd5, S_DARK = 4'd6, S_ON = 4'd7, S_HOLD = 4'd8,
               S_ACC = 4'd9, S_CONV = 4'd10, S_CWAIT = 4'd11;
    reg [3:0]  st;
    reg [31:0] t;                // 汎用タイマー
    reg [26:0] tr;               // req からの時間
    reg [26:0] t_sh;             // shown までの時間
    reg        got_sh, hit, white;
    reg [9:0]  sar, bitm, blk, wht;
    reg [RUNS_LOG2:0] n;
    reg [26:0] lag, mn, mx;
    reg [31:0] s_lag;
    reg [1:0]  ci;               // 変換する値の番号
    // しきい値の段数 → 0.01mV (× 75 = 64 + 8 + 2 + 1。LOW SIG の表示用)
    wire [16:0] blk_mv = {1'b0, blk, 6'd0} + {4'd0, blk, 3'd0} + {6'd0, blk, 1'b0} + {7'd0, blk};
    wire [16:0] sar_mv = {1'b0, sar, 6'd0} + {4'd0, sar, 3'd0} + {6'd0, sar, 1'b0} + {7'd0, sar};

    // 10µs 単位への変換 (逐次の割り算、四捨五入)
    reg         d_start;
    reg  [26:0] d_num;
    wire [46:0] d_quo;
    wire [29:0] d_rem;
    wire        d_done;
    generate if (SHARED) begin : g_sd
        assign d_quo = sd_quo; assign d_rem = sd_rem; assign d_done = sd_done;
    end else begin : g_sd_l
        udiv #(.NW(47), .DW(30)) u_div (.clk(clk), .start(d_start), .num({20'd0, d_num}), .den({21'd0, UNIT9}),
                                        .quo(d_quo), .rem(d_rem), .done(d_done));
    end endgenerate
    assign sd_start = d_start; assign sd_num = {20'd0, d_num}; assign sd_den = {21'd0, UNIT9};

    always @(posedge clk) begin
        d_start <= 1'b0;
        if (rst) begin
            st <= S_IDLE; active <= 1'b0; req <= 1'b0; status <= 4'd0; thr <= 10'd0;
            avg_lag <= 0; min_lag <= 0; max_lag <= 0;
        end else if (stop && st != S_IDLE) begin
            st <= S_IDLE; active <= 1'b0; req <= 1'b0; status <= 4'd8;
        end else begin
            case (st)
            S_IDLE: if (start) begin
                active <= 1'b1; req <= 1'b0; status <= 4'd1;
                avg_lag <= 0; min_lag <= 0; max_lag <= 0;
                white <= 1'b0; t <= 0; st <= S_DARK0;
            end
            // ---- 較正 ----
            S_DARK0: if (t == DARK_CYC) begin       // 黒 (または白) が表示されるのを待つ
                sar <= 10'd0; bitm <= 10'h200; t <= 0; st <= S_SAR_SET;
            end else t <= t + 1;
            S_SAR_SET: begin                         // しきい値を試し、落ち着くまで待つ
                thr <= sar | bitm;
                if (t == SETTLE) begin t <= 0; hit <= 1'b0; st <= S_SAR_WIN; end
                else t <= t + 1;
            end
            S_SAR_WIN: begin                         // 窓の間に 1 回でも超えたか
                if (se) hit <= 1'b1;
                if (t == WIN) begin
                    t <= 0;
                    if (hit || se) sar <= sar | bitm;
                    if (bitm == 10'd1) st <= white ? S_THR : S_WHITE0;
                    else begin bitm <= bitm >> 1; st <= S_SAR_SET; end
                end else t <= t + 1;
            end
            S_WHITE0: begin                          // 黒の最大値が出た → 白で同じことをする
                blk <= sar; white <= 1'b1; req <= 1'b1; t <= 0; st <= S_DARK0;
            end
            S_THR: begin
                wht <= sar; req <= 1'b0;
                if ({1'b0, sar} < {1'b0, blk} + MIN_DIFF) begin
                    st <= S_IDLE; active <= 1'b0; status <= 4'd4;
                    min_lag <= {10'd0, blk_mv}; max_lag <= {10'd0, sar_mv};     // 黒 / 白の電圧 [0.01mV]
                end
                else begin
                    thr <= ({1'b0, blk} + {1'b0, sar}) >> 1;
                    n <= 0; s_lag <= 0; mn <= {27{1'b1}}; mx <= 0;
                    status <= 4'd2; t <= 0; st <= S_DARK;
                end
            end
            // ---- 測定 ----
            S_DARK: begin                            // 黒。最後の WIN の間に光ったら NOISE
                if (t >= DARK_CHK && se) begin st <= S_IDLE; active <= 1'b0; status <= 4'd7; end
                else if (t == DARK_CYC) begin
                    req <= 1'b1; tr <= 0; got_sh <= 1'b0; st <= S_ON;
                end else t <= t + 1;
            end
            S_ON: begin                              // 白にする指示 → 出力 → 光
                tr <= tr + 1;
                if (sh && !got_sh) begin got_sh <= 1'b1; t_sh <= tr; end
                if (got_sh && se) begin
                    lag <= tr - t_sh; t <= 0; st <= S_HOLD;
                end else if (tr == TIMEOUT) begin
                    st <= S_IDLE; active <= 1'b0; req <= 1'b0; status <= got_sh ? 4'd6 : 4'd5;
                end
            end
            S_HOLD: if (t == HOLD_CYC) begin
                req <= 1'b0; t <= 0; st <= S_ACC;
            end else t <= t + 1;
            S_ACC: begin                             // 合計・最小・最大
                s_lag <= s_lag + lag;
                if (lag < mn) mn <= lag;
                if (lag > mx) mx <= lag;
                n <= n + 1'b1;
                if (n == RUNS - 1) begin req <= 1'b0; ci <= 2'd0; st <= S_CONV; end
                else st <= S_DARK;
            end
            // ---- 10µs 単位へ (平均は 2^RUNS_LOG2 で割る) ----
            S_CONV: begin
                case (ci)
                    2'd0: d_num <= s_lag[RUNS_LOG2 +: 27] + UNIT / 2;
                    2'd1: d_num <= mn + UNIT / 2;
                    default: d_num <= mx + UNIT / 2;
                endcase
                d_start <= 1'b1; st <= S_CWAIT;
            end
            S_CWAIT: if (d_done) begin
                case (ci)
                    2'd0: avg_lag <= d_quo[26:0]; 2'd1: min_lag <= d_quo[26:0];
                    default: max_lag <= d_quo[26:0];
                endcase
                ci <= ci + 2'd1;
                if (ci == 2'd2) begin st <= S_IDLE; active <= 1'b0; status <= 4'd3; end
                else st <= S_CONV;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
