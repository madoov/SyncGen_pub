// =============================================================
// SSD1306 (128x64 OLED) I2C テキスト表示ドライバ (書き込みのみ)
//   - 16文字 x 8行 のテキストバッファを内蔵(8x8フォント)
//   - 書き込みポートに文字コード(ASCII)を書くだけで表示される
//   - 文字コードの bit7 = 1 で反転表示(メニューの選択表示などに)
//   - 電源投入後に初期化し、以後は画面全体を繰り返し転送し続ける
//
//   I2C: SCL / SDA ともオープンドレイン。*_oe = 1 で Low に引く、0 で離す
//        (High はモジュールのプルアップ抵抗で上がる)。ACK は見ない
//        1 ビット = 4 区間 x I2C_Q クロック。50MHz, I2C_Q=34 → 約 368kHz
//        (Fast mode: SCL Low 1.36us ≥ 1.3us, High 1.36us ≥ 0.6us)
//   送り方: [START] アドレス 制御バイト バイト列 [STOP]
//        制御バイト 0x00 = 以後コマンド、0x40 = 以後表示データ
//        初期化 1 回 → (アドレス設定 + 表示データ 1024 バイト) を繰り返す
//        1 画面 約 1034 バイト ≒ 25ms (約 40 枚/秒)
//
//   フォント: font8x8.hex (128文字 x 8バイト, 列単位, bit0=上)
//             Efinity ではプロジェクトのフォルダに置くこと
// =============================================================
module ssd1306_text #(
    parameter integer I2C_Q        = 34,
    parameter [6:0]   I2C_ADDR     = 7'h3C,    // モジュールによっては 7'h3D
    parameter integer RESET_CYCLES = 50_000,   // 電源投入後、初期化を始めるまでの待ち (この 2 倍)
    parameter         FONT_FILE    = "font8x8.hex"
)(
    input  wire       clk,
    input  wire       rst,

    // テキストバッファ書き込みポート
    input  wire       wr_en,
    input  wire [6:0] wr_addr,     // {行[2:0], 桁[3:0]}  = 行*16 + 桁
    input  wire [7:0] wr_data,     // ASCII (bit7 = 反転表示)

    // OLED 接続 (オープンドレイン: 1 で Low に引く)
    output reg        oled_scl_oe,
    output reg        oled_sda_oe,

    output reg        frame_done   // 1画面転送するごとに1クロックのパルス
);
    // ---------------------------------------------------------
    // メモリ
    // ---------------------------------------------------------
    reg [7:0] tram [0:127];        // テキスト 16x8
    reg [7:0] font [0:1023];       // フォント 128文字 x 8列
    integer i;
    initial begin
        for (i = 0; i < 128; i = i + 1) tram[i] = 8'h20;   // 空白で初期化
        $readmemh(FONT_FILE, font);
    end

    always @(posedge clk)
        if (wr_en) tram[wr_addr] <= wr_data;

    reg  [6:0] tram_addr;
    reg  [7:0] tram_q;
    reg  [9:0] font_addr;
    reg  [7:0] font_q;
    always @(posedge clk) begin
        tram_q <= tram[tram_addr];
        font_q <= font[font_addr];
    end

    // ---------------------------------------------------------
    // 初期化コマンド列
    // ---------------------------------------------------------
    localparam integer INIT_LEN = 25;
    function [7:0] init_cmd(input [4:0] n);
        case (n)
            5'd0:  init_cmd = 8'hAE;   // 表示OFF
            5'd1:  init_cmd = 8'hD5;   // クロック分周
            5'd2:  init_cmd = 8'h80;
            5'd3:  init_cmd = 8'hA8;   // マルチプレクス比
            5'd4:  init_cmd = 8'h3F;   //   64行
            5'd5:  init_cmd = 8'hD3;   // 表示オフセット
            5'd6:  init_cmd = 8'h00;
            5'd7:  init_cmd = 8'h40;   // 開始ライン 0
            5'd8:  init_cmd = 8'h8D;   // チャージポンプ
            5'd9:  init_cmd = 8'h14;   //   ON(内部昇圧)
            5'd10: init_cmd = 8'h20;   // アドレッシングモード
            5'd11: init_cmd = 8'h00;   //   水平
            5'd12: init_cmd = 8'hA1;   // セグメント反転  (上下左右が逆なら A0)
            5'd13: init_cmd = 8'hC8;   // COM走査方向反転 (上下左右が逆なら C0)
            5'd14: init_cmd = 8'hDA;   // COMピン構成
            5'd15: init_cmd = 8'h12;
            5'd16: init_cmd = 8'h81;   // コントラスト
            5'd17: init_cmd = 8'hCF;
            5'd18: init_cmd = 8'hD9;   // プリチャージ期間
            5'd19: init_cmd = 8'hF1;
            5'd20: init_cmd = 8'hDB;   // VCOMH
            5'd21: init_cmd = 8'h40;
            5'd22: init_cmd = 8'hA4;   // RAMの内容を表示
            5'd23: init_cmd = 8'hA6;   // 通常表示(白黒反転しない)
            5'd24: init_cmd = 8'hAF;   // 表示ON
            default: init_cmd = 8'hE3; // NOP
        endcase
    endfunction

    // 毎フレーム先頭で送るアドレス設定
    function [7:0] addr_cmd(input [2:0] n);
        case (n)
            3'd0: addr_cmd = 8'h21;    // 列アドレス
            3'd1: addr_cmd = 8'h00;
            3'd2: addr_cmd = 8'h7F;
            3'd3: addr_cmd = 8'h22;    // ページアドレス
            3'd4: addr_cmd = 8'h00;
            default: addr_cmd = 8'h07;
        endcase
    endfunction

    // ---------------------------------------------------------
    // I2C 1バイト送信
    //   tx_first = 1: 先に START を出す / tx_last = 1: 送ったあと STOP を出す
    //   1 ビット: [SCL Low・SDA を変える][SCL Low][SCL High][SCL High]
    //   9 ビット目は ACK (SDA を離す。読まない)
    // ---------------------------------------------------------
    reg        tx_start;
    reg  [7:0] tx_byte;
    reg        tx_first, tx_last;
    reg        tx_busy;
    reg  [8:0] tx_sh;              // {データ 8bit, ACK 用の 1}
    reg  [3:0] tx_bit;
    reg  [7:0] tx_div;
    reg  [1:0] tx_q;               // ビット内の区間
    reg  [2:0] tx_ph;
    reg        last;
    localparam P_IDLE = 3'd0, P_START = 3'd1, P_BIT = 3'd2, P_STOP = 3'd3, P_FREE = 3'd4;
    wire q_end = (tx_div == I2C_Q - 1);

    always @(posedge clk) begin
        if (rst) begin
            tx_busy     <= 1'b0;
            tx_ph       <= P_IDLE;
            oled_scl_oe <= 1'b0;               // バスを離す (アイドル: 両方 High)
            oled_sda_oe <= 1'b0;
        end else begin
            if (tx_ph != P_IDLE) tx_div <= q_end ? 8'd0 : tx_div + 8'd1;
            case (tx_ph)
            P_IDLE: if (tx_start) begin
                tx_sh   <= {tx_byte, 1'b1};
                last    <= tx_last;
                tx_bit  <= 4'd0;
                tx_q    <= 2'd0;
                tx_div  <= 8'd0;
                tx_busy <= 1'b1;
                tx_ph   <= tx_first ? P_START : P_BIT;
            end
            // START: SCL High のまま SDA を Low → SCL を Low
            P_START: if (q_end) begin
                tx_q <= tx_q + 2'd1;
                case (tx_q)
                    2'd0: oled_sda_oe <= 1'b1;
                    2'd1: begin oled_scl_oe <= 1'b1; tx_q <= 2'd0; tx_ph <= P_BIT; end
                    default: ;
                endcase
            end
            P_BIT: if (q_end) begin
                tx_q <= tx_q + 2'd1;
                case (tx_q)
                    2'd0: oled_sda_oe <= ~tx_sh[8];        // SCL Low の間に SDA を変える (0 なら Low に引く)
                    2'd1: oled_scl_oe <= 1'b0;             // SCL を離す (High)
                    2'd3: begin                            // ビットの終わり: SCL を Low に
                        oled_scl_oe <= 1'b1;
                        tx_sh <= {tx_sh[7:0], 1'b1};
                        if (tx_bit == 4'd8) begin
                            tx_ph <= last ? P_STOP : P_IDLE;
                            if (!last) tx_busy <= 1'b0;    // SCL Low のまま次のバイトを待つ
                        end else
                            tx_bit <= tx_bit + 4'd1;
                    end
                    default: ;
                endcase
            end
            // STOP: SCL Low で SDA を Low → SCL High → SDA High
            P_STOP: if (q_end) begin
                tx_q <= tx_q + 2'd1;
                case (tx_q)
                    2'd0: oled_sda_oe <= 1'b1;
                    2'd1: oled_scl_oe <= 1'b0;
                    2'd2: begin oled_sda_oe <= 1'b0; tx_q <= 2'd0; tx_ph <= P_FREE; end
                    default: ;
                endcase
            end
            // バス開放時間 (次の START まで 2 区間以上)
            P_FREE: if (q_end) begin
                tx_q <= tx_q + 2'd1;
                if (tx_q == 2'd1) begin tx_busy <= 1'b0; tx_ph <= P_IDLE; end
            end
            default: tx_ph <= P_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------
    // 全体シーケンス
    // ---------------------------------------------------------
    localparam S_RST_LO = 4'd0,  S_RST_HI = 4'd1,
               S_INIT   = 4'd2,  S_ADDR   = 4'd3,
               S_RD0    = 4'd4,  S_RD1    = 4'd5,  S_RD2 = 4'd6, S_RD3 = 4'd7,
               S_DATA   = 4'd8,  S_WAIT   = 4'd9,  S_DHDR = 4'd10;

    reg [3:0]  st, st_ret;
    reg [31:0] cnt;
    reg [4:0]  idx;
    reg [9:0]  bidx;               // 0..1023 : 送信中のバイト位置
    reg        inv;
    wire [7:0] ADDR_W = {I2C_ADDR, 1'b0};

    // 1 バイト送る (first: START を付ける、lst: STOP を付ける)
    task send(input [7:0] b, input first, input lst, input [3:0] ret);
        begin
            tx_byte <= b; tx_first <= first; tx_last <= lst;
            tx_start <= 1'b1; st <= S_WAIT; st_ret <= ret;
        end
    endtask

    always @(posedge clk) begin
        tx_start   <= 1'b0;
        frame_done <= 1'b0;
        if (rst) begin
            st         <= S_RST_LO;
            cnt        <= 32'd0;
            idx        <= 5'd0;
            tram_addr  <= 7'd0;
            font_addr  <= 10'd0;
        end else begin
            case (st)
            S_RST_LO, S_RST_HI: begin              // 電源投入後の待ち (モジュールの内部リセット)
                if (cnt == RESET_CYCLES) begin cnt <= 0; st <= (st == S_RST_LO) ? S_RST_HI : S_INIT; end
                else cnt <= cnt + 1;
            end
            // 初期化: [START] アドレス 0x00 コマンド x INIT_LEN [STOP]
            S_INIT: begin
                if (idx == 5'd0)       send(ADDR_W, 1'b1, 1'b0, S_INIT);
                else if (idx == 5'd1)  send(8'h00,  1'b0, 1'b0, S_INIT);
                else                   send(init_cmd(idx - 5'd2), 1'b0, idx == INIT_LEN + 1, (idx == INIT_LEN + 1) ? S_ADDR : S_INIT);
                idx <= (idx == INIT_LEN + 1) ? 5'd0 : idx + 5'd1;
            end
            // アドレス設定: [START] アドレス 0x00 コマンド x 6 [STOP]
            S_ADDR: begin
                if (idx == 5'd0)       send(ADDR_W, 1'b1, 1'b0, S_ADDR);
                else if (idx == 5'd1)  send(8'h00,  1'b0, 1'b0, S_ADDR);
                else                   send(addr_cmd(idx[2:0] - 3'd2), 1'b0, idx == 5'd7, (idx == 5'd7) ? S_DHDR : S_ADDR);
                idx <= (idx == 5'd7) ? 5'd0 : idx + 5'd1;
            end
            // 表示データの頭: [START] アドレス 0x40
            S_DHDR: begin
                if (idx == 5'd0) begin send(ADDR_W, 1'b1, 1'b0, S_DHDR); idx <= 5'd1; end
                else begin send(8'h40, 1'b0, 1'b0, S_RD0); idx <= 5'd0; bidx <= 10'd0; end
            end
            // ---- 表示データ 1バイト分を読み出す ----
            S_RD0: begin                          // テキスト読み出し
                tram_addr <= {bidx[9:7], bidx[6:3]};   // 行, 桁
                st <= S_RD1;
            end
            S_RD1: st <= S_RD2;                   // tram_q 確定待ち
            S_RD2: begin                          // フォント読み出し
                font_addr <= {tram_q[6:0], bidx[2:0]};
                inv       <= tram_q[7];
                st <= S_RD3;
            end
            S_RD3: st <= S_DATA;                  // font_q 確定待ち
            S_DATA: begin                         // 最後のバイトで STOP、次のフレームへ
                send(inv ? ~font_q : font_q, 1'b0, bidx == 10'd1023, (bidx == 10'd1023) ? S_ADDR : S_RD0);
                bidx <= bidx + 10'd1;
                if (bidx == 10'd1023) frame_done <= 1'b1;
            end
            S_WAIT: begin                         // 送信開始〜完了待ち
                if (!tx_start && !tx_busy) st <= st_ret;
            end
            default: st <= S_RST_LO;
            endcase
        end
    end
endmodule
