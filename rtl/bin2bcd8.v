// =============================================================
// 2進数 → 10進8桁(BCD) 変換  (逐次 double dabble, 27クロック)
//   入力は最大 99,999,999 まで
// =============================================================
module bin2bcd8 (
    input  wire        clk,
    input  wire        start,
    input  wire [26:0] bin,
    output reg  [31:0] bcd,      // 8桁, bcd[31:28] が最上位
    output reg         done
);
    reg [26:0] sh;
    reg [31:0] acc;
    reg [4:0]  n;
    reg        run = 1'b0;

    // 各桁 5以上なら +3
    function [31:0] adj(input [31:0] v);
        integer k;
        begin
            for (k = 0; k < 8; k = k + 1)
                adj[k*4 +: 4] = (v[k*4 +: 4] >= 4'd5) ? v[k*4 +: 4] + 4'd3 : v[k*4 +: 4];
        end
    endfunction

    wire [31:0] a = adj(acc);

    always @(posedge clk) begin
        done <= 1'b0;
        if (start) begin
            sh  <= bin;
            acc <= 32'd0;
            n   <= 5'd0;
            run <= 1'b1;
        end else if (run) begin
            acc <= {a[30:0], sh[26]};
            sh  <= {sh[25:0], 1'b0};
            if (n == 5'd26) begin
                run  <= 1'b0;
                done <= 1'b1;
                bcd  <= {a[30:0], sh[26]};
            end
            n <= n + 5'd1;
        end
    end
endmodule



// =============================================================
// bin2bcd8 を 2 つの使い手 (menu_display と osd_text、どちらも 50MHz 側) で共有する (2026-11-13、容量削減)
//   使い手は start を 1 クロック出し、done が来るまで bin を変えない (どちらもそうなっている)。
//   変換中に来た start は覚えておき、終わったら順に変換する。bcd は共通で、done は頼んだ側にだけ返す
// =============================================================
module bcd_share (
    input  wire        clk,
    input  wire        a_start,
    input  wire [26:0] a_bin,
    output wire        a_done,
    input  wire        b_start,
    input  wire [26:0] b_bin,
    output wire        b_done,
    output wire [31:0] bcd
);
    reg        pa = 1'b0, pb = 1'b0;   // 待っている頼み
    reg        busy = 1'b0, own = 1'b0;   // 変換中 / いまの使い手 (0 = a、1 = b)
    reg        s_start = 1'b0;
    wire       s_done;
    wire       ga = !busy && pa;            // a に渡す
    wire       gb = !busy && !pa && pb;     // b に渡す (a が先)
    always @(posedge clk) begin
        pa <= (pa && !ga) || a_start;
        pb <= (pb && !gb) || b_start;
        s_start <= ga || gb;
        if (ga || gb) begin busy <= 1'b1; own <= gb; end
        else if (s_done) busy <= 1'b0;
    end
    bin2bcd8 u_cv (.clk(clk), .start(s_start), .bin(own ? b_bin : a_bin), .bcd(bcd), .done(s_done));
    assign a_done = s_done && !own;
    assign b_done = s_done && own;
endmodule
