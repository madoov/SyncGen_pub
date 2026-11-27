// =============================================================
// VGA タイミング生成 (ドットクロック・各期間をすべて可変)
//
//   1ラインの構成 (ドット数):  [表示 h_active][FP h_fp][同期 h_sync][BP h_bp]
//   1フレームの構成 (ライン数): [表示 v_active][FP v_fp][同期 v_sync][BP v_bp]
//
//   設定値 cfg_* は 50MHz 側など別のクロックで書き換えてよい。
//   書き換え後に cfg_toggle を反転させると、次のフレームの区切りで
//   まとめて反映される (画面の途中でタイミングが崩れない)。
//   ※ cfg_toggle を反転させてから反映されるまでの間 (最大1フレーム)、
//     cfg_* を変えないこと。
//
//   同期出力:
//     cfg_hs_neg / cfg_vs_neg : 1 で負極性 (同期期間が Low)
//     cfg_csync = 0 : HSYNC / VSYNC を別々に出力
//                 1 : 複合同期 (H と V の OR) を hsync_o に出力
//                 2 : 複合同期 (H と V の XOR) を hsync_o に出力
//                     (垂直同期中も水平パルスが残るのでモニタが同期を保ちやすい)
//     複合同期の極性は cfg_hs_neg に従う
//     複合同期 (cfg_csync = 1〜3) のとき VSYNC のピンは動かさない (同期なしのレベル = cfg_vs_neg)。元の機器は CSYNC だけで、
//       受ける側は VSYNC が動いていると H / V 別々と判断して CSYNC を H 同期として数えることがあるため (2026-11-12)
//     cfg_csync = 3 : 複合同期 EQ (2026-11-12): 等化パルス・切れ込みの入った放送の形 (プログレッシブ・インターレースとも)
//       (V9958 のダイから起こした IKA9958 の CSYNC の回路が、IL によらずこの形。V9938 のデータブックの
//        IL は「interlace (Complete NTSC timing)」。XOR のインターレースは VS OFS = 0 だと
//        フィールドの間隔がずれ、スキャンコンバータによっては取り違える)。半ライン間隔で、等化パルス (同期幅の半分) 6 個
//       → 広いパルス (半ライン - 同期幅、間の切れ込みは同期幅) 2 × V SYNC 個 → 等化パルス 6 個
//       (TV OUT が PAL / PAL-N なら 5 / 2 × V SYNC - 1 / 5)。広いパルスの始まりは VSYNC のピン (VS OFS = 0) と同じ
//       位置 (フィールド 0 はライン vs_s - 1 の H の同期の始まり、フィールド 1 はその半ライン前)。VS OFS の欄は下の EQ の形の設定。
//       プログレッシブでは fld = 0 のまま同じ計算 (広いパルスはライン vs_s - 1 の H の同期の始まりから)。OR / XOR は今までどおり
//       EQ の形 (2026-11-13): EQ のときは cfg_vs_ofs を VSYNC の位置ではなく形の設定に使う (VSYNC のピンは止まっていて VS OFS は効かないため)
//         bit11    = 半ラインずらす (プログレッシブで毎フィールド「奇数フィールド」の形。タイトー F3 などの odd-odd field。インターレースでは効かない)
//         bit10:8  = 等化パルスの幅 k/8 × 同期幅 の (k - 1) ^ 3 (0 = 4/8 = 今までの同期幅の半分。切り捨て、最低 1 ドット)
//         bit7:5   = 切れ込みの幅 m/8 × 同期幅 の (m - 1) ^ 7 (0 = 8/8 = 今までの同期幅。広いパルス = 半ライン - 切れ込み。最低 1 ドット)
//         bit4     = 等化パルスの数 (0 = 6 個、1 = 7 個。625 ライン系のテレビ出力のときは 5 個のまま)
//         0 が今までの形 (NTSC)。F3 は bit11 + k = 4 + m = 4 + 7 個 = 12'b1_000_100_1_0000 (0x890)
//     VSYNC の切り替わる位置 (cfg_vs_ofs、2026-11-05 追加。メニューの VS OFS):
//       H の同期の始まりから cfg_vs_ofs ドット後 (0〜H 合計 - 1。大きければ H 合計 - 1 に止める)。
//       0 = H の同期の始まり (初期値)。H 同期幅 + BP = ラインの頭 (表示の始まり。MC6845 系の CRTC の形)。
//       PC-8801FA の実測は 168 ドット (表示の始まりより 3 文字前)
//     0 のとき:
//       垂直同期はライン vs_s - 1 の H の同期の始まりから、ライン vs_e - 1 の H の同期の始まりまで。
//       H の同期で区切ったライン (モニタから見たライン) で数えると、表示のないライン FP 本 → 同期 SYNC 本 → BP 本
//       と設定どおりになる (実機の CRTC と同じ形。XOR の複合同期では、垂直同期の始まりと終わりの H パルスが VSYNC と重なる)
//
//   インターレース (cfg_interlace = 1、2026-10-23 追加):
//     V ACTIVE はフレームのライン数 (480 / 576 など)、V FP / SYNC / BP はフィールドのライン数。
//     フィールド 0 は偶数ライン (y = 0, 2, 4 …)、フィールド 1 は奇数ライン (y = 1, 3, 5 …) を出す。
//     fl = (V ACTIVE + 1) / 2 + FP + SYNC + BP として、フィールド 0 は fl + 1 ライン、フィールド 1 は fl ライン
//     (フレームは 2fl + 1 ライン。例: 240 + 3 + 3 + 16 = 262 → 525)。
//     フィールド 1 の垂直同期は、フィールド 0 (H の同期の始まり) から半ラインずれた位置で始まり、終わる
//     (同期の間隔がどちらのフィールドも fl + 0.5 ラインになり、テレビ・モニタはインターレースとして映す)。
//     設定の反映はフィールド 1 の終わり (次はフィールド 0 から)。
//
//   テレビ出力 (tv_encoder) へは、ラインごとに 2 か所の同期の種類を渡す:
//     slot_a = ラインの途中 M (H の同期の始まり - ht/2) から半ライン、slot_b = H の同期の始まり S から半ライン
//     slot_a: 0 なし / 2 等化パルス (同期幅の半分) / 3 広いパルス (半ライン - 同期幅)
//     slot_b: 1 H の同期 / 2 等化パルス / 3 広いパルス (半ライン) / 4 広いパルス (1 ライン、プログレッシブの垂直同期)
//     インターレースでは垂直同期 (2 × V SYNC 個の広いパルス) の前後に 6 個ずつ等化パルスを入れる
//     (525 ライン系)。625 ライン系 (cfg_l625 = 1、PAL / PAL-N) は広いパルス 2 × V SYNC - 1 個・等化パルス 5 個ずつ
//     (V SYNC = 3 で 5 / 5 / 5 = 2.5 ラインずつ、ITU-R BT.470 のとおり。2026-10-25 修正)
//     (表示のあるラインの途中には入れない)。プログレッシブは今までどおり (等化パルスなし、垂直同期は 1 ラインの長いパルス)
// =============================================================
module vga_timing (
    input  wire        dclk,          // ドットクロック (Si5351A → CLK0 ピン)
    input  wire        rst_n,         // 非同期リセット (内部で同期化)

    input  wire [11:0] cfg_h_active, cfg_h_fp, cfg_h_sync, cfg_h_bp,
    input  wire [11:0] cfg_v_active, cfg_v_fp, cfg_v_sync, cfg_v_bp,
    input  wire        cfg_hs_neg,
    input  wire        cfg_vs_neg,
    input  wire [1:0]  cfg_csync,
    input  wire        cfg_interlace, // 1 = インターレース
    input  wire [11:0] cfg_vs_ofs,    // VSYNC の切り替え位置: H の同期の始まりから何ドット後か
    input  wire        cfg_l625,      // 1 = テレビ出力が 625 ライン系 (PAL / PAL-N): 等化パルス 5・広いパルス 2 × V SYNC - 1
    input  wire        cfg_toggle,
    input  wire        out_en,        // 0 の間は RGB 黒・同期信号なし (別クロックから入れてよい)

    output reg         hsync_o,       // ピンへ (HSYNC または CSYNC)
    output reg         vsync_o,       // ピンへ
    output reg         de,            // 表示期間
    output reg  [11:0] x,             // 表示期間内の座標
    output reg  [11:0] y,
    output reg         frame_start,   // フレーム先頭 (x=0,y=0) で1クロック
    output wire [11:0] h_active,      // 現在使っている表示ドット数 (パターン生成用)
    output wire [11:0] v_active,
    output wire [11:0] v_total_m1,    // 総ライン数 - 1 (vga_pattern の円の先読み用)
    output reg         line_tgl,      // 1ラインごとに反転 (水平周波数の測定用)
    output reg         frame_tgl,     // 1フレームごとに反転 (垂直周波数の測定用)
    // テレビ出力 (tv_encoder) 用
    output wire [11:0] h_sync_s,      // 表示の始まりから同期の始まりまで (表示 + FP)
    output wire [11:0] h_sync_e,      // 表示の始まりから同期の終わりまで (表示 + FP + 同期)
    output reg         vs_line,       // このラインは垂直同期 (正論理。x / y / de と同じ遅れ)
    output reg         out_on,        // 出力中 (out_en を受け取った値。x / y / de と同じ遅れ)
    output reg  [1:0]  slot_a,        // ラインの途中の同期の種類 (上の表。x / y / de と同じ遅れ)
    output reg  [2:0]  slot_b,        // H の同期の位置の同期の種類
    output wire [11:0] h_mid,         // 表示の始まりから M まで (H の同期の始まり - ht/2)
    output wire [11:0] h_total,       // H 合計 (確定値から。波形コピーの wav_rec が使う、2026-11-14)
    output wire [11:0] v_sync_s,      // 垂直同期の始まりのライン (表示 + FP。波形コピーの再生 wav_play 用、2026-11-13)
    output wire        interlace      // 今使っている設定がインターレース (vga_pattern 用)
);
    // ---------- リセット同期化 ----------
    reg [1:0] rs;
    always @(posedge dclk or negedge rst_n)
        if (!rst_n) rs <= 2'b11; else rs <= {rs[0], 1'b0};
    wire rst = rs[1];

    // ---------- 設定の受け取り ----------
    (* async_reg = "true" *) reg [2:0] tg;
    always @(posedge dclk) tg <= {tg[1:0], cfg_toggle};
    (* async_reg = "true" *) reg [1:0] oe_s;
    always @(posedge dclk) oe_s <= {oe_s[0], out_en};
    wire oe = oe_s[1];
    wire tg_edge = tg[2] ^ tg[1];

    reg [11:0] ha, hs_s, hs_e, ht, va, vs_s, vs_e, vt;
    reg [11:0] ht_m1, vt_m1;     // ht-1 / vt-1 (カウンタの比較で毎クロック引き算しないように)
    reg [11:0] vt0_m1;           // フィールド 0 の最後のライン (インターレースは vt、プログレッシブは vt - 1)
    reg        il;               // インターレース
    reg        l625;             // 625 ライン系 (等化パルス 5 個)
    reg        fld;              // 今のフィールド (プログレッシブは 0)
    reg        hneg, vneg;
    reg [11:0] vofs;             // VSYNC の切り替え位置 (H の同期の始まりからのドット数)
    reg [1:0]  cs;
    reg        pending;

    assign h_active = ha;
    assign v_active = va;
    assign h_sync_s = hs_s;
    assign h_sync_e = hs_e;
    assign interlace = il;
    assign h_total = ht;

    // インターレースではフィールドの表示ライン数 (V ACTIVE + 1) / 2 で、FP 以降を数える
    wire [11:0] c_vah = cfg_interlace ? ((cfg_v_active + 12'd1) >> 1) : cfg_v_active;

    task load_cfg;
        begin
            ha   <= cfg_h_active;
            hs_s <= cfg_h_active + cfg_h_fp;
            hs_e <= cfg_h_active + cfg_h_fp + cfg_h_sync;
            ht   <= cfg_h_active + cfg_h_fp + cfg_h_sync + cfg_h_bp;
            ht_m1 <= cfg_h_active + cfg_h_fp + cfg_h_sync + cfg_h_bp - 12'd1;
            va   <= cfg_v_active;
            vs_s <= c_vah + cfg_v_fp;
            vs_e <= c_vah + cfg_v_fp + cfg_v_sync;
            vt   <= c_vah + cfg_v_fp + cfg_v_sync + cfg_v_bp;
            vt_m1 <= c_vah + cfg_v_fp + cfg_v_sync + cfg_v_bp - 12'd1;
            vt0_m1 <= c_vah + cfg_v_fp + cfg_v_sync + cfg_v_bp - (cfg_interlace ? 12'd0 : 12'd1);
            il   <= cfg_interlace;
            l625 <= cfg_l625;
            hneg <= cfg_hs_neg;
            vneg <= cfg_vs_neg;
            vofs <= cfg_vs_ofs;
            cs   <= cfg_csync;
        end
    endtask

    // ---------- カウンタ ----------
    reg [11:0] hc, vc;
    reg [11:0] vlast;            // 今のフィールドの最後のライン (fld から。毎クロックレジスタに)
    always @(posedge dclk) vlast <= fld ? vt_m1 : vt0_m1;
    wire h_end = (hc == ht_m1);
    wire v_end = (vc == vlast);
    assign v_total_m1 = vlast;

    always @(posedge dclk) begin
        if (rst) begin
            hc <= 12'd0;
            vc <= 12'd0;
            line_tgl  <= 1'b0;
            frame_tgl <= 1'b0;
            pending <= 1'b0;
            fld <= 1'b0;
            load_cfg;
        end else begin
            if (tg_edge) pending <= 1'b1;
            if (h_end) begin
                hc <= 12'd0;
                line_tgl <= ~line_tgl;
                if (v_end) begin
                    vc <= 12'd0;
                    frame_tgl <= ~frame_tgl;          // フィールドごと (垂直周波数の測定)
                    fld <= il && !fld;
                    if ((pending || tg_edge) && (!il || fld)) begin   // フレームの区切りで反映
                        load_cfg;
                        pending <= 1'b0;
                        fld <= 1'b0;
                    end
                end else
                    vc <= vc + 12'd1;
            end else
                hc <= hc + 12'd1;
        end
    end

    // ---------- めったに変わらない比較値 (レジスタ) ----------
    reg [11:0] hq, vsa_m1, vse_m1, mpos, mpe;   // mpe: EQ の M の位置 (下の mlate)
    reg        mlate;
    reg [12:0] mw;
    // VSYNC: フィールド 0 はライン l0s の p0s から、ライン l0e の p0s まで。フィールド 1 は半ライン前 (l1s / l1e / p1s)
    //   p0 = hs_s + ofs (ライン vs_s - 1 の頭から数えた位置。H 合計以上なら次のライン vs_s)
    //   フィールド 1 は p0 - ht/2 (負にならないよう p0 + hq をライン vs_s - 2 の頭から数える)
    //   めったに変わらない値なので段ごとにレジスタで区切る (cfg の反映はフレームの区切り。数クロックで落ち着く)
    reg [11:0] ofsc, vsa_m2, vse_m2, p0s, p1s, l0s, l0e, l1s, l1e;
    reg [12:0] p0, ht2;
    reg [13:0] q1;
    wire        eqm = (cs == 2'd3);           // 複合同期 EQ (vofs は形の設定)
    wire [12:0] neq = l625 ? 13'd5 : (eqm && vofs[4]) ? 13'd7 : 13'd6;   // 等化パルスの数 (前後それぞれ)
    reg [12:0] b0, b1, e0, e1;   // 半ラインの番号での広いパルスの範囲 [b0, b1) と等化パルスの範囲 [e0, b0)・[b1, e1)
    reg [11:0] hsw, w_eq, w_br;   // 複合同期 EQ: H の同期幅・等化パルス・広いパルスの幅
    always @(posedge dclk) begin
        hsw    <= hs_e - hs_s;
        w_eq   <= p_eq;                                  // 同期幅 × k/8 (最低 1 ドット。H SYNC = 1 で 0 にしない)
        w_br   <= ({1'b0, ht[11:1]} > p_br) ? {1'b0, ht[11:1]} - p_br : 12'd1;   // 半ライン - 切れ込み (同期幅 × m/8)
        hq     <= ht - {1'b0, ht[11:1]};                  // フィールド 1 の垂直同期の切り替わり (ラインの途中)
        vsa_m1 <= vs_s - 12'd1;
        vse_m1 <= vs_e - 12'd1;
        mpos   <= (hs_s >= {1'b0, ht[11:1]}) ? hs_s - {1'b0, ht[11:1]} : 12'd0;   // テレビ出力 (h_mid) 用は今までどおり
        mlate  <= (hs_s <= {1'b0, ht[11:1]});
        mw     <= {1'b0, hs_s} + {1'b0, hq};                  // mlate のときの M (ht ちょうどなら次のラインの 0)
        mpe    <= mlate ? ((mw == {1'b0, ht}) ? 12'd0 : mw[11:0]) : mpos;
        vsa_m2 <= vs_s - 12'd2;
        vse_m2 <= vs_e - 12'd2;
        ht2    <= {ht, 1'b0};
        ofsc   <= eqm ? 12'd0 : (vofs >= ht) ? ht_m1 : vofs;   // EQ では vofs は形の設定 (VSYNC は動かさない)
        p0     <= {1'b0, hs_s} + {1'b0, ofsc};
        q1     <= {1'b0, p0} + {2'b00, hq};
        if (p0 >= {1'b0, ht}) begin l0s <= vs_s;   l0e <= vs_e;   p0s <= p0[11:0] - ht; end
        else                  begin l0s <= vsa_m1; l0e <= vse_m1; p0s <= p0[11:0]; end
        if (q1 >= {1'b0, ht2})     begin l1s <= vs_s;   l1e <= vs_e;   p1s <= q1[11:0] - {ht[10:0], 1'b0}; end
        else if (q1 >= {2'b00, ht}) begin l1s <= vsa_m1; l1e <= vse_m1; p1s <= q1[11:0] - ht; end
        else                       begin l1s <= vsa_m2; l1e <= vse_m2; p1s <= q1[11:0]; end
        b0     <= {vs_s, 1'b1};
        b1     <= l625 ? {vs_e, 1'b0} : {vs_e, 1'b1};
        e0     <= ({vs_s, 1'b1} >= neq) ? {vs_s, 1'b1} - neq : 13'd0;
        e1     <= (l625 ? {vs_e, 1'b0} : {vs_e, 1'b1}) + neq;
    end
    assign h_mid = mpos;
    assign v_sync_s = vs_s;
    // EQ の等化パルス・切れ込みの幅 = 同期幅 × k/8・× m/8 (k, m = 1〜8)。めったに変わらない値なので、
    //   足し算 1 つを 16 クロックで使い回して同期幅を k 回・m 回足す (前半 8 クロックが k、後半が m。掛け算を 1 クロックで書かない)
    reg  [3:0]  ph, kq, mq;
    reg  [14:0] acc;
    reg  [11:0] p_eq, p_br;
    wire [3:0]  kk = ph[3] ? mq : kq;
    always @(posedge dclk) begin
        kq  <= {1'b0, vofs[10:8] ^ 3'd3} + 4'd1;
        mq  <= {1'b0, vofs[7:5]  ^ 3'd7} + 4'd1;
        ph  <= rst ? 4'd0 : ph + 4'd1;
        acc <= ((ph[2:0] == 3'd0) ? 15'd0 : acc) + (({1'b0, ph[2:0]} < kk) ? {3'd0, hsw} : 15'd0);
        if (ph[2:0] == 3'd0) begin
            // どちらも最低 1 ドット (H SYNC が短いと 0 になる。切れ込み 0 では広いパルスがつながってしまう)
            if (ph[3]) p_eq <= (acc[14:3] == 12'd0) ? 12'd1 : acc[14:3];   // 前半 (k) の結果
            else       p_br <= (acc[14:3] == 12'd0) ? 12'd1 : acc[14:3];   // 後半 (m) の結果
        end
    end

    // ---------- 出力 (すべてレジスタ出力) ----------
    wire hs_a = oe && (hc >= hs_s) && (hc < hs_e);     // 正論理の同期期間 (停止中は出さない)
    wire vs_p = (vc >= vs_s) && (vc < vs_e);         // ライン単位 (ラインの頭で切り替え。テレビ出力の slot_b もこれ)
    // VGA の VSYNC (H の同期の始まり + VS OFS で切り替え。フィールド 1 は半ライン前)
    wire vs_0 = ((vc == l0s) && (hc >= p0s)) || ((vc > l0s) && (vc < l0e)) || ((vc == l0e) && (hc < p0s));
    wire vs_i = ((vc == l1s) && (hc >= p1s)) || ((vc > l1s) && (vc < l1e)) || ((vc == l1e) && (hc < p1s));
    wire vs_a = oe && ((il && fld) ? vs_i : vs_0);
    // インターレースの同期の種類 (半ラインの番号 h = 2vc (M) / 2vc + 1 (S)。フィールド 1 は 1 つ先に数える)
    wire [12:0] h_a = {vc, 1'b0} + {12'd0, fld};
    wire [12:0] h_b = {vc, 1'b1} + {12'd0, fld};
    wire br_a = (h_a >= b0) && (h_a < b1);
    wire br_b = (h_b >= b0) && (h_b < b1);
    wire eq_a = ((h_a >= e0) && (h_a < b0)) || ((h_a >= b1) && (h_a < e1));
    wire eq_b = ((h_b >= e0) && (h_b < b0)) || ((h_b >= b1) && (h_b < e1));
    wire [12:0] ycalc = il ? {vc, fld} : {1'b0, vc};
    // 複合同期 EQ: 半ラインの番号を 2 つ (1 ライン) 先に数えて、広いパルスの始まりを VSYNC のピンにそろえる
    //   種類はラインの中で変わらないので毎クロックレジスタに (vc が変わるのは hc = 0、使うのは M と S の位置)
    //   比べる組は 1 つにして、M の位置の前は M の種類、M を過ぎたら S の種類を求める (2026-11-12、容量)
    reg         c_ms;             // 1 = M を過ぎた (次に使うのは S の種類)
    wire        fo   = il ? fld : (eqm && vofs[11]);   // プログレッシブで半ラインずらす (EQ の形 bit11)
    wire [12:0] hv   = {vc, c_ms} + {11'd0, mlate && !c_ms, 1'b0} + {12'd0, fo} + 13'd2;
    wire        c_br = (hv >= b0) && (hv < b1);
    wire        c_eq = ((hv >= e0) && (hv < b0)) || ((hv >= b1) && (hv < e1));
    reg  [1:0]  ct_a, ct_b;       // 0 なし (M のみ) / 1 H の同期 (S のみ) / 2 等化パルス / 3 広いパルス
    //   H の同期の始まりが半ライン以前 (hs_s <= ht/2) なら、M (hs_s - ht/2) は前のラインの S の後ろ hs_s + ht - ht/2 に来る
    //   (mlate。2026-11-13 修正: 以前は M を 0 に止めていて半ライン間隔にならなかった)。そのラインの M は次のライン (2vc + 2) の分。
    //   M の種類は S から M まで、S の種類はそれ以外で求める。hs_s = ht/2 ちょうどなら M は次のラインの頭 (hc = 0)
    always @(posedge dclk) begin
        c_ms <= mlate ? !((hc >= hs_s) && ({1'b0, hc} < mw)) : (hc >= mpe);
        if (!c_ms) ct_a <= c_br ? 2'd3 : (c_eq && (ycalc >= {1'b0, va})) ? 2'd2 : 2'd0;
        else       ct_b <= c_br ? 2'd3 : c_eq ? 2'd2 : 2'd1;
    end
    wire        st_m = (hc == mpe) && (ct_a != 2'd0);
    wire        st_s = (hc == hs_s);
    wire [1:0]  ct   = st_s ? ct_b : ct_a;
    wire [11:0] cw   = (ct == 2'd3) ? w_br : (ct == 2'd2) ? w_eq : hsw;
    reg  [11:0] ccnt;             // パルスの残り
    always @(posedge dclk)
        if (rst)                ccnt <= 12'd0;
        else if (st_s || st_m)  ccnt <= (cw == 12'd0) ? 12'd0 : cw - 12'd1;   // 幅 0 で 4095 にあふれないように
        else if (ccnt != 12'd0) ccnt <= ccnt - 12'd1;
    wire c_il = oe && (st_s || st_m || (ccnt != 12'd0));
    wire c_a  = (cs == 2'd3) ? c_il : (cs == 2'd2) ? (hs_a ^ vs_a) : (hs_a | vs_a);

    always @(posedge dclk) begin
        if (rst) begin
            hsync_o <= 1'b0; vsync_o <= 1'b0; de <= 1'b0;
            x <= 12'd0; y <= 12'd0; frame_start <= 1'b0;
            vs_line <= 1'b0; out_on <= 1'b0; slot_a <= 2'd0; slot_b <= 3'd1;
        end else begin
            hsync_o     <= ((cs == 2'd0) ? hs_a : c_a) ^ hneg;
            vsync_o     <= (cs == 2'd0) ? (vs_a ^ vneg) : vneg;   // 複合同期 (OR / XOR / EQ) では VSYNC のピンは同期なしのレベルのまま (2026-11-12)
            de          <= oe && (hc < ha) && (ycalc < {1'b0, va});
            x           <= hc;
            y           <= ycalc[11:0];
            frame_start <= (hc == 12'd0) && (vc == 12'd0);
            vs_line     <= vs_a;
            out_on      <= oe;
            if (il) begin
                slot_a <= br_a ? 2'd3 : (eq_a && (ycalc >= {1'b0, va})) ? 2'd2 : 2'd0;   // 表示のあるラインの途中には入れない
                slot_b <= br_b ? 3'd3 : eq_b ? 3'd2 : 3'd1;
            end else begin
                slot_a <= 2'd0;
                slot_b <= vs_p ? 3'd4 : 3'd1;
            end
        end
    end
endmodule
