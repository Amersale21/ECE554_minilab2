// image_proc.sv
// Two-mode Sobel - horizontal and vertical
//   iMODE = 0 -> use |Gx|  (x-derivative, highlights VERTICAL edges)
//   iMODE = 1 -> use |Gy|  (y-derivative, highlights HORIZONTAL edges)
//
// - Input: 12-bit grayscale stream + iDVAL (640-wide active pixels)
// - Builds 3x3 window via gray_window_3x3
// - Output cadence: oDVAL = iDVAL (DO NOT gate frame-buffer writes)
// - Edge handling: when window invalid, passthrough original gray

module image_proc #(
    parameter int MAG_SHIFT = 4
) (
    input  logic        iCLK,
    input  logic        iRST_N,   // active-low reset
    input  logic        iDVAL,
    input  logic [11:0] iGRAY,

    input  logic        iMODE,    // 0: |Gx|, 1: |Gy|

    output logic        oDVAL,
    output logic [11:0] oPIX12,
    output logic        oWIN_VALID
);

    // 3x3 window outputs
    logic win_valid;
    logic [11:0] w00, w01, w02;
    logic [11:0] w10, w11, w12;
    logic [11:0] w20, w21, w22;

    gray_window_3x3 u_win (
        .iCLK   (iCLK),
        .iRST_N (iRST_N),
        .iDVAL  (iDVAL),
        .iGRAY  (iGRAY),
        .oValid (win_valid),
        .w00(w00), .w01(w01), .w02(w02),
        .w10(w10), .w11(w11), .w12(w12),
        .w20(w20), .w21(w21), .w22(w22)
    );

    assign oWIN_VALID = win_valid;
    assign oDVAL      = iDVAL;

    // Sobel math
    logic signed [16:0] gx, gy;
    logic        [16:0] abs_gx, abs_gy;
    logic        [17:0] mag;
    logic        [17:0] mag_shifted;
    logic        [11:0] sobel_pix;

    function automatic [16:0] uabs17(input logic signed [16:0] v);
        if (v < 0) uabs17 = logic'( -v );
        else       uabs17 = logic'(  v );
    endfunction

    always_comb begin
        // Cast to signed with an extra 0 MSB so arithmetic is safe
        logic signed [16:0] s00, s01, s02, s10, s12, s20, s21, s22;

        s00 = $signed({5'd0, w00});  // 12->17
        s01 = $signed({5'd0, w01});
        s02 = $signed({5'd0, w02});
        s10 = $signed({5'd0, w10});
        s12 = $signed({5'd0, w12});
        s20 = $signed({5'd0, w20});
        s21 = $signed({5'd0, w21});
        s22 = $signed({5'd0, w22});

        // Gx: x-derivative (highlights vertical edges)
        gx = (s02 + (s12 <<< 1) + s22) - (s00 + (s10 <<< 1) + s20);

        // Gy: y-derivative (highlights horizontal edges)
        gy = (s20 + (s21 <<< 1) + s22) - (s00 + (s01 <<< 1) + s02);

        abs_gx = uabs17(gx);
        abs_gy = uabs17(gy);

        // Select ONE direction (no combining)
        mag = (iMODE == 1'b0) ? {1'b0, abs_gx} : {1'b0, abs_gy};

        // scale down for display
        mag_shifted = (MAG_SHIFT >= 0) ? (mag >> MAG_SHIFT) : mag;

        // clamp to 12-bit range
        if (mag_shifted[17:12] != 0)
            sobel_pix = 12'hFFF;
        else
            sobel_pix = mag_shifted[11:0];

        // Edge handling: omit window pixels by passthrough (or set to 0 if you prefer)
        oPIX12 = win_valid ? sobel_pix : iGRAY;
    end

endmodule