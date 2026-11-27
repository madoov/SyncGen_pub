// =============================================================
// キャプチャの測定から、ジェネレータの設定を推定する (2026-11-07、docs/capture_plan.md の 12 章)
//   解像度 (H ACTIVE / V ACTIVE) は既知 (ha / va、メニューで入れる値。推定の間は変えない)。0 は AUTO (2026-11-10):
//     V ACTIVE = 0: BLANK MEAS の上端・下端から (上端の小さい方のフィールドの 下端 − 上端 + 1。インターレースは × 2 = フレームのライン数)
//     H ACTIVE = 0: 4:3 で正方形のドットとみなした暫定の値 = round(V ACTIVE × 4/3 ÷ 8) × 8 = round(V ACTIVE ÷ 6) × 8
//       (V ACTIVE は上の自動の値か手で入れた値。÷ 6 は (V + 3) × 683 ÷ 4096 の切り捨て。V が 2044 までは割り算と同じ)
//     推定に使った値は e_ha / e_va に出す
//   cap_meas の結果 (同じ cclk) はフィールドの区切り (m_v) で取って覚える (有効なものだけ。推定中・結果を読まれている間は取らない)。
//   cap_blank (BLANK MEAS) の結果はこのモジュールが受け取る。新しい結果が来るたびに推定して e_* に出す (測定中の途中の結果でも推定する)。
//   e_* は e_tgl / e_ack (トグル + 変わらない値) で 50MHz 側へ。e_* は中のレジスタと cap_blank の b_* をそのまま出し、
//   受け取る側が読み終わる (e_ack) まで次の推定を始めず、b_ack も返さない (写しのレジスタを持たない。2026-11-07、LE を減らすため)。
//
//   推定 (位置は 1/256 サンプルの固定小数点。掛け算は 1 ビットずつ、割り算は udiv で逐次):
//     1. 端の端数: 左端 le = b_left + n1 / (n0 + n1)、右端 re = b_right − n0 / (n0 + n1) (cap_blank の 11.2)
//     2. H 合計 × 256 = T_H × H ACTIVE × 256 / (re − le) を四捨五入して H 合計。下 8 ビット (e_frac) は丸める前の端数
//        (128 に近いほど H 合計を間違えやすい。0 / 256 に近いほど確か)
//     3. H SYNC = round(H 同期の幅 × H 合計 / T_H)、左端のドット = round(le × H 合計 / T_H)
//        H BP = 左端のドット − H SYNC、H FP = H 合計 − H ACTIVE − H SYNC − H BP
//     4. V SYNC = V 同期のライン数、上端 = 2 種類のフィールドの小さい方、V BP = 上端 − V SYNC (インターレースは − 1)
//        V FP = フィールドのライン数 (インターレースは少ない方) − V ACTIVE (インターレースは (V ACTIVE + 1) / 2) − V SYNC − V BP
//     5. VS OFS = round(VS の位置 × H 合計 / T_H) (インターレースはライン数の少ないフィールドを始める VS。H 合計以上なら − H 合計)
//     6. DOTCLK [Hz] = round(H 合計 × 409.6e9 / T_H × 4096) (サンプリングのクロックを 50MHz とみなす。1e8 × 4096)
//        割り算は 2 段: q = H 合計 × 25.6e9 / T4096、DOTCLK = q × 16 + round(余り × 16 / T4096)
//   T_H は BLANK MEAS の START からのフィールドごとの T_H × 256 (cap_meas の 256 ライン分) の平均 (2026-11-21、ユーザーの依頼。
//     前はその時の 256 ライン分だけで、DOTCLK の下の桁が更新ごとに揺れていた)。推定のはじめに T4096 = 合計 × 16 / 回数 を求め、
//     DOTCLK は T4096、H 合計などは丸めた T256 = (T4096 + 8) / 16 を使う
//     極性・同期の形式・インターレースは cap_meas のまま
//   e_err: 0 推定できた / 1 cap_meas の結果がない / 2 左右か上の端が見つからない / 3 H 合計がおかしい
//          (幅が 0 以下、H ACTIVE 以下、4095 より大きい) / 4 H の FP か BP が負 / 5 V の FP か BP が負
// =============================================================
module cap_est #(
    // 右端の補正 [1/256 サンプル] (2026-11-08): 色ごとのコンパレータの + 入力の 330Ω と入力容量で、白 → 黒の端が
    //   約 0.4 サンプル遅れて見える分を右端の位置から引く。テスト (コンパレータの後のデジタルのモデル) では 0
    parameter [7:0] RCOMP = 8'd0,
    // T_H の平均の回数 = 2^AVG_LOG2 フィールド (2026-11-22。1〜8)
    parameter       AVG_LOG2 = 6
)(
    input  wire        clk,             // cap_clk
    input  wire        rst,
    input  wire [11:0] ha, va,          // 解像度 (別のクロックから)。推定を始めるときに取り込み (2 回続けて同じ値のとき)、その回は取り込んだ値だけを使う (2026-11-10)
    // cap_meas の結果 (フィールドの区切り m_v で取る)
    input  wire        m_v,
    input  wire [7:0]  m_flags,
    input  wire [23:0] m_th,
    input  wire [19:0] m_hsw,
    input  wire [11:0] m_vt0, m_vt1, m_vsw,
    input  wire [15:0] m_vo0, m_vo1,
    // cap_blank の結果 (ここで受け取る)
    input  wire        b_tgl,
    output reg         b_ack,
    input  wire [1:0]  b_stat,
    input  wire [15:0] b_nfield,
    input  wire [15:0] b_left, b_right,
    input  wire [15:0] b_ln0, b_ln1, b_rn0, b_rn1,
    input  wire [11:0] b_top0, b_top1,
    input  wire [11:0] b_bot0, b_bot1,  // V ACTIVE の自動のときに使う (2026-11-10)
    input  wire [3:0]  b_found,
    // 推定の結果 (50MHz 側へ)
    output reg         e_tgl,
    input  wire        e_ack,           // 別のクロックから
    output wire [2:0]  e_err,
    output wire [1:0]  e_bstat,         // BLANK MEAS の状態 (1 測定中 / 2 終わり / 3 エラー)
    output wire [15:0] e_nfield,
    output wire [11:0] e_ht, e_hf, e_hs, e_hb,
    output wire [11:0] e_vf, e_vs, e_vb, e_vt, e_vo,
    output wire        e_il, e_hneg, e_vneg,
    output wire [1:0]  e_cs,
    output wire [26:0] e_dot,           // [Hz]
    output wire [7:0]  e_frac,          // H 合計の丸める前の端数 (1/256)
    output wire [11:0] e_ha, e_va,      // この推定に使った解像度 (2026-11-10。COPY はこれと作業中の ACTIVE が同じときだけ)
    // 割り算を貸す (2026-11-13、容量削減: 波形コピーの wav_rec が変換中だけ使う。x_sel = 1 の間は外の start / num / den で動かす。
    //   その間この推定は割り算を待たない (キャプチャの MODE と CAP RAW は同時に使わない))
    input  wire        x_sel,
    input  wire        x_start,
    input  wire [47:0] x_num,
    input  wire [23:0] x_den,
    output wire [47:0] x_quo,
    output wire        x_done
);
    localparam [4:0] S_IDLE = 5'd0, S_FL = 5'd1, S_FR = 5'd2, S_W = 5'd3, S_M1 = 5'd4, S_HT = 5'd5,
                     S_M2 = 5'd6, S_HS = 5'd7, S_M3 = 5'd8, S_LD = 5'd9, S_M4 = 5'd10, S_VO = 5'd11,
                     S_M5 = 5'd12, S_DOT = 5'd13, S_FIN = 5'd14, S_OUT = 5'd15, S_WAIT = 5'd16, S_ACK = 5'd17,
                     S_AV = 5'd18, S_AH = 5'd19, S_D2 = 5'd22;
    reg  [4:0]  st;
    (* async_reg = "true" *) reg [1:0] ak;
    wire        rd_ok = (ak[1] == e_tgl);
    // 解像度: 50MHz 側の値を 2 段で取り、2 回続けて同じなら推定の始めに a_ha / a_va へ取り込む (途中で ACTIVE を変えても混ざらない)
    reg  [11:0] ha1, ha2, va1, va2, a_ha, a_va;
    always @(posedge clk) begin ha1 <= ha; ha2 <= ha1; va1 <= va; va2 <= va1; end
    wire        av_ok = (ha1 == ha2) && (va1 == va2);
    // ---------- cap_meas の結果を取る ----------
    reg        s_ok;
    reg [7:0]  s_flags;
    reg [23:0] s_th;
    reg [19:0] s_hsw;
    reg [11:0] s_vt0, s_vt1, s_vsw;
    reg [15:0] s_vo0, s_vo1;
    // T_H の平均 (2026-11-22、64 フィールドの固定で割り算をなくした): BLANK MEAS の測定中 (b_stat = 1) のフィールドごとに
    //   T_H × 256 を足し、64 回たまったら合計 (= T_H × 16384) を右へ 2 ビットずらして T_H × 4096 の平均 t_avg に取り、0 から足し直す。
    //   START (b_stat が 1 になったところ) で t_ok = 0。64 回たまるまで (60Hz で約 1 秒) は 1 フィールドの値を使う。
    //   BLANK MEAS は端のヒストグラムが 65535 回で自動で終わるので、縦 1024 ラインでも 64 フィールドは届く
    //   回数は 2^AVG_LOG2 (実機は 64。tb_presets は短く測るので 4)
    reg [23+AVG_LOG2:0] t_acc;
    reg [AVG_LOG2-1:0]  t_cnt;
    reg [27:0] t_avg;
    reg        t_ok, b_meas;
    wire [23+AVG_LOG2:0] t_sum = t_acc + {{AVG_LOG2{1'b0}}, m_th};
    wire [27+AVG_LOG2:0] t_x   = {t_sum, 4'd0};      // × 16 / 2^AVG_LOG2 は t_x[27+AVG_LOG2:AVG_LOG2]
    always @(posedge clk) begin
        b_meas <= (b_stat == 2'd1);
        if (rst || (b_stat == 2'd1 && !b_meas)) begin t_acc <= 0; t_cnt <= 0; t_ok <= 1'b0; end
        else if (m_v && m_flags[0] && (b_stat == 2'd1)) begin
            t_cnt <= t_cnt + 1'b1;
            if (&t_cnt) begin t_acc <= 0; t_avg <= t_x[27+AVG_LOG2:AVG_LOG2]; t_ok <= 1'b1; end   // 切り捨て (0.5/4096 サンプルの偏りは無視できる)
            else t_acc <= t_sum;
        end
    end
    always @(posedge clk) begin
        if (rst) s_ok <= 1'b0;
        // 取るのは BLANK MEAS の測定中 (b_stat = 1) だけ。終わり (2) のあとは次の START まで一式を変えない
        //   (2026-11-07 修正: DONE のあとも同期の幅・極性などが変わり、COPY で新旧が混ざっていた)
        else if (m_v && m_flags[0] && (st == S_IDLE) && rd_ok && (b_stat == 2'd1)) begin
            s_ok <= 1'b1; s_flags <= m_flags; s_th <= m_th; s_hsw <= m_hsw;
            s_vt0 <= m_vt0; s_vt1 <= m_vt1; s_vsw <= m_vsw; s_vo0 <= m_vo0; s_vo1 <= m_vo1;
        end
    end

    // 推定に使う値
    wire        c_f1  = (b_found[1] && b_found[2]) ? (b_top1 < b_top0) : !b_found[1];   // 上端に使うフィールド (1 = fd_par = 1)
    wire [11:0] c_top = c_f1 ? b_top1 : b_top0;
    // V ACTIVE の自動 (上端に使ったフィールドの 下端 − 上端 + 1。インターレースは 2 フィールド分)
    wire [11:0] c_rows = (c_f1 ? b_bot1 : b_bot0) - c_top + 12'd1;
    wire [11:0] c_va   = s_flags[5] ? {c_rows[10:0], 1'b0} : c_rows;
    wire [15:0] c_ofs = !s_flags[5] ? s_vo1 : ((s_vt1 < s_vt0) ? s_vo0 : s_vo1);   // インターレースはライン数の少ないフィールドを始める VS
    wire [16:0] l_sum = {1'b0, b_ln0} + {1'b0, b_ln1};
    wire [16:0] r_sum = {1'b0, b_rn0} + {1'b0, b_rn1};
    // 途中の値 (そのまま e_* に出す)
    reg  [23:0] le, re;
    reg  [8:0]  fl, fr;
    reg  [11:0] ht, hs, ld, vo;
    reg  [26:0] dot;
    reg  [27:0] t4096;                      // 平均の T_H × 4096
    reg  [23:0] t256;                       // 平均の T_H × 256 (丸め)
    reg  [7:0]  frac;
    reg  [12:0] r_hf, r_hb, r_vb, r_vf;     // 符号付き (13 ビット目が負)
    reg  [11:0] r_vt;
    reg  [2:0]  r_err;
    // 掛け算 (1 ビットずつ、12 クロック): m_p = {足し込み 36, 掛ける数 12} を、下のビットが 1 なら m_a を足してから右へずらす。
    //   12 回で m_p = m_a × 掛ける数 + 初めの足し込み (2026-11-14 容量削減。足し算は 48 → 37 ビット、m_a はずらさない)。
    //   割り算の前の四捨五入 (T_H / 2) は初めの足し込みに入れておく (以前は 48 ビットの足し算)
    reg  [34:0] m_a;
    reg  [47:0] m_p;
    wire [36:0] m_sum = {1'b0, m_p[47:12]} + (m_p[0] ? {2'b00, m_a} : 37'd0);
    reg  [3:0]  m_k;
    wire        m_end = (m_k == 4'd12);
    // ---------- 割り算 (逐次)。被除数・除数は、割り算を始めたクロック (d_start = 1) の状態で選ぶ (udiv が取り込む) ----------
    reg         d_start;
    wire [47:0] d_num = (st == S_FR) ? {24'd0, b_ln1, 8'd0} :
                        (st == S_W)  ? {24'd0, b_rn0, 8'd0} :
                        (st == S_M2) ? {m_p[39:0], 8'd0} :
                        (st == S_FIN) ? {16'd0, d_rem, 4'd0} + {21'd0, t4096[27:1]} : m_p;   // DOTCLK の 2 段目: 余り × 16
    wire [27:0] d_den = (st == S_FR) ? {11'd0, l_sum} : (st == S_W) ? {11'd0, r_sum} :
                        (st == S_M2) ? {4'd0, re - le} : (st == S_D2 || st == S_FIN) ? t4096 : {4'd0, t256};
    wire [47:0] d_quo;
    wire [27:0] d_rem;
    wire        dv_done;
    udiv #(.NW(48), .DW(28)) u_div (
        .clk(clk), .start(x_sel ? x_start : d_start), .num(x_sel ? x_num : d_num), .den(x_sel ? {4'd0, x_den} : d_den),
        .quo(d_quo), .rem(d_rem), .done(dv_done)
    );
    wire        d_done = dv_done && !x_sel;
    assign x_quo = d_quo, x_done = dv_done && x_sel;
    wire [11:0] vah  = s_flags[5] ? ((a_va + 12'd1) >> 1) : a_va;
    wire [11:0] fld  = s_flags[5] ? ((s_vt0 < s_vt1) ? s_vt0 : s_vt1) : s_vt1;

    // 結果: 中のレジスタと b_* をそのまま出す (読み終わるまで変えない)
    assign e_err = r_err; assign e_bstat = b_stat; assign e_nfield = b_nfield;
    assign e_ht = ht; assign e_hs = hs; assign e_hb = r_hb[11:0]; assign e_hf = r_hf[11:0];
    assign e_vs = s_vsw; assign e_vb = r_vb[11:0]; assign e_vf = r_vf[11:0]; assign e_vt = r_vt; assign e_vo = vo;
    assign e_il = s_flags[5]; assign e_hneg = s_flags[1]; assign e_vneg = s_flags[2]; assign e_cs = s_flags[4:3];
    assign e_dot = dot; assign e_frac = frac; assign e_ha = a_ha; assign e_va = a_va;

    always @(posedge clk) begin
        d_start <= 1'b0;
        ak      <= {ak[0], e_ack};
        if (rst) begin
            st <= S_IDLE; e_tgl <= 1'b0; b_ack <= 1'b0; r_err <= 3'd1;
        end else begin
            // 掛け算
            if (!m_end) begin
                m_p <= {m_sum, m_p[11:1]}; m_k <= m_k + 4'd1;
            end
            case (st)
            S_IDLE: if ((b_tgl != b_ack) && rd_ok && av_ok) begin   // cap_blank の新しい結果 (前の結果は読み終わっている)
                a_ha <= ha2; a_va <= va2;                      // この回の解像度 (0 は AUTO)
                if (!s_ok || !b_found[0] || !(b_found[1] || b_found[2]) || (b_stat == 2'd3) || (b_stat == 2'd0)) begin
                    r_err <= !s_ok ? 3'd1 : 3'd2; st <= S_OUT;
                end else if (!t_ok) begin t4096 <= {s_th, 4'd0}; t256 <= s_th; st <= S_AV; end
                else begin t4096 <= t_avg; t256 <= t_avg[27:4] + {23'd0, t_avg[3]}; st <= S_AV; end   // 64 フィールドの平均
            end
            S_AV: begin                                         // AUTO: V ACTIVE を測った上端・下端から。H は V ÷ 6 を掛け算で
                if (a_va == 12'd0) a_va <= c_va;
                m_a <= {23'd0, (a_va == 12'd0) ? c_va : a_va} + 35'd3; m_p <= {36'd0, 12'd683}; m_k <= 4'd0;
                st <= (a_ha == 12'd0) ? S_AH : S_FL;
            end
            S_AH: if (m_end) begin                              // H ACTIVE = round(V ÷ 6) × 8 (4:3 で正方形のドットの暫定)
                a_ha <= {m_p[20:12], 3'd0};
                st <= S_FL;
            end
            S_FL: begin                                         // 左端の端数 = n1 × 256 / (n0 + n1)
                if (l_sum == 17'd0) fl <= 9'd0; else d_start <= 1'b1;
                st <= S_FR;
            end
            S_FR: if (d_done || (l_sum == 17'd0)) begin         // 右端の端数 = n0 × 256 / (n0 + n1)
                if (l_sum != 17'd0) fl <= d_quo[8:0];
                if (r_sum == 17'd0) fr <= 9'd0; else d_start <= 1'b1;
                st <= S_W;
            end
            S_W: if (d_done || (r_sum == 17'd0)) begin
                if (r_sum != 17'd0) fr <= d_quo[8:0];
                st <= S_M1;
            end
            S_M1: begin                                         // le, re。T_H × H ACTIVE を掛け始める
                le <= {b_left, 8'd0} + {15'd0, fl};
                re <= {b_right, 8'd0} - {15'd0, fr} - {16'd0, RCOMP};
                m_a <= {11'd0, t256}; m_p <= {36'd0, a_ha}; m_k <= 4'd0;
                st <= S_HT;
            end
            S_HT: if (m_end) begin                              // H 合計 × 256 = T_H × H ACTIVE × 256 / 幅
                if (re <= le) begin r_err <= 3'd3; st <= S_OUT; end
                else begin d_start <= 1'b1; st <= S_M2; end
            end
            S_M2: if (d_done) begin                             // 四捨五入して H 合計。H 同期の幅 × H 合計を掛け始める
                frac <= d_quo[7:0];
                ht   <= d_quo[19:8] + {11'd0, d_quo[7]};
                if ((d_quo[47:20] != 28'd0) || ((d_quo[19:8] + {11'd0, d_quo[7]}) <= a_ha) || (d_quo[19:8] == 12'hFFF && d_quo[7])) begin
                    r_err <= 3'd3; st <= S_OUT;
                end else begin
                    m_a <= {15'd0, s_hsw}; m_p <= {13'd0, t256[23:1], d_quo[19:8] + {11'd0, d_quo[7]}}; m_k <= 4'd0; st <= S_HS;
                end
            end
            S_HS: if (m_end) begin d_start <= 1'b1; st <= S_M3; end   // H SYNC = round(幅 × H 合計 / T_H)
            S_M3: if (d_done) begin
                hs <= d_quo[11:0];
                m_a <= {11'd0, le}; m_p <= {13'd0, t256[23:1], ht}; m_k <= 4'd0; st <= S_LD;
            end
            S_LD: if (m_end) begin d_start <= 1'b1; st <= S_M4; end   // 左端のドット = round(le × H 合計 / T_H)
            S_M4: if (d_done) begin
                ld <= d_quo[11:0];
                m_a <= {11'd0, c_ofs, 8'd0}; m_p <= {13'd0, t256[23:1], ht}; m_k <= 4'd0; st <= S_VO;
            end
            S_VO: if (m_end) begin d_start <= 1'b1; st <= S_M5; end   // VS OFS = round(VS の位置 × H 合計 / T_H)
            S_M5: if (d_done) begin
                vo <= (d_quo[11:0] >= ht) ? d_quo[11:0] - ht : d_quo[11:0];
                m_a <= 35'd25_600_000_000; m_p <= {36'd0, ht}; m_k <= 4'd0; st <= S_DOT;
            end
            S_DOT: if (m_end) begin d_start <= 1'b1; st <= S_D2; end  // DOTCLK の 1 段目: q = H 合計 × 25.6e9 / T4096
            S_D2: if (d_done) begin                             // 2 段目: round(余り × 16 / T4096) (d_num は余りから作る)
                dot <= d_quo[26:0]; d_start <= 1'b1; st <= S_FIN;
            end
            S_FIN: if (d_done) begin                            // DOTCLK = q × 16 + 2 段目。FP・BP (足し算・引き算だけ)
                dot  <= {dot[22:0], 4'd0} + d_quo[26:0];
                r_hb <= {1'b0, ld} - {1'b0, hs};
                r_hf <= {1'b0, ht} - {1'b0, a_ha} - {1'b0, ld};
                r_vb <= {1'b0, c_top} - {1'b0, s_vsw} - {12'd0, s_flags[5]};
                r_vf <= {1'b0, fld} - {1'b0, vah} - {1'b0, c_top} + {12'd0, s_flags[5]};
                r_vt <= fld;
                st <= S_WAIT;
            end
            S_WAIT: begin
                r_err <= (r_hb[12] || r_hf[12]) ? 3'd4 : (r_vb[12] || r_vf[12]) ? 3'd5 : 3'd0;
                st <= S_OUT;
            end
            S_OUT: begin                                        // 出す (前の結果は読み終わっている)
                e_tgl <= ~e_tgl; st <= S_ACK;
            end
            S_ACK: if (rd_ok) begin                             // 読み終わったら cap_blank に返す (次の結果を受け取れる)
                b_ack <= b_tgl; st <= S_IDLE;
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
