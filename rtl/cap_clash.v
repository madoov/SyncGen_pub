// =============================================================
// 出力のぶつかりの見張り (2026-11-08、キャプチャ。schematic_todo.md の AK.4)
//   出力モードで外の機器 (ゲーム基板など) をつなぐと、同期の線 (J5-13 / 14) を両側から駆動してしまう
//   (SYNC LV = TTL では 47Ω の経路で 60〜70mA)。部品が傷むのは電流が続いて熱がたまるときなので、すぐに見つけて出力を止める。
//
//   出力モードでは、同期の受けのコンパレータ (cap_hs / cap_vs) は自分の出す HS / VS を見ている。
//   外の機器がつながっていなければ、受けた値は自分の出力と同じ (遅れは数 10ns)。ぶつかると線の電圧が
//   どちらでもない値になり、受けた値が自分の出力と食い違う。
//     - 自分の HS / VS (dot_clk 側のピンの値) を cap_clk にそろえ (2 段)、受けた値 (DDIO の後のサンプル) と比べる
//     - 食い違いが RUN_LOG2 クロック以上続いた時間だけ数える (端の前後の短い食い違いは数えない)
//     - 2^WIN_LOG2 クロックの中で 2^BAD_LOG2 クロックを超えたら clash = 1 (実機の値で 328µs 中 20µs)
//   clash は clr_tgl (別のクロックからの反転。トップは APPLY の cfg_toggle) まで 1 のまま。
//   見るのは en (出力している。別のクロックから) で、しきい値の合わせ込み中 (busy) でないときだけ。
//   見つからない場合: 自分の出力のほうが強く、線が自分の出力どおりに動くとき (相手の出力に電流が流れる。相手に直列の抵抗があれば小さい)
// =============================================================
module cap_clash #(
    parameter integer RUN_LOG2 = 4,            // 16 クロック (320ns) 以上続く食い違いだけ数える
    parameter integer WIN_LOG2 = 14,           // 2^14 クロック = 328µs ごとに数え直す
    parameter integer BAD_LOG2 = 10            // その中で 1024 クロック (20µs) を超えたらぶつかり
)(
    input  wire clk,                           // cap_clk
    input  wire rst,
    input  wire en,                            // 出力している (別のクロックから)
    input  wire busy,                          // cap_thr: しきい値を動かしている
    input  wire own_hs, own_vs,                // 自分の出力のピンの値 (dot_clk 側)
    input  wire hs_in, vs_in,                  // 受けたコンパレータの出力 (DDIO の後のサンプル)
    input  wire clr_tgl,                       // 別のクロックから (反転で clash を消す)
    output reg  clash
);
    (* async_reg = "true" *) reg [1:0] hs_s, vs_s, en_s;
    (* async_reg = "true" *) reg [2:0] cl_s;
    always @(posedge clk) begin
        hs_s <= {hs_s[0], own_hs}; vs_s <= {vs_s[0], own_vs}; en_s <= {en_s[0], en}; cl_s <= {cl_s[1:0], clr_tgl};
    end
    wire clr = cl_s[2] ^ cl_s[1];
    wire act = en_s[1] && !busy;
    wire mis = (hs_s[1] != hs_in) || (vs_s[1] != vs_in);
    reg  [RUN_LOG2:0]   run;
    reg  [WIN_LOG2-1:0] w;
    reg  [BAD_LOG2:0]   bad;
    always @(posedge clk) begin
        if (rst) begin
            clash <= 1'b0; run <= 0; w <= 0; bad <= 0;
        end else begin
            if (clr) clash <= 1'b0;
            if (!act) begin
                run <= 0; w <= 0; bad <= 0;
            end else begin
                run <= mis ? (run[RUN_LOG2] ? run : run + 1'b1) : 0;
                w   <= w + 1'b1;
                if (&w) bad <= 0;
                else if (run[RUN_LOG2] && !bad[BAD_LOG2]) bad <= bad + 1'b1;
                if (bad[BAD_LOG2] && !clr) clash <= 1'b1;
            end
        end
    end
endmodule
