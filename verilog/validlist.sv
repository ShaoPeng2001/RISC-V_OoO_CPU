    `include "sys_defs.svh"


    module ValidList(
    input                                    clock,
    input                                    reset,
    input                                    squash,
    input valid_packet [`N-1:0]				 valid_packet_in,

    output logic [`N-1:0]                    rs1_valid,
    output logic [`N-1:0]                    rs2_valid

    );

    logic [`PRF-1:0]            valid_rename_reg;
    logic [`PRF-1:0]            valid_rename_next;
    logic [`PRF-1:0]            valid_arch_reg;
    logic [`PRF-1:0]            valid_arch_next;
    logic [`PRF-1:0]            reset_value;

    logic [`N:0] [`PRF-1:0]     valid_rename_reg_tmp;

    logic [`N-1:0]              CDB_en;
    logic [`N-1:0]              ROB_retired;

    logic [`N-1:0] [`PRF-1:0]   CDB_one_hot;
    logic [`N-1:0] [`PRF-1:0]   arch_new_one_hot;
    logic [`N-1:0] [`PRF-1:0]   arch_old_one_hot;

    logic [`PRF-1:0] CDB_one_hot_total;
    logic [`PRF-1:0] arch_new_one_hot_total;
    logic [`PRF-1:0] arch_old_one_hot_total;

    assign CDB_en[0] = valid_packet_in[0].CDB_enable;
    assign CDB_en[1] = valid_packet_in[1].CDB_enable;

    assign ROB_retired[0] = valid_packet_in[0].rob_retire_en;
    assign ROB_retired[1] = valid_packet_in[1].rob_retire_en;

    assign CDB_one_hot[0]       = CDB_en[0] ? {`PRF'h1 << valid_packet_in[0].CDB_reg_idx} : `PRF'h0;
    assign CDB_one_hot[1]       = CDB_en[1] ? {`PRF'h1 << valid_packet_in[1].CDB_reg_idx} : `PRF'h0;

    assign arch_new_one_hot[0]  = ROB_retired[0] ? {`PRF'h1 << valid_packet_in[0].arch_reg_new} : `PRF'h0;
    assign arch_new_one_hot[1]  = ROB_retired[1] ? {`PRF'h1 << valid_packet_in[1].arch_reg_new} : `PRF'h0;
    assign arch_old_one_hot[0]  = ROB_retired[0] ? {`PRF'h1 << valid_packet_in[0].arch_reg_old} : `PRF'h0;
    assign arch_old_one_hot[1]  = ROB_retired[1] ? {`PRF'h1 << valid_packet_in[1].arch_reg_old} : `PRF'h0;


    assign CDB_one_hot_total      = CDB_one_hot[0] | CDB_one_hot[1];
    assign arch_new_one_hot_total = arch_new_one_hot[0] | arch_new_one_hot[1];
    assign arch_old_one_hot_total = arch_old_one_hot[0] | arch_old_one_hot[1]; 


    // RRAT 是用來準備 mispreidction rollback 使用的, backup 的概念
    // 進入 RRAT 的為 valid physical reister
    // 離開 RRAT 的為 free physical reister，為 invalid
    assign valid_arch_next = valid_arch_reg & (~arch_old_one_hot_total) | arch_new_one_hot_total;


    assign valid_rename_reg_tmp[0] = valid_rename_reg | CDB_one_hot_total;
    assign valid_rename_reg_tmp[1] = valid_rename_reg_tmp[0] & ~(valid_packet_in[0].rename_request ? {`PRF'h1 << valid_packet_in[0].dest_index} : `PRF'h0);
    assign valid_rename_reg_tmp[2] = valid_rename_reg_tmp[1] & ~(valid_packet_in[1].rename_request ? {`PRF'h1 << valid_packet_in[1].dest_index} : `PRF'h0);
    assign valid_rename_next       = valid_rename_reg_tmp[`N];

    assign rs1_valid[0] = valid_rename_reg_tmp[0][valid_packet_in[0].rs1_index];
    assign rs1_valid[1] = valid_rename_reg_tmp[1][valid_packet_in[1].rs1_index];
    assign rs2_valid[0] = valid_rename_reg_tmp[0][valid_packet_in[0].rs2_index];
    assign rs2_valid[1] = valid_rename_reg_tmp[1][valid_packet_in[1].rs2_index];

    // setting reset valid list status
    always_comb begin
        for(int i = 0; i < `PRF; i = i + 1) begin
            reset_value[i] = (i < 32) ? 1 : 0;
        end
    end

    always_ff @ (posedge clock) begin
        if (reset) begin                    // reset value setting 
            valid_rename_reg    <= reset_value;
            valid_arch_reg      <= reset_value;
        end
        else if (squash) begin              // rollback when branch mispredicted
            valid_rename_reg    <= valid_arch_next;
            valid_arch_reg      <= valid_arch_next;
        end
        // 正常情況下
        else begin
            valid_rename_reg    <= valid_rename_next;
            valid_arch_reg      <= valid_arch_next;
        end
    end


    endmodule
