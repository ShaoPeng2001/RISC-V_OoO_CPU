module RAS#(
    parameter STACK_SIZE = 8
)(
    input clock, reset,
    input [31:0] PC [1:0],
    input [1:0] is_call,
    input [1:0] is_return,
    input [1:0] is_valid,

    output logic [31:0] return_PC
);

    reg [31:0] stack_mem [STACK_SIZE-1:0];
    reg [$clog2(STACK_SIZE)-1:0] ptr, ptr_minus_1, ptr_minus_2, ptr_add_1, ptr_add_2;

    always_ff @(posedge clock) begin
        if (reset) begin
            ptr <= 0;
            for (int i = 0; i < STACK_SIZE; i++) begin
                stack_mem[i] <= 0;
            end
        end
        else begin
            case({is_call, is_return})
                4'b0000: begin
                    ptr <= ptr;
                end
                4'b0001: begin
                    ptr <= ptr_minus_1;
                end
                4'b0010: begin
                    ptr <= ptr_minus_1;
                end
                4'b0011: begin
                    ptr <= ptr_minus_2;
                end
                4'b0100: begin
                    ptr            <= ptr_add_1;
                    stack_mem[ptr] <= PC[0] + 4;
                end
                4'b0110: begin
                    ptr            <= ptr;
                    stack_mem[ptr] <= PC[0] + 4;
                end
                4'b1000: begin
                    ptr            <= ptr + 1;
                    stack_mem[ptr] <= PC[1] + 4;
                end
                4'b1001: begin
                    ptr                    <= ptr;
                    stack_mem[ptr_minus_1] <= PC[1] + 4;
                end
                4'b1100: begin
                    ptr                  <= ptr_add_2;
                    stack_mem[ptr]       <= PC[0] + 4;
                    stack_mem[ptr_add_1] <= PC[1] + 4;
                end
                default begin
                    ptr <= ptr;
                end
            endcase
        end
    end

    always_comb begin
        if (reset) begin
            return_PC = PC[0] + 8;
        end
        else begin
            case({is_call, is_return})
                4'b0000: begin
                    return_PC = PC[0] + 8;
                end
                4'b0001: begin
                    return_PC = stack_mem[ptr_minus_1];
                end
                4'b0010: begin
                    return_PC = stack_mem[ptr_minus_1];
                end
                4'b0011: begin
                    return_PC = stack_mem[ptr_minus_1];
                end
                4'b0100: begin
                    return_PC = PC[0] + 8;
                end
                4'b0110: begin
                    return_PC = PC[0] + 4;
                end
                4'b1000: begin
                    return_PC = PC[0] + 8;
                end
                4'b1001: begin
                    return_PC = stack_mem[ptr_minus_1];
                end
                4'b1100: begin
                    return_PC = PC[0] + 8;
                end
                default begin
                    return_PC = PC[0] + 8;
                end
            endcase
        end
    end

    assign ptr_minus_1 = ptr - 1;
    assign ptr_minus_2 = ptr - 2;
    assign ptr_add_1   = ptr + 1;
    assign ptr_add_2   = ptr + 2;

endmodule

