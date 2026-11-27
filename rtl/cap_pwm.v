// =============================================================
// コンパレータのしきい値の PWM (2026-11-07、キャプチャ。基板の RC (33kΩ → 10kΩ + 0.1µF) で平滑)
//   周期 1024 クロック (50MHz で 48.8kHz)。out = 1 の割合 = duty / 1024
//   しきい値の電圧 ≈ 3.3V × duty / 1024 × 10k / (33k + 10k) = 0.767V × duty / 1024
//   今は決まった値 (自動の合わせ込みはメニューと一緒に作る。docs/capture_plan.md の 10.3)
// =============================================================
module cap_pwm (
    input  wire       clk,
    input  wire       rst,
    input  wire [9:0] duty,
    output reg        out
);
    reg [9:0] c;
    always @(posedge clk) begin
        if (rst) begin c <= 10'd0; out <= 1'b0; end
        else begin c <= c + 10'd1; out <= (c < duty); end
    end
endmodule
