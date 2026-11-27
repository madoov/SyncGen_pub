// =============================================================
// 押しボタン入力 (4個、押すと Low になる配線を想定)
//   btn_n[0] SEL  : 短く押して離す → sel_next (決定) / 長押し → sel_prev を 1 回 (値を変える状態から出て、APPLY へ移って確定)
//   btn_n[1] UP   : 上の項目へ / 値を増やす (長押しで連続)
//   btn_n[2] DOWN : 下の項目へ / 値を減らす (長押しで連続)
//   UP + DOWN 同時押し → osd (VGA 出力へのメニュー表示の ON/OFF) を 1 回
//                   UP / DOWN は押してから CHORD (50ms) 待ってから効く (それより早く離したら離した時)。
//                   その間にもう片方が押されたら同時押しとして扱い、値は変えない
//   btn_n[3] STEP : 短く押す → 増減の幅を切り替え (x1 → x10 → x100 → x1000)
//                   長押し   → 変更を確定 (APPLY)
//   チャタリング除去: 1ms ごとに見て DEB 回同じなら確定
// =============================================================
module buttons #(
    parameter integer TICK_CYCLES = 50_000,   // 1ms (50MHz)
    parameter integer DEB  = 16,              // 16ms
    parameter integer LONG = 500,             // 長押し判定 500ms
    parameter integer REP  = 80,              // 連続入力の間隔 80ms
    parameter integer CHORD = 50              // UP+DOWN 同時押しとみなす時間 50ms
)(
    input  wire       clk,
    input  wire       rst,
    input  wire [3:0] btn_n,
    output reg        sel_next,
    output reg        sel_prev,
    output reg        up,
    output reg        dn,
    output reg        step,
    output reg        apply,
    output reg        osd             // UP+DOWN 同時押し
);
    // 1ms ティック
    reg [31:0] tc;
    reg        tick;
    always @(posedge clk) begin
        tick <= 1'b0;
        if (rst || tc == TICK_CYCLES - 1) begin tc <= 0; tick <= ~rst; end
        else tc <= tc + 1;
    end

    // 同期化
    (* async_reg = "true" *) reg [3:0] s1, s2;
    always @(posedge clk) begin s1 <= btn_n; s2 <= s1; end

    // チャタリング除去
    reg [3:0] st;              // 確定した状態 (1=押されている)
    reg [7:0] dc [0:3];
    integer i;
    always @(posedge clk) begin
        if (rst) begin
            st <= 4'd0;
            for (i = 0; i < 4; i = i + 1) dc[i] <= 8'd0;
        end else if (tick) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (~s2[i] != st[i]) begin
                    if (dc[i] == DEB - 1) begin st[i] <= ~s2[i]; dc[i] <= 8'd0; end
                    else dc[i] <= dc[i] + 8'd1;
                end else
                    dc[i] <= 8'd0;
            end
        end
    end

    reg [3:0]  st_d;
    reg [15:0] hold [0:3];
    reg [7:0]  rc   [0:3];
    reg [2:1]  fired;          // UP / DOWN: この押下で 1 回目を出した
    reg        combo;          // UP+DOWN 同時押し中 (両方離すまで)
    always @(posedge clk) begin
        sel_next <= 1'b0; sel_prev <= 1'b0; up <= 1'b0; dn <= 1'b0; step <= 1'b0; apply <= 1'b0; osd <= 1'b0;
        st_d <= st;
        if (rst) begin
            st_d <= 4'd0;
            fired <= 2'b00; combo <= 1'b0;
            for (i = 0; i < 4; i = i + 1) begin hold[i] <= 16'd0; rc[i] <= 8'd0; end
        end else begin
            // UP+DOWN 同時押し: 両方そろった時に 1 回。両方離すまで UP/DOWN は出さない
            if (st[1] & st[2] & ~combo) begin combo <= 1'b1; osd <= 1'b1; end
            else if (~st[1] & ~st[2])   combo <= 1'b0;
            // UP / DOWN の 1 回目: CHORD 押し続けた時、またはそれより前に離した時
            if (~st[1]) fired[1] <= 1'b0;
            if (~st[2]) fired[2] <= 1'b0;
            if (!combo && !(st[1] & st[2])) begin
                if (!fired[1] && ((tick && st[1] && hold[1] == CHORD - 1) || (~st[1] & st_d[1]))) begin
                    up <= 1'b1; if (st[1]) fired[1] <= 1'b1;
                end
                if (!fired[2] && ((tick && st[2] && hold[2] == CHORD - 1) || (~st[2] & st_d[2]))) begin
                    dn <= 1'b1; if (st[2]) fired[2] <= 1'b1;
                end
            end
            // SEL は離した時に「次へ」(長押しでなければ)
            if (~st[0] & st_d[0] && hold[0] < LONG) sel_next <= 1'b1;
            // STEP も離した時に「幅の切り替え」(長押しでなければ)
            if (~st[3] & st_d[3] && hold[3] < LONG) step <= 1'b1;

            if (tick) begin
                for (i = 0; i < 4; i = i + 1) begin
                    if (!st[i]) begin
                        hold[i] <= 16'd0;
                        rc[i]   <= 8'd0;
                    end else begin
                        if (hold[i] < LONG) hold[i] <= hold[i] + 16'd1;
                        // 長押し: LONG に達したら1回、その後 REP ごとに1回
                        if (i == 3) begin
                            if (hold[i] == LONG - 1) apply <= 1'b1;   // STEP 長押しは1回だけ
                        end else if (i == 0) begin
                            if (hold[i] == LONG - 1) sel_prev <= 1'b1; // SEL 長押しも1回だけ (確定するため、2026-11-05)
                        end else if (!combo &&
                                     (hold[i] == LONG - 1 || (hold[i] == LONG && rc[i] == REP - 1))) begin
                            rc[i] <= 8'd0;
                            if (i == 1) up       <= 1'b1;
                            if (i == 2) dn       <= 1'b1;
                        end else if (hold[i] == LONG)
                            rc[i] <= rc[i] + 8'd1;
                    end
                end
            end
        end
    end
endmodule
