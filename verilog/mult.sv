`include "sys_defs.svh"

module mult #(parameter LEN = 32, parameter NUM_STAGE = 4) 
(
    input clock, reset,
    input start,
    input [1:0] sign,
    input [LEN-1:0] mcand, mplier,
                
    output [(2*LEN)-1:0] product,
    output done
);
    logic [(2*LEN)-1:0] mcand_out, next_mplier, mcand_in, multiplier_in;
    logic [NUM_STAGE:0][2*LEN-1:0] internal_mcands, internal_mpliers;
    logic [NUM_STAGE:0][2*LEN-1:0] internal_sums;
    logic [NUM_STAGE:0] internal_dones;

    assign mcand_in  = sign[0] ? {{LEN{mcand[LEN-1]}}, mcand}   : {{LEN{1'b0}}, mcand} ;
    assign multiplier_in = sign[1] ? {{LEN{mplier[LEN-1]}}, mplier} : {{LEN{1'b0}}, mplier};

    assign internal_mcands[0]   = mcand_in;
    assign internal_mpliers[0]  = multiplier_in;
    assign internal_sums[0] = 'h0;
    assign internal_dones[0]    = start;

    assign done    = internal_dones[NUM_STAGE];
    assign product = internal_sums[NUM_STAGE];

    genvar i;
    for (i = 0; i < NUM_STAGE; ++i) begin : mstage
        mult_stage ms (
            .clock(clock),
            .reset(reset),
            .start(internal_dones[i]),
            .prev_sum(internal_sums[i]),
            .mplier(internal_mpliers[i]),
            .mcand(internal_mcands[i]),
            .product_sum(internal_sums[i+1]),
            .next_mplier(internal_mpliers[i+1]),
            .next_mcand(internal_mcands[i+1]),
            .done(internal_dones[i+1])
        );
    end
    endmodule

module mult_stage (
    input clock, reset, start,
    input [63:0] prev_sum, mplier, mcand,
    output logic [63:0] product_sum, next_mplier, next_mcand,
    output logic done
);
    parameter SHIFT = 64/`MULT_STAGES;
    logic [63:0] partial_product, shifted_mplier, shifted_mcand;
    assign partial_product = mplier[SHIFT-1:0] * mcand;
    assign shifted_mplier = {SHIFT'('b0), mplier[63:SHIFT]};
    assign shifted_mcand = {mcand[63-SHIFT:0], SHIFT'('b0)};
    always_ff @(posedge clock) begin
        product_sum <= prev_sum + partial_product;
        next_mplier <= shifted_mplier;
        next_mcand  <= shifted_mcand;
    end
    always_ff @(posedge clock) begin
        if (reset) begin
            done <= 1'b0;
        end else begin
            done <= start;
        end
    end
endmodule // mult_stage



