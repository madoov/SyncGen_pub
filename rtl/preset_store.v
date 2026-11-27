// =============================================================
// ユーザープリセットの保存 / 読み出し (SPI EEPROM 25LC640A など)
//
//   1スロット = 32バイト (25LC640A の1ページ) × SLOTS 個 (先頭アドレスから)
//     byte 0     : 0xA5 (記録済みの印)
//     byte 1..30 : 設定値 (settings.v が詰める)
//     byte 31    : byte 0〜30 の合計 (下位8bit) … 壊れたデータを読まないため
//
//   電源投入時: 全スロットを読んで有効なものを valid に記録し、
//               スロット1 (slot=0) が有効ならそれを自動で読み込む
//
//   保存: 書き込み → WIP が 0 になるのを待つ → 読み直して 32 バイトが書いた内容と一致したら成功
//         (2026-10-26 修正: 以前は WIP = 0 だけで成功にしていたので、書き込み保護 (BP ビット) などで
//          書き込みが無視されても「保存成功」になっていた)。一致しなければ ERROR、valid は読んだ内容で決める
//
//   読み出しの成功後は、1 バイトずつ (byte 1〜30) ld_we / ld_idx / ld_byte で settings へ渡す (2026-11-13、容量削減:
//   以前は 256 ビットの FF のバッファを並列に渡していた。バッファは 32 x 8 ビットのメモリ bm に)。渡し終わってから done_ok、
//   その間は busy のまま (起動時の自動読み込みのあとの APPLY は busy が下がるのを待つ)
//
//   波形コピーのスロット (2026-11-13、wav = 1 で SAVE / LOAD): 0x1000 + スロット × 0x200 (512 バイト、8 スロットで 0x1000〜0x1FFF)
//     ページ 0 (32 バイト): byte0 = 0x5A、1〜2 = 語数 (1〜240)、3〜4 = ライン数、5 = 頭のレベル、6 = データのページの全バイトの合計
//     ページ 1〜15: wav_store の cm の語 (16 ビット、下位バイトが先) を 16 語ずつ
//     保存はデータのページを先に (ページごとに読み直して確かめる)、見出しのページを最後に書く。読み出しは見出し → データ
//     (cm へ直接書く) → 合計を確かめて done_ok。ユーザープリセットの valid・名前は変えない
//   波形スロットの設定 (2026-11-20): スロットごとにユーザープリセットと同じ形の 32 バイトを 0x0100 + スロット × 0x20 に
//     (H / V の合計・DOTCLK・同期など。作業中の値 cur_data)。波形の保存 (見出しまで書けた) のあとに書き、
//     読み出しは波形の合計が合ったあとに読んで settings へ渡す (ld_we)。スロットは wslot (No.29 RAW SLOT、プリセットの SLOT とは別)
//
//   同じコマンドの FRAM (MB85RS64V など) でもそのまま動く
//   (FRAM は書き込み待ちが無いので、WIP がすぐ 0 になるだけ)
// =============================================================
module preset_store #(
    parameter integer SLOTS   = 8,
    parameter integer SPI_DIV = 8,             // SCK = 50MHz/16 = 3.1MHz (3.3V時の上限 5MHz)
    parameter integer WR_TIMEOUT = 5000        // 書き込み完了待ちの上限 (状態読み出し回数, 約30ms)
)(
    input  wire         clk,
    input  wire         rst,
    input  wire         save,          // 1クロックのパルス
    input  wire         load,
    input  wire [2:0]   slot,          // 0〜7 (表示上は 1〜8)
    input  wire [2:0]   wslot,         // 波形のスロット 0〜7 (RAW SLOT、2026-11-20)
    input  wire [255:0] cur_data,      // 保存する内容 (byte i = cur_data[i*8 +: 8]。書くときに 1 バイトずつ選ぶ)
    // 波形コピー (2026-11-13): wav = 1 の save / load は波形のスロット。cm は wav_store のメモリ
    input  wire         wav,
    input  wire [10:0]  wv_nw,         // 保存する語数・ライン数・頭のレベル (wav_store)
    input  wire [11:0]  wv_lines,
    input  wire [1:0]   wv_lv0,
    output wire [7:0]   cm_addr,       // 読む語 (1 クロック遅れの cm_q)
    input  wire [15:0]  cm_q,
    output reg          cm_we,
    output reg  [7:0]   cm_waddr,
    output reg  [15:0]  cm_wd,
    output reg          wv,            // 今の (最後の) 処理が波形のスロット
    output reg  [10:0]  wl_nw,         // 読み出した見出し (done_ok のとき有効)
    output reg  [11:0]  wl_lines,
    output reg  [1:0]   wl_lv0,
    output reg          ld_we,         // 読み出し成功のあと、1 バイトずつ (byte 1〜30) 1 クロック
    output reg  [4:0]   ld_idx,        // そのバイトの番号
    output reg  [7:0]   ld_byte,       // そのバイト
    output reg  [7:0]   valid,         // スロットごとの記録済みフラグ
    input  wire [2:0]   name_sel,      // 名前を読むスロット
    output reg  [63:0]  name_q,        // そのスロットの名前 (byte23〜30。name_sel から 1 クロック遅れ)
    output reg          busy,
    output reg          done_ok,       // 保存/読み出しの完了 (1クロック)
    output reg          done_err,
    output reg          ee_cs_n,
    output reg          ee_sck,
    output reg          ee_mosi,
    input  wire         ee_miso
);
    // ---------------- 1バイト送受信 (SPI モード0) ----------------
    reg       x_start, x_busy;
    reg [7:0] x_tx, x_rx, x_sh;
    reg [2:0] x_bit;
    reg [7:0] x_div;
    reg       x_ph;
    always @(posedge clk) begin
        if (rst) begin
            x_busy <= 1'b0; ee_sck <= 1'b0; ee_mosi <= 1'b0; x_ph <= 1'b0;
        end else if (x_start) begin
            x_sh <= x_tx; ee_mosi <= x_tx[7]; x_bit <= 3'd7;
            x_div <= 0; ee_sck <= 1'b0; x_busy <= 1'b1;
        end else if (x_busy) begin
            if (x_div == SPI_DIV - 1) begin
                x_div <= 0;
                if (!ee_sck) begin
                    ee_sck <= 1'b1;                          // 立ち上がりで受信
                    x_rx   <= {x_rx[6:0], ee_miso};
                end else begin
                    ee_sck <= 1'b0;                          // 立ち下がりで次のビット
                    if (x_bit == 3'd0) x_busy <= 1'b0;
                    else begin
                        x_bit   <= x_bit - 3'd1;
                        x_sh    <= {x_sh[6:0], 1'b0};
                        ee_mosi <= x_sh[6];
                    end
                end
            end else x_div <= x_div + 8'd1;
        end
    end

    // ---------------- 手順 ----------------
    localparam [7:0] C_READ = 8'h03, C_WRITE = 8'h02, C_WREN = 8'h06, C_RDSR = 8'h05;

    localparam S_BOOT  = 5'd0,  S_IDLE  = 5'd1,  S_XW    = 5'd2,  S_GAP   = 5'd3,
               S_RD0   = 5'd4,  S_RD1   = 5'd5,  S_RD2   = 5'd6,  S_RD3   = 5'd7,
               S_RD4   = 5'd8,  S_RDEND = 5'd9,
               S_WE0   = 5'd10, S_WE1   = 5'd11,
               S_WR0   = 5'd12, S_WR1   = 5'd13, S_WR2   = 5'd14, S_WR3   = 5'd15,
               S_WREND = 5'd16, S_PL0   = 5'd17, S_PL1   = 5'd18, S_PL2   = 5'd19,
               S_LD0   = 5'd20, S_LD1   = 5'd21, S_CP    = 5'd22;

    reg [4:0]   st, ret, gret;
    reg [7:0]   gap;
    reg [5:0]   bi;            // バイト番号 0..31
    reg [7:0]   sum;
    reg [2:0]   sl;            // 処理中のスロット
    reg         booting, op_load;
    reg         wa, wp;                  // 波形のページを読み書き中 / 波形スロットの設定 (ユーザープリセットと同じ形) を読み書き中
    reg         op_vfy, vmis, vsum_ok;   // 保存後の読み直し: 不一致あり / 読んだ byte31 が合計と一致
    reg [7:0]   vb0;                     // 読んだ byte0 (正しい記録なら 0xA5)
    reg [31:0]  to;

    reg  [3:0]  pg;                      // 波形: ページ (0 = 見出し、データは 1〜15 を全部)
    reg  [7:0]  hsum;                    // 波形: 読んだ見出しの合計 (データのページの合計は sum を続けて使う)
    // 番地: 波形のページ (wa) / 波形スロットの設定 (wp、0x0100 + スロット × 0x20、2026-11-20) / ユーザープリセット
    wire [15:0] addr = wa ? {4'b0001, sl, pg, 5'd0} : {7'd0, wp, sl, 5'd0};
    assign cm_addr = {pg - 4'd1, bi[4:1]};
    // 波形の見出し: byte0 = 0x5A, 1 = 語数 (1〜240), 2 = ライン数の下位, 3 = {頭のレベル VS / HS, 00, ライン数の上位 4}, 4 = データの合計
    wire [7:0]  wvbyte = (pg != 4'd0) ? (bi[0] ? cm_q[15:8] : cm_q[7:0]) :
                         (bi == 6'd0) ? 8'h5A : (bi == 6'd1) ? wv_nw[7:0] : (bi == 6'd2) ? wv_lines[7:0] :
                         (bi == 6'd3) ? {wv_lv0, 2'b00, wv_lines[11:8]} : (bi == 6'd4) ? sum : 8'd0;
    // ---- バッファ: 32 x 8 ビットのメモリ (2026-11-13、容量削減。以前は 256 ビットの FF) ----
    //   書き込み: 書いたバイトを bm[bi] に (読み直しで比べる)。読み出し: 読んだバイトを bm[bi] に (成功したら settings へ渡す)。
    //   番地はどちらも bi (読みは 1 クロック遅れの bm_q。比べるのは送受信の完了を待ったあとなので bi は落ち着いている)
    // 書くバイト: byte0 = 0xA5、byte31 = 合計、ほかは保存する内容から番号で選ぶ
    //   ユーザープリセットは SAVE の始めに 32 バイトを bm へ写してから (S_CP) 書く。書いている途中に作業中の値が変わっても
    //   保存を始めたときの一式になる (2026-11-14。以前は書くときに cur_data から 1 バイトずつ選んでいて、新旧が混ざった)
    wire [7:0]  cbyte = (bi == 6'd0) ? 8'hA5 : (bi == 6'd31) ? sum : cur_data[bi[4:0] * 8 +: 8];
    reg  [7:0]  bm [0:31];
    reg  [7:0]  bm_q;
    wire [7:0]  wbyte = wa ? wvbyte : bm_q;
    // 書くのは読み出し (読み直しでない) の受信と、書き込みの送信 (どちらも今の bi に)
    wire        bm_we = ((st == S_RD4) && !op_vfy) || ((st == S_WR3) && wa) || (st == S_CP);
    always @(posedge clk) begin
        if (bm_we) bm[bi[4:0]] <= (st == S_CP) ? cbyte : (st == S_WR3) ? wvbyte : x_rx;
        bm_q <= bm[bi[4:0]];
    end
    // 名前: 読んだ byte23〜30 を順に入れる (byte23 が先頭の文字 → 64bit の上位に)
    reg  [63:0] rec_name;
    // 読んだ記録が正しい: byte0 = 0xA5、byte31 = byte0〜30 の合計
    wire        rec_ok = (vb0 == 8'hA5) && vsum_ok;

    // ---- スロットごとの名前はメモリ (8 x 64 ビット)。読むのは表示中のスロットだけ (2026-11-07) ----
    reg  [63:0] nmem [0:7];
    // 名前の書き込みは S_RDEND で 1 回 (読み出し: 正しい記録なら名前、そうでなければ 0。
    //   保存の読み直し: 一致なら名前、不一致で記録が壊れていれば 0、壊れていなければ前のまま)
    wire        n_we = (st == S_RDEND) && !wa && !wp && (!op_vfy || !vmis || !((vb0 == 8'hA5) && vsum_ok));
    wire [63:0] n_wd = (op_vfy ? !vmis : rec_ok) ? rec_name : 64'd0;
    always @(posedge clk) begin
        if (n_we) nmem[sl] <= n_wd;
        name_q <= nmem[name_sel];
    end

    task send(input [7:0] b, input [4:0] next);
        begin x_tx <= b; x_start <= 1'b1; ret <= next; st <= S_XW; end
    endtask
    task cs_high(input [4:0] next);        // CS を上げて少し待つ
        begin ee_cs_n <= 1'b1; gap <= 0; gret <= next; st <= S_GAP; end
    endtask

    always @(posedge clk) begin
        x_start <= 1'b0; ld_we <= 1'b0; done_ok <= 1'b0; done_err <= 1'b0; cm_we <= 1'b0;
        if (rst) begin
            st <= S_BOOT; ee_cs_n <= 1'b1; valid <= 8'd0; busy <= 1'b1; wv <= 1'b0; wa <= 1'b0; wp <= 1'b0;
            booting <= 1'b1; sl <= 3'd0; op_load <= 1'b0; op_vfy <= 1'b0;
        end else begin
            case (st)
            // ---- 共通: 送受信の完了待ち / CS High 期間 ----
            S_XW:  if (!x_start && !x_busy) st <= ret;
            S_GAP: if (gap == 8'd20) st <= gret; else gap <= gap + 8'd1;

            S_BOOT: begin sl <= 3'd0; st <= S_RD0; end

            S_IDLE: begin
                busy <= 1'b0;
                if (save || load) begin wv <= wav; wa <= wav; wp <= 1'b0; pg <= 4'd0; end
                if (save) begin
                    busy <= 1'b1; sl <= wav ? wslot : slot; st <= S_WE0;
                    if (!wav) begin bi <= 6'd0; sum <= 8'hA5; st <= S_CP; end     // 先に 32 バイトを bm へ
                    if (wav) begin                                   // 波形: データのページ 1 から。語数が 1〜240 でなければ ERROR
                        pg <= 4'd1;
                        if (wv_nw == 11'd0 || wv_nw > 11'd240) begin done_err <= 1'b1; st <= S_IDLE; end
                    end
                end else if (load) begin
                    busy <= 1'b1; sl <= wav ? wslot : slot; op_load <= 1'b1; st <= S_RD0;
                end
            end

            // ---- 読み出し: READ addr(16bit) + 32バイト ----
            S_RD0: begin ee_cs_n <= 1'b0; send(C_READ, S_RD1); end
            S_RD1: send(addr[15:8], S_RD2);
            S_RD2: begin bi <= 0; if (!wa || pg <= 4'd1) sum <= 0; send(addr[7:0], S_RD3); end   // 波形のデータのページは合計を続ける
            S_RD3: send(8'h00, S_RD4);
            S_RD4: begin                                     // 読み出しは bm[bi] に書く (bm_we)。読み直しは書いた内容 bm_q と比べる
                if (op_vfy && x_rx != bm_q) vmis <= 1'b1;
                if (bi == 6'd0)  vb0 <= x_rx;
                if (bi == 6'd31) vsum_ok <= (x_rx == sum);
                if (bi >= 6'd23 && bi <= 6'd30) rec_name <= {rec_name[55:0], x_rx};
                // 波形の読み出し: 見出しの値を取る / データは cm へ (2 バイトで 1 語)
                if (wa && op_load && pg == 4'd0) begin
                    if (bi == 6'd1) wl_nw <= {3'd0, x_rx};
                    if (bi == 6'd2) wl_lines[7:0] <= x_rx;
                    if (bi == 6'd3) begin wl_lines[11:8] <= x_rx[3:0]; wl_lv0 <= x_rx[7:6]; end
                    if (bi == 6'd4) hsum <= x_rx;
                end
                if (wa && op_load && pg != 4'd0) begin
                    if (!bi[0]) cm_wd[7:0] <= x_rx;
                    else begin cm_wd[15:8] <= x_rx; cm_we <= 1'b1; cm_waddr <= cm_addr; end
                end
                if (bi != 6'd31 || (wa && pg != 4'd0)) sum <= sum + x_rx;   // 波形のデータは 32 バイトとも (保存の読み直しでも数え、見出しに書く)
                if (bi == 6'd31) cs_high(S_RDEND);
                else begin bi <= bi + 6'd1; st <= S_RD3; end
            end
            S_RDEND: if (wa) begin                                   // 波形のスロット
                op_vfy <= 1'b0;
                if (op_vfy) begin                                    // 保存: ページを読み直した
                    if (vmis) begin done_err <= 1'b1; st <= S_IDLE; end
                    else if (pg == 4'd0) begin wa <= 1'b0; wp <= 1'b1; bi <= 6'd0; sum <= 8'hA5; st <= S_CP; end   // 見出しまで書けた → 設定を書く
                    else begin pg <= (pg == 4'd15) ? 4'd0 : pg + 4'd1; st <= S_WE0; end    // 次のページ (最後に見出し)
                end else if (pg == 4'd0) begin                       // 読み出し: 見出し
                    if (vb0 == 8'h5A && wl_nw[7:0] != 8'd0 && wl_nw[7:0] <= 8'd240) begin pg <= 4'd1; st <= S_RD0; end
                    else begin op_load <= 1'b0; done_err <= 1'b1; st <= S_IDLE; end
                end else if (pg == 4'd15) begin                      // 読み出し: 最後のデータのページ
                    if (sum == hsum) begin wa <= 1'b0; wp <= 1'b1; st <= S_RD0; end   // 合計が合えば設定を読む (op_load のまま)
                    else begin op_load <= 1'b0; done_err <= 1'b1; st <= S_IDLE; end
                end else begin pg <= pg + 4'd1; st <= S_RD0; end
            end else if (op_vfy) begin
                op_vfy <= 1'b0;
                if (!vmis) begin
                    if (!wp) valid[sl] <= 1'b1;
                    done_ok <= 1'b1;                                     // 名前は n_we で書く
                end else begin
                    // 書けていない: スロットは読んだ内容が正しい記録なら有効のまま (名前は前のまま)
                    if (!wp) valid[sl] <= (vb0 == 8'hA5) && vsum_ok;
                    done_err <= 1'b1;
                end
                st <= S_IDLE;
            end else begin
                if (!wp) valid[sl] <= rec_ok;                            // 名前は n_we で書く (波形スロットの設定は valid・名前を変えない)
                if (booting) begin
                    if (sl == SLOTS - 1) begin
                        booting <= 1'b0;
                        // スロット1 が有効なら自動で読み込む
                        if (valid[0]) begin sl <= 3'd0; op_load <= 1'b1; st <= S_RD0; end
                        else st <= S_IDLE;
                    end else begin sl <= sl + 3'd1; st <= S_RD0; end
                end else begin
                    if (op_load) begin
                        op_load <= 1'b0;
                        if (rec_ok) begin bi <= 6'd1; st <= S_LD0; end   // byte 1〜30 を settings へ渡してから done_ok
                        else begin done_err <= 1'b1; st <= S_IDLE; end
                    end else st <= S_IDLE;
                end
            end

            // ---- 書き込み: WREN → WRITE addr + 32バイト → 完了待ち ----
            S_WE0: begin ee_cs_n <= 1'b0; send(C_WREN, S_WE1); end
            S_WE1: cs_high(S_WR0);
            S_WR0: begin ee_cs_n <= 1'b0; send(C_WRITE, S_WR1); end
            S_WR1: send(addr[15:8], S_WR2);
            S_WR2: begin bi <= 0; send(addr[7:0], S_WR3); end
            S_WR3: begin                                     // 書いたバイトは bm[bi] にも (bm_we、読み直しで比べる)
                send(wbyte, (bi == 6'd31) ? S_WREND : S_WR3);
                bi <= bi + 6'd1;
            end
            S_WREND: begin to <= 0; cs_high(S_PL0); end      // CS の立ち上がりで書き込み開始
            // ---- SAVE の始め: 保存する 32 バイト (byte31 は合計) を bm へ写す ----
            S_CP: begin
                if (bi != 6'd0 && bi != 6'd31) sum <= sum + cbyte;
                if (bi == 6'd31) st <= S_WE0; else bi <= bi + 6'd1;
            end
            // ---- 状態レジスタの WIP が 0 になるまで待つ ----
            S_PL0: begin ee_cs_n <= 1'b0; send(C_RDSR, S_PL1); end
            S_PL1: send(8'h00, S_PL2);
            S_PL2: begin
                if (!x_rx[0]) begin                          // 書き込み完了 → 読み直して確かめる
                    op_vfy <= 1'b1; vmis <= 1'b0; cs_high(S_RD0);
                end else if (to > WR_TIMEOUT) begin
                    done_err <= 1'b1; cs_high(S_IDLE);
                end else begin
                    to <= to + 32'd1; cs_high(S_PL0);
                end
            end
            // ---- 読み出し成功: byte 1〜30 を 1 バイトずつ settings へ (bm_q は 1 クロック遅れ) ----
            S_LD0: st <= S_LD1;
            S_LD1: begin
                ld_we <= 1'b1; ld_idx <= bi[4:0]; ld_byte <= bm_q;
                if (bi == 6'd30) begin done_ok <= 1'b1; st <= S_IDLE; end
                else begin bi <= bi + 6'd1; st <= S_LD0; end
            end
            default: st <= S_IDLE;
            endcase
        end
    end
endmodule
