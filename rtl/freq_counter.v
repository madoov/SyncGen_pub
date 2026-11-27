// =============================================================
// 周波数カウンタ (Si5351A などの外部クロックを 50MHz 基準で測定)
//
//   方式: 測定クロック側でグレイコードのカウンタを回し続け、
//         基準クロック側で同期化して読み、ゲート時間ごとの差分を取る
//         → 測定クロックが基準より速くても (68MHz でも) 正しく測れる
//
//   freq_hz = (ゲート時間内のカウント数) * SCALE
//     GATE_CYCLES = 50_000_000, SCALE = 1   → 1秒ゲート,  1Hz単位
//     GATE_CYCLES =  5_000_000, SCALE = 10  → 0.1秒ゲート, 10Hz単位
//   精度は基準の50MHz発振器の精度(例 ±50ppm)で決まる
//
//   meas_clk は CLKn ピン(グローバルクロック)から入れること
// =============================================================
module freq_counter #(
    parameter integer GATE_CYCLES = 50_000_000,
    parameter integer SCALE       = 1,
    parameter integer W           = 28          // カウンタ幅 (ゲート内の最大カウント < 2^W)
)(
    input  wire          clk,        // 基準 50MHz
    input  wire          rst,        // clk 同期リセット
    input  wire          meas_clk,   // 測定するクロック
    output reg  [26:0]   freq_hz,    // 測定結果 [Hz]
    output reg           valid,      // 結果を更新したとき1クロックのパルス
    output reg           no_signal   // 1ゲートの間クロックが来なかった
);
    // ---------------- 測定クロック側 ----------------
    reg [W-1:0] bin_x = {W{1'b0}};
    reg [W-1:0] gray_x = {W{1'b0}};
    always @(posedge meas_clk) begin
        bin_x  <= bin_x + 1'b1;
        gray_x <= (bin_x >> 1) ^ bin_x;   // 1ビットずつしか変化しない
    end

    // ---------------- 基準クロック側 ----------------
    (* async_reg = "true" *) reg [W-1:0] gray_s1, gray_s2;
    always @(posedge clk) begin
        gray_s1 <= gray_x;
        gray_s2 <= gray_s1;
    end

    // グレイコード → 2進数
    function [W-1:0] g2b(input [W-1:0] g);
        integer k;
        begin
            g2b[W-1] = g[W-1];
            for (k = W-2; k >= 0; k = k - 1)
                g2b[k] = g2b[k+1] ^ g[k];
        end
    endfunction

    reg  [W-1:0] now_b, prev_b;
    reg  [31:0]  gate;
    reg          first;                     // リセット後最初のゲートは捨てる
    wire [W-1:0] diff = now_b - prev_b;     // 周回しても差分は正しい

    always @(posedge clk) begin
        valid <= 1'b0;
        now_b <= g2b(gray_s2);
        if (rst) begin
            gate      <= 32'd0;
            first     <= 1'b1;
            prev_b    <= {W{1'b0}};
            freq_hz   <= 27'd0;
            no_signal <= 1'b1;
        end else if (gate == GATE_CYCLES - 1) begin
            gate      <= 32'd0;
            prev_b    <= now_b;
            first     <= 1'b0;
            if (!first) begin
                freq_hz   <= diff * SCALE;
                no_signal <= (diff == {W{1'b0}});
                valid     <= 1'b1;
            end
        end else begin
            gate <= gate + 32'd1;
        end
    end
endmodule
