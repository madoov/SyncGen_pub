# SyncGen_pub
Outlay sync generator

OUTLAW ビデオ信号ジェネレータの公開用リポジトリです。
昔のパソコン・ゲーム機・アーケード基板の映像信号のタイミングを、ドットクロックから同期の形まで設定して出力する、Efinix Trion T20Q144 の基板です。

## 中身

| フォルダ | 内容 |
| --- | --- |
| `rtl/` | FPGA の RTL (Verilog-2001、Efinity)。トップは `video_gen_top.v`。`*.hex` は文字列・フォント・プリセットの ROM、`timing.sdc` はタイミング制約 |
| `docs/` | 取扱説明書 [`manual.md`](docs/manual.md) と PDF 版 [`SyncGen.pdf`](docs/SyncGen.pdf)、ピン配置 [`pinout.md`](docs/pinout.md) (RTL のポート ⇔ 回路図のネット ⇔ FPGA のピン) |
| `pcb/` | KiCad 10 のプロジェクト (回路図・基板) |
| `efinity/` | Efinity のプロジェクト (`OUTLAW_video_signa_gen.xml`、Interface Designer のピン設定 `.peri.xml`)。プロジェクトは RTL を `../../RTL/` から読む (Windows の Efinity 用) |

## ライセンス

BSD 3-Clause License ([`LICENSE`](LICENSE))。無保証です。
