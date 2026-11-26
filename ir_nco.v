module ir_nco
#(
    parameter FREQDIV = 50
)
(
    output reg o_clk,
    input      i_clk,
    input      i_rstn
);

    reg [31:0] cnt;

    always @(posedge i_clk or negedge i_rstn) begin
        if(!i_rstn) begin
            cnt   <= 0;
            o_clk <= 0;
        end
        else begin
            if(cnt == (FREQDIV/2)-1) begin
                cnt   <= 0;
                o_clk <= ~o_clk;
            end
            else begin
                cnt <= cnt + 1'b1;
            end
        end
    end

endmodule