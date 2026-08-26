`timescale 1ns / 1ps
// Full-spectrum sweep testbench for ucf11_top_fractal_core
// Sweeps a grid of complex coordinates and records whether each coordinate
// remains bounded or escapes according to the DUT outputs.

module ucf11_top_fractal_core_spectrum_tb;
  // Parameters matching the DUT
  localparam BIT_WIDTH = 32;
  localparam FRAC_BIT  = 16;

  reg clk = 0;
  reg rst_n = 0;
  reg vector_valid = 0;
  reg signed [BIT_WIDTH-1:0] c_r = 0;
  reg signed [BIT_WIDTH-1:0] c_i = 0;
  wire manifold_bounded;
  wire manifold_escape;

  // Clock generation: 10 ns period
  always #5 clk = ~clk;

  // Simple fibonacci prime clock manager stub (matches DUT instance name)
  // Generates a periodic enable pulse every N cycles unless system_fracture asserted
  module ucf11_fibonacci_prime_clock_manager (
    input clk,
    input rst_n,
    input system_fracture,
    output reg fib_clk_en
  );
    parameter PULSE_PERIOD = 4; // generates pulse every 4 cycles
    integer counter;
    always @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
        counter <= 0;
        fib_clk_en <= 0;
      end else if (system_fracture) begin
        fib_clk_en <= 0;
      end else begin
        counter <= (counter + 1) % PULSE_PERIOD;
        fib_clk_en <= (counter == 0);
      end
    end
  endmodule

  // Instantiate the DUT
  ucf11_top_fractal_core #(.BIT_WIDTH(BIT_WIDTH), .FRAC_BIT(FRAC_BIT)) dut (
    .clk(clk),
    .rst_n(rst_n),
    .vector_valid(vector_valid),
    .coordinate_c_r(c_r),
    .coordinate_c_i(c_i),
    .manifold_bounded(manifold_bounded),
    .manifold_escape(manifold_escape)
  );

  // Simulation parameters for sweep
  real real_min = -2.0;
  real real_max = 2.0;
  real imag_min = -2.0;
  real imag_max = 2.0;
  real step = 0.05; // grid spacing (adjust for resolution/performance)

  integer out_f;
  integer i_count;

  // Convert real value to Q16.16 signed integer
  function signed [BIT_WIDTH-1:0] to_q16_16;
    input real val;
    real scaled;
    begin
      scaled = val * 65536.0; // 2^16
      to_q16_16 = $rtoi(scaled);
    end
  endfunction

  initial begin
    $display("Starting full-spectrum sweep testbench...");
    $dumpfile("ucf11_top_fractal_core_spectrum_tb.vcd");
    $dumpvars(0, ucf11_top_fractal_core_spectrum_tb);

    // Open CSV output
    out_f = $fopen("spectrum_results.csv", "w");
    $fwrite(out_f, "real,imag,result,cycles_to_result,time_ns\n");

    // Reset sequence
    rst_n = 0; #100;
    rst_n = 1; #100;

    // Sweep loops
    real xr;
    real yi;
    i_count = 0;
    for (xr = real_min; xr <= real_max; xr = xr + step) begin
      for (yi = imag_min; yi <= imag_max; yi = yi + step) begin
        // Apply coordinate (converted to Q16.16)
        c_r = to_q16_16(xr);
        c_i = to_q16_16(yi);

        // Pulse vector_valid for one clock cycle
        @(posedge clk);
        vector_valid = 1; @(posedge clk);
        vector_valid = 0;

        // Wait for DUT evaluation outputs with timeout
        integer cycles_waited;
        cycles_waited = 0;
        integer TIMEOUT_CYCLES = 2000; // safety
        while (!(manifold_bounded || manifold_escape) && cycles_waited < TIMEOUT_CYCLES) begin
          @(posedge clk);
          cycles_waited = cycles_waited + 1;
        end

        // Determine result
        string res;
        if (manifold_bounded) res = "bounded";
        else if (manifold_escape) res = "escape";
        else res = "timeout";

        // Write result to CSV (real, imag, result, cycles, time_ns)
        $fwrite(out_f, "%0.6f,%0.6f,%s,%0d,%0d\n", xr, yi, res, cycles_waited, $time);

        i_count = i_count + 1;

        // small pause between vectors to allow stabilization
        repeat (2) @(posedge clk);
      end
    end

    $fclose(out_f);
    $display("Sweep complete. Points tested: %0d", i_count);
    $display("Results written to spectrum_results.csv");
    $finish;
  end

  // Optional monitor prints
  always @(posedge clk) begin
    // Uncomment for verbose tracing of asserts
    // if (manifold_bounded) $display("%0t: bounded", $time);
    // if (manifold_escape) $display("%0t: escape", $time);
  end

endmodule
