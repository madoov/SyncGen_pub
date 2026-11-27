# FPGA ピン割り当て (T20Q144、U7)

RTL のトップ `rtl/video_gen_top.v` のポートと、KiCad 回路図 (`pcb/Video_signal_checker.kicad_sch`) のネット・FPGA ピンの対応です。
Efinity の Interface Designer でピンを割り当てるときと、回路図を直すときの基準にします。

5 回目のアップロード (main 89ad2e4) の基板ファイルのネットと、下の表がすべて一致することを確認済み。
ブランチ tv-out では 2026-10-25 のアップロード (5f85024) の基板ファイルと、Efinity のコンパイル結果 (a608661 の `*.pinout.csv`) の両方と一致を確認済み。
このブランチ (lag-check-version) では 2026-10-21 のアップロード (cef5e5f、遅延測定・JAMMA・Si5351A・同期の電圧の切り替え) の基板ファイルと一致を確認済み (部品番号もこの版の番号)。

すべてのバンクの VCCIO は 3.3V。

## 一覧

| RTL ポート | 向き | ネット | ピン | FPGA ピン名 | 状態 |
|---|---|---|---|---|---|
| `clk50` | 入力 | /50MHz | 132 | GPIOL_74_PLLIN0 | Y1 KC2520Z (tv-out 5832bb6 で U9 → Y1)。Interface Designer で PLL_TL0 (50MHz → 50MHz) を通す |
| `dot_clk` | 入力 | /5351_CLK | **14** | GPIOL_25_CLK1 | **Si5351A (U4) CLK0** → R20 22Ω (グローバルクロック入力)。(main は LTC6903 CLK)。tv-out (0d98a15) で 15 番から 14 番に移した (ユーザーの判断、配線の都合) |
| `tv_clk` | 入力 | /5351_TVCLK | **15** | GPIOL_24_CLK0 | tv-out。**Si5351A (U4) CLK1** (27MHz) → R47 22Ω (グローバルクロック入力) |
| `rst_n` | 入力 | /rst_n | 48 | GPIOB_TXN09 | S3 (押すと Low)、R5 10k プルアップ、C5 0.1µF |
| `osc_sda_out` / `osc_sda_oe` | 出力 + OE | /5351_SDA | 144 | GPIOL_64 | Si5351A SDA (5 番、直結)。R16 4.7kΩ で 3V3_OSC にプルアップ。オープンドレイン |
| `osc_scl_out` / `osc_scl_oe` | 出力 + OE | /5351_SCL | 141 | GPIOL_65 | Si5351A SCL (4 番、直結)。R14 4.7kΩ で 3V3_OSC にプルアップ。オープンドレイン |
| (なし) | — | — | 6 / 139 | GPIOL_46 / GPIOL_68 | Si5351A 版では使わない (LTC6903 の /SEN と OE だった)。tv-out では 6 = `tv_c[0]`、139 = `tv_cvbs[5]` |
| `btn_n[0]` (SEL) | 入力 | /BTN_SEL | 39 | GPIOB_TXN00 | S4、R9 10k、C3 0.1µF |
| `btn_n[1]` (UP) | 入力 | /BTN_UP | 41 | GPIOB_TXN02 | S5、R6 10k、C4 0.1µF |
| `btn_n[2]` (DOWN) | 入力 | /BTN_DN | 43 | GPIOB_TXN04 | S6、R7 10k、C2 0.1µF |
| `btn_n[3]` (STEP) | 入力 | /BTN_STEP | 46 | GPIOB_TXN06 | S2、R4 10k、C6 0.1µF |
| `oled_scl_out` / `oled_scl_oe` | 出力 + OE | /OLED_SCL | 81 | GPIOR_139 | J3-3 (SCL)。R17 4.7k プルアップ。オープンドレイン (下の注) |
| `oled_sda_out` / `oled_sda_oe` | 出力 + OE | /OLED_SDA | 82 | GPIOR_138 | J3-4 (SDA)。R18 4.7k プルアップ。オープンドレイン (下の注) |
| `ee_cs_n` | 出力 | /EE_CS_N | 124 | GPIOR_76_PLLIN0 | U5 25LC640A、R19 プルアップ |
| `ee_sck` | 出力 | /EE_SCK | 123 | GPIOR_77_PLLIN1 | |
| `ee_mosi` | 出力 | /EE_MOSI | 119 | GPIOR_78_EXTFB0_CDI31 | |
| `ee_miso` | 入力 | /EE_MISO | 118 | GPIOR_79_EXTFB1_CDI30 | |
| `vga_r3` | 出力 | /R3 | 59 | GPIOB_RXN02 | R26 510Ω |
| `vga_r2` | 出力 | /R2 | 56 | GPIOB_RXN00 | R27 1kΩ |
| `vga_r1` | 出力 | /R1 | 71 | GPIOB_CLKP0 | R28 2kΩ |
| `vga_r0` | 出力 | /R0 | 72 | GPIOB_CLKN0 | R29 3.3kΩ |
| `vga_g3` | 出力 | /G3 | 66 | GPIOB_RXP07 | R30 510Ω |
| `vga_g2` | 出力 | /G2 | 61 | GPIOB_RXP03 | R31 1kΩ |
| `vga_g1` | 出力 | /G1 | 58 | GPIOB_RXP02 | R32 2kΩ |
| `vga_g0` | 出力 | /G0 | 55 | GPIOB_RXP00 | R33 3.3kΩ |
| `vga_b3` | 出力 | /B3 | 69 | GPIOB_RXN12 | R34 510Ω |
| `vga_b2` | 出力 | /B2 | 68 | GPIOB_RXN10 | R35 1kΩ |
| `vga_b1` | 出力 | /B1 | 65 | GPIOB_RXN07 | R36 2kΩ |
| `vga_b0` | 出力 | /B0 | 60 | GPIOB_RXN03 | R37 3.3kΩ |
| `vga_hsync` | 出力 | /HS | 67 | GPIOB_RXP10 | U8 74AHCT125 (キャプチャの改版では 74LVC125A、+3V3、回路図 4d0f8e9 では U6): 回路 1 (OE = GND、改版では /OUT_OE_N) → R41 470Ω (改版では 270Ω) と、回路 2 (OE = /HS_TTL_OE_N) → R42 47Ω を /HSYNC で合流 |
| `vga_vsync` | 出力 | /VS | 70 | GPIOB_RXP12 | U8 74AHCT125 (改版では 74LVC125A): 回路 4 (OE = GND、改版では /OUT_OE_N) → R44 470Ω (改版では 270Ω) と、回路 3 (OE = /HS_TTL_OE_N) → R43 47Ω を /VSYNC で合流 |
| `lag_sens` | 入力 | /LAG_SENS | 83 | GPIOR_136_CDI16 | U9 LM393 の OUT A (1 番、tv-out fafed13 で LMV331 から変更)、R38 10k プルアップ (`docs/lag_meas.md`) |
| `lag_thr` | 出力 | /LAG_THR | 84 | GPIOR_135_CDI17 | R25 33k → /LAG_VTH (R24 10k、C31 0.1µF) → U9 IN- A (2 番) |
| `tv_y[0]`〜`tv_y[7]` | 出力 | /y0〜/y7 | 109, 110, 111, 112, 113, 114, 115, 116 | GPIOR_88, 87, 85, 86, 84, 83, 82, 81 | tv-out。Y の DAC (2kΩ アレイ RN5 (y0〜y3)・RN6 (y4〜y7)、1kΩ アレイ RN7・RN8、終端 R64、出力 R48 680Ω) → IC1 THS7314 CH1 → R51 75Ω → J7-4 (S 端子、8174060 から) |
| `tv_c[0]`〜`tv_c[7]` | 出力 | /c0〜/c7 | 6, 7, 8, 10, 11, 16, 17, 18 | GPIOL_46, 41, 40, 32, 31, 22, 21, 20 | tv-out。C の DAC (RN9・RN11、RN10・RN12、R65、R49) → IC1 CH2 → R52 → J7-2 (S 端子、8174060 から) |
| `tv_cvbs[0]`〜`tv_cvbs[7]` | 出力 | /cvbs0〜/cvbs7 | 131, 134, 135, 139, 140, 142, 3, 4 | GPIOL_75, 73, 72, 68, 67, 66, 53, 54 | tv-out。CVBS の DAC (RN13・RN15、RN14・RN16、R66、R50) → IC1 CH3 → R53 → J6-2 (RCA) |
| `hs_ttl_oe_n` | 出力 | /HS_TTL_OE_N | 75 | GPIOR_157_PLLIN | U8 74AHCT125 の 2OE (4 番)・3OE (10 番)。0 = TTL (R42 / R43 47Ω の側も出す)、1 = LOW (Hi-Z、初期値)。R40 10k で +3V3 にプルアップ (コンフィグ前も LOW)。PLL の入力にも使えるピンだが、ここでは普通の出力 |
| `cap_clk` | 入力 | /Cap_CLK | 92 | GPIOR_125_CLK10 | capture-meas、**回路図・基板 (517c097) に入った、Interface Designer に入れた (2026-11-07)**。Si5351A (U4) CLK2 (50MHz) → R55 22Ω。GCLK |
| `cap_vr_hi` / `cap_vr_lo` | 入力 (DDIO) | /cap_vid_r | 77 | GPIOR_154 | **回路図・基板 (8f9dd33) に入った**。R を IC3 TLV3502 A で見る (R59 100Ω → +IN A)。R が黒以外なら 1。DDIO resync、クロック cap_clk。RTL は 3 色を OR して「黒以外」に |
| `cap_vg_hi` / `cap_vg_lo` | 入力 (DDIO) | /cap_vid_g | 86 | GPIOR_133_CDI18 | **回路図・基板 (8f9dd33) に入った**。G を IC3 TLV3502 B で見る (R60 100Ω → +IN B)。以前の cap_vid (合成) のピン |
| `cap_vb_hi` / `cap_vb_lo` | 入力 (DDIO) | /cap_vid_b | 76 | GPIOR_155 | **回路図・基板 (8f9dd33) に入った**。B を IC4 TLV3502 A で見る (R61 100Ω → +IN A) |
| `cap_hs_hi` / `cap_hs_lo` | 入力 (DDIO) | /cap_hs | 87 | GPIOR_132_CDI19 | **回路図・基板 (8f9dd33) に入った**。入力の HSYNC か CSYNC (J5-13 を R68 / R70 で分圧して IC2 TLV3502 A で受ける) |
| `cap_vs_hi` / `cap_vs_lo` | 入力 (DDIO) | /cap_vs | 89 | GPIOR_129_CTRL10 | **回路図・基板 (8f9dd33) に入った**。入力の VSYNC (J5-14、R69 / R71 で分圧して IC2 B。CSYNC のときはつながない) |
| `cap_tx` | 出力 | /cap_tx | 90 | GPIOR_128_CTRL11 | **回路図・基板 (8f9dd33) に入った**。J8-1。2026-11-10 から使わない (High のまま。確かめ用の UART を容量のため外した) |
| `cap_thr` | 出力 | /cap_thr | 98 | GPIOR_117_CTRL14 | **回路図に入った**。RTL は `cap_pwm` (cap_clk) の PWM を `cap_thr` が自動で合わせる (CAP RUN のとき)。U6 のしきい値 (PWM → R63 33kΩ / R67 10kΩ / C48) |
| `cap_sthr` | 出力 | /cap_sthr | 99 | GPIOR_116_CTRL15 | **回路図・基板 (674245b) に入った** (674245b で 100 番から 99 番へ入れ替え)。RTL は `cap_pwm` の PWM を `cap_thr` が自動で合わせる。IC2 のしきい値 (PWM → R74 33kΩ / R75 10kΩ / C49、A / B 共用) |
| `out_oe_n` | 出力 | /OUT_OE_N | 100 | GPIOR_113_CDI22 | **回路図・基板 (674245b) に入った** (99 番から 100 番へ入れ替え、R54 1kΩ 越し)。RTL はメニューの CAP IN とぶつかりの見張りで 1。0 = 出力モード、1 = 入力モード (U8 の 1OE / 4OE、S3 経由で Q3〜Q5)。R76 10kΩ プルアップ。S2 = IN で基板が +3V3 に |
| `mode_sw` | 入力 | /OUT_OE_N | 101 | GPIOR_112_CDI23 | **回路図・基板 (674245b) に入った** (`schematic_todo.md` の AK3)。切り替えスイッチ S2 の向き (1 = IN = 入力モード)。S2 が IN なら /OUT_OE_N は基板でじかに +3V3 |
| `term_sw` | 入力 | /TERM_SW (AS 節で /TERM_EN から) | 102 | GPIOR_105_CDI24 | **改版で足す** (`schematic_todo.md` の AK10 / AS1)。終端の切り替えスイッチ S3 の向き (1 = 75Ω の終端あり。S3 の NO をじかに読む)。入力モードで終端ありのとき、VID が高すぎないかを見る。スイッチのない基板では未接続 (弱いプルダウン) |
| `term_off` | 出力 | /TERM_OFF | 103 | GPIOR_104_CDI25 | **改版で足す** (`schematic_todo.md` の AS 節、2026-11-09)。1 = 終端を切る (Q6 で /TERM_EN を GND に)。入力モードで S3 = 75Ω、HI LEVEL でないときだけ 0。基板で R81 100kΩ のプルアップ (コンフィグ中もプルアップで切る) |

キャプチャのピン (cap_*・out_oe_n) は 2026-11-07 に `efinity/OUTLAW_video_signa_gen/OUTLAW_video_signa_gen.peri.xml` に入れた (ユーザーの依頼):
cap_clk = GPIOR_125 (GCLK)、cap_vr / cap_vg (以前の cap_vid) / cap_vb / cap_hs / cap_vs = GPIOR_154 / 133 / 155 / 132 / 129 (2026-11-08 に回路図 8f9dd33 の割り当てに合わせた) (入力、レジスタ、DDIO resync、クロック cap_clk、
名前は `*_hi` と name_ddio_lo の `*_lo`)、cap_tx / cap_thr / out_oe_n / cap_sthr = GPIOR_128 / 117 / 113 / 116 (出力、レジスタなし。2026-11-08 に回路図 674245b に合わせて out_oe_n と cap_sthr を入れ替え)。

`vga_r3` / `vga_g3` / `vga_b3` が最上位ビット (510Ω 側)。RGB は Interface Designer で 1 本ずつ register にできるよう、1 ビットずつのポートにしている (バスにすると 1 本ずつ設定できないため)。

コンフィグ用 (RTL のポートではない): SPI フラッシュ U2 (W25Q128) は GPIOL_00_SS_N (31) / GPIOL_01_CCK (30) / GPIOL_08_CDI0 (29) / GPIOL_09_CDI1 (28)、JTAG・CRESET (S7)・CDONE は J1 とつながっている。CBUS0〜2・TEST_N は RN2 で固定。

**OLED (I2C、2026-10-15 に SPI から変更)**: SSD1306 の I2C 4 ピンモジュール (アドレス 0x3C)。J3 は 4 ピン
(よくある並びは GND / VCC / SCL / SDA だが、VCC と GND が逆のものもある。買うモジュールのシルクに合わせる)。
75 / 76 / 77 番 (RES / DC / CS) は使わなくなる (75 番は 2026-10-21 から `hs_ttl_oe_n`)。
- SCL / SDA はオープンドレイン: Efinity の Interface Designer で 81 / 82 番の GPIO を inout (双方向) にし、
  OUT = `oled_*_out` (常に 0)、OE = `oled_*_oe` につなぐ。OE = 1 で Low、0 で離す。
  IN (入力) は今の RTL では使わない (ACK を読まないため。使う場合は `oled_sda_in` などを足す)
- High はモジュールのプルアップ抵抗 (多くは 4.7k〜10k で VCC へ) で上がる。モジュールにプルアップがなければ
  基板に 4.7kΩ を +3V3 へ付ける (または FPGA 側の弱いプルアップを有効にする)
- モジュールの VCC は +3V3 につなぐ (5V につなぐとプルアップで SCL / SDA が 5V になる)


## Interface Designer の出力レジスタ (Register Option)

RTL の出力はどれもモジュールの中でフリップフロップから出している (`osc_*_out` と `oled_*_out` は定数 0)。
I/O のレジスタ (Register) を使うのは VGA の 14 本だけ。ほかは none (レジスタなし) でよい。

| ポート | Register Option | 出力クロック | 理由 |
|---|---|---|---|
| `vga_r0`〜`vga_r3`、`vga_g0`〜`vga_g3`、`vga_b0`〜`vga_b3`、`vga_hsync`、`vga_vsync` | **register** | `dot_clk` | 最大 48MHz。I/O のレジスタから出すと、ピンまでの遅れが 14 本でそろい、RGB と同期のずれがなくなる。遅れは 14 本とも 1 クロック増えるだけなので表示は変わらない (14 本は必ず全部そろえる) |
| `osc_scl_oe`、`osc_sda_oe` | none | — | Si5351A の I2C (約 368kHz)。141 / 144 番は OLED と同じく inout |
| `ee_cs_n`、`ee_sck`、`ee_mosi` | none | — | EEPROM の SPI。同上 |
| `oled_scl_oe`、`oled_sda_oe` | none | — | I2C (約 368kHz) |
| `osc_scl_out`、`osc_sda_out`、`oled_scl_out`、`oled_sda_out` | none | — | 定数 (0) |
| `lag_thr` | none | — | 遅延測定のしきい値 PWM (約 49kHz) |
| `hs_ttl_oe_n` | none | — | 同期の電圧の切り替え (APPLY のときだけ変わる) |
| `tv_y[7:0]`、`tv_c[7:0]`、`tv_cvbs[7:0]` (tv-out) | **register** | `tv_clk` | 27MHz。R-2R はビットを同時に足すので、ピンまでの遅れの差が切り替わりのひげになる。24 本とも 1 クロック遅れるだけ |

入力も none でよい (`btn_n` と `lag_sens` は RTL の中で 2 段の同期、`rst_n` は非同期で入って clk50 で同期して解除、`ee_miso` は SCK を出している clk50 でそのまま読む)。

## 2026-10-14 の変更 (KiCad)

- LTC6903 の制御 4 本をコンフィグ兼用ピン (17〜20) から 144 / 141 / 6 / 139 へ (OE は 2 回目のアップロードで 140 → 139)
- コンデンサのフットプリントを C_0402 / C_0603 に、RN6 を 10k に
- リセット用タクトスイッチ S10 (/rst_n → 48) を追加。各ボタンに 0.1µF (C8〜C12) を追加
- OLED を I2C 版 4 ピン (J4) から SPI 版 7 ピン (J5) へ
- 50MHz 発振器の 131 番 (PLLIN1) への接続をなくした (132 番 PLLIN0 だけ)
- J1 の 12 番を GND に
- (3 回目) USB-C (J2) の GND を GND ネットに。FPGA のパスコン 0.1µF × 22 (C13〜C20, C22〜C35)、VCCA_BR (73 番) を FB2 + C21 で分離。C5 10µF / C7 22µF
- (2026-10-15、RTL) OLED を I2C に変更。J5 は 4 ピン (GND / VCC / SCL / SDA)、75〜77 番は不要に。**KiCad の回路図の変更が必要**
- (4 回目、main c9106bb) OLED を J4 (I2C 4 ピン、GND / +3V3 / SCL / SDA) に。R44 / R45 で SCL / SDA をプルアップ。基板のネットと上の表 (50MHz は 132 番のまま) が一致することを確認。**50MHz の 92 番への変更はまだ**
- (5 回目、main 89ad2e4) U4 のパスコン C40 を追加、C38 の位置を修正、スイッチに LCSC 番号。50MHz は 132 番 (PLLIN0) のまま、REF_RES (36 番) は未接続のままに決定。ピンは上の表とすべて一致
- (2026-10-16) タクトスイッチを TL3305 に戻し、番号を変更: SEL = S7、UP = S8、DOWN = S9、STEP = S10、リセット (/rst_n) = S12、FPGA リセット (/CRESET) = S13。電源スイッチは S5 (MSK12C02)
- (2026-10-16、RTL) 表示遅延の測定を追加。`lag_sens` (83 番)・`lag_thr` (84 番) を使う。**KiCad の回路図・基板への追加が必要** (`docs/lag_meas.md`、`schematic_todo.md` の L)
- (2026-10-20、ブランチ lag-check-version、遅延測定のブランチをマージ済み) LTC6903 を Si5351A に置き換え。141 番 = SCL、144 番 = SDA (I2C、オープンドレイン)、6 番と 139 番は不要に。詳しくは `docs/si5351.md`
- (2026-10-21、RTL、lag-check-version) 同期の電圧の切り替え (メニュー No.13 SYNC LV) を追加。`hs_ttl_oe_n` を使う。2026-10-21 (cef5e5f) の基板で U8 74AHCT125 (4 回路を 1 個に) と FPGA 75 番で追加済み (`schematic_todo.md` の O)
- (2026-10-21、cef5e5f) 回路図の部品番号を振り直した (FPGA は U5 → U7、VGA は J3 → J5、OLED は J4 → J3、遅延測定のセンサーは J5 → J4 など)。上の表は新しい番号。下の古い記録は当時の番号のまま
  - 対応 (旧 → 新): C1→C16、C2→C19、C3→C21、C4→C1、C5→C7、C6→C8、C7→C9、C8→C3、C9→C4、C10→C2、C11→C5、C12→C6、C13→C24、C14→C22、C15→C29、C16→C34、C17→C23、C18→C25、C19→C30、C20→C35、C21→C40、C22→C26、C23→C27、C24→C32、C25→C33、C26→C36、C27→C37、C28→C38、C29→C39、C30→C17、C31→C20、C32→C12、C33→C13、C34→C15、C35→C14、C38→C18、C39→C41、C40→C28、C41→C10、C42→C11、C51→C43、C52→C45、C62→C42、C63→C31、D7→D2、J3→J5、J4→J3、J5→J4、R1→R2、R2→R3、R6→R26、R8→R20、R9→R27、R10→R28、R11→R29、R12→R30、R13→R31、R14→R32、R15→R33、R16→R34、R17→R35、R18→R36、R19→R37、R22→R1、R23→R10、R24→R11、R25→R12、R26→R13、R27→R16、R28→R14、R40→R15、R42→R8、R43→R19、R44→R17、R45→R18、R47→R39、R48→R45、R49→R46、R50→R9、R51→R6、R52→R7、R53→R4、R54→R5、R60→R22、R61→R23、R62→R38、R63→R25、R64→R24、R65→R21、RN6→RN1、RN7→RN2、RN8→RN3、RN9→RN4、S5→S1、S7→S4、S8→S5、S9→S6、S10→S2、S12→S3、S13→S7、U1→U3、U4→U2、U5→U7、U6→U9、U7→U1、U8→U5、U9→U6、U10→U4、Y2→Y1。同期のバッファ U2 / U3 (74AHCT1G125) と R20 / R21 / C36 / C37 は、U8 (74AHCT125)・R41〜R44・C44 に置き換え
- (2026-10-22、tv-out 0d98a15) テレビ出力の回路を追加。`dot_clk` を 15 番 → **14 番**に、`tv_clk` (Si5351A CLK1、27MHz) を **15 番**に (ユーザーの判断)。Interface Designer で `dot_clk` のピンを 14 番に変える。DAC 3 つ (`tv_y` / `tv_c` / `tv_cvbs`) のピンは上の表。回路図と基板のネットが一致することを確認 (`tools/sch_nets.py`)
- (2026-10-23、tv-out 3d9ac0a) CVBS のピンの割り当てを FPGA の周に沿った順に変更 (cvbs0〜7 = 131, 134, 135, 139, 140, 142, 3, 4。交差を減らすため)。RTL は変えない (Interface Designer の割り当てだけ)
