# Efinity 用タイミング制約 (video_gen_top)
create_clock -name clk50   -period 20.000 [get_ports {clk50}]
create_clock -name dot_clk -period 20.833 [get_ports {dot_clk}]   ;# ドットクロックは最大 48MHz (settings.v の vmax)
create_clock -name tv_clk  -period 37.037 [get_ports {tv_clk}]    ;# テレビ出力 27MHz (Si5351A CLK1)
create_clock -name cap_clk -period 20.000 [get_ports {cap_clk}]   ;# 映像入力の測定 50MHz (Si5351A CLK2、capture-meas)
set_clock_groups -asynchronous -group {clk50} -group {dot_clk} -group {tv_clk} -group {cap_clk}
