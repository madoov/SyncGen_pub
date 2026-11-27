// =============================================================
// VGA 出力への情報表示 (OSD)
//   32 文字 x 8 行のテキストを、画面の中央に重ねて表示する
//     - テキストは osd_text が 50MHz 側で書く (読むのはドットクロック側)
//       内容: ドットクロック・H/V のドット数と同期・水平/垂直周波数
//     - 文字コードの bit7 = 1 は反転表示
//     - 白い文字に黒い背景。表示幅 576 ドット以上かつ 256 ライン以上なら 2 倍
//       (512x128 ドット)、それより小さい画面では等倍 (256x64 ドット)
//     - 表示幅が 256 ドットより狭いときは右側が切れる
//     - osd_en (別クロックから入れてよい) が 0 のときは何もしない
//     - メニュー (2026-11-11): menu_en が 1 の間は、OLED と同じ 16 文字 x 8 行 (menu_display が書く) を枠の中央
//       (32 文字のうち 9〜24 文字目) に出す (osd_en によらない。左右の 8 文字ずつは重ねない)
//
//   遅れ: vga_pattern の出力 (RGB・同期) に 3 クロック足して出す
//         (OSD の画素は x/y から 4 クロック: 座標計算 → 文字メモリ → フォント → 合成)
//         同期信号も同じだけ遅らせるので、画面の位置はずれない
// =============================================================
module vga_osd #(
    parameter FONT_FILE = "font8x8.hex",
    parameter ZOOM = 0              // 1: 576x256 以上で 2 倍に拡大 (2026-11-23 に 0 = いつも等倍へ。解像度をわかりやすくするため。戻すときは 1)
)(
    // テキストの書き込み (osd_text から)
    input  wire        wclk,
    input  wire        wr_en,
    input  wire [7:0]  wr_addr,       // {行[2:0], 桁[4:0]}
    input  wire [7:0]  wr_data,       // ASCII (bit7 = 反転表示)
    // メニュー (OLED と同じ文字、menu_display から。wclk)
    input  wire        mwr_en,
    input  wire [6:0]  mwr_addr,      // {行[2:0], 桁[3:0]}
    input  wire [7:0]  mwr_data,      // bit7 = 反転表示 (選んでいる項目)
    input  wire        menu_en,       // 1 = メニューを出す (別クロックから入れてよい)

    input  wire        dclk,
    input  wire        osd_en,        // 1 = 表示 (別クロックから入れてよい)
    // vga_timing から (遅れ 0)
    input  wire        de,
    input  wire [11:0] x, y, h_active, v_active,
    // vga_pattern から (遅れ 1)
    input  wire [3:0]  r_in, g_in, b_in,
    input  wire        hs_in, vs_in,
    input  wire        sub_in,        // vga_pattern: 黒より下の画素 (SMPTE の PLUGE、r_in と同じ遅れ)
    // ピンへ (遅れ 4)
    output reg  [3:0]  r, g, b,
    output reg         hsync_o, vsync_o,
    output reg         osd_o,         // 1 = この画素は OSD (r / g / b と同じ遅れ。テレビ出力が使う)
    output reg         sub_o          // 黒より下の画素 (OSD の画素では 0。r / g / b と同じ遅れ。テレビ出力が使う)
);
    // ---------- メモリ ----------
    reg [7:0] tram [0:255];           // テキスト 32x8 (書き込み wclk / 読み出し dclk)
    reg [7:0] mram [0:127];           // メニュー 16x8 (書き込み wclk / 読み出し dclk)
    reg [7:0] font [0:1023];          // フォント 128 文字 x 8 列 (列ごと、bit0 = 上)
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) tram[i] = 8'h20;
        for (i = 0; i < 128; i = i + 1) mram[i] = 8'h20;
        $readmemh(FONT_FILE, font);
    end
    always @(posedge wclk)
        if (wr_en) tram[wr_addr] <= wr_data;
    always @(posedge wclk)
        if (mwr_en) mram[mwr_addr] <= mwr_data;

    (* async_reg = "true" *) reg [1:0] en_s;
    (* async_reg = "true" *) reg [1:0] mn_s;
    always @(posedge dclk) begin en_s <= {en_s[0], osd_en}; mn_s <= {mn_s[0], menu_en}; end
    wire en = en_s[1];
    wire mn = mn_s[1];

    // ---------- 表示サイズから決まる値 (めったに変わらないのでレジスタに) ----------
    //   2 倍: 512x128 ドット、等倍: 256x64 ドット。左上 = (表示 - 大きさ) / 2。2 倍は ZOOM = 1 のときだけ
    reg        big;
    reg [11:0] x0, y0, x1, y1;        // 枠: x0 <= x < x1, y0 <= y < y1
    always @(posedge dclk) begin
        big <= (ZOOM != 0) && (h_active >= 12'd576) && (v_active >= 12'd256);
        x0  <= big ? ((h_active - 12'd512) >> 1) : (h_active >= 12'd256 ? (h_active - 12'd256) >> 1 : 12'd0);
        y0  <= big ? ((v_active - 12'd128) >> 1) : (v_active >= 12'd64  ? (v_active - 12'd64)  >> 1 : 12'd0);
        x1  <= x0 + (big ? 12'd512 : 12'd256);
        y1  <= y0 + (big ? 12'd128 : 12'd64);
    end

    // ---------- 1 段目: OSD の中の座標 ----------
    reg  [11:0] rx, ry;
    reg         in1, mn1;
    wire [11:0] dx = x - x0, dy = y - y0;
    always @(posedge dclk) begin
        rx  <= big ? (dx >> 1) : dx;              // 等倍の座標 (0〜255, 0〜63)
        ry  <= big ? (dy >> 1) : dy;
        in1 <= (en || mn) && de && (x >= x0) && (x < x1) && (y >= y0) && (y < y1);
        mn1 <= mn;
    end

    // ---------- 2 段目: 文字メモリ ----------
    reg [7:0] ch;
    reg [2:0] bx2, by2;
    reg       in2;
    always @(posedge dclk) begin
        // メニュー: 9〜24 文字目 (rx[7:3] = 8〜23、rx[7] ^ rx[6]) に 1〜16 桁目 ({rx[7], rx[5:3]})
        ch  <= mn1 ? mram[{ry[5:3], rx[7], rx[5:3]}] : tram[{ry[5:3], rx[7:3]}];
        bx2 <= rx[2:0]; by2 <= ry[2:0]; in2 <= in1 && (!mn1 || (rx[7] ^ rx[6]));
    end

    // ---------- 3 段目: フォント (1 列 8 ドット) ----------
    reg [7:0] fcol;
    reg [2:0] by3;
    reg       inv3, in3;
    always @(posedge dclk) begin
        fcol <= font[{ch[6:0], bx2}];
        by3  <= by2; inv3 <= ch[7]; in3 <= in2;
    end
    wire on = fcol[by3] ^ inv3;

    // ---------- vga_pattern の出力 (遅れ 1) を 2 段遅らせ、3 段目の OSD とそろえて合成 ----------
    reg [14:0] d1, d2;                            // {黒より下, r, g, b, hs, vs}
    always @(posedge dclk) begin
        d1 <= {sub_in, r_in, g_in, b_in, hs_in, vs_in};
        d2 <= d1;
        {r, g, b}          <= in3 ? (on ? 12'hFFF : 12'h000) : d2[13:2];
        {hsync_o, vsync_o} <= d2[1:0];
        osd_o              <= in3;
        sub_o              <= d2[14] && !in3;
    end
endmodule
