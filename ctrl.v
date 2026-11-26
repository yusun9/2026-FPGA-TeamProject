`include "switch_event.v"

module ctrl #(
    parameter integer CLK_FREQ = 50000000,
    parameter integer DEBOUNCE_COUNT = 250000
)
(
    output reg       o_alarm_en,
    output reg [2:0] o_mode,
    output reg [1:0] o_target,

    output reg       o_inc_pulse,
    output reg       o_dec_pulse,
    output reg       o_timer_start,

    output wire      o_blink_en,
    output reg       o_1hz_tick,

    input wire [7:0] i_sw,
    input wire       i_clk,
    input wire       i_rstn,

    input wire [31:0] ir_data,
    input wire        ir_valid
);

//================================================
// MODE
//================================================

localparam [2:0] MODE_CLOCK_RUN  = 3'b000;
localparam [2:0] MODE_CLOCK_SET  = 3'b001;
localparam [2:0] MODE_ALARM_SET  = 3'b010;
localparam [2:0] MODE_TIMER_SET  = 3'b011;
localparam [2:0] MODE_TIMER_RUN  = 3'b100;

//================================================
// TARGET
//================================================

localparam [1:0] TARGET_SEC  = 2'b00;
localparam [1:0] TARGET_MIN  = 2'b01;
localparam [1:0] TARGET_HOUR = 2'b10;

//================================================
// SWITCH EVENT
//================================================

wire sw0_event;
wire sw1_event;
wire sw2_event;
wire sw3_event;
wire sw4_event;

switch_event #(
    .DEBOUNCE_COUNT(DEBOUNCE_COUNT)
) u_sw0 (
    .i_clk(i_clk),
    .i_rstn(i_rstn),
    .i_sw(i_sw[0]),
    .o_event(sw0_event)
);

switch_event #(
    .DEBOUNCE_COUNT(DEBOUNCE_COUNT)
) u_sw1 (
    .i_clk(i_clk),
    .i_rstn(i_rstn),
    .i_sw(i_sw[1]),
    .o_event(sw1_event)
);

switch_event #(
    .DEBOUNCE_COUNT(DEBOUNCE_COUNT)
) u_sw2 (
    .i_clk(i_clk),
    .i_rstn(i_rstn),
    .i_sw(i_sw[2]),
    .o_event(sw2_event)
);

switch_event #(
    .DEBOUNCE_COUNT(DEBOUNCE_COUNT)
) u_sw3 (
    .i_clk(i_clk),
    .i_rstn(i_rstn),
    .i_sw(i_sw[3]),
    .o_event(sw3_event)
);

switch_event #(
    .DEBOUNCE_COUNT(DEBOUNCE_COUNT)
) u_sw4 (
    .i_clk(i_clk),
    .i_rstn(i_rstn),
    .i_sw(i_sw[4]),
    .o_event(sw4_event)
);

//================================================
// 1MHz IR -> 50MHz CLOCK SYNCHRONIZATION
//================================================

reg ir_valid_meta;
reg ir_valid_sync;
reg ir_valid_sync_d;

reg [31:0] ir_data_meta;
reg [31:0] ir_data_sync;

reg [31:0] ir_command;
reg        ir_command_valid;

wire ir_event;

assign ir_event = ir_valid_sync & ~ir_valid_sync_d;

always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        ir_valid_meta   <= 1'b0;
        ir_valid_sync   <= 1'b0;
        ir_valid_sync_d <= 1'b0;

        ir_data_meta <= 32'd0;
        ir_data_sync <= 32'd0;

        ir_command <= 32'd0;
        ir_command_valid <= 1'b0;
    end
    else begin
        ir_valid_meta   <= ir_valid;
        ir_valid_sync   <= ir_valid_meta;
        ir_valid_sync_d <= ir_valid_sync;

        ir_data_meta <= ir_data;
        ir_data_sync <= ir_data_meta;

        ir_command_valid <= 1'b0;

        if (ir_event) begin
            ir_command <= ir_data_sync;
            ir_command_valid <= 1'b1;
        end
    end
end

//================================================
// 1Hz CLOCK TICK
//================================================

reg [31:0] clk_count;

always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        clk_count  <= 32'd0;
        o_1hz_tick <= 1'b0;
    end
    else begin
        o_1hz_tick <= 1'b0;

        if (clk_count >= CLK_FREQ - 1) begin
            clk_count  <= 32'd0;
            o_1hz_tick <= 1'b1;
        end
        else begin
            clk_count <= clk_count + 1'b1;
        end
    end
end

//================================================
// CONTROL
//================================================

always @(posedge i_clk or negedge i_rstn) begin

    if (!i_rstn) begin

        o_mode <= MODE_CLOCK_RUN;
        o_target <= TARGET_SEC;

        o_alarm_en <= 1'b0;

        o_inc_pulse <= 1'b0;
        o_dec_pulse <= 1'b0;
        o_timer_start <= 1'b0;

    end
    else begin

        o_inc_pulse <= 1'b0;
        o_dec_pulse <= 1'b0;
        o_timer_start <= 1'b0;

        //----------------------------------------
        // MENU : MODE CHANGE
        // IR CODE : 00FD40BF
        //----------------------------------------

        if (sw0_event ||
            (ir_command_valid && ir_command == 32'h00FD40BF)) begin

            case (o_mode)

                MODE_CLOCK_RUN:
                    o_mode <= MODE_CLOCK_SET;

                MODE_CLOCK_SET:
                    o_mode <= MODE_ALARM_SET;

                MODE_ALARM_SET:
                    o_mode <= MODE_TIMER_SET;

                MODE_TIMER_SET: begin
                    o_mode <= MODE_TIMER_RUN;
                    o_timer_start <= 1'b1;
                end

                MODE_TIMER_RUN:
                    o_mode <= MODE_CLOCK_RUN;

                default:
                    o_mode <= MODE_CLOCK_RUN;

            endcase
        end

        //----------------------------------------
        // RIGHT : SELECT SEC / MIN / HOUR
        // IR CODE : 00FD50AF
        //----------------------------------------

        if (sw1_event ||
            (ir_command_valid && ir_command == 32'h00FD50AF)) begin

            case (o_target)

                TARGET_SEC:
                    o_target <= TARGET_MIN;

                TARGET_MIN:
                    o_target <= TARGET_HOUR;

                TARGET_HOUR:
                    o_target <= TARGET_SEC;

                default:
                    o_target <= TARGET_SEC;

            endcase
        end

        //----------------------------------------
        // PLUS : INCREASE SELECTED VALUE
        // IR CODE : 00FD20DF
        //----------------------------------------

        if (sw2_event ||
            (ir_command_valid && ir_command == 32'h00FD20DF)) begin

            if ((o_mode == MODE_CLOCK_SET) ||
                (o_mode == MODE_ALARM_SET) ||
                (o_mode == MODE_TIMER_SET)) begin

                o_inc_pulse <= 1'b1;

            end
        end

        //----------------------------------------
        // MINUS : DECREASE SELECTED VALUE
        // IR CODE : 00FD30CF
        //----------------------------------------

        if (sw4_event ||
            (ir_command_valid && ir_command == 32'h00FD30CF)) begin

            if ((o_mode == MODE_CLOCK_SET) ||
                (o_mode == MODE_ALARM_SET) ||
                (o_mode == MODE_TIMER_SET)) begin

                o_dec_pulse <= 1'b1;

            end
        end

        //----------------------------------------
        // OK : ALARM ON / OFF
        // IR CODE : 00FD906F
        //----------------------------------------

        if (sw3_event ||
            (ir_command_valid && ir_command == 32'h00FD906F)) begin

            o_alarm_en <= ~o_alarm_en;

        end

    end
end

//================================================
// BLINK ENABLE
//================================================

assign o_blink_en =
    (o_mode == MODE_CLOCK_SET) ||
    (o_mode == MODE_ALARM_SET) ||
    (o_mode == MODE_TIMER_SET);

endmodule