// =============================================================
// コンパレータのしきい値の自動の合わせ込み (2026-11-07、キャプチャ。docs/capture_plan.md の 10.3 / 14 章)
//   クロックは cap_clk。しきい値は PWM (cap_pwm、基板の RC で平滑。時定数 約 0.77ms) で出す。
//   req_tgl (別のクロックからの反転) で始め、終わったら ok を決めてから done_tgl を反転する (トグル + 変わらない値)。
//
//   1. 同期 (sthr): HS (CSYNC) のコンパレータの出力を見て、2 分探索を 2 回
//        T_lo = 0 が出る最も低いしきい値 (信号の Low のすぐ上)
//        T_hi = 1 が出なくなる最も低いしきい値 (信号の High のすぐ上)
//      sthr = (T_lo + T_hi) / 2。T_hi − T_lo が SMIN より小さければ同期がない (ok = 0)
//      (VS も同じしきい値を使う。VS が来ないときは 0 のまま = CSYNC)
//   2. HS の極性: 決めたしきい値で落ち着くのを待ち、HS が 1 のサンプルと 0 のサンプルを数えて、少ない方を同期の側とする
//      (2026-11-07: cap_meas の極性を読んでいたが、しきい値を探している間に乱れた判定を読むことがあったのでやめた)
//   3. 映像の黒: 同期の中 (必ず黒) で VID が 1 にならない最も低いしきい値 T_b を 2 分探索で求める
//   4. 映像の白 (2026-11-20): どこでも VID が 1 にならない最も低いしきい値 T_w (= 一番明るいところのすぐ上) を 2 分探索で
//      (1 回の試しはフィールドの区切り fd (cap_meas の fd_v) を 3 回見るまで = 続いた 2 フィールドを丸ごと見る。明るいところが
//       インターレースの片方のフィールドにしかなくても見逃さない。前は 21ms の固定で、60Hz のインターレースの 1 フレーム 33ms に
//       届かなかった。区切りが来ないときは 2^FLD_TO_LOG2 クロック (84ms) で打ち切る)。上限でもまだ 1 なら T_w = 1024
//      vthr = (T_b + T_w) / 2 (黒と白の中間)。ただし T_b + VMARGIN より下にはしない (絵がない・暗いとき)
//      (前は vthr = T_b + VMARGIN (黒から約 25mV) だった。しきい値が黒に近いと、ケーブルの容量でなまった白 → 黒の端が
//       黒に戻りきるまで遅れて見え、絵の幅が長く測られる (実機の PC98 GDC で 0.6 ドット)。中間なら立ち上がり・立ち下がりの
//       遅れがそろう。暗い色だけの端は拾えなくなる (測るときは四辺まで白い絵を出す))
//      入力モードで終端あり (S3 = 75Ω) のとき、T_w = 1024 (上限 約 0.77V でもまだ黒以外) なら hi_lvl = 1
//      (75Ω の終端に TTL などの高い電圧が来ている。終端の抵抗や相手の出力に無理がかかる → S3 を TTL に。2026-11-08 から。
//       前は別の試しで見ていた)
//   見張り (2026-11-09、schematic_todo.md の AS 節): 入力モードで終端ありのとき、合わせ込みも測定もしていない間 (hold = 0) は
//      VID のしきい値を上限にしたまま VID を見張り、落ち着いたあと (2^SET_LOG2 クロック) 黒以外が出たら hi_lvl = 1。
//      トップは hi_lvl = 1 で終端を切る (term_off)。hi_lvl は入力モードを出るか S3 を TTL にする (term = 0) まで 1 のまま
//   入力モードから出力モードに戻ったら、しきい値を初期値に戻す (外の機器に合わせた同期のしきい値のままだと、自分の出力の
//   低いレベルの同期 (75Ω の終端で約 0.3V) を受けられず、ぶつかりの見張り (cap_clash) が誤って止めるため)
//   (2026-11-20 修正: 戻す処理が待機中 (T_IDLE) にしかなく、合わせ込みの途中で抜けると外の機器向けのしきい値が残っていた。
//    今は状態によらず優先して、探索をやめて初期値に戻す。途中だったら ok = 0 で done_tgl を返す。戻したあと PWM の RC が
//    落ち着くまで (2^SET_LOG2 クロック) busy を 1 のままにして、ぶつかりの見張りを止める)
//   1 回の試し: しきい値を変えて 2^SET_LOG2 クロック待ち (平滑の RC が落ち着く)、2^WIN_LOG2 クロック見る。
//   10 ビットの 2 分探索 × 4 = 40 回 + 極性 1 回で、実機の値では 約 0.6〜0.9 秒 (白の 10 回は 1 回 5ms + 2〜3 フィールド)
// =============================================================
module cap_thr #(
    parameter integer SET_LOG2 = 18,           // 落ち着くまでの待ち 2^18 クロック = 5.2ms (RC の約 7 倍)
    parameter integer WIN_LOG2 = 17,           // 見る時間 2^17 クロック = 2.6ms (15kHz で 40 ライン)
    parameter integer FLD_TO_LOG2 = 22,        // 白の試しの打ち切り 2^22 クロック = 84ms (フィールドの区切りが来ないとき)
    parameter [9:0]   SMIN     = 10'd16,       // 同期の Low と High の差の最小 (約 12mV)
    parameter [9:0]   VMARGIN  = 10'd32,       // VID のしきい値を黒から上げる分 (約 25mV)
    parameter [9:0]   S_INIT   = 10'd200,      // 合わせる前のしきい値 (約 0.15V)
    parameter [9:0]   V_INIT   = 10'd200
)(
    input  wire       clk,                     // cap_clk
    input  wire       rst,
    input  wire       req_tgl,                 // 別のクロックから
    input  wire       vid_hi, vid_lo,          // コンパレータの出力 (DDIO の 2 サンプル)
    input  wire       hs_hi,  hs_lo,
    input  wire       fd,                      // フィールドの区切り (cap_meas の fd_v、同じ cap_clk の 1 クロック)
    input  wire       inmode,                  // 入力モード (別のクロックから)
    input  wire       term,                    // 終端あり (S3 = 75Ω、別のクロックから)
    input  wire       hold,                    // 合わせ込み・測定中 (cap_ctrl が止まっていない。別のクロックから)。0 の間は見張る
    output wire       busy,                    // 合わせ込み中 (しきい値を動かしている。ぶつかりの見張りを止める)
    output reg        hi_lvl,                  // 4. と見張りの結果 (入力モードを出るか term = 0 で 0 に戻る)
    output reg  [9:0] sthr,
    output reg  [9:0] vthr,
    output reg        done_tgl,
    output reg        ok
);
    (* async_reg = "true" *) reg [2:0] rq;
    always @(posedge clk) rq <= {rq[1:0], req_tgl};
    wire req_ev = rq[2] ^ rq[1];
    (* async_reg = "true" *) reg [2:0] im;
    (* async_reg = "true" *) reg [1:0] tm, hd;
    always @(posedge clk) begin im <= {im[1:0], inmode}; tm <= {tm[0], term}; hd <= {hd[0], hold}; end
    wire im_fall = im[2] && !im[1];            // 入力モード → 出力モード
    wire imtm    = im[1] && tm[1];             // 入力モードで終端あり

    localparam [2:0] T_IDLE = 3'd0, T_SLO = 3'd1, T_SHI = 3'd2, T_POL = 3'd3, T_VID = 3'd4, T_VW = 3'd5;
    reg  [2:0]  st;
    reg  [10:0] lo, hi;                        // 2 分探索の範囲 [lo, hi] (hi = 1024 は「見つからない」)
    reg  [9:0]  t_lo;                          // T_lo (同期)、そのあと T_b (映像の黒)
    reg  [SET_LOG2:0] tc;                      // 落ち着くまでの待ち (最上位が 1 になったら見始める)
    reg  [FLD_TO_LOG2-1:0] tw;                 // 見ている時間 (2026-11-07: 待ちより長い設定でも数えられるよう分けた。白は打ち切りまで)
    reg  [1:0]  nf;                            // 白の試しで見たフィールドの区切りの数 (3 で終わり)
    reg  [WIN_LOG2+1:0] n1;                    // 極性: 見ている間の HS = 1 のサンプル数 (1 クロック 2 サンプル)
    reg         seen;                          // 見ている間に条件 (0 が出た / 1 が出た / 同期の中で VID = 1) があった
    reg         hneg;
    reg         stl;                           // 初期値に戻したあと RC が落ち着くのを待っている
    reg  [SET_LOG2:0] sc;
    assign busy = (st != T_IDLE) || stl;
    wire [10:0] mid  = (lo + hi) >> 1;
    wire        tst  = (st != T_IDLE);
    wire        look = tc[SET_LOG2];           // 落ち着いたあと、見ている
    // 白の探索の終わりに: vthr = max((T_b + T_w) / 2, T_b + VMARGIN)、上限 1023
    wire [10:0] t_w   = pred ? lo : hi;
    wire [11:0] v_sum = {2'b0, t_lo} + {1'b0, t_w};
    wire [10:0] v_lo  = {1'b0, t_lo} + {1'b0, VMARGIN};
    wire [10:0] v_h   = (v_sum[11:1] > v_lo) ? v_sum[11:1] : v_lo;
    wire [9:0]  v_mid = v_h[10] ? 10'd1023 : v_h[9:0];
    wire        wend = look && ((st == T_VW) ? (nf == 2'd3 || &tw) : (&tw[WIN_LOG2-1:0]));
    // 条件 (サンプルごと)
    wire        c_zero = !hs_hi || !hs_lo;
    wire        c_one  = hs_hi || hs_lo;
    wire        c_vid  = (vid_hi && (hs_hi ^ hneg)) || (vid_lo && (hs_lo ^ hneg));   // 同期の中で VID = 1
    wire        cond   = (st == T_SLO) ? c_zero : (st == T_SHI) ? c_one : (st == T_VW) ? (vid_hi || vid_lo) : c_vid;
    // 探す述語 (しきい値を上げると成り立つようになる): T_SLO = 0 が出た、T_SHI / T_VID / T_VW = 条件が出なかった
    wire        pred   = (st == T_SLO) ? seen : !seen;

    always @(posedge clk) begin
        if (rst) begin
            st <= T_IDLE; sthr <= S_INIT; vthr <= V_INIT; done_tgl <= 1'b0; ok <= 1'b0; tc <= 0; tw <= 0; nf <= 2'd0; seen <= 1'b0; hi_lvl <= 1'b0;
            stl <= 1'b0; sc <= 0;
        end else begin
            if (!imtm) hi_lvl <= 1'b0;             // 入力モードを出た・S3 を TTL にした
            if (tst) begin
                if (!look) tc <= tc + 1'b1; else tw <= tw + 1'b1;
                if (look && cond) seen <= 1'b1;
                if (look && fd && nf != 2'd3) nf <= nf + 2'd1;
                if (st == T_VID || st == T_VW) vthr <= mid[9:0]; else if (st == T_SLO || st == T_SHI) sthr <= mid[9:0];
            end
            case (st)
            T_IDLE: begin
                if (req_ev) begin lo <= 11'd0; hi <= 11'd1024; tc <= 0; tw <= 0; nf <= 2'd0; seen <= 1'b0; st <= T_SLO; end
                else if (imtm && !hd[1]) begin     // 見張り: しきい値を上限にして、落ち着いたら黒以外が出ないか見る
                    if (vthr != 10'd1023) begin vthr <= 10'd1023; tc <= 0; end
                    else if (!look) tc <= tc + 1'b1;
                    else if (vid_hi || vid_lo) hi_lvl <= 1'b1;
                end else tc <= 0;
            end
            T_SLO, T_SHI, T_VID, T_VW: if (wend) begin
                tc <= 0; tw <= 0; nf <= 2'd0; seen <= 1'b0;
                if (lo + 11'd1 >= hi) begin            // 決まった: 最後の試しで pred なら mid (= lo)、でなければ hi
                    if (st == T_SLO) begin
                        t_lo <= pred ? lo[9:0] : hi[9:0];
                        if (!pred && hi[10]) begin ok <= 1'b0; sthr <= S_INIT; done_tgl <= ~done_tgl; st <= T_IDLE; end   // 0 が出ない
                        else begin lo <= 11'd0; hi <= 11'd1024; st <= T_SHI; end
                    end else if (st == T_SHI) begin
                        // T_hi = pred ? lo : hi。差が小さければ同期がない
                        if ((pred ? lo : hi) < {1'b0, t_lo} + {1'b0, SMIN}) begin
                            ok <= 1'b0; sthr <= S_INIT; done_tgl <= ~done_tgl; st <= T_IDLE;
                        end else begin
                            sthr <= ({1'b0, t_lo} + (pred ? lo : hi)) >> 1; n1 <= 0; st <= T_POL;
                        end
                    end else if (st == T_VID) begin    // T_b を覚えて白を探す
                        t_lo <= (pred ? lo[9:0] : hi[9:0]);
                        lo <= 11'd0; hi <= 11'd1024; st <= T_VW;
                    end else begin                     // T_w = pred ? lo : hi (1024 は上限でもまだ黒以外)
                        vthr <= v_mid;
                        if (imtm && !pred && hi[10]) hi_lvl <= 1'b1;
                        ok <= 1'b1; done_tgl <= ~done_tgl; st <= T_IDLE;
                    end
                end else if (pred) hi <= mid; else lo <= mid + 11'd1;
            end
            T_POL: begin                               // 決めたしきい値で落ち着いたら、HS = 1 のサンプルを数える
                if (look) n1 <= n1 + hs_hi + hs_lo;
                if (wend) begin
                    hneg <= n1[WIN_LOG2+1] | n1[WIN_LOG2];  // 1 が半分 (2^WIN_LOG2 サンプル) より多い → 同期は 0 の側 (負極性)
                    lo <= 11'd0; hi <= 11'd1024; tc <= 0; tw <= 0; nf <= 2'd0; seen <= 1'b0; st <= T_VID;
                end
            end
            default: st <= T_IDLE;
            endcase
            // RC が落ち着くまでの待ち
            if (stl) begin if (sc[SET_LOG2]) stl <= 1'b0; else sc <= sc + 1'b1; end
            // 入力モード → 出力モード: 状態によらず優先して、探索をやめて初期値に戻す (上の case の書き込みより後に書いて勝たせる)
            if (im_fall) begin
                st <= T_IDLE; sthr <= S_INIT; vthr <= V_INIT; tc <= 0; tw <= 0; nf <= 2'd0; seen <= 1'b0;
                if (st != T_IDLE || req_ev) begin ok <= 1'b0; done_tgl <= ~done_tgl; end   // 途中だった (始めたところ) → 失敗で返す
                stl <= 1'b1; sc <= 0;
            end
        end
    end
endmodule
