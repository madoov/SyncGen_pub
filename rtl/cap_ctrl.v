// =============================================================
// キャプチャの操作 (50MHz 側、2026-11-07。メニューの CAP RUN から。docs/capture_plan.md の 14 章)
//   SEL (sel、1 クロック): 止まっていれば しきい値の合わせ込み (cap_thr) → BLANK MEAS の START、
//                          測定中なら END (結果が出るまで待つ)。しきい値の合わせ込み中は何もしない
//   en = 0 (MODE をキャプチャ以外にした) になったら止める。
//   測定中に cap_blank が自動で終わった (回数の飽和) ときは、END を待たずに DONE / 推定のエラーを出す (2026-11-09)
//   cap_clk 側へは反転 (thr_req / bl_start / bl_stop)、cap_clk 側からは thr_done (反転) + thr_ok (変わらない値) と
//   推定の e_tgl (反転) + e_bstat / e_err (変わらない値。e_tgl を変えたあと、ここが e_ack を返すまで変わらない。
//   2026-11-10 に cap_uart を外し、e_ack はここで同期化した e_tgl を返す)
//
//   status (メニューの CAP RUN の表示):
//     0 PUSH+ / 1 THR (しきい値を合わせている) / 2 RUN (測定中、途中の結果が出る) / 3 DONE (推定できた) /
//     4 NO SYNC (同期が見つからない) / 5 ERROR (BLANK MEAS のエラー: 入力が変わった・測定が無効) /
//     6〜10 推定のエラー (e_err 1〜5: NO MEAS / NO EDGE / BAD HTOT / H NEG / V NEG) /
//     11 HI LEVEL (入力モード・終端あり (S3 = 75Ω) で VID が 0.77V を超えた = TTL などが来ている。S3 を TTL に。測らない)
//   止まっている間も、cap_thr の見張りで HI LEVEL になったら status = 11 (2026-11-09。終端はトップが切る)。
//   見張りが解けたら (S3 を TTL に・入力モードを出た) PUSH+ に戻す。active = 止まっていない (cap_thr の hold)
//   rr / rr_v (2026-11-09): 推定の H 合計の丸める前の端数。RUN / DONE の表示に符号付きで添える (0 に近いほど推定が確か)
// =============================================================
module cap_ctrl #(
    parameter integer TO_LOG2 = 27               // END のあと結果が来なければエラー (2^27 クロック = 2.7 秒)
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       en,
    input  wire       sel,
    output reg        thr_req,
    input  wire       thr_done,                  // cap_clk から
    input  wire       thr_ok,
    input  wire       thr_hi,                    // 入力モード・終端ありで VID が高すぎる (S3 を TTL に。2026-11-08。cap_clk の変わらない値)
    output wire       active,                    // 合わせ込み・測定中 (cap_thr はこの間は見張らない)
    output reg        bl_start,
    output reg        bl_stop,
    input  wire       e_tgl,                     // cap_clk から
    input  wire [1:0] e_bstat,
    input  wire [2:0] e_err,
    input  wire [7:0] e_frac,                    // 推定の H 合計の丸める前の端数 (1/256、変わらない値)
    output reg  [7:0] rr,                        // 最後に推定できたときの e_frac (2026-11-09、CAP RUN の表示の確かさ)
    output reg        rr_v,                      // rr が今回の測定の値 (START で 0)
    output reg  [3:0] status,
    output wire       e_ack                      // 推定を受け取った (同期化した e_tgl。cap_est へ)
);
    (* async_reg = "true" *) reg [2:0] td, et, th;
    always @(posedge clk) begin td <= {td[1:0], thr_done}; et <= {et[1:0], e_tgl}; th <= {th[1:0], thr_hi}; end
    wire thr_ev = td[2] ^ td[1];
    wire e_ev   = et[2] ^ et[1];
    assign e_ack = et[2];

    localparam [1:0] C_IDLE = 2'd0, C_THR = 2'd1, C_RUN = 2'd2, C_STOP = 2'd3;
    reg [1:0]         st;
    assign active = (st != C_IDLE);
    reg               seen1;                     // START のあと、測定中 (b_stat = 1) の結果が来た
    reg [TO_LOG2:0]   to;
    always @(posedge clk) begin
        if (rst) begin
            st <= C_IDLE; status <= 4'd0; thr_req <= 1'b0; bl_start <= 1'b0; bl_stop <= 1'b0; seen1 <= 1'b0; to <= 0;
            rr <= 8'd0; rr_v <= 1'b0;
        end else begin
            to <= to + 1'b1;
            // 推定の端数: 推定できた結果 (測定中・終わり) が来るたびに覚える。e_* は e_tgl のあと ack まで変わらない
            if (e_ev && (st == C_RUN || st == C_STOP) && e_err == 3'd0 && (e_bstat == 2'd1 || e_bstat == 2'd2)) begin rr <= e_frac; rr_v <= 1'b1; end
            case (st)
            C_IDLE: begin
                if (en && sel) begin thr_req <= ~thr_req; status <= 4'd1; st <= C_THR; rr_v <= 1'b0; end
                else if (th[1] && !th[2]) status <= 4'd11;                    // 見張りで HI LEVEL
                else if (!th[1] && th[2] && status == 4'd11) status <= 4'd0;  // 見張りが解けた
            end
            C_THR: begin
                if (thr_ev) begin
                    if (thr_ok && thr_hi) begin status <= 4'd11; st <= C_IDLE; end   // 測らずに知らせる
                    else if (thr_ok) begin bl_start <= ~bl_start; seen1 <= 1'b0; status <= 4'd2; st <= C_RUN; end
                    else begin status <= 4'd4; st <= C_IDLE; end
                end
                if (!en) begin status <= 4'd0; st <= C_IDLE; end   // 合わせ込みは最後まで回るが、結果は使わない
            end
            C_RUN: begin
                if (e_ev && e_bstat == 2'd1) seen1 <= 1'b1;
                if (e_ev && seen1 && e_bstat == 2'd3) begin status <= 4'd5; st <= C_IDLE; end
                else if (e_ev && seen1 && e_bstat == 2'd2) begin   // cap_blank が自動で終わった (回数の飽和、2026-11-09)
                    status <= (e_err == 3'd0) ? 4'd3 : 4'd5 + {1'b0, e_err}; st <= C_IDLE;
                end
                else if (sel || !en) begin bl_stop <= ~bl_stop; to <= 0; st <= C_STOP; end
            end
            default: begin                         // END のあと、終わりの結果を待つ
                if (e_ev && (e_bstat != 2'd1 || !seen1)) begin
                    if (e_bstat == 2'd1) seen1 <= 1'b1;          // START の直後の結果 (まだ測定中の印) は読み飛ばす
                    else begin
                        st <= C_IDLE;
                        status <= (e_bstat == 2'd2) ? ((e_err == 3'd0) ? 4'd3 : 4'd5 + {1'b0, e_err}) :
                                  (e_bstat == 2'd3) ? 4'd5 : 4'd0;   // 0 = 数え始める前に止めた
                    end
                end
                if (to[TO_LOG2]) begin status <= 4'd5; st <= C_IDLE; end
                if (!en) begin status <= 4'd0; st <= C_IDLE; end
            end
            endcase
        end
    end
endmodule


// =============================================================
// 波形コピー (2026-11-13、MODE = CAP RAW。docs/capture_plan.md 15 章)
//   ファイルを増やさないため (Efinity のプロジェクトのファイル一覧を変えない) cap_ctrl.v に置く
//
// wav_rec (cap_clk): 入力の同期 (HS または CSYNC と、VS) の変わり目を 1 フィールド分記録し、ドット単位に直して wav_play のメモリへ書く。
//   - rec_tgl (別のクロックからの反転) で始める → 次のフィールドの区切り (cap_meas の fd_v。垂直同期が決まったところ) から
//     その次の区切りまで、変わり目を (ライン, ラインの始まりからの位置 [サンプル], HS / VS, 新しいレベル) で raw に書く。
//     ラインは cap_meas の番号 (V の同期の始まりのラインが 0)。終わりの区切りの前の、次のフィールドのライン (番号 N 以上) は
//     N を引いて頭のラインに回す (1 フィールドがちょうど 1 回ずつになる。N = そのフィールドのライン数)
//   - 変わり目は 1 クロックの 2 サンプルで見る。1 サンプルだけのひげは書かない
//   - 記録のあと 1 つずつ: ドット = 位置 × H 合計 × 256 / T_H (× 256) の四捨五入 (逐次の掛け算と udiv)。H 合計以上なら次のラインの頭へ
//   - 同じ (ライン, ドット) の変わり目 (HS と VS が同時など) は 1 項目にまとめる。項目は変わり目のあとの両方のレベルを持つ
//   - 再生の頭 (ライン 0、ドット 0) に当たる項目の番号 s0 と、その前のレベル lv0 も求める (変換したラインの番号が初めて戻った項目)
//   - 変換した項目は wav_store (50MHz) のメモリへ書く。圧縮・再生用のメモリへの展開は wav_store が行う (2026-11-13)
//   - インターレースは 2 フィールド (1 フレーム) を記録する (2026-11-14)。項目は 2047 まで (FULL)。フィールドの区切りが 0.34 秒来なければ NO SYNC
//   stat: 0 待機 / 1 区切り待ち / 2 記録中 / 3 変換中 / 4 済み / 5 FULL / 6 IL / 7 NO SYNC
// =============================================================
module wav_rec (
    input  wire        clk,             // cap_clk
    input  wire        rst,
    input  wire        rec_tgl,         // 記録の開始 (反転、別のクロックから)
    input  wire [11:0] ht,              // H 合計 [ドット] (ジェネレータの確定値。COPY → APPLY のあと。別のクロックの変わらない値)
    // cap_meas から
    input  wire [15:0] w_pa, w_pb,
    input  wire [11:0] w_lna, w_lnb,
    input  wire        w_sa, w_sb, w_ua, w_ub, w_csy,
    input  wire        fd_v,
    input  wire        fd_par,          // そのフィールドの VS が H の同期から半ライン以上ずれている (インターレースの見分け)
    input  wire [11:0] fd_cnt,
    input  wire [7:0]  fd_flags,
    input  wire [23:0] m_th,
    // 割り算 (cap_est の udiv を借りる。2026-11-13、容量削減。dv_sel = 1 の間 = 変換中)
    output wire        dv_sel,
    output reg         dv_go,
    output wire [47:0] dv_num,
    output wire [23:0] dv_den,
    input  wire [47:0] dv_q,
    input  wire        dv_done,
    // 状態と結果 (済みのあとは変わらない)
    output reg  [2:0]  stat,
    output reg  [11:0] n_lines,         // 1 フィールドのライン数
    output reg  [10:0] n_ent,           // 項目の数
    output reg  [10:0] s0,              // 再生の頭の項目
    output reg  [1:0]  lv0,             // 再生の頭のレベル {VS, HS} (正論理)
    output reg         rdy_tgl,         // 済みになるたびに反転 (wav_play がそこで n_ent / s0 / lv0 を取る)
    // wav_play のメモリへ ({ライン 11, ドット 12, その変わり目のあとの VS, HS}。同じ位置の変わり目は 1 項目にまとめる)
    output reg         pw_en,
    output reg  [10:0] pw_addr,
    output reg  [24:0] pw_data
);
    (* async_reg = "true" *) reg [2:0] rt;
    always @(posedge clk) rt <= {rt[1:0], rec_tgl};
    wire go = rt[2] ^ rt[1];

    localparam S_IDLE = 3'd0, S_WAIT = 3'd1, S_REC = 3'd2, S_CONV = 3'd3, S_DONE = 3'd4, S_FULL = 3'd5, S_IL = 3'd6, S_NOS = 3'd7;
    // 生の記録: {ライン 12, 位置 16, VS / HS, レベル}
    reg  [29:0] raw [0:2047];
    reg  [10:0] wp;
    reg         r_we;
    reg  [29:0] r_wd;
    reg  [10:0] r_ra;
    reg  [29:0] r_q;
    always @(posedge clk) begin
        if (r_we) raw[wp] <= r_wd;
        r_q <= raw[r_ra];
    end
    reg         sp, up;                 // 前のクロックの後のサンプル
    reg  [1:0]  lv;                     // 記録を始めたときのレベル
    reg         vpend;                  // VS の変わり目を 1 つ待たせている (同じクロックに HS の変わり目があった)
    reg  [29:0] vq;
    reg  [24:0] to;                     // 区切りを待つ時間
    reg  [11:0] nl;
    // インターレース (2026-11-14): VS が H の同期にそろったフィールドの区切りから 2 フィールド (1 フレーム) を記録し、
    //   ラインはフレームで通しの番号 (2 つ目のフィールドは 1 つ目のライン数 n0 を足す)。再生も 1 フレームごとに頭へ
    reg         il_r, f2rec, f2c;
    reg  [11:0] n0;
    reg  [10:0] split;                  // 2 つ目のフィールドの最初の生の記録の番号 (プログレッシブは 2047 = なし)
    // 変わり目 (1 サンプルだけのひげは書かない)
    wire h_ea = (w_sa != sp) && (w_sb == w_sa);
    wire h_eb = (w_sb != w_sa) && (w_sa == sp);
    wire v_ea = !w_csy && (w_ua != up) && (w_ub == w_ua);
    wire v_eb = !w_csy && (w_ub != w_ua) && (w_ua == up);
    wire [29:0] h_ev = h_ea ? {w_lna, w_pa, 1'b0, w_sa} : {w_lnb, w_pb, 1'b0, w_sb};
    wire [29:0] v_ev = v_ea ? {w_lna, w_pa, 1'b1, w_ua} : {w_lnb, w_pb, 1'b1, w_ub};
    // 変換: 位置 × H 合計 (逐次の掛け算 12 クロック) → udiv → ドットが H 合計を超えたら次のラインへ → ラインをフィールドのライン数で折り返す
    //   (2026-11-14 容量削減: 掛け算は右へずらす形で 18 ビットの足し算 1 つ、折り返しは 1 クロックずつ)
    reg  [3:0]  cs;                     // 変換の手順
    reg  [10:0] ci;
    reg  [28:0] mp;                     // {足し込み 17, 掛ける数 12}: 12 回で 位置 × H 合計 + 初めの足し込み
    reg  [15:0] ma;
    reg  [3:0]  mk;
    reg  [11:0] cln;                    // ライン (変換の途中で折り返す)
    reg  [12:0] dr;                     // ドット (同)
    reg  [1:0   ] cst;                  // 変換中のレベル (lv0 を求める)
    reg         s0_set;
    reg  [10:0] nraw, wi;               // 生の記録の数 / 書いた項目の数
    wire [1:0]  nst = r_q[1] ? {r_q[0], cst[0]} : {cst[1], r_q[0]};   // この変わり目のあとのレベル {VS, HS}
    wire        same = (wi != 11'd0) && ({cln[10:0], dr[11:0]} == pw_data[24:2]);   // 最後に書いた項目 (pw_data) と同じ位置
    reg  [23:0] cth;                    // 変換に使う T_H (記録の終わりで取り込む。変換の途中で m_th が変わっても同じ値で)
    assign dv_sel = (stat == S_CONV);
    assign dv_num = {12'd0, mp[27:0], 8'd0};   // 丸めの T_H / 2 は掛け算の初めに T_H / 512 として足し込む (下の 8 ビット分は捨てる。2026-11-14 容量削減)
    assign dv_den = cth;
    wire [17:0] msum = {1'b0, mp[28:12]} + (mp[0] ? {2'b00, ma} : 18'd0);
    wire [13:0] dsub = {1'b0, dr} - {2'b00, ht};       // [13] = 借り (dr < ht)
    wire [12:0] lsub = {1'b0, cln} - {1'b0, nl};       // [12] = 借り (cln < nl)
    always @(posedge clk) begin
        r_we <= 1'b0; pw_en <= 1'b0; dv_go <= 1'b0;
        sp <= w_sb; up <= w_ub;
        if (rst) begin
            stat <= S_IDLE; rdy_tgl <= 1'b0; vpend <= 1'b0;
        end else begin
            if (go) begin stat <= S_WAIT; to <= 25'd0; vpend <= 1'b0; end
            else case (stat)
            S_WAIT: begin
                to <= to + 25'd1;
                if (to[24]) stat <= S_NOS;
                else if (fd_v && fd_flags[0] && !(fd_flags[5] && fd_par)) begin   // インターレースは VS が H の同期にそろったフィールドから
                    stat <= S_REC; wp <= 11'd0; lv <= {w_ub & !w_csy, w_sb}; to <= 25'd0;
                    il_r <= fd_flags[5]; f2rec <= 1'b0; split <= 11'h7FF;
                end
            end
            S_REC: begin
                to <= to + 25'd1;
                // HS を先に書き、同じクロックの VS は次の空いたクロックへ
                if (h_ea || h_eb) begin r_we <= 1'b1; r_wd <= h_ev; if (v_ea || v_eb) begin vpend <= 1'b1; vq <= v_ev; end end
                else if (v_ea || v_eb) begin r_we <= 1'b1; r_wd <= v_ev; end
                else if (vpend) begin r_we <= 1'b1; r_wd <= vq; vpend <= 1'b0; end
                if (r_we) begin
                    if (wp == 11'd2046) stat <= S_FULL; else wp <= wp + 11'd1;
                end
                if (to[24]) stat <= S_NOS;
                else if (fd_v && il_r && !f2rec) begin            // インターレース: 1 つ目のフィールドの終わり。2 つ目を続けて記録
                    f2rec <= 1'b1; n0 <= fd_cnt; split <= wp + {10'd0, r_we};
                end
                else if (fd_v) begin                               // 次の区切り: 記録を終わって変換へ
                    nl <= il_r ? n0 + fd_cnt : fd_cnt; nraw <= wp + {10'd0, r_we}; n_lines <= il_r ? n0 + fd_cnt : fd_cnt;
                    wi <= 11'd0; cth <= m_th; f2c <= 1'b0;
                    stat <= S_CONV; ci <= 11'd0; cs <= 4'd0; cst <= lv; s0_set <= 1'b0; s0 <= 11'd0; lv0 <= lv;
                end
            end
            S_CONV: case (cs)
                4'd0: begin r_ra <= ci; if (ci == split) f2c <= 1'b1; cs <= 4'd1; end   // ここから 2 つ目のフィールド
                4'd1: cs <= 4'd2;                                  // r_q を待つ
                4'd2: begin
                    cln <= r_q[29:18] + (f2c ? n0 : 12'd0);         // 2 つ目のフィールドはフレームの通しの番号に
                    ma <= r_q[17:2]; mp <= {2'b00, cth[23:9], ht}; mk <= 4'd0; cs <= 4'd3;
                end
                4'd3: begin                                        // 位置 × H 合計 (下のビットから見て、足してから右へずらす)
                    mp <= {msum, mp[11:1]}; mk <= mk + 4'd1;
                    if (mk == 4'd11) begin cs <= 4'd4; end
                end
                4'd4: begin dv_go <= 1'b1; cs <= 4'd5; end
                4'd5: if (dv_done) begin dr <= dv_q[12:0]; cs <= 4'd6; end
                4'd6: begin                                        // ドットが H 合計以上なら次のラインのドットへ
                    if (!dsub[13]) begin dr <= dsub[12:0]; cln <= cln + 12'd1; end
                    cs <= 4'd7;
                end
                4'd7: begin                                        // 次のフィールドの続きは頭のラインへ
                    if (!lsub[12]) cln <= lsub[11:0];
                    cs <= 4'd8;
                end
                4'd8: begin
                    // 前の項目と同じ位置ならその項目を書き直す (レベルをまとめる)
                    pw_en <= 1'b1; if (!same) pw_addr <= wi; pw_data <= {cln[10:0], dr[11:0], nst};   // 同じなら pw_addr は前の項目のまま
                    cst <= nst;
                    // ラインの番号が初めて戻ったところ (次のフィールドの頭へ回った項目) が再生の頭 (2026-11-13: 前のラインの終わりから
                    //   次のラインのドット 0 へ回った項目 (H の同期の始まり) も頭のラインに入るように、変換したあとのラインで見る)
                    if (!s0_set && wi != 11'd0 && !same && cln[10:0] < pw_data[24:14]) begin s0_set <= 1'b1; s0 <= wi; lv0 <= cst; end
                    if (!same) wi <= wi + 11'd1;
                    if (ci + 11'd1 == nraw) begin stat <= S_DONE; rdy_tgl <= ~rdy_tgl; n_ent <= same ? wi : wi + 11'd1; end
                    else begin ci <= ci + 11'd1; cs <= 4'd0; end
                end
                default: cs <= 4'd0;
            endcase
            default: ;
            endcase
        end
    end
endmodule

// =============================================================
// wav_store (clk50): 波形コピーの圧縮・展開と EEPROM との受け渡し (2026-11-13、2 段目)
//   wav_rec の変換した項目 (cv、cap_clk で書く) を再生の頭から 1 ラインずつ見て、cm (16 ビット x 1024 語) に圧縮する:
//     見出し   {1, 0000, ライン数 11}: 同じ形のラインがいくつ続くか。そのあとに組の最初のラインの変わり目を並べる
//     変わり目 {0, ドット 12, 0, VS, HS} (変わり目のあとのレベル)
//   同じ形 = 変わり目の数とレベルが同じで、どの変わり目もドットの差が ±1 以内 (サンプルの丸めで 1 ドット揺れても
//   まとめる。ドットは組の最初のラインの値。ずれが積み重ならないように、いつも組の最初のラインと比べる)
//   圧縮したら cm を展開して wav_play のメモリ (pm) へ書く ({ライン, ドット, レベル}、頭の項目は 0)。
//   再生はいつも cm から作る (EEPROM に保存したものと同じ絵になる)
//   EEPROM (preset_store) は cm を直接読み書きする (SAVE は cm を読む。LOAD は cm に書いてから展開だけ)
//   stat: wav_rec の状態をそのまま見せる (RAW REC で SEL したあと) か、自分の状態
//         (3 圧縮・展開・読み出し中 / 4 済み / 5 FULL (cm や pm に入らない) / 0 なし (読み出しの失敗))
// =============================================================
module wav_store (
    input  wire        clk,
    input  wire        rst,
    input  wire        rec_tgl,         // settings の RAW REC (反転、同じ clk): ここから wav_rec の状態を見せる
    input  wire [2:0]  r_stat,          // wav_rec の状態 (clk に同期化済み)
    input  wire        r_rdy_tgl,       // wav_rec の済み (反転、cap_clk)
    input  wire [10:0] r_ent, r_s0,     // wav_rec の結果 (済みのあとは変わらない)
    input  wire [1:0]  r_lv0,
    input  wire [11:0] r_lines,
    // wav_rec の変換した項目 (cap_clk)
    input  wire        wclk,
    input  wire        cw_en,
    input  wire [10:0] cw_addr,
    input  wire [24:0] cw_data,
    // preset_store (EEPROM)
    input  wire        ld_beg,          // RAW LOAD を始めた (1 クロック)
    input  wire        ld_ok,           // 読み出しが済んだ (1 クロック): ld_* で展開する
    input  wire        ld_err,          // 読み出しの失敗 (1 クロック)
    input  wire [10:0] ld_nw,
    input  wire [11:0] ld_lines,
    input  wire [1:0]  ld_lv0,
    input  wire [7:0]  e_addr,          // 読む番地 (1 クロック遅れの e_q)
    output wire [15:0] e_q,
    input  wire        e_we,
    input  wire [7:0]  e_waddr,
    input  wire [15:0] e_wd,
    // 状態と結果
    output wire [2:0]  stat,
    output reg  [11:0] n_lines,
    output reg  [10:0] n_words,         // cm の語数
    output reg  [1:0]  lv0,             // 頭のレベル {VS, HS}
    // wav_play へ (pw_* は clk で書く)
    output reg         p_rdy_tgl,
    output reg  [10:0] p_ent,
    output reg         pw_en,
    output reg  [10:0] pw_addr,
    output reg  [24:0] pw_data
);
    reg  [24:0] cv [0:2047];
    always @(posedge wclk) if (cw_en) cv[cw_addr] <= cw_data;
    reg  [10:0] ci;                     // cv の番地 (= 見ている項目)
    reg  [24:0] cq;
    always @(posedge clk) cq <= cv[ci];

    localparam W_IDLE = 4'd0, W_C0 = 4'd1, W_C1 = 4'd2, W_C2 = 4'd3, W_K1 = 4'd4, W_K2 = 4'd5,
               W_D0 = 4'd6, W_D1 = 4'd7, W_D2 = 4'd8, W_D3 = 4'd9, W_D4 = 4'd10, W_LD = 4'd11;
    reg  [3:0]  ws;
    reg         own, rt_d;
    reg  [2:0]  os;
    assign stat = own ? os : (r_stat == 3'd4) ? 3'd3 : r_stat;   // wav_rec の済みは、こちらの圧縮・展開が済むまで CONV
    wire        busy = (ws != W_IDLE) && (ws != W_LD);

    reg  [15:0] cm [0:1023];
    reg  [9:0]  ma;                     // cm の番地 (圧縮・展開)
    reg  [15:0] mq;
    reg         m_we;
    reg  [9:0]  m_wa;
    reg  [15:0] m_wd;
    wire        cm_we = m_we || e_we;
    wire [9:0]  cm_wa = m_we ? m_wa : {2'b00, e_waddr};
    wire [15:0] cm_wd = m_we ? m_wd : e_wd;
    always @(posedge clk) begin
        if (cm_we) cm[cm_wa] <= cm_wd;
        mq <= cm[busy ? ma : {2'b00, e_addr}];
    end
    assign e_q = mq;

    (* async_reg = "true" *) reg [2:0] rr;
    always @(posedge clk) rr <= {rr[1:0], r_rdy_tgl};
    wire        r_go = rr[2] ^ rr[1];

    reg  [10:0] nm1, nl, li, j, gm, gc, r, dk, l;
    reg  [9:0]  gs, hp, wp;
    reg         first;
    // 見ている項目が今のラインの変わり目 (項目の数は数えない。最後のラインの次は頭の項目 (ライン 0 側) に戻るので外れる。
    //   全部が 1 ラインのときは cm があふれて FULL で止まる。2026-11-14 容量削減)
    wire        inl = (cq[24:14] == l);
    wire [12:0] dd  = {1'b0, cq[13:2]} - {1'b0, mq[14:3]};
    wire        mt  = (cq[1:0] == mq[1:0]) && (dd == 13'd0 || dd == 13'd1 || dd == 13'h1FFF);   // 組の最初のラインと同じ (±1)
    wire [10:0] cin = (ci == nm1) ? 11'd0 : ci + 11'd1;
    always @(posedge clk) begin
        m_we <= 1'b0; pw_en <= 1'b0;
        rt_d <= rec_tgl;
        if (rst) begin
            ws <= W_IDLE; own <= 1'b0; os <= 3'd0; p_rdy_tgl <= 1'b0;
        end else begin
            if (rec_tgl != rt_d) own <= 1'b0;
            case (ws)
            W_IDLE: if (r_go) begin
                own <= 1'b1; os <= (r_ent == 11'd0) ? 3'd5 : 3'd3; nm1 <= r_ent - 11'd1; nl <= r_lines[10:0]; n_lines <= r_lines; lv0 <= r_lv0;
                ci <= r_s0; l <= 11'd0; first <= 1'b1; wp <= 10'd0; hp <= 10'd0; gs <= 10'd0; gc <= 11'd0; gm <= 11'd0;
                ws <= (r_ent == 11'd0) ? W_IDLE : W_C0;
            end else if (ld_beg) begin own <= 1'b1; os <= 3'd3; ws <= W_LD; end
            W_LD: if (ld_ok) begin
                n_words <= ld_nw; n_lines <= ld_lines; lv0 <= ld_lv0; ws <= W_D0;
            end else if (ld_err) begin os <= 3'd0; ws <= W_IDLE; end
            // ---- 圧縮: ライン l の頭 ----
            W_C0: if (l == nl) begin                                   // 終わり: 最後の組の見出しを書いて展開へ
                if (!first) begin m_we <= 1'b1; m_wa <= hp; m_wd <= {5'b10000, gc}; end
                n_words <= {1'b0, wp}; ws <= W_D0;
            end else begin li <= ci; j <= 11'd0; ma <= gs; ws <= W_C1; end
            W_C1: ws <= W_C2;                                          // cq / mq を待つ
            W_C2: if (inl && !first && j != gm && mt) begin            // ここまで組の最初のラインと同じ
                ci <= cin; j <= j + 11'd1; ma <= ma + 10'd1; ws <= W_C1;
            end else if (!inl && !first && j == gm) begin              // ラインが終わって全部同じ: 組を 1 ライン延ばす
                gc <= gc + 11'd1; l <= l + 11'd1; ws <= W_C0;
            end else if (wp == 10'h3FF) begin os <= 3'd5; ws <= W_IDLE; end
            else begin                                                 // 違う: 前の組の見出しを書き、このラインで新しい組
                if (!first) begin m_we <= 1'b1; m_wa <= hp; m_wd <= {5'b10000, gc}; end
                hp <= wp; wp <= wp + 10'd1; gs <= wp + 10'd1; gc <= 11'd1; gm <= 11'd0; first <= 1'b0;
                ci <= li; ws <= W_K1;
            end
            W_K1: ws <= W_K2;
            W_K2: if (inl) begin                                       // このラインの変わり目を書く
                if (wp == 10'h3FF) begin os <= 3'd5; ws <= W_IDLE; end
                else begin
                    m_we <= 1'b1; m_wa <= wp; m_wd <= {1'b0, cq[13:2], 1'b0, cq[1:0]};
                    wp <= wp + 10'd1; gm <= gm + 11'd1; ci <= cin; ws <= W_K1;
                end
            end else begin l <= l + 11'd1; ws <= W_C0; end
            // ---- 展開: cm → pm ----
            W_D0: if (n_words == 11'd0) begin os <= 3'd5; ws <= W_IDLE; end
                  else begin ma <= 10'd0; dk <= 11'd0; l <= 11'd0; ws <= W_D1; end
            W_D1: ws <= W_D2;
            W_D2: if (!mq[15]) begin os <= 3'd5; ws <= W_IDLE; end     // 見出しでない (壊れている)
                  else begin r <= mq[10:0]; gs <= ma + 10'd1; ma <= ma + 10'd1; ws <= W_D3; end
            W_D3: ws <= W_D4;
            W_D4: if ({1'b0, ma} != n_words && !mq[15]) begin              // 変わり目
                if (dk == 11'h7FF) begin os <= 3'd5; ws <= W_IDLE; end
                else begin
                    pw_en <= 1'b1; pw_addr <= dk; pw_data <= {l, mq[14:3], mq[1:0]};
                    dk <= dk + 11'd1; ma <= ma + 10'd1; ws <= W_D3;
                end
            end else begin                                             // ラインの終わり
                l <= l + 11'd1;
                if (r > 11'd1) begin r <= r - 11'd1; ma <= gs; ws <= W_D3; end           // 同じ組の次のライン (r = 残りのライン数)
                else if ({1'b0, ma} == n_words) begin                                         // 全部済み
                    p_ent <= dk; p_rdy_tgl <= ~p_rdy_tgl; os <= (dk == 11'd0) ? 3'd5 : 3'd4; ws <= W_IDLE;
                end else ws <= W_D2;                                                      // mq は次の組の見出し
            end
            default: ws <= W_IDLE;
            endcase
        end
    end
endmodule

// =============================================================
// wav_play (dot_clk): wav_rec の記録をジェネレータのライン・ドットに合わせて繰り返し出す
//   ジェネレータ (vga_timing) は COPY で入力と同じ H / V の合計になっている前提。
//   記録のライン 0 の頭 = ジェネレータのライン vs_s - 1 の H の同期の始まり (vga_timing の VSYNC と同じ位置)。
//   そこから H の同期の始まりごとにライン gn を進め、ドット kn を数え、項目 (ライン, ドット) に来たらレベルを変える。
//   kn / gn は「次の画素」の値 (出力はレジスタで 1 クロック遅れるので、x = hs_s + ドット の画素でちょうど変わる)。
//   項目は 2 つ先まで持つ (e0 / e1) ので、1 ドットおきの変わり目にも間に合う。番地は使ったかどうかで先に選ぶ。
//   フレームの頭で項目の番号が 0 (頭) でなければ (ライン数が合わないなど) 読み直す
// =============================================================
module wav_play (
    input  wire        dclk,
    input  wire        en,              // 再生する (別のクロックから)
    input  wire        rdy_tgl,         // wav_rec の済み (反転、別のクロック)
    input  wire [10:0] n_ent,           // wav_store の結果 (済みのあとは変わらない)
    input  wire [1:0]  lv0,
    input  wire [11:0] x, y,            // vga_timing の座標 (hsync_o と同じ時刻)
    input  wire [11:0] hs_s, vs_s,      // vga_timing: H の同期の始まり (表示 + FP)、垂直同期の始まりのライン (表示 + FP)
    input  wire        il,              // インターレース (y = {フィールドのライン, フィールド}。頭はフィールド 0 だけ)
    // wav_rec からの書き込み (cap_clk)
    input  wire        wclk,
    input  wire        pw_en,
    input  wire [10:0] pw_addr,
    input  wire [24:0] pw_data,
    output reg         act,             // 再生中 (1 なら hs_lv / vs_lv をピンへ)
    output reg         hs_lv, vs_lv     // 正論理 (1 = 同期中)
);
    reg  [24:0] pm [0:2047];
    always @(posedge wclk) if (pw_en) pm[pw_addr] <= pw_data;
    reg  [10:0] ra;
    reg  [24:0] q;
    always @(posedge dclk) q <= pm[ra];

    (* async_reg = "true" *) reg [1:0] en_s;
    (* async_reg = "true" *) reg [2:0] rd_s;
    always @(posedge dclk) begin en_s <= {en_s[0], en}; rd_s <= {rd_s[1:0], rdy_tgl}; end
    reg         rdy = 1'b0;             // 済みの記録がある (反転を見たら)
    reg  [10:0] nm1;
    reg  [1:0]  slv;
    reg  [11:0] hs2, vs1;               // vs1: 頭のライン (インターレースは y の形 {vs_s - 1, 0} で比べる)
    always @(posedge dclk) begin
        if (rd_s[2] ^ rd_s[1]) begin rdy <= 1'b1; nm1 <= n_ent - 11'd1; slv <= lv0; end
        hs2 <= hs_s - 12'd2;
        vs1 <= il ? {vs_s[10:0] - 11'd1, 1'b0} : vs_s - 12'd1;
    end

    // 頭の項目は番地 0 (wav_store が展開するとき 0 から書く)
    localparam P_OFF = 3'd0, P_L0 = 3'd1, P_L1 = 3'd2, P_L2 = 3'd3, P_WAIT = 3'd4, P_RUN = 3'd5;
    reg  [2:0]  ps = P_OFF;
    reg  [11:0] kn;
    reg  [10:0] gn;
    reg  [10:0] p1, p2, p3;             // e1 の次 / その次 / その次 の番地
    reg         z0;                     // e0 は番地 0 (頭の項目)
    reg  [24:0] e0, e1;
    wire        lp   = (x == hs2);                        // 次の画素で H の同期が始まる (次の次でなく、kn / gn を次のクロックで 0 にする)
    wire        fp   = lp && (y == vs1);                  // 記録のライン 0 の頭
    wire        hit  = (ps == P_RUN) && (e0[24:14] == gn) && (e0[13:2] == kn);
    // 番地を 1 つ進める足し算は 1 つを使い回す (2026-11-14 容量削減)
    wire [10:0] ii   = (ps == P_L0) ? 11'd0 : (ps == P_L1) ? p1 : (ps == P_L2) ? p2 : p3;
    wire [10:0] io   = (ii == nm1) ? 11'd0 : ii + 11'd1;
    always @(*) begin
        case (ps)
        P_L0:    ra = 11'd0;
        P_L1:    ra = p1;
        default: ra = hit ? p3 : p2;
        endcase
    end
    always @(posedge dclk) begin
        kn <= lp ? 12'd0 : kn + 12'd1;
        if (lp) gn <= (y == vs1) ? 11'd0 : gn + 11'd1;
        if (!en_s[1] || !rdy) begin ps <= P_OFF; act <= 1'b0; end
        else case (ps)
        P_OFF:  ps <= P_L0;
        P_L0:   begin p1 <= io; z0 <= 1'b1; ps <= P_L1; end                        // 番地 0
        P_L1:   begin e0 <= q; p2 <= io; ps <= P_L2; end                            // 番地 1 (q は 0)
        P_L2:   begin e1 <= q; p3 <= io; ps <= P_WAIT; end                          // q は 1、以後の番地は p2
        P_WAIT: if (fp) begin ps <= P_RUN; act <= 1'b1; {vs_lv, hs_lv} <= slv; end
        P_RUN: begin
            if (hit) begin
                {vs_lv, hs_lv} <= e0[1:0];                         // 項目は変わり目のあとの両方のレベル
                e0 <= e1; e1 <= q; z0 <= (p1 == 11'd0); p1 <= p2; p2 <= p3; p3 <= io;
            end
            if (fp && !(hit ? (p1 == 11'd0) : z0)) begin ps <= P_L0; act <= 1'b0; end   // ずれた: 読み直す
        end
        default: ps <= P_OFF;
        endcase
    end
endmodule
