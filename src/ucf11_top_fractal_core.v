`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Rick Collard (UCF-11 Framework Architecture)
// Module Name: ucf11_top_fractal_core
// Description: Top-Level Integration Architecture. Links the non-linear Fibonacci
//              Clock Manager directly into the 1D Mandelbrot Geometric Sequencer.
//////////////////////////////////////////////////////////////////////////////////

module ucf11_top_fractal_core #(
    parameter integer BIT_WIDTH = 32,
    parameter integer FRAC_BIT  = 16
)(
    input  wire                       clk,              // Master High-Speed Oscillator
    input  wire                       rst_n,            // Global Asynchronous Reset
    input  wire                       vector_valid,     // Trigger pulse for new 11D coordinates
    input  wire signed [BIT_WIDTH-1:0] coordinate_c_r, // Real component input stream
    input  wire signed [BIT_WIDTH-1:0] coordinate_c_i, // Imaginary component input stream
    output wire                       manifold_bounded, // Lock flag asserted to robotics layer
    output wire                       manifold_escape   // Fracture flag asserted to robotics layer
);

    // Internal interconnect wire linking the clock pulse to the sequencer
    wire fib_pulse_gate;

    // =========================================================================
    // INSTANTIATION: NON-LINEAR FIBONACCI CLOCK MANAGER
    // =========================================================================
    // This block monitors system behavior and outputs a pseudo-periodic clock 
    // enable pulse based on nature's sequence, automatically resetting on Primes.
    ucf11_fibonacci_prime_clock_manager #(
        .BIT_WIDTH(16)
    ) clock_manager_inst (
        .clk(clk),
        .rst_n(rst_n),
        .system_fracture(manifold_escape), // Feedback loop: Freeze clocking if system escapes
        .fib_clk_en(fib_pulse_gate)       // Output pulse feeding the sequencer
    );

    // =========================================================================
    // INSTANTIATION: FRACTAL GATED 1D SEQUENCER
    // =========================================================================
    // Modulating the original core logic so that its internal processing states
    // are synchronously stepped ONLY when the fib_pulse_gate is active.
    
    reg signed [BIT_WIDTH-1:0] z_r;
    reg signed [BIT_WIDTH-1:0] z_i;
    reg [7:0]                  iteration_count;
    reg [1:0]                  state;

    localparam S_IDLE     = 2'b00,
               S_ITERATE  = 2'b01,
               S_EVALUATE = 2'b10;

    // Structural multipliers mapping complex fractal bounds
    wire signed [(2*BIT_WIDTH)-1:0] z_r_sq = z_r * z_r;
    wire signed [(2*BIT_WIDTH)-1:0] z_i_sq = z_i * z_i;
    wire signed [(2*BIT_WIDTH)-1:0] z_r_z_i = z_r * z_i;

    wire signed [BIT_WIDTH-1:0] z_r_sq_trunc = z_r_sq[31+FRAC_BIT : FRAC_BIT];
    wire signed [BIT_WIDTH-1:0] z_i_sq_trunc = z_i_sq[31+FRAC_BIT : FRAC_BIT];
    wire signed [BIT_WIDTH-1:0] z_r_z_i_trunc = z_r_z_i[31+FRAC_BIT : FRAC_BIT];

    wire signed [BIT_WIDTH-1:0] magnitude_sq = z_r_sq_trunc + z_i_sq_trunc;
    localparam [BIT_WIDTH-1:0] ESCAPE_THRESHOLD = 32'h0004_0000; // 4.0 in Q16.16
    localparam [7:0] MAX_ITERATIONS = 8'd32;

    // Unified Datapath driven by the Master Clock, gated by Fibonacci enables
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            z_r              <= {BIT_WIDTH{1'b0}};
            z_i              <= {BIT_WIDTH{1'b0}};
            iteration_count  <= 8'd0;
            state            <= S_IDLE;
        end else begin
            case (state)
                S_IDLE: begin
                    if (vector_valid) begin
                        z_r              <= 32'h0000_0000;
                        z_i              <= 32'h0000_0000;
                        iteration_count <= 8'd0;
                        state           <= S_ITERATE;
                    end
                end

                S_ITERATE: begin
                    // THE CORE LINK: The fractal math only steps if the Fibonacci manager says GO
                    if (fib_pulse_gate) begin
                        iteration_count <= iteration_count + 1'b1;
                        z_r <= (z_r_sq_trunc - z_i_sq_trunc) + coordinate_c_r;
                        z_i <= (z_r_z_i_trunc << 1) + coordinate_c_i;

                        if (magnitude_sq > ESCAPE_THRESHOLD || iteration_count >= MAX_ITERATIONS) begin
                            state <= S_EVALUATE;
                        end
                    end
                end

                S_EVALUATE: begin
                    // Evaluation completes instantly on the next standard clock edge
                    state <= S_IDLE;
                end
                
                default: state <= S_IDLE;
            endcase
        end
    end

    // Continuous assignment outputs mapping results directly back to pins
    assign manifold_bounded = (state == S_EVALUATE) && (magnitude_sq <= ESCAPE_THRESHOLD);
    assign manifold_escape  = (state == S_EVALUATE) && (magnitude_sq > ESCAPE_THRESHOLD);

endmodule
