// image_proc.sv
// - Input: 12-bit grayscale stream + iDVAL (640-wide active pixels)
// - Builds 3x3 window via gray_window_3x3 (your module)
// - Computes Sobel Gx/Gy, magnitude approx = |Gx| + |Gy|
// - Edge handling: when window invalid, passthrough original gray
// - Output cadence: oDVAL = iDVAL (DO NOT gate frame-buffer writes)

module image_proc #(
    // Adjust this if the image is too bright or too dim.
    // magnitude can be up to ~32760; shifting right by 3..5 is common.
    parameter int MAG_SHIFT = 4
) (
    input  logic        iCLK,
    input  logic        iRST_N,   // active-low reset
    input  logic        iDVAL,
    input  logic [11:0] iGRAY,

    output logic        oDVAL,
    output logic [11:0] oPIX12,   // processed pixel (12-bit), ready for R=G=B
    output logic        oWIN_VALID // debug/optional: window valid (edges omitted)
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

    // expose for debug
    assign oWIN_VALID = win_valid;

    // Keep cadence identical to input stream (important for SDRAM layout)
    assign oDVAL = iDVAL;

    // -----------------------------
    // Sobel math (combinational)
    // Gx = (w02 + 2*w12 + w22) - (w00 + 2*w10 + w20)
    // Gy = (w20 + 2*w21 + w22) - (w00 + 2*w01 + w02)
    // magnitude ≈ |Gx| + |Gy|
    // -----------------------------
    logic signed [16:0] gx, gy;        // signed enough for ~±16380
    logic        [16:0] abs_gx, abs_gy;
    logic        [17:0] mag;           // up to ~32760
    logic        [17:0] mag_shifted;   // after shift
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

        gx = (s02 + (s12 <<< 1) + s22) - (s00 + (s10 <<< 1) + s20);
        gy = (s20 + (s21 <<< 1) + s22) - (s00 + (s01 <<< 1) + s02);

        abs_gx = uabs17(gx);
        abs_gy = uabs17(gy);

        mag = {1'b0, abs_gx} + {1'b0, abs_gy}; // 18-bit unsigned

        // scale down for display
        mag_shifted = (MAG_SHIFT >= 0) ? (mag >> MAG_SHIFT) : mag;

        // clamp to 12-bit range
        if (mag_shifted[17:12] != 0)
            sobel_pix = 12'hFFF;
        else
            sobel_pix = mag_shifted[11:0];

        // Edge handling: omit window pixels by passthrough (or set to 0 if you prefer)
        // IMPORTANT: do NOT gate oDVAL based on win_valid.
        oPIX12 = win_valid ? sobel_pix : iGRAY;
    end

endmodule