`include "sys_defs.svh"

module PRF(
    // inputs
    input                                clock,
    input                                reset,
    input  [1:0] [$clog2(`PRF)-1:0]      rda_idx,
    input  [1:0] [$clog2(`PRF)-1:0]      rdb_idx,
    input  [1:0] [$clog2(`PRF)-1:0]      wr_idx,
    input  [1:0] [31:0]                  wr_data,
    input  [1:0]                         wr_en,
    input  [1:0] [$clog2(`PRF)-1:0]      dest_PRN_out,
    input  [1:0]                         valid_out,

    // outputs
    output logic [1:0] [31:0]            rda_data,
    output logic [1:0] [31:0]            rdb_data,
    output logic [1:0] [31:0]            committed_data
);
  
    logic [`PRF-1:0] [31:0]      registers;  // 所有 physical register 所儲存的位置
    logic [`PRF-1:0] [31:0]      next_reg;   // 若有寫入發生，更新的 physical register 的位置

    assign committed_data[0] = valid_out[0] ? registers[dest_PRN_out[0]] : 0;
    assign committed_data[1] = valid_out[1] ? registers[dest_PRN_out[1]] : 0;

    always_comb begin
        next_reg = registers;
        if (wr_en[0]) next_reg[wr_idx[0]] = wr_data[0];
        if (wr_en[1]) next_reg[wr_idx[1]] = wr_data[1];
    end

    always_comb begin
        rda_data[0] = registers[rda_idx[0]];
        rdb_data[0] = registers[rdb_idx[0]];

        if (wr_en[0] && (wr_idx[0] == rda_idx[0])) rda_data[0] = wr_data[0];
        if (wr_en[1] && (wr_idx[1] == rda_idx[0])) rda_data[0] = wr_data[1];
        if (wr_en[0] && (wr_idx[0] == rdb_idx[0])) rdb_data[0] = wr_data[0];
        if (wr_en[1] && (wr_idx[1] == rdb_idx[0])) rdb_data[0] = wr_data[1];

        rda_data[1] = registers[rda_idx[1]];
        rdb_data[1] = registers[rdb_idx[1]];

        if (wr_en[0] && (wr_idx[0] == rda_idx[1])) rda_data[1] = wr_data[0];
        if (wr_en[1] && (wr_idx[1] == rda_idx[1])) rda_data[1] = wr_data[1];
        if (wr_en[0] && (wr_idx[0] == rdb_idx[1])) rdb_data[1] = wr_data[0];
        if (wr_en[1] && (wr_idx[1] == rdb_idx[1])) rdb_data[1] = wr_data[1];
    end

    always_ff @ (posedge clock) begin
        if (reset) 
            registers <= 0;
        else 
            registers <= next_reg;
    end
endmodule 
