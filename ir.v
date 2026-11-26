`include    "ir_nco.v"


module  ir
(
    output reg  [31:0]  o_data,
    output reg        o_valid,
    input               i_ir_rxb,
    input               i_clk,
    input               i_rstn
);


    localparam  LEADCODE    = 1'b0;
    localparam  DATACODE    = 1'b1; // include Custom Code


    //  Generate 1MHz Clock
    wire                clk_1M;
    ir_nco
    #(
        .FREQDIV        (50         )
    )
    u_ir_nco(
        .o_clk          (clk_1M     ),
        .i_clk          (i_clk      ),
        .i_rstn         (i_rstn     )
    );


    // Sequential Rx Bits
    wire                ir_rx;
    assign              ir_rx   = ~i_ir_rxb;


    reg     [1:0]       seq_rx;
    always @(posedge clk_1M or negedge i_rstn) begin
        if (!i_rstn) begin
            seq_rx  <= 2'b00;
        end else begin
            seq_rx  <= {seq_rx[0], ir_rx};
        end
    end


    // Count Signal Polarity (High & Low)
    reg     [15:0]      cnt_h;
    reg     [15:0]      cnt_l;
    always @(posedge clk_1M or negedge i_rstn) begin
        if (!i_rstn) begin
            cnt_l   <= 16'd0;
            cnt_h   <= 16'd0;
        end else begin
            case(seq_rx)
                2'b00:  begin
                    cnt_l   <= cnt_l + 1;
                    cnt_h   <= cnt_h;
                end
                2'b01:  begin
                    cnt_l   <= 16'd0;
                    cnt_h   <= 16'd0;
                end
                2'b10:  begin
                    cnt_l   <= cnt_l;
                    cnt_h   <= cnt_h;
                end
                2'b11:  begin
                    cnt_l   <= cnt_l;
                    cnt_h   <= cnt_h + 1;
                end
            endcase
        end
    end


    // FSM
    reg             c_state;
    reg             n_state;
    reg     [5:0]   cnt;


    // State Register
    always @(posedge clk_1M or negedge i_rstn) begin
        if (!i_rstn) begin
            c_state <=  LEADCODE;
        end else begin
            if (seq_rx == 2'b01) begin
                c_state <=  n_state;
            end else begin
                c_state <=  c_state;
            end
        end
    end


    always @(posedge clk_1M or negedge i_rstn) begin
        if (!i_rstn) begin
            cnt <= 5'd0;
        end else begin
            if (c_state == LEADCODE) begin
                cnt <= 5'd0;
            end else begin
                if (seq_rx == 2'b01) begin
                    cnt <= cnt + 1;
                end else begin
                    cnt <= cnt;
                end
            end
        end
    end


    // Next State Logic
    always @(*) begin
        case (c_state)
            LEADCODE: begin
                if (cnt_h >= 8500 && cnt_l >= 4000) begin
                    n_state = DATACODE;
                end else begin
                    n_state = LEADCODE;
                end
            end
            DATACODE: begin
                if (cnt == 5'd31) begin
                    n_state = LEADCODE;
                end else begin
                    n_state = DATACODE;
                end
            end
        endcase
    end
    
    // Output Logic
    reg         rx_bit;
    always @(*) begin
        case (c_state)
            DATACODE: begin
                if (cnt_l >= 1000) begin
                    rx_bit  = 1'b1;
                end else begin
                    rx_bit  = 1'b0;
                end
            end
            default:rx_bit  = 1'b0;
        endcase
    end


    always @(posedge clk_1M or negedge i_rstn) begin
        if (!i_rstn) begin
            o_data <= 32'd0;
        end
        else begin

            // 새로운 프레임 시작 시 데이터 초기화
            if(c_state == LEADCODE &&
               n_state == DATACODE) begin
                o_data <= 32'd0;
            end

            else if(c_state == DATACODE &&
                    seq_rx == 2'b01) begin
                o_data <= {o_data[30:0], rx_bit};
            end
        end
    end

    always @(posedge clk_1M or negedge i_rstn) begin
        if (!i_rstn) begin
            o_valid <= 1'b0;
        end
        else begin
            o_valid <= 1'b0;

            if (c_state == DATACODE &&
                seq_rx == 2'b01 &&
                cnt == 6'd31) begin
                o_valid <= 1'b1;
            end
        end
    end

endmodule