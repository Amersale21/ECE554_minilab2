`timescale 1ns/1ps

module tb_image_proc;

  // ----------------------------------------
  // Parameters to match your design assumptions
  // ----------------------------------------
  localparam int IMG_W      = 640;
  localparam int IMG_H      = 6;     // keep small for fast sim (still uses W=640)
  localparam int BLANK_CYC  = 20;    // cycles of iDVAL=0 between lines
  localparam int MAG_SHIFT  = 4;     // match your image_proc default

  // Edge pattern: vertical step edge at this x
  localparam int EDGE_X     = 320;
  localparam logic [11:0] DARK  = 12'd0;
  localparam logic [11:0] BRIGHT= 12'd4095;

  // ----------------------------------------
  // DUT I/O
  // ----------------------------------------
  logic        clk;
  logic        rst_n;
  logic        iDVAL;
  logic [11:0] iGRAY;

  logic        oDVAL;
  logic [11:0] oPIX12;
  logic        oWIN_VALID;

  // ----------------------------------------
  // Instantiate DUT
  // ----------------------------------------
  image_proc #(.MAG_SHIFT(MAG_SHIFT)) dut (
    .iCLK(clk),
    .iRST_N(rst_n),
    .iDVAL(iDVAL),
    .iGRAY(iGRAY),
    .oDVAL(oDVAL),
    .oPIX12(oPIX12),
    .oWIN_VALID(oWIN_VALID)
  );

  // ----------------------------------------
  // Clock: 50MHz (20ns period)
  // ----------------------------------------
  initial clk = 1'b0;
  always #10 clk = ~clk;

  // ----------------------------------------
  // Simple scoreboard helpers
  // ----------------------------------------
  int x, y;
  int err_count = 0;

  // Drive one pixel (valid cycle)
  task automatic drive_pixel(input logic [11:0] pix);
    begin
      iDVAL = 1'b1;
      iGRAY = pix;
      @(posedge clk);
    end
  endtask

  // Drive blanking (invalid cycles)
  task automatic drive_blank(input int n);
    int k;
    begin
      iDVAL = 1'b0;
      iGRAY = '0;
      for (k = 0; k < n; k++) @(posedge clk);
    end
  endtask

  // Expected grayscale input for a given x,y (our synthetic image)
  function automatic logic [11:0] expected_gray(input int xx, input int yy);
    begin
      // Vertical step edge: left side dark, right side bright
      expected_gray = (xx < EDGE_X) ? DARK : BRIGHT;
    end
  endfunction

  // ----------------------------------------
  // Assertions / checks each cycle
  // ----------------------------------------
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      // ignore during reset
    end else begin
      // DUT should preserve cadence: oDVAL must equal iDVAL
      if (oDVAL !== iDVAL) begin
        $display("[%0t] ERROR: oDVAL (%b) != iDVAL (%b)", $time, oDVAL, iDVAL);
        err_count++;
      end
    end
  end

  // ----------------------------------------
  // Main stimulus
  // ----------------------------------------
  initial begin
    // init
    iDVAL = 1'b0;
    iGRAY = '0;

    // reset: hold low for a few cycles
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    $display("=== Starting stimulus: %0dx%0d step-edge image (EDGE_X=%0d) ===",
             IMG_W, IMG_H, EDGE_X);

    // Feed IMG_H lines of IMG_W valid pixels each
    for (y = 0; y < IMG_H; y++) begin
      for (x = 0; x < IMG_W; x++) begin
        drive_pixel(expected_gray(x, y));

        // Spot-check behavior when window is valid:
        // We expect near-zero away from edge, high around edge.
        // Because your design outputs passthrough gray when window invalid,
        // we only check Sobel behavior when oWIN_VALID=1.
        if (oWIN_VALID) begin
          // pick a few x locations to check
          if (x == 10 || x == 100) begin
            // far left: uniform region -> sobel should be ~0
            if (oPIX12 > 12'd10) begin
              $display("[%0t] ERROR: expected low edge response at (x=%0d,y=%0d), got oPIX12=%0d",
                       $time, x, y, oPIX12);
              err_count++;
            end
          end

          if (x == EDGE_X || x == EDGE_X-1 || x == EDGE_X+1) begin
            // near the edge: should be non-zero (often quite large)
            if (oPIX12 < 12'd50) begin
              $display("[%0t] ERROR: expected strong edge response near edge at (x=%0d,y=%0d), got oPIX12=%0d",
                       $time, x, y, oPIX12);
              err_count++;
            end
          end

          if (x == 500) begin
            // far right: uniform region -> sobel should be ~0
            if (oPIX12 > 12'd10) begin
              $display("[%0t] ERROR: expected low edge response at (x=%0d,y=%0d), got oPIX12=%0d",
                       $time, x, y, oPIX12);
              err_count++;
            end
          end
        end

        // Optional debug prints for a few points
        if ((y == 2) && (x == EDGE_X || x == EDGE_X+1 || x == EDGE_X+2)) begin
          $display("[%0t] DBG y=%0d x=%0d iGRAY=%0d win=%b oPIX12=%0d",
                   $time, y, x, iGRAY, oWIN_VALID, oPIX12);
        end
      end

      // blanking between lines
      drive_blank(BLANK_CYC);
    end

    // let pipeline settle a bit
    drive_blank(50);

    // Summary
    if (err_count == 0) begin
      $display("=== PASS: No errors detected ===");
    end else begin
      $display("=== FAIL: err_count=%0d ===", err_count);
    end

    $stop;
  end

endmodule
