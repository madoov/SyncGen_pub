// =============================================================
// 符号なし割り算 (逐次, NW クロック)
//   quo = num / den, rem = num % den
//   1 クロックあたり 引き算 1 回 (DW+2 bit) だけ。比較は引き算の借りで判定する
// =============================================================
module udiv #(
    parameter integer NW = 40,     // 被除数ビット幅
    parameter integer DW = 27      // 除数ビット幅
)(
    input  wire          clk,
    input  wire          start,
    input  wire [NW-1:0] num,
    input  wire [DW-1:0] den,
    output reg  [NW-1:0] quo,
    output reg  [DW-1:0] rem,
    output reg           done
);
    reg [NW-1:0] n;
    reg [DW:0]   r;
    reg [7:0]    k;
    reg          run = 1'b0;
    wire [DW:0]   r_sh = {r[DW-1:0], n[NW-1]};
    wire [DW+1:0] sub  = {1'b0, r_sh} - {2'b00, den};
    wire          ge   = !sub[DW+1];             // 借りなし = r_sh >= den

    always @(posedge clk) begin
        done <= 1'b0;
        if (start) begin
            n   <= num;
            r   <= {(DW+1){1'b0}};
            quo <= {NW{1'b0}};
            k   <= 8'd0;
            run <= 1'b1;
        end else if (run) begin
            r   <= ge ? sub[DW:0] : r_sh;
            quo <= {quo[NW-2:0], ge};
            n   <= {n[NW-2:0], 1'b0};
            if (k == NW - 1) begin
                run  <= 1'b0;
                done <= 1'b1;
                rem  <= ge ? sub[DW-1:0] : r_sh[DW-1:0];
            end
            k <= k + 8'd1;
        end
    end
endmodule

// =============================================================
// 割り算器の共有 (2026-11-14、容量削減): 50MHz 側の N 個の使い手が 1 つの udiv を順番に使う
//   使い手は今までどおり start を 1 クロック出し、done が来るまで num / den を変えずに待つ
//   (割り算を始めるのは順番が来たとき。そのときの num / den を取り込む)。quo / rem は全員に配り、
//   done[i] のクロックだけ有効。待ちが重なったら番号の小さい方が先
// =============================================================
module udiv_share #(
    parameter integer N  = 6,
    parameter integer NW = 47,
    parameter integer DW = 30
)(
    input  wire            clk,
    input  wire [N-1:0]    start,
    input  wire [N*NW-1:0] num,
    input  wire [N*DW-1:0] den,
    output wire [NW-1:0]   quo,
    output wire [DW-1:0]   rem,
    output reg  [N-1:0]    done = {N{1'b0}}
);
    reg [N-1:0] pend = {N{1'b0}};
    reg [N-1:0] own = {N{1'b0}};       // 今の使い手 (1 ビットだけ 1)
    reg         busy = 1'b0, go = 1'b0;
    // 番号のいちばん小さい待ち (1 ビットだけ 1)
    wire [N-1:0] pick = pend & ~(pend - {{(N-1){1'b0}}, 1'b1});
    // 選んだ使い手の num / den (AND-OR。可変の位置の切り出しは書かない)
    reg  [NW-1:0] mnum;
    reg  [DW-1:0] mden;
    integer i, j;
    always @* begin
        mnum = {NW{1'b0}}; mden = {DW{1'b0}};
        for (i = 0; i < N; i = i + 1) begin
            mnum = mnum | (num[i*NW +: NW] & {NW{own[i]}});
            mden = mden | (den[i*DW +: DW] & {DW{own[i]}});
        end
    end
    wire d_done;
    udiv #(.NW(NW), .DW(DW)) u_div (
        .clk(clk), .start(go), .num(mnum), .den(mden),
        .quo(quo), .rem(rem), .done(d_done)
    );
    wire take = !busy && (pend != {N{1'b0}});
    always @(posedge clk) begin
        go <= 1'b0; done <= {N{1'b0}};
        // 1 ビットずつ if で (使い手の start がリセット前に不定でも、シミュレーションで pend が不定のままにならない)
        for (j = 0; j < N; j = j + 1) begin
            if (take && pick[j]) pend[j] <= 1'b0;
            if (start[j])        pend[j] <= 1'b1;
        end
        if (take) begin own <= pick; go <= 1'b1; busy <= 1'b1; end
        if (d_done) begin busy <= 1'b0; done <= own; end
    end
endmodule
