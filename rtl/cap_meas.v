// =============================================================
// 映像入力 (キャプチャ) のタイミング測定 (2026-11-06、docs/capture_plan.md の 8.4・9 章)
//
//   入力は 3 本 (どれも基板のコンパレータで受けたもの。docs/capture_plan.md の 10 章):
//     vid : 黒以外なら 1 (R+G+B を合成してコンパレータで比べたもの)
//     hs  : HSYNC、または複合同期 (CSYNC)
//     vs  : VSYNC (CSYNC のときは何もつながない。動かなければ CSYNC とみなす)
//   どれも入力の DDR レジスタ (Interface Designer の DDIO、resync) で、サンプリングのクロック cclk
//   (Si5351A CLK2、50MHz) の立ち上がりと立ち下がりの両方で取る。1 クロックに 2 サンプル。
//   resync では *_lo (立ち下がりで取り、次の立ち上がりで取り直す) が半クロック前、*_hi (立ち上がり) が後のサンプル
//   (LO_FIRST = 1。Efinity の資料・実機で逆と分かったら 0 にする。逆だと位置が 1 サンプルずれ、端の判定が乱れる)
//   時間の単位はすべて「サンプル」= 1 / (2 f_s) (50MHz なら 10ns)。ドットへの直し (÷ 画素の間隔 P) はこのあとの推定でする。
//
//   測るもの (1 フィールドごとに、フィールドの区切り fd_v で fd_* に出す):
//     極性           : 一定の時間 (HS 1.3ms、VS 42ms) の High と Low の長い方を「同期でない」とする
//     同期の形式     : VS が 42ms 動かなければ CSYNC。OR / XOR は垂直同期中 (終わりのラインより前) の H の位置の切れ込みの有無で
//                      (変わったらフィールドを数え直す。垂直同期の中に H の同期がない XOR は OR と区別できない)
//     T_H (m_th)     : H の同期の始まりの間隔を 256 ライン足したもの (= T_H × 256、下 8 ビットが端数)
//     H 同期の幅     : 同じく 256 ライン分の合計 (m_hsw = 幅 × 256)。幅の 3/4 より短いパルス (等化パルス) は足さない
//     ライン数       : V の同期の始まりの間の H の同期の数 (フィールドごと。インターレースは 2 つが 1 違う)
//     V 同期の幅     : ライン数 (H の同期で区切ったライン)
//     VS OFS         : V の同期の始まり − そのラインの H の同期の始まり [サンプル] (フィールドごと)
//     表示の端       : ラインごとの記録 (ln_*) を cap_blank (BLANK MEAS) に出す (フィールドごとの端は 2026-11-07 にやめた。LE を減らすため)
//
//   H の同期の始まり (ライン) の決め方:
//     T_H が分かったあとは、前のラインの始まり + T_H (端数付き) を予測し、本物の同期の始まりが
//       予測の T_H/4 前から、予測の Dc (H 同期の幅の半分) あとまでに来たら、それでそろえ直す。
//       それ以外の同期 (半ラインの等化パルス・切れ込み・XOR の垂直同期中の端) は使わない。
//       垂直同期の外で、予測で始めたライン 2 本続けて本物が来なければロックが外れたとし、次の同期の始まりでそろえ直す。
//       垂直同期の間 (vst = V_VS) は本物を見ず、予測だけで進める (OR の CSYNC は垂直同期中に H の同期がない)。
//     T_H が分かるまでは、同期の始まりをすべてラインの始まりとし、同じ間隔が 2 回続いたら T_H の仮の値にする。
//   CSYNC の垂直同期: 予測した H の同期 (ラインの始まりから幅 W の間) を使って、
//     XOR は CSYNC ^ H、OR は CSYNC & ~H を VSYNC とみなす。T_H/4 より長く続いたら垂直同期の始まり、
//     T_H/4 より長く途切れたら終わり (H の同期の分の切れ目はつなぐ)。始まりは続き始めた位置。
//   注意: 表示の中の黒とブランクの黒は区別できない (表示の端は「黒以外が出た範囲」)。
//         等化パルスのある CSYNC (実機のインターレース) はまだ確かめていない (vga_timing は等化パルスを出さない)。
//         OR の CSYNC で V の同期が H の同期の中で切り替わると、その位置は分からない (H の同期の始まりか終わりになる)
//
//   ラインごとの記録 (ln_*) とフィールドの区切り (fd_*) を cap_blank (BLANK MEAS) へ出す (同じ cclk、1 クロックのパルス)。
//   受け渡し: 受け取る側 (cap_est) は同じ cclk。fd_v (1 クロック) のときに fd_* と m_th / m_hsw / m_vsw を取る
//             (2026-11-07 から。以前は r_* をトグル + 変わらない値で別のクロックへ出していた。LE を減らすためにやめた)
// =============================================================
module cap_meas #(
    parameter integer HWIN_LOG2 = 16,     // HS の極性の判定の時間 (2^16 クロック = 1.3ms)
    parameter integer VWIN_LOG2 = 21,     // VS の極性・CSYNC の判定の時間 (2^21 クロック = 42ms。フィールドより長く)
    parameter         LO_FIRST = 1        // 1 = *_lo の方が先のサンプル (DDIO の resync)
)(
    input  wire        cclk,
    input  wire        rst_n,
    input  wire        vid_hi, vid_lo,
    input  wire        hs_hi,  hs_lo,
    input  wire        vs_hi,  vs_lo,
    output wire [23:0] m_th,               // T_H × 256 [サンプル] (256 ラインごとに変わる)
    output wire [19:0] m_hsw,              // H 同期の幅 × 256 [サンプル]
    output wire [11:0] m_vsw,              // V 同期の幅 [ライン] (今のフィールドの始まりの垂直同期。終わりで変わる)
    // cap_blank (ブランクの測定、同じ cclk) へ: ラインごと・フィールドごとの記録
    output reg         ln_v,               // 1 ラインの記録 (1 クロック)
    output reg  [11:0] ln_no,              //   ライン (V の同期の始まりのラインが 0)
    output reg  [15:0] ln_rise, ln_fall,   //   黒以外の最初 (立ち上がり) / 最後に黒に戻った位置 [サンプル]
    output reg         ln_hasr, ln_any,    //   立ち上がりがあった / 黒以外があった
    output reg         fd_v,               // フィールドの区切り (垂直同期の始まり、1 クロック)
    output reg         fd_par,             //   VS OFS が T_H/2 以上 (インターレースのフィールドの見分け)
    output reg  [11:0] fd_cnt,             //   終わったフィールドのライン数
    output reg  [11:0] fd_cnt0,            //   その 1 つ前のフィールドのライン数
    output reg  [15:0] fd_vo, fd_vo0,      //   VS OFS [サンプル]: 始まったフィールド / 1 つ前のフィールド
    output reg  [7:0]  fd_flags,           //   bit0 有効 / bit1 HS 負極性 / bit2 VS 負極性 / bit4:3 同期 0 SEP 1 OR 2 XOR / bit5 インターレース
                                           //   (2026-11-09: 隣のフィールドとライン数が 1 違い、かつ VS の位置が半ライン (T_H/4〜3T_H/4) ずれていることが
                                           //    2 組続いたとき。ライン数の揺れ・同期の取りこぼしだけではインターレースにしない)
    output reg         fd_ok,              //   測定が有効 (fd_flags の bit0 と同じ)
    // 波形の記録 (cap_wav の wav_rec、2026-11-13) へ: 2 段目のサンプルごとの値 (先 = a、後 = b)
    output wire [15:0] w_pa, w_pb,         //   ラインの始まりからの位置 [サンプル]
    output wire [11:0] w_lna, w_lnb,       //   ライン (V の同期の始まりのラインが 0。垂直同期が決まるまでは前のフィールドの続きの番号)
    output wire        w_sa, w_sb,         //   HS (または CSYNC)、正論理 (1 = 同期中)
    output wire        w_ua, w_ub,         //   VS、正論理
    output wire        w_csy               //   CSYNC (VS の入力を使わない)
);
    // ---------- リセット ----------
    reg [1:0] rs;
    always @(posedge cclk or negedge rst_n)
        if (!rst_n) rs <= 2'b11; else rs <= {rs[0], 1'b0};
    wire rst = rs[1];

    // ---------- 入力 (DDR のレジスタのあとに 2 段) ----------
    (* async_reg = "true" *) reg [5:0] in1;
    reg [5:0] in2;
    always @(posedge cclk) begin
        in1 <= LO_FIRST ? {vid_lo, vid_hi, hs_lo, hs_hi, vs_lo, vs_hi}
                        : {vid_hi, vid_lo, hs_hi, hs_lo, vs_hi, vs_lo};
        in2 <= in1;
    end
    // ---------- 同期の変わり目の飛び込みを捨てる (2026-11-20) ----------
    //   実機で、TTL の同期の変わり目 (負極性の H 同期の終わり) のノイズが RGB のコンパレータに飛び込み、毎ライン (垂直の
    //   ブランキングも) BP の始まりに「黒以外」が出た (PC98 GDC で絵の幅が BP の 64 ドット広く、V NEG)。
    //   HS / VS の変わり目の近く (DLY クロック前〜EW − DLY クロック後) に始まり、黒以外が SPK サンプルより短く続いたものだけを
    //   黒にする (同期の終わりの直後から始まる絵は長く続くので残る。窓の外の 1 ドットの点も残る)。
    //   全部の信号を DLY クロック遅らせ (先読みの分)、VID は前後 SPK − 1 サンプルを見る (長さ SPK の並びに入るか)。
    localparam integer DLY = 4;           // 遅らせるクロック数 (= 8 サンプル。窓を変わり目の前にも広げる分と先読み)
    localparam integer EW  = 12;          // 変わり目から窓を開けておくクロック数 (遅れを引いて 160ns あとまで)
    //   捨てる長さ SPK = 4 サンプル (40ns。48MHz の 1 ドット 2 サンプルの 2 倍、下の k_a / k_b で決め打ち)
    reg  [2*DLY+7:0]  vsh;                // VID のサンプル (添え字が大きいほど新しい)
    reg  [4*DLY+3:0]  ssh;                // HS / VS を DLY クロック遅らせる {h_a, h_b, v_a, v_b} × (DLY + 1)。[3:0] が DLY クロック前の値
    reg  [1:0]        hv_p;               // 前のクロックの後の HS / VS
    reg  [3:0]        ew;                 // 窓の残り
    wire hv_e = (in2[3] != in2[2]) || (in2[1] != in2[0]) || (hv_p != {in2[3], in2[1]});
    always @(posedge cclk) begin
        vsh  <= {in2[4], in2[5], vsh[2*DLY+7:2]};       // 先 (_a = in2[5]) を小さい添え字に
        ssh  <= {in2[3:0], ssh[4*DLY+3:4]};
        hv_p <= {in2[2], in2[0]};
        ew   <= hv_e ? EW[3:0] : (ew != 4'd0) ? ew - 4'd1 : 4'd0;
    end
    // 出すサンプルは vsh[6] (先) と vsh[7] (後)。前後 3 サンプル (SPK − 1) が vsh の中にある (DLY = 4 の決め打ち)
    wire k_a = (vsh[3] & vsh[4] & vsh[5]) | (vsh[4] & vsh[5] & vsh[7]) | (vsh[5] & vsh[7] & vsh[8]) | (vsh[7] & vsh[8] & vsh[9]);
    wire k_b = (vsh[4] & vsh[5] & vsh[6]) | (vsh[5] & vsh[6] & vsh[8]) | (vsh[6] & vsh[8] & vsh[9]) | (vsh[8] & vsh[9] & vsh[10]);
    wire d_a = vsh[6] & ((ew == 4'd0) | k_a);   // _a = 先のサンプル、_b = 後のサンプル
    wire d_b = vsh[7] & ((ew == 4'd0) | k_b);
    wire h_a = ssh[3], h_b = ssh[2];
    wire v_a = ssh[1], v_b = ssh[0];

    // ---------- 極性・CSYNC の判定 ----------
    //   HS: 2^HWIN_LOG2 クロック (1.3ms、20 ライン以上) ごと。VS と CSYNC かどうか: 2^VWIN_LOG2 クロック (42ms) ごと
    //   HS の極性か同期の形式が変わったら測り直す (VS の極性だけならフィールドを数え直す)
    reg [VWIN_LOG2-1:0] wv;
    wire [HWIN_LOG2-1:0] wh = wv[HWIN_LOG2-1:0];   // HS の窓は VS の窓の下の桁 (数えるのを 1 つにする)
    reg [HWIN_LOG2-2:0] hcnt;      // 4 クロックに 1 回数える (窓の 1/4)
    reg [VWIN_LOG2-4:0] vcnt;      // 16 クロックに 1 回数える (窓の 1/16)
    reg                 vact, v_pb;
    reg                 hneg, vneg, csy;
    reg                 pol_chg, vpol_chg;
    wire                hn_n = hcnt[HWIN_LOG2-2] | hcnt[HWIN_LOG2-3];   // 半分より多く High なら負極性
    wire                vn_n = vcnt[VWIN_LOG2-4] | vcnt[VWIN_LOG2-5];
    always @(posedge cclk) begin
        pol_chg  <= 1'b0;
        vpol_chg <= 1'b0;
        v_pb     <= v_b;
        if (rst) begin
            wv <= 0; hcnt <= 0; vcnt <= 0; vact <= 1'b0;
            hneg <= 1'b0; vneg <= 1'b0; csy <= 1'b0;
        end else begin
            wv <= wv + 1'b1;
            if (&wh) begin
                hneg <= hn_n; hcnt <= 0;
                if (hneg != hn_n) pol_chg <= 1'b1;
            end else if (wv[1:0] == 2'd0) hcnt <= hcnt + h_a;
            if (&wv) begin
                vneg <= vn_n; csy <= !vact;
                if (csy != !vact) pol_chg <= 1'b1;
                if (vact && (vneg != vn_n)) vpol_chg <= 1'b1;
                vcnt <= 0; vact <= 1'b0;
            end else begin
                if (wv[3:0] == 4'd0) vcnt <= vcnt + v_a;
                if ((v_a != v_pb) || (v_a != v_b)) vact <= 1'b1;
            end
        end
    end
    // 正論理 (1 = 同期中) にそろえる
    wire s_a = h_a ^ hneg, s_b = h_b ^ hneg;
    wire u_a = v_a ^ vneg, u_b = v_b ^ vneg;
    reg  s_p;                             // 前のクロックの後のサンプル
    always @(posedge cclk) s_p <= s_b;

    // =============================================================
    // 1 段目: ライン (H の同期の始まり) を決める
    // =============================================================
    reg  [23:0] lp;          // 今のクロックの先のサンプルの、ラインの始まりからの位置 (下 8 ビットが端数)
    reg  [23:0] th;          // T_H (下 8 ビットが端数)
    reg         valid;       // T_H が分かっている
    reg         vq;          // valid を 1 クロック遅らせたもの (th が変わったクロックは nth1 / nth2 が古いので折り返さない)
    reg  [24:0] nth1, nth2;  // 256 - th、512 - th
    reg  [22:0] pc;          // 最後に使った本物の同期の始まりからのサンプル数 (先のサンプルの位置)
    reg         have_real;
    reg  [15:0] pprev;       // T_H が分かるまで: 1 つ前の間隔
    reg  [15:0] dq, late_lo, good_hi, dc;   // T_H/4、T_H - T_H/4、T_H + T_H/4、Dc (レジスタに入れておく)
    reg  [15:0] thh1;        // T_H/2
    reg  [15:0] wq3;         // H 同期の幅の 3/4 (これより短いパルス = 等化パルスは幅に足さない。2026-11-12)
    reg  [15:0] thm1;        // T_H − 1
    reg  [1:0]  miss;        // 本物の同期の始まりが来ないまま予測で始めたラインの数 (垂直同期の外。2 でロックが外れたとする)
    reg         xe;          // 今のラインに、使わなかった同期の始まり (予測にも位相のそろえ直しにも当たらない) があった
    reg  [4:0]  xcnt;        // xe のラインが続いた数 (垂直同期の外。16 で T_H を測り直す。2026-11-07)
    reg  [4:0]  mscore;      // 本物の同期の来ない予測のライン: 来ないと +2、来ると −1。16 で測り直す (周波数が半分などになると
                             //   1 本おきに来なくなり、2 本続けて来ないときの miss では外れないため。2026-11-07)
    reg  [23:0] sum_th;
    reg  [7:0]  n_th;
    reg  [19:0] hsw, sum_w;
    reg  [7:0]  n_w;
    reg         hsw_ok;
    reg         wopen;       // 使った同期の始まりのあと、まだ終わりが来ていない
    reg  [15:0] wpend;       // 測った H 同期の幅 (次のラインの始まりまでに垂直同期が始まらなければ足す)
    reg         wpv;
    reg         vflag;       // 前のラインの始まりから、垂直同期中だった・始まった (間隔・幅を足さない)
    wire        in_vs;       // 2 段目から: 垂直同期中 (本物の同期を見ない)
    wire        vmark;       // 2 段目から: 垂直同期中か、垂直同期の始まりが決まった

    wire [15:0] thi = th[23:8];
    wire        ea  = !s_p && s_a && s_b;            // 同期の始まりが先のサンプル (1 サンプルだけのひげは見ない)
    wire        eb  = !s_a && s_b;                   // 後のサンプル
    wire        fa  = s_p && !s_a;                   // 同期の終わり
    wire        fb  = s_a && !s_b;
    // 折り返し: lp + 256 - th / lp + 512 - th を並べて計算 (256 - th、512 - th はレジスタ。lp < th なので 2 回は折り返さない)
    wire [23:0] pbf  = lp + 24'd256;
    wire [24:0] s1   = {1'b0, lp} + nth1;
    wire [24:0] s2   = {1'b0, lp} + nth2;
    wire        wrapb = vq && !s1[24];
    wire [23:0] pbf2 = wrapb ? s1[23:0] : pbf;
    wire [15:0] pai  = lp[23:8];
    wire [15:0] pbi  = pbf2[23:8];
    wire [15:0] lpe  = ea ? pai : pbi;
    wire        e_late  = lpe >= late_lo;            // 予測より前 (次のラインの始まり)
    wire        e_early = lpe < dc;                  // 予測のすぐあと (位相のそろえ直しだけ)
    // ロックが外れた (垂直同期の外で、予測のライン 2 本続けて本物が来ない) ときは、次の同期の始まりでそろえ直す。
    //   T_H の半分より後ならそこが新しいライン、前なら位相だけ (予測でラインはもう始まっている)
    wire        unlock = miss[1];
    wire        acc  = (ea || eb) && (!valid || (!in_vs && (e_late || e_early || unlock)));
    wire        newl = !valid || e_late || (eb && wrapb) || (unlock && (lpe >= thh1));
    // 使わなかった同期の始まり: 入力の周波数が 2 倍などになると、本物の同期が 1 本おきに予測と重なってロックが外れないので、
    //   垂直同期の外で、こういう始まりのあるラインが 16 本続いたら最初から測り直す (等化パルスは垂直同期の前後の数ラインだけ)
    wire        ign  = (ea || eb) && valid && !acc && !in_vs;
    wire        wrap2 = vq && !s2[24];
    wire        wrapn = wrap2 && !wrapb;             // 次のクロックの先のサンプルで折り返す
    // 間隔 = pc + eb、幅 = pc + fb。範囲の比べは pc で (1 サンプルの違いは問題ない。足し算と比べを続けない)
    wire        per_good = have_real && !vflag && !vmark && (pc[22:16] == 7'd0) &&
                           (pc[15:0] >= late_lo) && (pc[15:0] <= good_hi);

    // 2 段目へ
    reg  [15:0] pa1, pb1;
    reg         na1, nb1;
    reg         wrap_a;      // 次のクロックの先のサンプルで予測のラインが始まる (lp を T_H で折り返した)
    reg         s_a1, s_b1, u_a1, u_b1, d_a1, d_b1;

    always @(posedge cclk) begin
        nth1    <= 25'd256 - {1'b0, th};
        nth2    <= 25'd512 - {1'b0, th};
        vq      <= valid && !rst && !pol_chg;
        dq      <= thi >> 2;
        thh1    <= thi >> 1;
        thm1    <= thi - 16'd1;
        late_lo <= thi - dq;
        good_hi <= thi + dq;
        dc      <= hsw_ok ? {5'd0, hsw[19:9]} : 16'd8;
        wq3     <= {4'd0, hsw[19:8]} - {6'd0, hsw[19:10]};
        if (rst || pol_chg) begin
            lp <= 24'd0; th <= 24'd0; valid <= 1'b0; pc <= 23'd0; have_real <= 1'b0; pprev <= 16'd0;
            sum_th <= 24'd0; n_th <= 8'd0; hsw <= 20'd0; sum_w <= 20'd0; n_w <= 8'd0; hsw_ok <= 1'b0; wopen <= 1'b0; wpv <= 1'b0; vflag <= 1'b0;
            pa1 <= 16'd0; pb1 <= 16'd0; na1 <= 1'b0; nb1 <= 1'b0; wrap_a <= 1'b0; miss <= 2'd0; xe <= 1'b0; xcnt <= 5'd0; mscore <= 5'd0;
        end else begin
            if (acc && valid && mscore != 5'd0) mscore <= mscore - 5'd1;
            else if (!acc && valid && (wrapb || wrap_a) && !in_vs) mscore <= (mscore > 5'd13) ? 5'd16 : mscore + 5'd2;
            if (ign) xe <= 1'b1;
            if (acc) begin xe <= 1'b0; xcnt <= (xe && valid) ? xcnt + 5'd1 : 5'd0; end
            // 位置とライン
            wrap_a <= !acc && wrapn;
            if (acc || !valid) miss <= 2'd0;
            else if ((wrapb || wrap_a) && !in_vs && !miss[1]) miss <= miss + 2'd1;
            if (acc) begin
                lp  <= ea ? 24'd512 : 24'd256;
                pa1 <= ea ? 16'd0 : pai;
                pb1 <= ea ? 16'd1 : 16'd0;
                na1 <= wrap_a || (ea && newl);
                nb1 <= eb && newl;
            end else begin
                lp  <= wrap2 ? s2[23:0] : lp + 24'd512;
                pa1 <= pai;
                pb1 <= pbi;
                na1 <= wrap_a;
                nb1 <= wrapb;
            end
            // 本物の同期の始まりからの数
            if (acc) pc <= ea ? 23'd2 : 23'd1;
            else if (!pc[22]) pc <= pc + 23'd2;
            if (acc) have_real <= 1'b1;
            // T_H: 分かるまでは同じ間隔が 2 回続くのを待つ。分かったあとは 256 ライン分の合計
            if (acc && have_real) begin
                if (!valid) begin
                    pprev <= pc[15:0];
                    if ((pc[22:16] == 7'd0) && (pc[15:6] != 10'd0) && (pc[15:5] == pprev[15:5])) begin   // 同じくらいの間隔 (32 サンプルの区切りで同じ) が 2 回
                        th <= {pc[15:0] + {15'd0, eb}, 8'd0}; valid <= 1'b1; sum_th <= 24'd0; n_th <= 8'd0;
                    end
                end else if (per_good) begin
                    if (n_th == 8'd255) begin th <= sum_th + {8'd0, pc[15:0]} + {23'd0, eb}; sum_th <= 24'd0; end
                    else sum_th <= sum_th + {8'd0, pc[15:0]} + {23'd0, eb};
                    n_th <= n_th + 8'd1;
                end
            end
            // H 同期の幅: 終わりで測り、次の本物の始まりまでに垂直同期が始まっていなければ足す
            //   (XOR の CSYNC で垂直同期が H の同期の中で始まると、その同期は短くなるため)
            if (acc) begin
                wopen <= 1'b1; wpv <= 1'b0;
                if (wpv && !vflag && !vmark) begin
                    if (n_w == 8'd255) begin hsw <= sum_w + {4'd0, wpend}; sum_w <= 20'd0; hsw_ok <= 1'b1; end
                    else sum_w <= sum_w + {4'd0, wpend};
                    n_w <= n_w + 8'd1;
                end
            end else if ((fa || fb) && wopen) begin
                wopen <= 1'b0;
                wpend <= pc[15:0] + {15'd0, fb};
                wpv   <= valid && !in_vs && (pc[22:16] == 7'd0) && (pc[15:0] < dq) &&
                         (!hsw_ok || (pc[15:0] >= wq3));   // インターレースの複合同期の等化パルス (幅は半分) は足さない
            end
            if (acc) vflag <= vmark; else if (vmark) vflag <= 1'b1;
            // 同期が来なくなった (約 42ms) → 最初から
            // 使わなかった同期の始まりのあるラインが 16 本続いた・来ないラインが多い → 最初から (周波数が変わった)
            if (pc[22] || xcnt[4] || mscore[4]) begin valid <= 1'b0; have_real <= 1'b0; hsw_ok <= 1'b0; n_w <= 8'd0; sum_w <= 20'd0; xcnt <= 5'd0; xe <= 1'b0; mscore <= 5'd0; end
        end
        s_a1 <= s_a; s_b1 <= s_b; u_a1 <= u_a; u_b1 <= u_b; d_a1 <= d_a; d_b1 <= d_b;
    end

    // =============================================================
    // 2 段目: 垂直同期・フィールド・表示の端
    // =============================================================
    localparam [1:0] V_IDLE = 2'd0, V_QUAL = 2'd1, V_VS = 2'd2;
    reg  [1:0]  vst;
    reg  [11:0] ln;          // 今のフィールドのライン (V の同期の始まりのラインが 0)
    reg  [15:0] wreg, wmid, thh;
    reg  [15:0] qt, lr;
    reg  [15:0] cpos, spos, epos;
    reg  [11:0] cline, eline;
    reg         x_p, xmode;  // xmode: 1 = XOR の CSYNC
    reg  [7:0]  n_x, n_o;    // 垂直同期中の H の位置で、CSYNC が同期でなかった (XOR の切れ込み) / 同期だった (OR)
    reg  [7:0]  s_x, s_o;    // 途切れ始めたときの n_x / n_o (終わりのラインの H の同期は数えない)
    reg  [11:0] vt_last, vsw;
    reg  [15:0] vo_last;
    reg  [1:0]  nf;          // T_H が分かってからのフィールドの区切りの数 (3 で止める。2 回目のあとから 2 フィールドとも正しい。有効は 3 のとき)
    reg  [15:0] thq, th3q;   // T_H/4、3T_H/4
    reg         il_dl, il_ok;
    reg  [16:0] il_dp;       // 隣のフィールドとの VS の位置の差 (符号付き)。垂直同期を確かめている間 (V_QUAL、T_H/8 クロック以上) に計算しておく
    reg  [1:0]  il_cnt;      // インターレースらしい組が続いた数 (3 で止める)
    wire [15:0] il_ad = il_dp[16] ? (~il_dp[15:0] + 16'd1) : il_dp[15:0];
    reg         d_p1;
    always @(posedge cclk) d_p1 <= d_b1;
    reg  [15:0] l_rise, l_fall;  // 今のラインの黒以外の最初の立ち上がり / 最後の立ち下がり
    reg         l_hasr, l_any;
    wire        bnd   = na1 | nb1;                     // このクロックで新しいラインが始まった (クロック単位で区切る。端は同期の中なので黒)
    wire        r_hit = (!d_p1 && d_a1) || (!d_a1 && d_b1);
    wire [15:0] r_pos = (!d_p1 && d_a1) ? pa1 : pb1;
    wire        f_hit = (d_p1 && !d_a1) || (d_a1 && !d_b1);
    wire [15:0] f_pos = (d_p1 && !d_a1) ? pa1 : pb1;

    wire [11:0] lna = ln + {11'd0, na1};
    wire [11:0] lnb = lna + {11'd0, nb1};
    wire hp_a = pa1 < wreg, hp_b = pb1 < wreg;        // 予測した H の同期
    wire x_a = csy ? (xmode ? (s_a1 ^ hp_a) : (s_a1 & ~hp_a)) : u_a1;
    wire x_b = csy ? (xmode ? (s_b1 ^ hp_b) : (s_b1 & ~hp_b)) : u_b1;
    wire [15:0] lr_n  = x_b ? 16'd0 : x_a ? 16'd1 : lr + 16'd2;
    // 垂直同期の始まりがラインの終わりぎりぎり (1 サンプル以内) なら、次のラインの頭とする
    wire        c_nx  = (cpos >= thm1);
    wire [11:0] c_ln  = cline + {11'd0, c_nx};
    wire [15:0] c_pos = c_nx ? 16'd0 : cpos;
    wire        conf  = (vst == V_QUAL) && (lr_n < 16'd4) && valid && (qt + 16'd2 >= dq);
    wire [16:0] sdiff = {1'b0, epos} - {1'b0, spos};   // 符号付き (17 ビット)
    wire        e_dn  = (vst == V_VS) && (lr_n >= dq);
    wire [11:0] vsw_n = (!sdiff[16] && (sdiff[15:0] > thh)) ? eline + 12'd1 :
                        ( sdiff[16] && ((~sdiff[15:0] + 16'd1) > thh)) ? eline - 12'd1 : eline;
    assign in_vs = (vst == V_VS);
    assign vmark = (vst == V_VS) || conf;

    always @(posedge cclk) begin
        wreg <= hsw_ok ? {4'd0, hsw[19:8]} : 16'd0;
        wmid <= {5'd0, hsw[19:9]};
        thh  <= thi >> 1;
        thq  <= thi >> 2;
        th3q <= (thi >> 1) + (thi >> 2);
        x_p  <= x_b;
        ln_v <= 1'b0;
        fd_v <= 1'b0;
        // ---- ラインごとの記録 (cap_blank へ) ----
        if (bnd) begin
            ln_v <= 1'b1; ln_no <= ln; ln_rise <= l_rise; ln_fall <= l_fall; ln_hasr <= l_hasr; ln_any <= l_any;
        end
        l_rise <= (r_hit && (bnd || !l_hasr)) ? r_pos : l_rise;
        l_hasr <= bnd ? r_hit : (l_hasr | r_hit);
        l_fall <= f_hit ? f_pos : (bnd ? 16'd0 : l_fall);
        l_any  <= bnd ? (d_a1 | d_b1) : (l_any | d_a1 | d_b1);
        if (rst || pol_chg) begin
            vst <= V_IDLE; ln <= 12'd0; qt <= 16'd0; lr <= 16'd0; xmode <= 1'b0; n_x <= 8'd0; n_o <= 8'd0;
            vt_last <= 12'd0; vo_last <= 16'd0; vsw <= 12'd0; nf <= 2'd0;
            fd_flags <= 8'd0; fd_ok <= 1'b0; il_cnt <= 2'd0;
        end else begin
            ln <= conf ? lnb - c_ln : lnb;
            if (!valid || vpol_chg) begin nf <= 2'd0; il_cnt <= 2'd0; end
            // インターレースの確かめ (V_QUAL の間に 2 段で): ライン数が 1 違い、VS の位置が半ラインずれている
            il_dl <= (c_ln == vt_last + 12'd1) || (vt_last == c_ln + 12'd1);
            il_dp <= {1'b0, c_pos} - {1'b0, vo_last};
            il_ok <= il_dl && (il_ad >= thq) && (il_ad <= th3q);
            case (vst)
            V_IDLE: if (x_a || x_b) begin
                cpos <= x_a ? pa1 : pb1; cline <= x_a ? lna : lnb;
                qt <= 16'd0; lr <= x_b ? 16'd0 : 16'd1; vst <= V_QUAL;
            end
            V_QUAL: begin
                lr <= lr_n; qt <= qt + 16'd2;
                if (lr_n >= 16'd4) vst <= V_IDLE;
                else if (conf) begin
                    // ---- 垂直同期の始まり = フィールドの区切り ----
                    vst <= V_VS; lr <= 16'd0; spos <= c_pos; n_x <= 8'd0; n_o <= 8'd0;
                    vt_last <= c_ln; vo_last <= c_pos;
                    fd_v <= 1'b1; fd_par <= (c_pos >= thh); fd_cnt <= c_ln; fd_ok <= (nf == 2'd3) && hsw_ok;
                    if (nf != 2'd3) nf <= nf + 2'd1;
                    fd_cnt0 <= vt_last; fd_vo <= c_pos; fd_vo0 <= vo_last;
                    fd_flags <= {2'd0, il_ok && (il_cnt != 2'd0), csy ? (xmode ? 2'd2 : 2'd1) : 2'd0, vneg && !csy, hneg,
                                 (nf == 2'd3) && hsw_ok};   // インターレース = この組と前の組が両方インターレースらしい
                    // 有効は 4 フィールド目から (2026-11-09: 正しいライン数の組が 2 つそろい、インターレースの判定が決まってから)
                    il_cnt <= il_ok ? ((il_cnt == 2'd3) ? 2'd3 : il_cnt + 2'd1) : 2'd0;
                end
            end
            V_VS: begin
                lr <= lr_n;
                if (x_p && !x_a)      begin epos <= pa1; eline <= lna; s_x <= n_x; s_o <= n_o; end   // 途切れ始めた位置
                else if (x_a && !x_b) begin epos <= pb1; eline <= lnb; s_x <= n_x; s_o <= n_o; end
                if (e_dn) begin
                    vst <= V_IDLE; vsw <= vsw_n;
                    if (csy && (s_x != s_o)) begin
                        xmode <= (s_x > s_o);
                        if (xmode != (s_x > s_o)) nf <= 2'd0;   // OR / XOR が変わった → フィールドを数え直す
                    end
                end
                // OR / XOR: 垂直同期中、H の同期の真ん中で CSYNC が同期でなければ XOR の切れ込み
                if (csy && hsw_ok && ((pa1 == wmid) || (pb1 == wmid))) begin
                    if ((pa1 == wmid) ? s_a1 : s_b1) begin if (n_o != 8'hFF) n_o <= n_o + 8'd1; end
                    else                              begin if (n_x != 8'hFF) n_x <= n_x + 8'd1; end
                end
            end
            default: vst <= V_IDLE;
            endcase
        end
    end
    assign m_th = th, m_hsw = hsw, m_vsw = vsw;
    assign w_pa = pa1, w_pb = pb1, w_lna = lna, w_lnb = lnb, w_sa = s_a1, w_sb = s_b1, w_ua = u_a1, w_ub = u_b1, w_csy = csy;
endmodule
