// =============================================================
// VGA 出力へ重ねる情報表示 (OSD) の文字を作る (50MHz 側)
//   32 文字 x 8 行。表示するのは「いま出力している」値 (APPLY で確定した値) と測定値
//
//     |DOT CLOCK   25.175000 MHz       |  ← ドットクロック目標 (確定値)
//     |MEASURED    25.166000 MHz       |  ← ドットクロック実測
//     |  |ACTIVE|  FP|SYNC|  BP|TOTAL  |
//     |H |   640|  16|  96|  48|  800  |  ← 水平 表示/FP/同期/BP/合計 [ドット]
//     |V |   480|  10|   2|  33|  525  |  ← 垂直 表示/FP/同期/BP/合計 [ライン]
//        (| は縦線の字 0x1F。上下の行とつながる 8 ドットの線で、表の列を区切る。2026-10-30)
//     |SYNC SEP TTL  HS NEG  VS NEG INT|  ← 同期の出し方 (SEP/OR/XOR/EQ)・電圧 (TTL/LOW)・極性・インターレース (INT)
//                                             インターレースの V の合計はフレームのライン数 (2 × フィールド + 1)
//     |H FREQ      31.469 kHz          |  ← 水平周波数 (実測)
//     |V FREQ       59.94 Hz           |  ← 垂直周波数 (実測)
//        単位は Hz / kHz / MHz (フォントに小文字の z と k がある)
//
//   REFRESH ごとに書き直す。固定の文字を書いてから数値を書くが、数値の場所は
//   固定の文字で上書きしない (書き直しの途中で数値が消えて見えないように)
//   書き込み先は vga_osd の文字メモリ (アドレス = 行*32 + 桁、bit7 = 反転表示)
// =============================================================
module osd_text #(
    parameter integer REFRESH = 2_500_000,     // 50ms ごとに書き直す
    parameter         STR_FILE = "osd_str.hex" // 固定の文字 (tools/make_menu_rom.py)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire [26:0] dot_hz,                 // ドットクロック目標 (確定値)
    input  wire [26:0] meas_hz,                // ドットクロック実測
    input  wire [11:0] ha, hf, hs, hb,         // 確定値 (cfg_*)
    input  wire [11:0] va, vf, vs, vb,
    input  wire        hneg, vneg,
    input  wire [1:0]  csync,
    input  wire        sync_lv,                // 同期の電圧 0 = TTL、1 = LOW
    input  wire        ilace,                  // インターレース
    input  wire [26:0] hfreq_hz,               // 水平周波数 [Hz]
    input  wire [26:0] vfreq_x100,             // 垂直周波数 [0.01Hz]
    output reg         wr_en,
    output reg  [7:0]  wr_addr,
    output reg  [7:0]  wr_data,
    // 2 進 → 10 進の変換 (トップの bcd_share。done が来るまで cv_in を変えない)
    output reg         cv_start,
    output reg  [26:0] cv_in,
    input  wire [31:0] cv_bcd,
    input  wire        cv_done
);
    // ---------- 固定の文字 ("~" の場所は数値が入るので書かない) ----------
    //   2026-11-07: 表を LUT からメモリブロックの ROM へ移した。rtl/osd_str.hex (tools/make_menu_rom.py で作る)
    //   アドレス = 行 x 32 + 桁、256 バイト。中身は上の図のとおり (縦線は 0x1F、数値の場所は "~")
    reg [7:0] trom [0:255];
    initial $readmemh(STR_FILE, trom);
    reg [7:0] trom_q;

    // ---------- 数値の欄 ----------
    //   番号 → 位置 (行, 桁)、桁数 nd (小数部を含む数字の数)、小数部 fd、種類 (0 = 数値, 1 = 文字 3 つ)
    localparam NF = 19;
    function [17:0] fdef(input [4:0] k);       // {行[2:0], 桁[4:0], nd[3:0], fd[3:0], 種類, 予備}
        case (k)
            5'd0:  fdef = {3'd0, 5'd12, 4'd8, 4'd6, 1'b0, 1'b0};   // 25.175000
            5'd1:  fdef = {3'd1, 5'd12, 4'd8, 4'd6, 1'b0, 1'b0};
            5'd2:  fdef = {3'd3, 5'd5,  4'd4, 4'd0, 1'b0, 1'b0};   // H ACTIVE
            5'd3:  fdef = {3'd3, 5'd10, 4'd4, 4'd0, 1'b0, 1'b0};
            5'd4:  fdef = {3'd3, 5'd15, 4'd4, 4'd0, 1'b0, 1'b0};
            5'd5:  fdef = {3'd3, 5'd20, 4'd4, 4'd0, 1'b0, 1'b0};
            5'd6:  fdef = {3'd3, 5'd26, 4'd4, 4'd0, 1'b0, 1'b0};   // H TOTAL
            5'd7:  fdef = {3'd4, 5'd5,  4'd4, 4'd0, 1'b0, 1'b0};   // V ACTIVE
            5'd8:  fdef = {3'd4, 5'd10, 4'd4, 4'd0, 1'b0, 1'b0};
            5'd9:  fdef = {3'd4, 5'd15, 4'd4, 4'd0, 1'b0, 1'b0};
            5'd10: fdef = {3'd4, 5'd20, 4'd4, 4'd0, 1'b0, 1'b0};
            5'd11: fdef = {3'd4, 5'd26, 4'd4, 4'd0, 1'b0, 1'b0};   // V TOTAL
            5'd12: fdef = {3'd5, 5'd5,  4'd3, 4'd0, 1'b1, 1'b0};   // SYNC SEP/OR/XOR/EQ
            5'd13: fdef = {3'd5, 5'd17, 4'd3, 4'd0, 1'b1, 1'b0};   // HS POS/NEG
            5'd14: fdef = {3'd5, 5'd25, 4'd3, 4'd0, 1'b1, 1'b0};   // VS POS/NEG
            5'd15: fdef = {3'd6, 5'd11, 4'd6, 4'd3, 1'b0, 1'b0};   // 31.469 (kHz)
            5'd16: fdef = {3'd7, 5'd12, 4'd5, 4'd2, 1'b0, 1'b0};   // 59.94
            5'd17: fdef = {3'd5, 5'd9, 4'd3, 4'd0, 1'b1, 1'b0};    // 同期の電圧 TTL/LOW
            default: fdef = {3'd5, 5'd29, 4'd3, 4'd0, 1'b1, 1'b0}; // インターレース INT
        endcase
    endfunction

    // 合計 (めったに変わらないのでレジスタに)
    reg [12:0] ht, vt, vtf;
    wire [11:0] vah = ilace ? ((va + 12'd1) >> 1) : va;
    always @(posedge clk) begin
        ht  <= {1'b0, ha} + {1'b0, hf} + {1'b0, hs} + {1'b0, hb};
        vtf <= {1'b0, vah} + {1'b0, vf} + {1'b0, vs} + {1'b0, vb};
        vt  <= ilace ? {vtf[11:0], 1'b1} : vtf;
    end

    function [26:0] fval(input [4:0] k);
        case (k)
            5'd0:  fval = dot_hz;      5'd1:  fval = meas_hz;
            5'd2:  fval = ha;          5'd3:  fval = hf;     5'd4: fval = hs;  5'd5: fval = hb;  5'd6: fval = ht;
            5'd7:  fval = va;          5'd8:  fval = vf;     5'd9: fval = vs;  5'd10: fval = vb; 5'd11: fval = vt;
            5'd15: fval = hfreq_hz;    default: fval = vfreq_x100;
        endcase
    endfunction

    function [23:0] fstr(input [4:0] k);
        case (k)
            5'd12: fstr = (csync == 2'd0) ? "SEP" : (csync == 2'd1) ? " OR" : (csync == 2'd2) ? "XOR" : " EQ";
            5'd13: fstr = hneg ? "NEG" : "POS";
            5'd14: fstr = vneg ? "NEG" : "POS";
            5'd17:   fstr = sync_lv ? "LOW" : "TTL";
            default: fstr = ilace ? "INT" : "   ";
        endcase
    endfunction

    // ---------- 2 進 → 10 進 ----------
    // 2 進 → 10 進の変換はトップの bcd_share (menu_display と osd_text で共有、2026-11-13)

    // ---------- 書き込みの順番 ----------
    localparam S_WAIT = 3'd0, S_TRD = 3'd1, S_TWR = 3'd2, S_FLD = 3'd3,
               S_CONV = 3'd4, S_DIG = 3'd5, S_STR = 3'd6;
    reg [2:0]  st;
    reg [31:0] tmr;
    reg [7:0]  ta;              // 固定の文字: アドレス
    reg [4:0]  k;               // 欄の番号
    reg [2:0]  frow;
    reg [4:0]  fcol;
    reg [3:0]  nd, fd, j, w;
    reg [31:0] bcd;
    reg [23:0] str;
    reg        nz;
    wire [17:0]  fk = fdef(k);
    always @(posedge clk) trom_q <= trom[ta];         // S_TRD で読み、S_TWR で使う
    // j 文字目に出す数字 (先頭から)。小数点の位置は nd - fd
    wire [3:0] ip  = nd - fd;                               // 整数部の桁数
    wire [3:0] di  = (fd != 4'd0 && j > ip) ? j - 4'd1 : j;  // 何番目の数字か (先頭 0)
    wire [3:0] dn  = nd - 4'd1 - di;                        // 下から何桁目か
    wire [3:0] dig = bcd[dn * 4 +: 4];

    always @(posedge clk) begin
        cv_start <= 1'b0;
        wr_en    <= 1'b0;
        if (rst) begin
            st <= S_TRD; tmr <= 0; ta <= 0;
        end else begin
            case (st)
            S_WAIT: if (tmr == REFRESH) begin tmr <= 0; ta <= 0; st <= S_TRD; end
                    else tmr <= tmr + 1;
            // 固定の文字 256 個
            S_TRD: st <= S_TWR;                               // ROM の読み出し待ち
            S_TWR: begin
                if (trom_q != "~") begin wr_en <= 1'b1; wr_addr <= ta; wr_data <= trom_q; end
                ta <= ta + 8'd1;
                if (ta == 8'd255) begin k <= 0; st <= S_FLD; end
                else st <= S_TRD;
            end
            // 欄ごとに数値を変換して書く
            S_FLD: begin
                frow <= fk[17:15]; fcol <= fk[14:10]; nd <= fk[9:6]; fd <= fk[5:2];
                j <= 0; nz <= 1'b0;
                w <= fk[9:6] + ((fk[5:2] != 4'd0) ? 4'd1 : 4'd0);
                if (fk[1]) begin
                    str <= fstr(k); st <= S_STR;
                end else begin
                    cv_in <= fval(k); cv_start <= 1'b1; st <= S_CONV;
                end
            end
            S_CONV: if (cv_done) begin bcd <= cv_bcd; st <= S_DIG; end
            S_DIG: begin
                wr_en   <= 1'b1;
                wr_addr <= {frow, fcol + {1'b0, j}};
                if (fd != 4'd0 && j == ip)                       // 小数点
                    wr_data <= ".";
                else if (dig != 4'd0 || nz || j + 4'd1 >= ip) begin  // 整数部の最後の桁と小数部は必ず出す
                    wr_data <= {4'h3, dig}; nz <= 1'b1;
                end else
                    wr_data <= " ";                               // 上の桁の 0 は空白
                j <= j + 4'd1;
                if (j + 4'd1 == w) st <= (k == NF - 1) ? S_WAIT : S_FLD;
                if (j + 4'd1 == w) k <= k + 5'd1;
            end
            S_STR: begin
                wr_en   <= 1'b1;
                wr_addr <= {frow, fcol + {1'b0, j}};
                wr_data <= str[(2 - j) * 8 +: 8];
                j <= j + 4'd1;
                if (j == 4'd2) begin
                    k  <= k + 5'd1;
                    st <= (k == NF - 1) ? S_WAIT : S_FLD;
                end
            end
            default: st <= S_WAIT;
            endcase
        end
    end
endmodule
