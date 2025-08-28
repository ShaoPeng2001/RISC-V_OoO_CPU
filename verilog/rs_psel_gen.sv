`include "sys_defs.svh"

module rs_psel_gen #(parameter REQS = 3, parameter WIDTH = 128)
(   // inputs
    input                         en,
    input                         reset,
    input        [WIDTH-1:0]      req,

    // outputs
    output logic [WIDTH*REQS-1:0] gnt_bus
);

    // Internal connect
    logic  [WIDTH*REQS-1:0]  tmp_reqs;
    logic  [WIDTH*REQS-1:0]  tmp_reqs_rev;
    logic  [WIDTH*REQS-1:0]  tmp_gnts;
    logic  [WIDTH*REQS-1:0]  tmp_gnts_rev;
    wand   [WIDTH*REQS-1:0]  tmp_gnt_bus;

    assign gnt_bus = reset ? {WIDTH*REQS{1'b1}} : (en ? tmp_gnt_bus:{WIDTH*REQS{1'b0}});

    genvar j, k;
    for (j = 0; j < REQS; j++) begin
    // priority selector
        if (j == 0) begin
            assign tmp_reqs[WIDTH-1:0]      = req[WIDTH-1:0];
            assign tmp_gnt_bus[WIDTH-1:0]   = tmp_gnts[WIDTH-1:0];
        end 
        else if (j == 1) begin
            for (k = 0; k < WIDTH; k++) begin
                assign tmp_reqs[2*WIDTH-1-k] = req[k];
            end
            assign tmp_gnt_bus[2*WIDTH-1 -: WIDTH] = tmp_gnts_rev[2*WIDTH-1 -: WIDTH] & ~tmp_gnts[WIDTH-1 : 0];
        end 
        else begin    // mask out gnt from req[j-2]
            assign tmp_reqs[(j+1)*WIDTH-1 -: WIDTH] = tmp_reqs[(j-1)*WIDTH-1 -: WIDTH] & ~tmp_gnts[(j-1)*WIDTH-1 -: WIDTH];
            if (j % 2 == 0) begin
                assign tmp_gnt_bus[(j+1)*WIDTH-1 -: WIDTH] = reset ? 1 : tmp_gnts[(j+1)*WIDTH-1 -: WIDTH];
            end
            else begin
                assign tmp_gnt_bus[(j+1)*WIDTH-1 -: WIDTH] = reset ? 1 : tmp_gnts_rev[(j+1)*WIDTH-1 -: WIDTH];
            end
        end

        // instantiate priority selectors
        wand_sel #(WIDTH) psel (
            .req(tmp_reqs[(j+1)*WIDTH-1 -: WIDTH]), 
            .gnt(tmp_gnts[(j+1)*WIDTH-1 -: WIDTH])
        );

        // reverse gnts
        for (k = 0; k < WIDTH; k++) begin
            assign tmp_gnts_rev[(j+1)*WIDTH-1-k] = tmp_gnts[(j)*WIDTH+k];
        end

        // Mask out
        for (k = j + 1; k < REQS; k = k + 2) begin
            assign tmp_gnt_bus[(k+1)*WIDTH-1 -: WIDTH] = ~tmp_gnt_bus[(j+1)*WIDTH-1 -: WIDTH];
        end
    end
endmodule