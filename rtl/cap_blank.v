// =============================================================
// ブランクの測定 (BLANK MEAS、2026-11-06、docs/capture_plan.md の 11 章)
//   START から END までの全フィールドで、黒以外が出た範囲をヒストグラムに数え、
//   「K 回以上出た一番外側」を表示の端とする (ひげ・ノイズは K 回に届かないので捨てられる)。
//   動く絵 (ゲームの画面など) でも、時間をかけるほど本当の表示の端に近づく。
//
//   ヒストグラム (FPGA のメモリ):
//     mem_l : ラインの黒以外の最初の位置 (立ち上がり) ごとの回数。8192 語 × 16 ビット (1 サンプルごと、82µs まで。
//             それより後は最後の番地に入れる)。回数は 65535 で止める
//     mem_r : ラインの最後に黒に戻った位置ごとの回数 (mem_l と同じ形)
//     mem_v : 黒以外があったフィールドの数。2048 語 × 16 ビット、番地 = {フィールドの種類 (fd_par), ライン 10 ビット}
//             (V の同期の始まりのラインが 0。1024 ライン以上は最後の番地に入れる)
//     (2026-11-07: 4 サンプルごとの番地 + 番地の中の 4 つの回数 (半分にする仕組みつき) から、1 サンプルごとの番地に変えた。
//      メモリは 36 → 72 ブロックに増えるが、更新の回路が簡単になり LE が減る)
//   結果 (サンプル・ライン):
//     b_left  = 回数が K 以上の位置のうち最小、b_ln0 / b_ln1 = b_left / b_left + 1 の位置の回数
//     b_right = 回数が K 以上の位置のうち最大、b_rn0 / b_rn1 = b_right − 1 / b_right の位置の回数
//       端の位置はサンプルの位相で隣り合う 2 つの位置に分かれ、その比が本当の端の端数になる (平均 = 本当の位置)。
//       本当の左端 = b_left + b_ln1 / (b_ln0 + b_ln1)、右端 = b_right − b_rn0 / (b_rn0 + b_rn1)
//     b_top0 / b_bot0 = fd_par = 0 のフィールドで、回数が K 以上の最初 / 最後のライン (b_top1 / b_bot1 は fd_par = 1)
//   測定中も 16 フィールドごとに数え直して結果を出す (END を押す前に値が落ち着くのを見られる)。
//   数え直し (8192 クロック = 164µs) はフィールドの区切り (垂直同期の始まり) の直後にする (その間のラインは数えない。
//   垂直同期・BP のラインなので表示のあるラインは落とさない)。
//
//   状態 b_stat: 0 止まっている / 1 測定中 (結果は途中の値) / 2 終わり (END のあとの結果) / 3 エラー
//     エラー: 測定中にフィールドのライン数が START のあとの 2 フィールドと違った (入力の画面モードが変わった)、
//             測定が無効になった (fd_ok = 0)、フィールドが 84ms 来ない、
//             位置が測れる範囲を超えた (横 HMAX サンプル = 82µs 以降・縦 VMAX ライン以降。2026-11-09、b_range = 1)
//   回数の飽和 (2026-11-09): どれかの番地の回数が CMAX に届いたら、それ以上数えずに自動で終わる (b_stat = 2、b_sat = 1)。
//     端の端数は隣の番地との回数の比で出すので、片方だけが頭打ちになると比が狂うため (480 ライン・60Hz なら約 2.3 秒で届きうる)
//   start_tgl / stop_tgl は別のクロックからでもよい (反転で 1 回。中で同期化)。
//   結果は res_tgl / res_ack (トグル + 変わらない値)。受け取る側が読み終わるまで、数え直しを始めず b_* を変えない
//   (b_left などは数え直しのレジスタをそのまま出す)
// =============================================================
module cap_blank #(
    parameter integer K_MIN    = 4,     // 端とみなす最小の回数 (ライン数 / フィールド数)
    parameter integer LIVE_LOG2 = 4,    // 測定中、2^LIVE_LOG2 フィールドごとに数え直す
    parameter integer TO_LOG2  = 22,    // フィールドが 2^TO_LOG2 クロック来なければエラー (84ms)
    parameter [15:0]  CMAX     = 16'hFFFF,  // 回数の上限 (届いたら自動で終わる。テストでは小さくする)
    parameter [15:0]  HMAX     = 16'd8191,  // 横の位置の上限 [サンプル] (超えたらエラー)
    parameter [11:0]  VMAX     = 12'd1023   // 縦の位置の上限 [ライン] (超えたらエラー)
)(
    input  wire        clk,             // cap_clk
    input  wire        rst,
    input  wire        start_tgl,
    input  wire        stop_tgl,
    // cap_meas から
    input  wire        ln_v,
    input  wire [11:0] ln_no,
    input  wire [15:0] ln_rise, ln_fall,
    input  wire        ln_hasr, ln_any,
    input  wire        fd_v,
    input  wire        fd_par,
    input  wire [11:0] fd_cnt,
    input  wire        fd_ok,
    // 結果
    output reg         res_tgl,
    input  wire        res_ack,         // 別のクロックからでもよい
    output reg  [1:0]  b_stat,
    output reg  [15:0] b_nfield,        // 数えたフィールドの数
    output wire [15:0] b_left, b_right,
    output wire [15:0] b_ln0, b_ln1, b_rn0, b_rn1,
    output wire [11:0] b_top0, b_bot0, b_top1, b_bot1,
    output wire [3:0]  b_found,         // bit0 左右、bit1 上下 (fd_par = 0)、bit2 上下 (fd_par = 1) が見つかった
    output reg         b_sat,           // 回数が CMAX に届いて自動で終わった
    output reg         b_range          // 位置が測れる範囲を超えてエラーになった
);
    (* async_reg = "true" *) reg [2:0] st_s, sp_s;
    (* async_reg = "true" *) reg [1:0] ak;
    always @(posedge clk) begin st_s <= {st_s[1:0], start_tgl}; sp_s <= {sp_s[1:0], stop_tgl}; ak <= {ak[0], res_ack}; end
    wire start_ev = st_s[2] ^ st_s[1];
    wire stop_ev  = sp_s[2] ^ sp_s[1];
    wire rd_ok    = (ak[1] == res_tgl);

    localparam [2:0] S_IDLE = 3'd0, S_CLEAR = 3'd1, S_SYNC = 3'd2, S_RUN = 3'd3, S_SCAN = 3'd4, S_DONE = 3'd5, S_ERR = 3'd6;
    reg  [2:0]  st;
    reg  [1:0]  up;            // ラインの記録の読み書き: 0 なし / 1 読み出し待ち / 2 書き込み
    reg         u_l, u_r;

    // ---------- メモリ (1 ポート、読み出しは 1 クロック遅れ。書き込みの値は読んだ値 + 1、消すときは 0) ----------
    reg  [15:0] mem_l [0:8191];
    reg  [15:0] mem_r [0:8191];
    reg  [15:0] mem_v [0:2047];
    reg  [12:0] a_l, a_r;
    reg  [10:0] a_v;
    reg         we_l, we_r, we_v;
    reg  [15:0] q_l, q_r, q_v;
    wire        clr = (st == S_CLEAR);
    wire [15:0] w_l = clr ? 16'd0 : (q_l >= CMAX) ? q_l : q_l + 16'd1;
    wire [15:0] w_r = clr ? 16'd0 : (q_r >= CMAX) ? q_r : q_r + 16'd1;
    wire [15:0] w_v = clr ? 16'd0 : (q_v >= CMAX) ? q_v : q_v + 16'd1;
    reg         full;              // 回数が CMAX に届いた (それ以上数えない)
    wire        sat_hit = (u_l && (q_l >= CMAX - 16'd1)) || (u_r && (q_r >= CMAX - 16'd1)) || (q_v >= CMAX - 16'd1);
    always @(posedge clk) begin
        if (we_l) mem_l[a_l] <= w_l;
        q_l <= mem_l[a_l];
    end
    always @(posedge clk) begin
        if (we_r) mem_r[a_r] <= w_r;
        q_r <= mem_r[a_r];
    end
    always @(posedge clk) begin
        if (we_v) mem_v[a_v] <= w_v;
        q_v <= mem_v[a_v];
    end

    // ---------- 状態 ----------
    reg  [13:0] ci;            // 消す・数え直すときの番地 (14 ビット目は終わりの印)
    reg  [1:0]  nsync;
    reg  [11:0] vt_a, vt_b;    // START のあとの 2 フィールドのライン数
    reg  [15:0] nfield;
    reg  [TO_LOG2:0] tcnt;
    reg         fin, fin_req, live_req;
    wire        live = (nfield[LIVE_LOG2-1:0] == {LIVE_LOG2{1'b0}});
    wire        f_bad = fd_v && (!fd_ok || ((fd_cnt != vt_a) && (fd_cnt != vt_b)));   // S_RUN: このフィールドはエラー
    // 数え直し: 番地を出した 2 クロック後に読み出しが来る
    reg  [12:0] sa;
    reg         iss, sv;
    reg         pend;
    reg  [1:0]  stat_n;
    reg         fd_par_r;
    reg         f_l, f_r, f_t0, f_t1, f_b0, f_b1, l_nx;
    reg  [12:0] r_lpos, r_rpos;
    reg  [15:0] r_ln0, r_ln1, r_rn0, r_rn1, prv_r;
    reg  [11:0] r_t0, r_b0, r_t1, r_b1;
    wire        k_l = (q_l >= K_MIN);
    wire        k_r = (q_r >= K_MIN);
    wire        k_v = (q_v >= K_MIN) && !sa[12] && !sa[11];   // mem_v は 2048 語 (sa の 0〜2047 だけ見る)
    wire [11:0] ln_c = (ln_no > 12'd1023) ? 12'd1023 : ln_no;
    // 測れる範囲を超えた (横: 立ち上がり / 黒に戻った位置が HMAX より後、縦: ライン番号が VMAX より後)
    wire        rng = ln_v && ln_any && (((ln_rise > HMAX) && ln_hasr) || (ln_fall > HMAX) || (ln_no > VMAX));
    assign b_left = {3'd0, r_lpos}; assign b_right = {3'd0, r_rpos};
    assign b_ln0 = r_ln0; assign b_ln1 = r_ln1; assign b_rn0 = r_rn0; assign b_rn1 = r_rn1;
    assign b_top0 = r_t0; assign b_bot0 = r_b0; assign b_top1 = r_t1; assign b_bot1 = r_b1;
    assign b_found = {1'b0, f_t1 && f_b1, f_t0 && f_b0, f_l && f_r};

    always @(posedge clk) begin
        we_l <= 1'b0; we_r <= 1'b0; we_v <= 1'b0;
        iss  <= 1'b0;
        sa   <= a_l;
        sv   <= iss;
        if (fd_v) fd_par_r <= fd_par;
        if (rst) begin
            st <= S_IDLE; b_stat <= 2'd0; res_tgl <= 1'b0; up <= 2'd0; sv <= 1'b0; pend <= 1'b0; stat_n <= 2'd0;
            b_nfield <= 16'd0; nfield <= 16'd0; l_nx <= 1'b0; fin_req <= 1'b0; live_req <= 1'b0;
            full <= 1'b0; b_sat <= 1'b0; b_range <= 1'b0;
            f_l <= 1'b0; f_r <= 1'b0; f_t0 <= 1'b0; f_t1 <= 1'b0; f_b0 <= 1'b0; f_b1 <= 1'b0;
        end else begin
            // 受け取る側が読み終わっていれば、結果と状態を渡す (数え直しの途中は渡さない)
            if (pend && rd_ok && (st != S_SCAN)) begin
                pend <= 1'b0; res_tgl <= ~res_tgl; b_stat <= stat_n; b_nfield <= nfield;
            end
            // 数え直しで読んだ値を見る
            if (sv) begin
                l_nx <= 1'b0;
                if (l_nx) r_ln1 <= q_l;                                         // 左端の次の位置の回数
                if (k_l && !f_l) begin r_lpos <= sa; r_ln0 <= q_l; r_ln1 <= 16'd0; l_nx <= 1'b1; f_l <= 1'b1; end
                if (k_r) begin r_rpos <= sa; r_rn1 <= q_r; r_rn0 <= prv_r; f_r <= 1'b1; end   // 右端は最後に見つかったもの
                prv_r <= q_r;
                if (k_v && !sa[10]) begin if (!f_t0) r_t0 <= {2'd0, sa[9:0]}; f_t0 <= 1'b1; r_b0 <= {2'd0, sa[9:0]}; f_b0 <= 1'b1; end
                if (k_v &&  sa[10]) begin if (!f_t1) r_t1 <= {2'd0, sa[9:0]}; f_t1 <= 1'b1; r_b1 <= {2'd0, sa[9:0]}; f_b1 <= 1'b1; end
            end
            if (!tcnt[TO_LOG2]) tcnt <= tcnt + 1'b1;
            case (st)
            S_IDLE, S_DONE, S_ERR: begin
                if (start_ev) begin
                    st <= S_CLEAR; ci <= 14'd0; stat_n <= 2'd1; pend <= 1'b1; nfield <= 16'd0; fin_req <= 1'b0; live_req <= 1'b0;
                    full <= 1'b0; b_sat <= 1'b0; b_range <= 1'b0;
                end
            end
            S_CLEAR: begin                                  // 3 つのメモリを 0 に (8192 クロック)
                a_l <= ci[12:0]; a_r <= ci[12:0]; a_v <= ci[10:0];
                we_l <= 1'b1; we_r <= 1'b1; we_v <= 1'b1;
                ci <= ci + 14'd1;
                if (ci == 14'd8191) begin st <= S_SYNC; nsync <= 2'd0; nfield <= 16'd0; tcnt <= 0; up <= 2'd0; end
            end
            S_SYNC: begin                                   // 2 フィールドのライン数を覚える (数えるのはそのあとから)
                if (fd_v) begin
                    tcnt <= 0;
                    if (!fd_ok) nsync <= 2'd0;
                    else begin
                        nsync <= nsync + 2'd1;
                        if (nsync == 2'd0) vt_a <= fd_cnt;
                        if (nsync == 2'd1) begin vt_b <= fd_cnt; st <= S_RUN; end
                    end
                end
                if (stop_ev) begin st <= S_IDLE; stat_n <= 2'd0; pend <= 1'b1; end
                if (tcnt[TO_LOG2]) begin st <= S_ERR; stat_n <= 2'd3; pend <= 1'b1; end
            end
            S_RUN: begin
                // ラインの記録 → 3 つのメモリを読んで 1 足して書く
                case (up)
                2'd0: if (ln_v && ln_any && !full) begin
                    a_l <= (ln_rise[15:13] != 3'd0) ? 13'd8191 : ln_rise[12:0];
                    a_r <= (ln_fall[15:13] != 3'd0) ? 13'd8191 : ln_fall[12:0];
                    a_v <= {fd_par_r, ln_c[9:0]};
                    u_l <= ln_hasr; u_r <= (ln_fall != 16'd0);
                    up <= 2'd1;
                end
                2'd1: up <= 2'd2;                           // 読み出し待ち
                default: begin
                    we_l <= u_l; we_r <= u_r; we_v <= 1'b1;
                    up <= 2'd0;
                    if (sat_hit) begin full <= 1'b1; b_sat <= 1'b1; fin_req <= 1'b1; end   // 届いたら終わる
                end
                endcase
                // エラー (入力が変わった・測定が無効・フィールドが来ない) を最優先に (2026-11-07 修正:
                //   以前は同じクロックの数え直しが S_SCAN で上書きし、エラーにならずに RUN へ戻ることがあった)
                if (f_bad || tcnt[TO_LOG2] || rng) begin st <= S_ERR; stat_n <= 2'd3; pend <= 1'b1; if (rng) b_range <= 1'b1; end
                else begin
                    // フィールドの区切り
                    if (fd_v) begin
                        tcnt <= 0;
                        nfield <= nfield + 16'd1;
                        if (live) live_req <= 1'b1;
                    end
                    if (stop_ev) fin_req <= 1'b1;
                    // 数え直し (前の結果が読み終わってから。途中の結果はフィールドの区切りの直後だけ)
                    if (rd_ok && !pend && (fin_req || stop_ev || (live_req && fd_v))) begin
                        st <= S_SCAN; ci <= 14'd0; fin <= fin_req || stop_ev; up <= 2'd0; live_req <= 1'b0;
                    end
                end
            end
            S_SCAN: begin                                   // 全番地を読んで、K 回以上の一番外側を探す
                if (ci == 14'd0) begin
                    f_l <= 1'b0; f_r <= 1'b0; f_t0 <= 1'b0; f_t1 <= 1'b0; f_b0 <= 1'b0; f_b1 <= 1'b0; prv_r <= 16'd0;
                end
                if (!ci[13]) begin a_l <= ci[12:0]; a_r <= ci[12:0]; a_v <= ci[10:0]; iss <= 1'b1; end
                ci <= ci + 14'd1;
                // 数え直しの間は数えないので、途中で END が来てもこの結果が最後の結果になる
                if (ci == 14'd8194) begin                   // 最後の番地の読み出しまで見終わった
                    pend <= 1'b1; fin_req <= 1'b0;
                    if (fin || stop_ev) begin stat_n <= 2'd2; st <= S_DONE; end
                    else begin stat_n <= 2'd1; st <= S_RUN; end
                end else if (stop_ev) fin <= 1'b1;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
