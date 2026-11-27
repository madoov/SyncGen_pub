// =============================================================
// 水平・垂直周波数の測定 (基準 50MHz 側で動作)
//   hfreq_hz   : 1秒間のライン数 → [Hz]  (GATE/SCALE で短縮可)
//   vfreq_x100 : 2 フィールド (frame_tgl の 2 回分) の周期を数えて 0.01Hz 単位で算出 (例 5994 = 59.94Hz)
//                (2026-10-26 修正: インターレースは 263 / 262 ラインのフィールドが交互なので、
//                 1 回ずつ測ると 60.05 / 59.82Hz と交互に揺れていた。プログレッシブは 2 フレームの平均になる)
//   line_tgl / frame_tgl は vga_timing から (ドットクロック側の信号)
// =============================================================
module sync_meas #(
    parameter integer SHARED = 0,       // 1: 割り算器をトップで共有 (2026-11-14)
    parameter integer CLK_HZ = 50_000_000,
    parameter integer GATE   = 50_000_000,    // 水平の測定時間 (1秒)
    parameter integer SCALE  = 1
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        line_tgl,
    input  wire        frame_tgl,
    output reg  [26:0] hfreq_hz,
    output reg  [26:0] vfreq_x100,
    // 割り算器の共有 (2026-11-14、容量削減): SHARED = 1 ならトップの udiv_share を使う (0 なら自前の udiv。単体のテスト用)
    output wire        sd_start,
    output wire [46:0] sd_num,
    output wire [29:0] sd_den,
    input  wire [46:0] sd_quo,
    input  wire [29:0] sd_rem,
    input  wire        sd_done
);
    (* async_reg = "true" *) reg [2:0] ls, fs;
    always @(posedge clk) begin ls <= {ls[1:0], line_tgl}; fs <= {fs[1:0], frame_tgl}; end
    wire l_ev = ls[2] ^ ls[1];
    wire f_ev = fs[2] ^ fs[1];

    // ---- 水平: ゲート時間内のライン数 ----
    reg [31:0] g;
    reg [26:0] lc;
    always @(posedge clk) begin
        if (rst) begin g <= 0; lc <= 0; hfreq_hz <= 0; end
        else if (g == GATE - 1) begin
            g <= 0;
            hfreq_hz <= (lc + l_ev) * SCALE;
            lc <= 0;
        end else begin
            g  <= g + 1;
            lc <= lc + l_ev;
        end
    end

    // ---- 垂直: 2 回分の周期 → 周波数 (CLK_HZ*200 / 周期) ----
    localparam [33:0] NUMV = CLK_HZ * 64'd200;
    reg  [27:0] pc;
    reg  [26:0] per;
    reg         dv_start;
    wire [46:0] dv_quo;
    wire [29:0] dv_rem;
    wire        dv_done;
    generate if (SHARED) begin : g_sd
        assign dv_quo = sd_quo; assign dv_rem = sd_rem; assign dv_done = sd_done;
    end else begin : g_sd_l
        udiv #(.NW(47), .DW(30)) u_div (
            .clk(clk), .start(dv_start), .num({13'd0, NUMV}), .den({3'd0, per}),
            .quo(dv_quo), .rem(dv_rem), .done(dv_done)
        );
    end endgenerate
    assign sd_start = dv_start; assign sd_num = {13'd0, NUMV}; assign sd_den = {3'd0, per};
    reg first, ph;              // ph: 2 回のうちの何回目か
    always @(posedge clk) begin
        dv_start <= 1'b0;
        if (rst) begin
            pc <= 0; per <= 27'd1; first <= 1'b1; ph <= 1'b0; vfreq_x100 <= 0;
        end else begin
            if (f_ev && (first || ph)) begin       // 区切り (最初の 1 回と、そのあと 2 回ごと)
                pc <= 28'd1; ph <= 1'b0;
                if (!first) begin per <= pc[26:0]; dv_start <= 1'b1; end
                first <= 1'b0;
            end else if (f_ev) begin               // 1 回目: そのまま数え続ける
                pc <= pc + 28'd1; ph <= 1'b1;
            end else if (pc[27]) begin             // 約2.7秒 2 フィールドが来ない → 0表示
                vfreq_x100 <= 0;
                first <= 1'b1; ph <= 1'b0; pc <= 0;
            end else
                pc <= pc + 28'd1;
            if (dv_done) vfreq_x100 <= dv_quo[26:0];
        end
    end
endmodule
