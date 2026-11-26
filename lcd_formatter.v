// ============================================================================
// lcd_formatter.v
//  - 디지털 시계 상태를 받아서 LCD 두 줄(각 16글자) 문자열을 만든다.
//  - 팀 코드에 맞춤: 모드 5개, 시/분/초 6비트 2진수, 알람·타이머도 시:분:초
//
//  [기본 화면]  (PPT 필수: 모드 + 알람 시각 + On/Off)
//   시계 동작   : "NORMAL  23:07:12" / "AL 07:30:00 ON  "
//   시계 설정   : "CLK SET 23:07:12" / "AL 07:30:00 ON  "   (설정 칸 깜빡임)
//   알람 설정   : "ALM SET 07:30:00" / "AL 07:30:00 ON  "   (설정 칸 깜빡임)
//   타이머 설정 : "TMR SET 00:03:00" / "STATUS: STOP    "   (설정 칸 깜빡임)
//   타이머 동작 : "TIMER   00:02:59" / "STATUS: RUN     "
//   2번째 줄 마지막 칸: PSD에 손이 감지되면 '*'
//
//  [PSD 연동 화면]  (우선순위 높은 순)
//   1) 알람 울리는 중         : " ALARM RINGING! " / "WAVE HAND->OFF  "
//   2) 알람 꺼진 직후 2초     : " ALARM STOPPED  " / (빈 줄)
//   3) 시계 동작 중 손 감지   : "NEXT AL 07:30:00" / "IN 08h 23m      "
//      (손을 떼도 3초 유지, 알람 OFF면 "NO ALARM SET")
//   4) 타이머 동작 중 손 감지 : 2번째 줄 "STATUS: PAUSE"
//
//  [디버그 화면]  dbg = 1 이면 2번째 줄 "PSD ADC: 1234  *" (PSD 기준값 맞출 때 사용)
// ============================================================================
module lcd_formatter #(
    parameter integer CLK_FREQ     = 50_000_000,
    parameter integer BCD          = 0,     // 시각이 BCD면 1
    parameter [2:0]   MODE_NORMAL  = 3'd0,
    parameter [2:0]   MODE_CLK_SET = 3'd1,
    parameter [2:0]   MODE_ALM_SET = 3'd2,
    parameter [2:0]   MODE_TMR_SET = 3'd3,
    parameter [2:0]   MODE_TIMER   = 3'd4,
    parameter integer SHOW_SEC     = 3,     // 손 뗀 뒤 알람 정보 유지 시간
    parameter integer OFF_MSG_SEC  = 2      // "ALARM STOPPED" 표시 시간
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [2:0]   mode,
    input  wire [7:0]   cur_h, cur_m, cur_s,   // 현재 시각
    input  wire [7:0]   alm_h, alm_m, alm_s,   // 알람 시각
    input  wire         alm_on,                // 알람 On/Off
    input  wire         alm_ringing,           // 알람 울리는 중
    input  wire [7:0]   tmr_h, tmr_m, tmr_s,   // 타이머 (설정값 또는 남은 시간)
    input  wire         tmr_run,               // 타이머 카운트다운 중
    input  wire         tmr_pause,             // 타이머 일시정지 중 (손 감지)
    input  wire [1:0]   set_pos,               // 깜빡일 칸: 0 없음, 1 시, 2 분, 3 초
    input  wire         blink,                 // 1Hz 깜빡임
    input  wire         psd_near,              // PSD 손 감지
    input  wire         dbg,                   // 1이면 2번째 줄에 PSD 측정값 표시 (기준값 맞출 때)
    input  wire [11:0]  adc_value,             // PSD 측정값 0~4095
    output reg  [127:0] line1,
    output reg  [127:0] line2
);
    // ======================= 숫자 변환 함수 =======================
    function [6:0] to_bin;              // 입력값 -> 2진수
        input [7:0] v;
        begin
            if (BCD != 0) to_bin = {3'b000, v[7:4]} * 7'd10 + {3'b000, v[3:0]};
            else          to_bin = v[6:0];
        end
    endfunction

    function [31:0] d4;                 // 0~9999 -> ASCII 네 글자
        input [13:0] v;
        reg   [3:0]  g3, g2, g1, g0;        // 천, 백, 십, 일의 자리
        begin
            g3 = v / 1000;
            g2 = (v / 100) % 10;
            g1 = (v / 10) % 10;
            g0 = v % 10;
            d4 = {8'h30 + {4'h0, g3}, 8'h30 + {4'h0, g2},
                  8'h30 + {4'h0, g1}, 8'h30 + {4'h0, g0}};
        end
    endfunction

    function [15:0] d2;                 // 0~99 -> ASCII 두 글자
        input [6:0] v;
        reg   [3:0] g1, g0;                 // 십, 일의 자리
        begin
            g1 = v / 10;
            g0 = v % 10;
            d2 = {8'h30 + {4'h0, g1}, 8'h30 + {4'h0, g0}};
        end
    endfunction

    // ======================= 2진수로 통일 =======================
    wire [6:0] H  = to_bin(cur_h), M  = to_bin(cur_m), S  = to_bin(cur_s);
    wire [6:0] AH = to_bin(alm_h), AM = to_bin(alm_m), AS = to_bin(alm_s);
    wire [6:0] TH = to_bin(tmr_h), TM = to_bin(tmr_m), TS = to_bin(tmr_s);

    // ======================= 알람까지 남은 시간 (초 단위) =======================

    // 현재 시각을 초 단위로 변환
    wire [16:0] now_sec =
        H * 17'd3600 + M * 17'd60 + S;

    // 알람 시각을 초 단위로 변환
    wire [16:0] alm_sec =
        AH * 17'd3600 + AM * 17'd60 + AS;

    // 알람까지 남은 시간 (다음 날까지 고려)
    wire [16:0] left_total_sec =
        (alm_sec > now_sec) ? (alm_sec - now_sec)
                            : (alm_sec + 17'd86400 - now_sec);

    // 남은 시간을 시:분:초로 분리
    wire [6:0] left_h = left_total_sec / 3600;
    wire [6:0] left_m = (left_total_sec % 3600) / 60;
    wire [6:0] left_s = left_total_sec % 60;

    // ======================= 깜빡임 =======================
    wire set_mode = (mode == MODE_CLK_SET) || (mode == MODE_ALM_SET) || (mode == MODE_TMR_SET);
    wire hide     = set_mode && !blink;
    wire hide_h   = hide && (set_pos == 2'd1);
    wire hide_m   = hide && (set_pos == 2'd2);
    wire hide_s   = hide && (set_pos == 2'd3);

    wire [15:0] sH  = hide_h ? "  " : d2(H);
    wire [15:0] sM  = hide_m ? "  " : d2(M);
    wire [15:0] sS  = hide_s ? "  " : d2(S);
    wire [15:0] sAH = hide_h ? "  " : d2(AH);
    wire [15:0] sAM = hide_m ? "  " : d2(AM);
    wire [15:0] sAS = hide_s ? "  " : d2(AS);
    wire [15:0] sTH = hide_h ? "  " : d2(TH);
    wire [15:0] sTM = hide_m ? "  " : d2(TM);
    wire [15:0] sTS = hide_s ? "  " : d2(TS);
    wire [15:0] aH  = d2(AH);           // 깜빡이지 않는 알람 시각 (2번째 줄용)
    wire [15:0] aM  = d2(AM);
    wire [15:0] aS  = d2(AS);
    wire [7:0]  psd_ch = psd_near ? "*" : " ";

    // ======================= PSD 연동 타이머 =======================
    localparam [31:0] SHOW_CYC = CLK_FREQ * SHOW_SEC;
    localparam [31:0] OFF_CYC  = CLK_FREQ * OFF_MSG_SEC;

    reg        ring_d;     // 알람 이전 상태 (꺼지는 순간 찾기용)
    reg        block;      // 알람 끄려고 댄 손에는 알람 정보 화면 안 띄움
    reg [31:0] show_cnt;   // 알람 정보 화면 남은 시간
    reg [31:0] off_cnt;    // "ALARM STOPPED" 화면 남은 시간

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ring_d   <= 1'b0;
            block    <= 1'b0;
            show_cnt <= 32'd0;
            off_cnt  <= 32'd0;
        end else begin
            ring_d <= alm_ringing;

            if (alm_ringing)    block <= 1'b1;   // 손을 한 번 뗄 때까지 막기
            else if (!psd_near) block <= 1'b0;

            if (alm_ringing || block || mode != MODE_NORMAL) show_cnt <= 32'd0;
            else if (psd_near)                               show_cnt <= SHOW_CYC;
            else if (show_cnt != 0)                          show_cnt <= show_cnt - 1'b1;

            if (alm_ringing)                 off_cnt <= 32'd0;
            else if (ring_d && !alm_ringing) off_cnt <= OFF_CYC;
            else if (off_cnt != 0)           off_cnt <= off_cnt - 1'b1;
        end
    end

    wire show_on = (show_cnt != 0);
    wire off_on  = (off_cnt  != 0);

    // ======================= 화면 문자열 =======================
    always @(*) begin
        // ----- 1번째 줄: 모드 + 시각 -----
        case (mode)
            MODE_NORMAL:  line1 = {"NORMAL  ", sH,  ":", sM,  ":", sS};
            MODE_CLK_SET: line1 = {"CLK SET ", sH,  ":", sM,  ":", sS};
            MODE_ALM_SET: line1 = {"ALM SET ", sAH, ":", sAM, ":", sAS};
            MODE_TMR_SET: line1 = {"TMR SET ", sTH, ":", sTM, ":", sTS};
            MODE_TIMER:   line1 = {"TIMER   ", sTH, ":", sTM, ":", sTS};
            default:      line1 = "MODE ?          ";
        endcase

        // ----- 2번째 줄: 알람 정보 또는 타이머 상태 -----
        if (mode == MODE_TIMER || mode == MODE_TMR_SET)
            line2 = {"STATUS: ",
                     (tmr_pause ? "PAUSE" : (tmr_run ? "RUN  " : "STOP ")),
                     "  ", psd_ch};
        else
            line2 = {"AL ", aH, ":", aM, ":", aS, " ", (alm_on ? "ON " : "OFF"), psd_ch};

        // ----- 디버그: PSD 측정값 표시 -----
        if (dbg)
            line2 = {"PSD ADC: ", d4({2'b00, adc_value}), "  ", psd_ch};   // 9+4+2+1

        // ----- PSD 연동 화면 (위 내용을 덮어씀) -----
        if (alm_ringing) begin
            line1 = " ALARM RINGING! ";
            line2 = "WAVE HAND->OFF  ";
        end else if (off_on) begin
            line1 = " ALARM STOPPED  ";
            line2 = "                ";
        end else if (show_on) begin
            if (alm_on) begin
                line1 = {"NEXT AL ", aH, ":", aM, ":", aS};
                line2 = {"IN ", d2(left_h), ":", d2(left_m), ":", d2(left_s), "     "};
            end else begin
                line1 = "NO ALARM SET    ";
                line2 = "                ";
            end
        end
    end
endmodule
