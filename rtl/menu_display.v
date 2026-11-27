// =============================================================
// 設定メニューの OLED 表示 (16文字 x 8行)
//   1行目     : STEP (いまの増減幅)
//   2〜8行目  : 項目 7個ぶん (選択中の項目に合わせて自動でスクロール)
//               選択中の項目はラベルが反転表示。値を変える状態 (edit) では値の欄が点滅 (反転 / 通常)
//               NAME の編集中は、編集している桁だけが点滅
// =============================================================
module menu_display #(
    parameter integer REFRESH = 2_500_000,     // 50ms ごとに書き直す
    parameter integer BLINK   = 8,             // 点滅の半周期 (書き直しの回数、8 回 = 0.4 秒)
    parameter         STR_FILE = "menu_str.hex"   // 項目名・選択肢の文字列 (tools/make_menu_rom.py)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [4:0]  mpos,             // カーソルの行の位置 (グループの中、2026-11-20 の階層メニューから)
    input  wire [4:0]  mcnt,             // グループの行の数
    input  wire        edit,             // 1 = 値を変える状態
    input  wire [26:0] step_val,
    output reg  [4:0]  rd_pos,           // 読む行の位置 → settings が項目 rd_code に (次のクロック)
    input  wire [5:0]  rd_code,          // bit5 = 1: 項目ではない階層メニューの行 ([1:0] = 0 BACK / 1〜3)
    input  wire [26:0] rd_val,
    input  wire [1:0]  rd_kind,
    input  wire        pending,          // 未確定の変更あり → 1行目に "*"
    input  wire [63:0] rd_text,          // kind 3 (文字列) の内容
    input  wire [3:0]  rd_cursor,        // kind 3 で反転する桁 (8 = なし)
    input  wire        rd_lock,          // 1 = TV OUT のため変更できない (選択肢は ----、数値はラベルを AUTO に)
    input  wire        rd_mv,            // 1 = 電圧 [mV、小数 2 桁] (例 "  767.25mV"。LOW SIG のときの LAG MIN / MAX)
    input  wire [1:0]  rd_q,             // キャプチャ: 推定した値の印 ? (2026-11-15)。[0] H (TOTAL の形の左、または 1 つの値)、[1] V
                                         //   TOTAL の形: H を 6〜9 桁目、10 桁目に ? / V を 12〜14 桁目、15 桁目に ?。数値 (kind 0): 7〜14 桁目、15 桁目に ?
    input  wire [1:0]  rd_auto,          // キャプチャの ACTIVE: H (7〜10 桁目) / V (12〜15 桁目) を AUTO と表示 (2026-11-15)
    input  wire        rd_ro,            // 1 = 変更できない項目 → 項目名の頭 (1 桁目) に "*"、項目名は 2 桁目から 7 文字 (2026-11-07)
    input  wire [3:0]  slot_no,          // "SLOT n" の n
    input  wire        cap,              // 1 = MODE がキャプチャ (No.27〜31 の項目名・選択肢を切り替える)
    input  wire        wav,              // 1 = MODE が CAP RAW (波形コピー。No.27〜31 を WAV の項目に。2026-11-13)
    output reg         wr_en,
    output reg  [6:0]  wr_addr,
    output wire [7:0]  wr_data,
    // 2 進 → 10 進の変換 (トップの bcd_share。done が来るまで cv_in を変えない)
    output reg         cv_start,
    output reg  [26:0] cv_in,
    input  wire [31:0] cv_bcd,
    input  wire        cv_done
);
    localparam N = 32;

    // ---- 文字列 ROM (2026-11-07: 項目名・選択肢の表を LUT からメモリブロックへ移した) ----
    //   rtl/menu_str.hex (tools/make_menu_rom.py で作る)。1 本 8 文字、アドレス = 番号 x 8 + 桁 (256 本、2026-11-07 に 128 本から)
    //   番号 0〜31 は項目名 (No.0〜31)。下の L_* / E_* は make_menu_rom.py の表と同じにする (スクリプトが照合する)
    //   項目名・選択肢を変えるときは make_menu_rom.py の表を直して hex を作り直す
    localparam integer NPRE = 42;   // 内蔵プリセットの数 (64 個まで。make_menu_rom.py が settings.v の NPRE と表の数を照合する)
    localparam [7:0] L_STEP = 8'd32, L_DOTA = 8'd33, L_VBPA = 8'd34, L_BLANK = 8'd35;
    localparam [7:0] E_POL = 8'd36, E_SYNC = 8'd38, E_SLV = 8'd42, E_SCAN = 8'd44, E_PAT = 8'd46,
                     E_PRE = 8'd56, E_TV = 8'd98, E_LOAD = 8'd111, E_SAVE = 8'd116, E_APPLY = 8'd121,
                     E_MODE = 8'd125, E_LRUN = 8'd132,
                     L_CAP = 8'd141, E_CRUN = 8'd146, E_COPY = 8'd159, E_CLASH = 8'd163,   // E_CLASH + 1 = TTL OK? (2026-11-17)
                     L_EQF = 8'd165,
                     L_WAV = 8'd166, E_WREC = 8'd171, E_WPLY = 8'd179,
                     E_CUST = 8'd181,
                     L_TOP = 8'd182;   // 階層メニューの行 (2026-11-20): +0 BACK / +1〜3 最初の画面、値の欄は +4〜7   // PRESET の (CUSTOM) (値 63、2026-11-18)   // 波形コピー (MODE = CAP RAW、2026-11-13)   // SYNC = EQ のときの No.14 の項目名 EQ FORM (2026-11-13)

    reg [7:0] srom [0:2047];
    initial $readmemh(STR_FILE, srom);
    reg [7:0] srom_q;

    // 選択肢の文字列の番号 (値の範囲外は今までどおりの既定の文字列に)
    function [7:0] enum_idx(input [4:0] i, input [5:0] v, input c, input w);   // v: プリセットは 6 ビット (64 個まで)
        case (i)
            5'd10, 5'd11: enum_idx = E_POL + v[0];
            5'd12: enum_idx = E_SYNC + {6'd0, v[1:0]};   // SEP / OR / XOR / EQ
            5'd13: enum_idx = E_SLV + v[0];
            5'd15: enum_idx = E_SCAN + v[0];
            5'd18: enum_idx = E_PAT + ((v[3:0] > 4'd9) ? 8'd9 : v[3:0]);
            5'd19: enum_idx = (v == 6'd63) ? E_CUST : E_PRE + ((v > NPRE - 1) ? 8'd0 : {2'd0, v});   // 63 = (CUSTOM) (settings の pmod)
            5'd20: enum_idx = E_TV + ((v[3:0] > 4'd12) ? 8'd0 : v[3:0]);
            5'd23: enum_idx = E_LOAD + ((v[3:0] > 4'd4) ? 8'd4 : v[3:0]);
            5'd24: enum_idx = E_SAVE + ((v[3:0] > 4'd4) ? 8'd4 : v[3:0]);
            5'd25: enum_idx = (v[3:0] == 4'd4) ? E_CLASH : (v[3:0] == 4'd5) ? E_CLASH + 8'd1 :   // 5 = TTL OK? (同期を TTL に上げる確かめ)
                              E_APPLY + ((v[3:0] == 4'd0) ? 8'd0 : (v[3:0] == 4'd1) ? 8'd1 :
                                         (v[3:0] == 4'd3) ? 8'd3 : 8'd2);
            5'd26: enum_idx = E_MODE + ((v[2:0] > 3'd6) ? 8'd0 : v[2:0]);
            5'd27: enum_idx = w ? E_WREC + v[2:0] :
                              c ? E_CRUN + ((v[3:0] > 4'd12) ? 8'd5 : v[3:0]) : E_LRUN + ((v[3:0] > 4'd8) ? 8'd8 : v[3:0]);
            5'd28: enum_idx = E_WPLY + v[0];                // CAP RAW のときだけ (ほかのモードでは選択肢でない)
            5'd30: enum_idx = E_SAVE + ((v[3:0] > 4'd4) ? 8'd4 : v[3:0]);   // CAP RAW の RAW SAVE のときだけ (ほかのモードでは選択肢でない)
            5'd31: enum_idx = w ? E_LOAD + ((v[3:0] > 4'd4) ? 8'd4 : v[3:0]) : E_COPY + v[1:0];
            default: enum_idx = L_BLANK;
        endcase
    endfunction

    // 変換
    // 2 進 → 10 進の変換はトップの bcd_share (menu_display と osd_text で共有、2026-11-13)

    localparam S_WAIT = 4'd0, S_LINE = 4'd1, S_READ = 4'd2, S_CONV = 4'd3, S_WR = 4'd4, S_STR = 4'd5, S_WA = 4'd6, S_M1 = 4'd7, S_M2 = 4'd8;
    reg [3:0]  st;
    reg [31:0] tmr;
    reg [4:0]  top;
    reg [2:0]  line;
    reg [3:0]  col;
    reg [4:0]  item;
    reg [4:0]  pos;                  // 行の位置
    reg        spc;                  // 階層メニューの行 (item[1:0] が番号)
    wire       lv = (line != 3'd0) && !spc;   // 項目の行 (印・変更不可などを見る)
    reg        blank, sel, lk, mv, cp, wv, rol;
    reg        hq, vq, ah, av;       // 推定の印 ? (H / V)、AUTO の表示 (H / V)
    reg        crn, crs;             // CAP RUN の RUN / DONE に推定の端数を添える、その符号 (1 = 負)
    reg        wrn;                  // RAW REC の DONE にライン数を添える ("525 DONE"、2026-11-20)
    wire [7:0] cr_a8  = rd_val[15] ? (~rd_val[15:8] + 8'd1) : rd_val[15:8];
    wire [6:0] cr_abs = (cr_a8 > 8'd99) ? 7'd99 : cr_a8[6:0];
    reg [1:0]  kind;
    reg [26:0] val;
    reg [63:0] txt;
    reg [3:0]  tcur;
    reg [31:0] bcd;
    reg        nz;
    reg  [7:0] wd;                   // 書き込む文字 (bit7 = 反転)
    reg        winv;                 // 値の欄の点滅で反転する
    reg  [4:0] bc;
    reg        blink;
    assign wr_data = {wd[7] | winv, wd[6:0]};

    // TV OUT の FIX で自動で決まる数値の項目はラベルを AUTO に
    //   キャプチャのときは No.27〜31 の項目名を L_CAP から
    wire [7:0]  lidx = blank ? L_BLANK : (line == 3'd0) ? L_STEP : spc ? L_TOP + {6'd0, item[1:0]} :
                       (lk && item == 5'd0) ? L_DOTA : (lk && item == 5'd9) ? L_VBPA :
                       (cp && item >= 5'd27) ? L_CAP + {3'd0, item} - 8'd27 :
                       (wv && item >= 5'd27) ? L_WAV + {3'd0, item} - 8'd27 :
                       (kind == 2'd3 && item == 5'd14) ? L_EQF : {3'd0, item};   // EQ FORM (settings が文字列で渡す)
    wire [7:0]  eidx = spc ? L_TOP + 8'd4 + {6'd0, item[1:0]} : enum_idx(item, val[5:0], cp, wv);
    // 文字列は書く桁ごとに ROM から直接読む (S_WA で番地を出し、S_WR で srom_q を使う。2026-11-14 容量削減。
    //   以前は 8 文字ずつ lab / es に読み込んで桁の番号で選んでいた)。変更できない項目は頭の "*" の分 1 桁ずらす
    wire [2:0]  li   = rol ? col[2:0] - 3'd1 : col[2:0];
    wire [10:0] sa   = col[3] ? {eidx, col[2:0]} : {lidx, li};
    always @(posedge clk) srom_q <= srom[sa];
    // SLOT の 6 文字目 (文字 5) はスロット番号
    wire        slot_d = (li == 3'd5) && (lidx == 8'd21);
    wire [7:0]  lch  = slot_d ? {4'h3, slot_no} : srom_q;
    // No.16 TOTAL は "TOTAL   858/ 525" のように 1 行で: 7〜10 桁目に H (8 桁の BCD の上 4 桁)、11 桁目に "/"、12〜15 桁目に V
    //   キャプチャのときの No.28 ACTIVE (H / V ACTIVE) と No.29 C.TOT (推定の H / V 合計) も同じ形 (2026-11-07)
    wire        tot  = (line != 3'd0) && !blank && ((item == 5'd16) || (cp && (item == 5'd28 || item == 5'd29)));
    // No.17 FREQ は "*FRQ15.98k 62.42" のように 1 行で (2026-11-05。2026-11-07 に頭の * のため項目名を FRQ に): 値は H [10Hz] × 10000 + V [0.01Hz]。
    //   4〜8 桁目に H (BCD の上 4 桁、小数点は 6 桁目)、9 桁目に "k"、11〜15 桁目に V (小数点は 13 桁目)
    wire        fq   = (line != 3'd0) && !blank && (item == 5'd17);
    wire [7:0]  tch  = txt[(15 - col) * 8 +: 8];
    // 桁の取り出し: 表示の形ごとに BCD の桁の番号 di (0 = 一の位) を決めて、選ぶのは 1 か所 (2026-11-14 容量削減)
    //   FREQ: 4〜8 桁目に H、11〜15 桁目に V / TOTAL: 7〜10 桁目に H、12〜15 桁目に V /
    //   mV: 8〜10 桁目に整数 (3 桁)、11 桁目に小数点、12・13 桁目に小数 / kind 2: 7 桁 + 小数点 (13 桁目) / kind 0: 8 桁
    reg  [2:0]  di;
    always @(*) begin
        if (fq)
            case (col)
            4'd4: di = 3'd7;  4'd5: di = 3'd6;  4'd7: di = 3'd5;  4'd8: di = 3'd4;
            4'd11: di = 3'd3; 4'd12: di = 3'd2; 4'd14: di = 3'd1; default: di = 3'd0;
            endcase
        else if (tot)                     di = (col <= 4'd10) ? (hq ? 3'd5 : 3'd6) - col[2:0] : (vq ? 3'd6 : 3'd7) - col[2:0];
        else if (hq && kind == 2'd0)      di = 3'd6 - col[2:0];   // 推定の印: 7〜14 桁目
        else if (kind == 2'd2 && mv)
            case (col)
            4'd8: di = 3'd4; 4'd9: di = 3'd3; 4'd10: di = 3'd2; 4'd12: di = 3'd1; default: di = 3'd0;
            endcase
        else if (kind == 2'd2 && col < 4'd13) di = 3'd6 - col[2:0];
        else                              di = 3'd7 - col[2:0];
    end
    wire [3:0]  dg   = bcd[di * 4 +: 4];
    // AUTO の文字: H は 7〜10 桁目、V は 12〜15 桁目
    wire [1:0]  ai   = col[1:0] + {1'b0, col <= 4'd10};
    wire [7:0]  auto_ch = (ai == 2'd0) ? "A" : (ai == 2'd1) ? "U" : (ai == 2'd2) ? "T" : "O";

    always @(posedge clk) begin
        cv_start <= 1'b0;
        wr_en    <= 1'b0;
        if (rst) begin
            st <= S_LINE; tmr <= 0; top <= 0; line <= 0; bc <= 0; blink <= 1'b0;
        end else begin
            case (st)
            S_WAIT: if (tmr == REFRESH) begin
                tmr <= 0; line <= 0; st <= S_LINE;
                if (bc == BLINK - 1) begin bc <= 0; blink <= ~blink; end
                else bc <= bc + 5'd1;
            end else tmr <= tmr + 1;
            S_LINE: begin
                // スクロール位置 (行1〜7 に項目 top〜top+6)
                //   (位置で数える。行の位置 → 項目は settings が rd_code に出すので 2 クロック待つ、2026-11-20)
                if (line == 3'd0) begin
                    if (mpos < top) top <= mpos;
                    else if (mpos > top + 5'd6) top <= mpos - 5'd6;
                    else if (top + 5'd7 > mcnt && top != 5'd0) top <= (mcnt > 5'd7) ? mcnt - 5'd7 : 5'd0;   // グループを移って行が減った
                end
                pos     <= top + {2'd0, line} - 5'd1;
                rd_pos  <= top + {2'd0, line} - 5'd1;
                st      <= S_M1;
            end
            S_M1: st <= S_M2;
            S_M2: begin item <= rd_code[4:0]; spc <= rd_code[5] && (line != 3'd0); st <= S_READ; end
            S_READ: begin
                blank <= (line != 3'd0) && (pos >= mcnt);
                sel   <= (line != 3'd0) && (pos == mpos);
                lk    <= lv && rd_lock;
                mv    <= lv && rd_mv;
                rol   <= lv && rd_ro && !((line != 3'd0) && (pos >= mcnt));   // 一覧の下の空き行には * を出さない (2026-11-21)
                hq    <= lv && rd_q[0];  vq <= lv && rd_q[1];
                ah    <= lv && rd_auto[0]; av <= lv && rd_auto[1];
                cp    <= cap;
                wv    <= wav;
                crn   <= (line != 3'd0) && cap && (item == 5'd27) && rd_val[16];
                crs   <= rd_val[15];
                wrn   <= (line != 3'd0) && wav && (item == 5'd27) && rd_val[14];
                if (line == 3'd0) begin kind <= 2'd0; val <= step_val; end
                else begin kind <= spc ? 2'd1 : rd_kind; val <= rd_val; end
                txt <= rd_text; tcur <= rd_cursor;
                // CAP RUN の端数: 8 ビットを符号付きにして絶対値 (99 で頭打ち) を BCD に (2026-11-09)
                cv_in    <= (line == 3'd0) ? step_val :
                            (cap && item == 5'd27) ? {20'd0, cr_abs} : (wav && item == 5'd27) ? {15'd0, rd_val[26:15]} : rd_val;
                st       <= S_STR;
            end
            S_STR: begin cv_start <= 1'b1; st <= S_CONV; end   // cv_in を出してから変換を始める
            S_CONV: if (cv_done) begin
                bcd <= cv_bcd; col <= 0; nz <= 1'b0; st <= S_WA;
            end
            S_WA: st <= S_WR;                               // 文字列の ROM を読む (srom_q は次のクロック)
            S_WR: begin
                st      <= S_WA;
                wr_en   <= 1'b1;
                wr_addr <= {line, col};
                // ACTIVE (H / V の 1 行) の値を変えているときは、変えている方 (tcur 0 = H、1 = V) だけ点滅
                winv    <= sel && edit && blink && (kind != 2'd3) &&
                           (tot ? (tcur[0] ? (col >= 4'd12) : (col >= 4'd7 && col <= 4'd10)) : (col >= 4'd8));
                if (line == 3'd0 && col == 4'd5)
                    wd <= pending ? "*" : " ";
                else if (fq && col >= 4'd4) begin                   // FREQ の数字 (10 の位の 0 は空白)
                    if (col == 4'd6 || col == 4'd13)                wd <= ".";
                    else if (col == 4'd9)                           wd <= "k";
                    else if (col == 4'd10)                          wd <= " ";
                    else if ((col == 4'd4 || col == 4'd11) && dg == 4'd0) wd <= " ";
                    else                                            wd <= {4'h3, dg};
                end
                else if (tot && (col >= 4'd7 || (hq && col == 4'd6))) begin   // TOTAL の数字 (上の桁の 0 は空白)
                    if (col == 4'd11) begin                         wd <= "/"; nz <= 1'b0; end
                    else if (col >= 4'd7 && ((col <= 4'd10) ? ah : av)) wd <= auto_ch;   // AUTO
                    else if ((hq && col == 4'd10) || (vq && col == 4'd15)) wd <= "?";   // 推定した値の印
                    else if (dg != 0 || nz || col == (hq ? 4'd9 : 4'd10) || col == (vq ? 4'd14 : 4'd15)) begin wd <= {4'h3, dg}; nz <= 1'b1; end
                    else                                            wd <= 8'h20;
                end
                else if (hq && kind == 2'd0 && col >= 4'd7) begin   // 推定した値 (C.DOT): 7〜14 桁目に数字、15 桁目に ?
                    if (col == 4'd15)                               wd <= "?";
                    else if (dg != 0 || nz || col == 4'd14) begin   wd <= {4'h3, dg}; nz <= 1'b1; end
                    else                                            wd <= 8'h20;
                end
                else if (col < 4'd8)                                // 項目名 (変更できない項目は頭に "*" を付けて 1 桁ずらす)
                    wd <= {sel, (rol && col == 4'd0) ? 7'h2A : lch[6:0]};
                else if (blank)
                    wd <= 8'h20;
                else if (kind == 2'd1 && crn && col <= 4'd11) begin  // CAP RUN: 8〜10 桁目に符号付きの端数、12〜15 桁目に状態 ("+31 DONE"、" +3  RUN")
                    if (col == 4'd11)      wd <= " ";
                    else if (col == 4'd10) wd <= {4'h3, bcd[3:0]};
                    else if (col == 4'd9)  wd <= (bcd[7:4] != 4'd0) ? {4'h3, bcd[7:4]} : (crs ? "-" : "+");
                    else                   wd <= (bcd[7:4] != 4'd0) ? (crs ? "-" : "+") : " ";
                end
                else if (kind == 2'd1 && wrn && col <= 4'd11) begin  // RAW REC: 8〜11 桁目にライン数 ("525 DONE"、4 桁は "1050DONE")
                    if (bcd[15:12] != 4'd0)  wd <= {4'h3, (col == 4'd8) ? bcd[15:12] : (col == 4'd9) ? bcd[11:8] : (col == 4'd10) ? bcd[7:4] : bcd[3:0]};
                    else if (col == 4'd11)   wd <= " ";
                    else if (col == 4'd10)   wd <= {4'h3, bcd[3:0]};
                    else if (col == 4'd9)    wd <= (bcd[11:4] != 8'd0) ? {4'h3, bcd[7:4]} : " ";
                    else                     wd <= (bcd[11:8] != 4'd0) ? {4'h3, bcd[11:8]} : " ";
                end
                else if (kind == 2'd1)                              // 選択肢 (変更できないときは ----)
                    wd <= (lk && !spc) ? ((col >= 4'd12) ? "-" : " ") :
                          {srom_q[7] | (sel && spc && item[1:0] != 2'd0), srom_q[6:0]};   // 最初の画面の行は 1 行すべて反転 (2026-11-21)
                else if (kind == 2'd3)                              // 文字列 (編集中の桁は反転)
                    wd <= {(tcur == col - 4'd8) && blink, (tch == 8'd0) ? 7'h20 : tch[6:0]};
                else if (kind == 2'd2 && mv) begin                 // 電圧 (上の桁の 0 は空白)
                    if (col == 4'd11)                               wd <= ".";
                    else if (col == 4'd14)                          wd <= "m";
                    else if (col == 4'd15)                          wd <= "V";
                    else if (dg != 0 || nz || col >= 4'd10) begin   wd <= {4'h3, dg}; nz <= 1'b1; end
                    else                                            wd <= 8'h20;
                end
                else if (kind == 2'd2) begin
                    if (col == 4'd13)                               wd <= ".";
                    else if (dg != 0 || nz || col >= 4'd12) begin   wd <= {4'h3, dg}; nz <= 1'b1; end
                    else                                            wd <= 8'h20;
                end else begin
                    if (dg != 0 || nz || col == 4'd15) begin        wd <= {4'h3, dg}; nz <= 1'b1; end
                    else                                            wd <= 8'h20;
                end
                if (col == 4'd15) begin
                    if (line == 3'd7) st <= S_WAIT;
                    else begin line <= line + 3'd1; st <= S_LINE; end
                end
                col <= col + 4'd1;
            end
            default: st <= S_WAIT;
            endcase
        end
    end
endmodule
