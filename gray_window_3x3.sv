// Builds a 3x3 grayscale window from a streaming 640-wide pixel stream.
// - Input pixels shift only when iDVAL=1 (clken)
// - Uses Gray_Line_Buffer_640 (2 taps @ 640) to get previous 2 rows
// - Uses 2 flip-flop delays per row stream to get x-1 and x-2
// - Edge handling: omit (oValid=0) until we have >=2 rows and >=2 cols

module gray_window_3x3 (
    input  logic        iCLK,
    input  logic        iRST_N,     // active-low reset recommended for consistency
    input  logic        iDVAL,      // valid for input pixel
    input  logic [11:0] iGRAY,      // grayscale pixel (12-bit)

    output logic        oValid,     // valid for window outputs
    output logic [11:0] w00, w01, w02,
    output logic [11:0] w10, w11, w12,
    output logic [11:0] w20, w21, w22
);

    // -----------------------------
    // Row buffer taps (vertical neighbors)
    // -----------------------------
    logic [11:0] row_y1;   // y-1 at current x
    logic [11:0] row_y2;   // y-2 at current x
    logic [11:0] unused_shiftout;

    Gray_Line_Buffer_640 u_linebuf (
        .clken   (iDVAL),
        .clock   (iCLK),
        .shiftin (iGRAY),
        .shiftout(unused_shiftout),
        .taps0x  (row_y1),
        .taps1x  (row_y2)
    );

    // -----------------------------
    // Horizontal delays (x-1, x-2) for each of the 3 row streams
    // -----------------------------
    logic [11:0] y0_z1, y0_z2; // current row (y)
    logic [11:0] y1_z1, y1_z2; // row y-1
    logic [11:0] y2_z1, y2_z2; // row y-2

    // -----------------------------
    // Edge tracking (omit first 2 cols and first 2 rows)
    // We count pixels ONLY when iDVAL is asserted.
    // We don't rely on X_Cont/Y_Cont yet.
    // -----------------------------
    logic [9:0]  x_cnt;         // 0..639
    logic [2:0]  valid_rows;    // saturating counter for "how many rows have been seen"

    // Detect end-of-line based on x_cnt reaching 639 while iDVAL=1.
    logic eol;
    assign eol = iDVAL && (x_cnt == 10'd639);

    always_ff @(posedge iCLK or negedge iRST_N) begin
        if (!iRST_N) begin
            x_cnt      <= 10'd0;
            valid_rows <= 3'd0;

            y0_z1 <= '0; y0_z2 <= '0;
            y1_z1 <= '0; y1_z2 <= '0;
            y2_z1 <= '0; y2_z2 <= '0;

            oValid <= 1'b0;

            w00 <= '0; w01 <= '0; w02 <= '0;
            w10 <= '0; w11 <= '0; w12 <= '0;
            w20 <= '0; w21 <= '0; w22 <= '0;
        end else begin
            // Default: invalid unless updated in iDVAL block
            oValid <= 1'b0;

            if (iDVAL) begin
                // ---- update horizontal shift regs ----
                // current row stream (y)
                y0_z2 <= y0_z1;
                y0_z1 <= iGRAY;

                // previous row stream (y-1)
                y1_z2 <= y1_z1;
                y1_z1 <= row_y1;

                // two rows back stream (y-2)
                y2_z2 <= y2_z1;
                y2_z1 <= row_y2;

                // ---- update x counter ----
                if (x_cnt == 10'd639)
                    x_cnt <= 10'd0;
                else
                    x_cnt <= x_cnt + 10'd1;

                // ---- update row counter at end-of-line ----
                if (eol) begin
                    if (valid_rows != 3'd7) // saturate
                        valid_rows <= valid_rows + 3'd1;
                end

                // ---- form the 3x3 window outputs ----
                // Note: These are aligned to the "current" sample on this cycle.
                // The center is y1_z1 (one pixel delayed in x, one row delayed in y).
                w00 <= y2_z2;  w01 <= y2_z1;  w02 <= row_y2;
                w10 <= y1_z2;  w11 <= y1_z1;  w12 <= row_y1;
                w20 <= y0_z2;  w21 <= y0_z1;  w22 <= iGRAY;

                // ---- valid window condition (omit edges) ----
                // Need at least 2 full previous rows and 2 previous columns:
                // - valid_rows >= 2 means we have y-2 data
                // - x_cnt >= 2 means x-2 exists (note x_cnt is current x before increment)
                if ((valid_rows >= 3'd2) && (x_cnt >= 10'd2))
                    oValid <= 1'b1;
            end
        end
    end

endmodule