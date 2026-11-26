`include "ctrl.v"
`include "clock.v"
`include "alarm.v"
`include "timer_setting.v"
`include "setting_display.v"
`include "timer.v"       // Must implement the interface documented in TIMER_INTERFACE_KO.txt.
`include "buzzer.v"
`include "ssegdisp.v"
`include "psd.v"
`include "text_lcd_top.v"
`include "lcd_formatter.v"
`include "text_lcd_ctrl.v"
`include "blink_gen.v"
`include "ir.v"

// NEW top-level for the user's settings implementation.
// This is NOT the teammate's temporary top.v.
// Display format: HH:MM:SS on six 7-segment digits.
module top(
    output wire       o_buzzer,
    output wire [5:0] o_seg_enb,
    output wire [7:0] o_seg,

    output wire       o_lcd_rs,
    output wire       o_lcd_rw,
    output wire       o_lcd_e,
    output wire [7:0] o_lcd_data,

    output wire       o_sclk,    
    output wire       o_csn,   
    output wire       o_din,      
    input  wire       i_dout,
    input  wire [7:0] i_sw,
    input  wire       i_clk,
    input  wire       i_rstn,
    input  wire	 i_ir_rxb
    
);
    wire [2:0] mode;
    wire [1:0] target;
    wire alarm_en;
    wire inc_pulse, dec_pulse;
    wire timer_start;
    wire blink_en;
    wire tick_1hz;

    wire [5:0] clock_hour, clock_min, clock_sec;
    wire [5:0] alarm_hour, alarm_min, alarm_sec;
    wire [5:0] timer_set_hour, timer_set_min, timer_set_sec;
    wire [5:0] timer_run_hour, timer_run_min, timer_run_sec;
    wire timer_buzzer_enb;

    wire [3:0] disp_num0, disp_num1, disp_num2;
    wire [3:0] disp_num3, disp_num4, disp_num5;
    wire [5:0] blink_mask;

    wire alarm_buzzer_enb;
    wire buzzer_enb;

    wire [11:0] psd_data;
    reg  [11:0] psd_sync1, psd_sync2;
    wire        psd_near;

    wire [31:0] ir_data;
    wire ir_valid;

    ir u_ir(
        .o_data(ir_data),
        .o_valid(ir_valid),
        .i_ir_rxb(i_ir_rxb),
        .i_clk(i_clk),
        .i_rstn(i_rstn)
    );

    localparam [11:0] PSD_NEAR_TH = 12'h700; 

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            psd_sync1 <= 12'd0;
            psd_sync2 <= 12'd0;
        end else begin
            psd_sync1 <= psd_data;
            psd_sync2 <= psd_sync1;
        end
    end

    assign psd_near = (psd_sync2 >= PSD_NEAR_TH);

    ctrl #(
        .CLK_FREQ(50000000),
        .DEBOUNCE_COUNT(250000)
    ) u_ctrl(
        .o_alarm_en(alarm_en),
        .o_mode(mode),
        .o_target(target),
        .o_inc_pulse(inc_pulse),
        .o_dec_pulse(dec_pulse),
        .o_timer_start(timer_start),
        .o_blink_en(blink_en),
        .o_1hz_tick(tick_1hz),
        .i_sw(i_sw),
        .i_clk(i_clk),
        .i_rstn(i_rstn),
	.ir_data(ir_data),
        .ir_valid(ir_valid)
    );

    clock u_clock(
        .o_hour(clock_hour),
        .o_min(clock_min),
        .o_sec(clock_sec),
        .i_mode(mode),
        .i_target(target),
        .i_inc_pulse(inc_pulse),
        .i_dec_pulse(dec_pulse),
        .i_1hz_tick(tick_1hz),
        .i_clk(i_clk),
        .i_rstn(i_rstn)
    );

    alarm u_alarm(
        .o_hour(alarm_hour),
        .o_min(alarm_min),
        .o_sec(alarm_sec),
        .i_mode(mode),
        .i_target(target),
        .i_inc_pulse(inc_pulse),
        .i_dec_pulse(dec_pulse),
        .i_clk(i_clk),
        .i_rstn(i_rstn)
    );

    timer_setting u_timer_setting(
        .o_hour(timer_set_hour),
        .o_min(timer_set_min),
        .o_sec(timer_set_sec),
        .i_mode(mode),
        .i_target(target),
        .i_inc_pulse(inc_pulse),
        .i_dec_pulse(dec_pulse),
        .i_clk(i_clk),
        .i_rstn(i_rstn)
    );

    // Countdown engine is owned by the timer teammate.
    // Its required port contract is documented in TIMER_INTERFACE_KO.txt.
    timer u_timer(
        .o_hour(timer_run_hour),
        .o_min(timer_run_min),
        .o_sec(timer_run_sec),
        .o_buzzer_enb(timer_buzzer_enb),
        .i_mode(mode),
        .i_start(timer_start),
        .i_set_hour(timer_set_hour),
        .i_set_min(timer_set_min),
        .i_set_sec(timer_set_sec),
        .i_1hz_tick(tick_1hz),
        .i_clk(i_clk),
        .i_rstn(i_rstn)
    );

    setting_display u_setting_display(
        .o_num0(disp_num0), .o_num1(disp_num1),
        .o_num2(disp_num2), .o_num3(disp_num3),
        .o_num4(disp_num4), .o_num5(disp_num5),
        .o_blink_mask(blink_mask),
        .i_mode(mode),
        .i_target(target),
        .i_clock_hour(clock_hour), .i_clock_min(clock_min), .i_clock_sec(clock_sec),
        .i_alarm_hour(alarm_hour), .i_alarm_min(alarm_min), .i_alarm_sec(alarm_sec),
        .i_timer_hour(timer_set_hour), .i_timer_min(timer_set_min), .i_timer_sec(timer_set_sec),
        .i_timer_run_hour(timer_run_hour), .i_timer_run_min(timer_run_min),
        .i_timer_run_sec(timer_run_sec)
    );

    psd u_psd(
        .o_sclk(o_sclk),
        .o_csn(o_csn),
        .o_din(o_din),
        .o_data(psd_data),
        .i_dout(i_dout),
        .i_addr(3'd0),
        .i_clk(i_clk),
        .i_rstn(i_rstn)
    );

    // Alarm triggers once when HH:MM:SS matches, then re-arms after time changes.
    reg alarm_done;
    reg alarm_active;
    reg [27:0] alarm_duration_count;

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            alarm_done <= 1'b0;
            alarm_active <= 1'b0;
            alarm_duration_count <= 28'd0;
        end else if ((mode != 3'b000) || !alarm_en) begin
            alarm_done <= 1'b0;
            alarm_active <= 1'b0;
            alarm_duration_count <= 28'd0;
        end else begin
            if ((clock_hour == alarm_hour) &&
                (clock_min == alarm_min) &&
                (clock_sec == alarm_sec) && !alarm_done) begin
                alarm_done <= 1'b1;
                alarm_active <= 1'b1;
                alarm_duration_count <= 28'd0;
            end else if (alarm_active) begin
                if (psd_near) begin
                    alarm_active <= 1'b0;
                end
            end

            if ((clock_hour != alarm_hour) ||
                (clock_min != alarm_min) ||
                (clock_sec != alarm_sec))
                alarm_done <= 1'b0;
        end
    end

assign alarm_buzzer_enb = ~alarm_active;

reg timer_alarm_muted;

always @(posedge i_clk or negedge i_rstn) begin
    if (!i_rstn) begin
        timer_alarm_muted <= 1'b0;
    end else begin
        if (timer_buzzer_enb) begin
            timer_alarm_muted <= 1'b0;
        end
        else if (psd_near) begin
            timer_alarm_muted <= 1'b1;
        end
    end
end

assign buzzer_enb = alarm_buzzer_enb &
                    (timer_buzzer_enb | timer_alarm_muted);
    buzzer u_buzzer(
        .o_out(o_buzzer),
        .i_enb(buzzer_enb),
        .i_clk(i_clk),
        .i_rstn(i_rstn)
    );

    wire [5:0] sseg_enb;    // [Text LCD] 7-segment 출력 (아래에서 LCD 와 골라서 핀으로 내보냄)
    wire [7:0] sseg;

    ssegdisp #(
        .FREQDIV(5000),
        .BLINK_DIV(25000000)
    ) u_ssegdisp(
        .o_seg_enb(sseg_enb),
        .o_seg(sseg),
        .i_num0(disp_num0), .i_num1(disp_num1),
        .i_num2(disp_num2), .i_num3(disp_num3),
        .i_num4(disp_num4), .i_num5(disp_num5),
        .i_dp0(1'b0), .i_dp1(1'b0), .i_dp2(1'b1),
        .i_dp3(1'b0), .i_dp4(1'b0), .i_dp5(1'b0),
        .i_blink_mask(blink_mask),
        .i_blink_enable(blink_en),
        .i_clk(i_clk),
        .i_rstn(i_rstn)
    );


    // ==================== [Text LCD] ====================
    localparam [2:0] MODE_TIMER_SET = 3'b011;   // ctrl.v 와 같은 번호
    localparam [2:0] MODE_TIMER_RUN = 3'b100;

    // i_sw[5] 버튼을 누를 때마다 7-segment <-> Text LCD 전환 (처음엔 7-segment)
    //  - 팀 ctrl.v 와 같은 switch_event 사용 (버튼: 안 누르면 1, 누르면 0)
    wire lcd_sw_event;
    switch_event #(.DEBOUNCE_COUNT(250000)) u_lcd_sw (
        .i_clk(i_clk), .i_rstn(i_rstn), .i_sw(i_sw[5]), .o_event(lcd_sw_event)
    );
    reg lcd_sel;
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn)           lcd_sel <= 1'b0;
        else if (lcd_sw_event) lcd_sel <= ~lcd_sel;
    end
    wire lcd_rstn = i_rstn & lcd_sel;    // LCD 로 바꿀 때마다 LCD 를 처음부터 초기화

    wire lcd_blink;
    blink_gen #(.CLK_FREQ(50_000_000)) u_lcd_blink (
        .clk(i_clk), .rst_n(i_rstn), .blink(lcd_blink)
    );

    // ctrl.v 의 target(0 초, 1 분, 2 시) -> LCD 의 set_pos(1 시, 2 분, 3 초)
    wire [1:0] lcd_set_pos = (target == 2'b00) ? 2'd3 :
                             (target == 2'b01) ? 2'd2 :
                             (target == 2'b10) ? 2'd1 : 2'd0;

    // 타이머 설정 모드에서는 설정값, 동작 모드에서는 남은 시간 표시
    wire [5:0] lcd_tmr_hour = (mode == MODE_TIMER_SET) ? timer_set_hour : timer_run_hour;
    wire [5:0] lcd_tmr_min  = (mode == MODE_TIMER_SET) ? timer_set_min  : timer_run_min;
    wire [5:0] lcd_tmr_sec  = (mode == MODE_TIMER_SET) ? timer_set_sec  : timer_run_sec;

    // 타이머가 카운트다운 중인지 (0 이 아니고 부저가 안 울릴 때)
    wire lcd_tmr_zero = (timer_run_hour == 6'd0) && (timer_run_min == 6'd0) && (timer_run_sec == 6'd0);
    wire lcd_tmr_run  = (mode == MODE_TIMER_RUN) && !lcd_tmr_zero && timer_buzzer_enb;

    wire       lcd_e, lcd_rs, lcd_rw;
    wire [7:0] lcd_data;

    text_lcd_top #(
        .CLK_FREQ(50_000_000), .BCD(0),
        .MODE_NORMAL(3'd0), .MODE_CLK_SET(3'd1), .MODE_ALM_SET(3'd2),
        .MODE_TMR_SET(3'd3), .MODE_TIMER(3'd4)
    ) u_text_lcd (
        .i_clk(i_clk), .i_rstn(lcd_rstn),
        .i_mode(mode),
        .i_hour({2'b00, clock_hour}), .i_min({2'b00, clock_min}), .i_sec({2'b00, clock_sec}),
        .i_set_pos(lcd_set_pos), .i_blink(lcd_blink),
        .i_alm_hour({2'b00, alarm_hour}), .i_alm_min({2'b00, alarm_min}), .i_alm_sec({2'b00, alarm_sec}),
        .i_alm_on(alarm_en), .i_alm_ringing(alarm_active),
        .i_tmr_hour({2'b00, lcd_tmr_hour}), .i_tmr_min({2'b00, lcd_tmr_min}), .i_tmr_sec({2'b00, lcd_tmr_sec}),
        .i_tmr_run(lcd_tmr_run), .i_tmr_pause(1'b0),
        .i_psd_near(psd_near),                    // 팀 top.v 의 PSD 감지 신호 그대로 사용
        .i_dbg(1'b0), .i_adc_value(psd_sync2),
        .o_lcd_e(lcd_e), .o_lcd_rs(lcd_rs),
        .o_lcd_rw(lcd_rw), .o_lcd_data(lcd_data)
    );

    // ---- 핀 출력 선택: 7-segment 또는 Text LCD ----
    //  o_seg[0]=T11=LCD D7 ... o_seg[7]=F13=LCD D0 (순서 반대)
    wire [7:0] lcd_data_rev = {lcd_data[0], lcd_data[1], lcd_data[2], lcd_data[3],
                               lcd_data[4], lcd_data[5], lcd_data[6], lcd_data[7]};

assign o_seg     = sseg;
assign o_seg_enb = sseg_enb;

assign o_lcd_rs   = lcd_rs;
assign o_lcd_rw   = lcd_rw;
assign o_lcd_e    = lcd_e;
assign o_lcd_data = lcd_data;

endmodule
