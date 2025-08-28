module wand_sel #(
  parameter WIDTH = 64
)(
    input wire  [WIDTH-1:0] req,
    output wand [WIDTH-1:0] gnt
);

    wire  [WIDTH-1:0] req_r;
    wand  [WIDTH-1:0] gnt_r;

    genvar i;
    for (i = 0; i < WIDTH; i++) begin
        assign req_r[WIDTH-1-i] = req[i];
        assign gnt[WIDTH-1-i]   = gnt_r[i];
    end

    for (i = 0; i < WIDTH-1 ; i++) begin
        assign gnt_r [WIDTH-1:i] = {{(WIDTH-1-i){~req_r[i]}},req_r[i]};
    end

    assign gnt_r[WIDTH-1] = req_r[WIDTH-1];

endmodule

