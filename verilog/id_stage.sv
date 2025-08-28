`include "sys_defs.svh"

module id_stage(         
    input                               clock,              
    input                               reset,              
    input                               squash,
    input ID_packet [`N-1:0]            id_packet_in,

    //-----------------branch predictor-----------------------------
    input [`N-1:0] [31:0]          PC_update,
    input [`N-1:0]                      direction_update,
    input [`N-1:0] [31:0]          target_update,
    input [`N-1:0]                      valid_update,

    // Output
    output logic [31:0]            next_PC,
    output logic [`N-1:0]               predictions,

    //--------------------------------------------------------------

    output ID_EX_PACKET [`N-1:0]        id_packet_out,
    output logic [`N-1:0]               sign_out,
    output logic [`N-1:0]               opa_valid,          // source register 是否為 valid
    output logic [`N-1:0]               opb_valid,          // source register 是否為 valid
    output logic [`N-1:0] [31:0]   committed_data
);

    logic [1:0] [$clog2(`PRF)-1:0]      CDB_write_idx;      // from CDB, valid register index
    logic [1:0]                         CDB_write_en;
    logic [1:0] [31:0]             CDB_write_data;     // CDB data

    logic [1:0] [4:0]                   ARCH_ARF_idx;       // arch reg number to be renamed
    logic [1:0]                         rob_retire;
    logic [1:0] [$clog2(`PRF)-1:0]      ARCH_PRF_idx;       // 寫進 RRAT 的 physical register index

    IF_ID_PACKET [1:0]                  if_id_packet_in;

    logic [1:0] [$clog2(`PRF)-1:0]      dest_PRN_out;
    logic [1:0]                         retired;

    assign CDB_write_idx[0]     = id_packet_in[0].CDB_write_idx;
    assign CDB_write_en[0]      = id_packet_in[0].CDB_write_en;   
    assign CDB_write_data[0]    = id_packet_in[0].CDB_write_data;
    assign ARCH_ARF_idx[0]      = id_packet_in[0].ARCH_ARF_idx;
    assign rob_retire[0]        = id_packet_in[0].rob_retire;
    assign ARCH_PRF_idx[0]      = id_packet_in[0].ARCH_PRF_idx;
    assign if_id_packet_in[0]   = id_packet_in[0].if_id_packet_in;
    assign dest_PRN_out[0]      = id_packet_in[0].dest_PRN_out;
    assign retired[0]           = id_packet_in[0].retired;

    assign CDB_write_idx[1]     = id_packet_in[1].CDB_write_idx;
    assign CDB_write_en[1]      = id_packet_in[1].CDB_write_en;   
    assign CDB_write_data[1]    = id_packet_in[1].CDB_write_data;
    assign ARCH_ARF_idx[1]      = id_packet_in[1].ARCH_ARF_idx;
    assign rob_retire[1]        = id_packet_in[1].rob_retire;
    assign ARCH_PRF_idx[1]      = id_packet_in[1].ARCH_PRF_idx;
    assign if_id_packet_in[1]   = id_packet_in[1].if_id_packet_in;
    assign dest_PRN_out[1]      = id_packet_in[1].dest_PRN_out;
    assign retired[1]           = id_packet_in[1].retired;

    logic [1:0] [$clog2(`PRF)-1:0]      dest_PRF;
    logic [1:0]                         dest_PRF_valid;
    logic [1:0][4:0]                    rs1_arn;              // 紀錄 rs1 的 architecture register number
    logic [1:0][4:0]                    rs2_arn;              // 紀錄 rs2 的 architecture register number
    logic [1:0][4:0]                    dest_arn;             // 紀錄 destination 的 architecture register number

    logic [1:0][$clog2(`PRF)-1:0] 	    rs1_prn;              // rs1 的 physical register number
    logic [1:0][$clog2(`PRF)-1:0]       rs2_prn;              // rs2 的 physical register number
    logic [1:0][31:0]              rs1_value;            // rs1 的 physical register value
    logic [1:0][31:0]              rs2_value;            // rs2 的 physical register value
    logic [1:0]                         rs1_valid_tmp;
    logic [1:0]                         rs2_valid_tmp;
    logic [1:0]                         inst_valid_tmp;
    logic [1:0]                         has_dest;
    logic [1:0]                         dest_arn_valid;

    logic [1:0]                         COND_BRANCH;
    logic [1:0]                         UNCOND_BRANCH;
    logic [1:0]                         JAL;
    logic [1:0]                         JALR;

    // 從 IF_stage 進來的 signal
    // 保持 signal 從 IF 到 ID 階段的流動
    assign id_packet_out[0].inst        = if_id_packet_in[0].inst;
    assign id_packet_out[0].NPC         = if_id_packet_in[0].NPC;
    assign id_packet_out[0].PC          = if_id_packet_in[0].PC;
    assign dest_arn[0]                  = if_id_packet_in[0].inst.r.rd;     // destination architecture register
    assign rs1_arn[0]                   = if_id_packet_in[0].inst.r.rs1;    // architectural register
    assign rs2_arn[0]                   = if_id_packet_in[0].inst.r.rs2;    // architectural register
    assign dest_arn_valid[0]            = (has_dest[0] == `TRUE) & id_packet_out[0].valid & ~(dest_arn[0] == 0);	// dest_arn_valid 是用來確認, destination register 是否需要 renaming, 如果 destination register 是 0 的話，就不需要 renaming
    assign id_packet_out[0].reg_write   = dest_arn_valid[0];                // reg_write 可以用來表達當前 instruction 是否是進行有效的 reg_write

    assign id_packet_out[1].inst        = if_id_packet_in[1].inst;
    assign id_packet_out[1].NPC         = if_id_packet_in[1].NPC;
    assign id_packet_out[1].PC          = if_id_packet_in[1].PC;
    assign dest_arn[1]                  = if_id_packet_in[1].inst.r.rd;	    // destination architecture register
    assign rs1_arn[1]                   = if_id_packet_in[1].inst.r.rs1;	// architectural register
    assign rs2_arn[1]                   = if_id_packet_in[1].inst.r.rs2;	// architectural register
    assign dest_arn_valid[1]            = (has_dest[1] == `TRUE) & id_packet_out[1].valid & ~(dest_arn[1] == 0);	// dest_arn_valid 是用來確認, destination register 是否需要 renaming, 如果 destination register 是 0 的話，就不需要 renaming
    assign id_packet_out[1].reg_write   = dest_arn_valid[1];	

    assign COND_BRANCH[0]               = id_packet_out[0].cond_branch;
    assign COND_BRANCH[1]               = id_packet_out[1].cond_branch;
    assign UNCOND_BRANCH[0]             = id_packet_out[0].uncond_branch;
    assign UNCOND_BRANCH[1]             = id_packet_out[1].uncond_branch;
    assign JAL[0]                       = id_packet_out[0].uncond_jal;
    assign JAL[1]                       = id_packet_out[1].uncond_jal;
    assign JALR[0]                      = id_packet_out[0].uncond_jalr;
    assign JALR[1]                      = id_packet_out[1].uncond_jalr;

    decoder decoder_0 (
        //Input
        .if_packet(if_id_packet_in[0]),	 
        // Outputs
        .sign(sign_out[0]),
        .memory_size(id_packet_out[0].mem_size),
        .opa_select(id_packet_out[0].opa_select),
        .opb_select(id_packet_out[0].opb_select),
        .alu_func(id_packet_out[0].alu_func),
        .has_dest(has_dest[0]),
        .rd_mem(id_packet_out[0].rd_mem),
        .wr_mem(id_packet_out[0].wr_mem),
        .cond_branch(id_packet_out[0].cond_branch),
        .uncond_branch(id_packet_out[0].uncond_branch),
        .uncond_jal(id_packet_out[0].uncond_jal),
        .uncond_jalr(id_packet_out[0].uncond_jalr),
        .csr_op(id_packet_out[0].csr_op),
        .halt(id_packet_out[0].halt),
        .illegal(id_packet_out[0].illegal),
        .valid_inst(inst_valid_tmp[0])
    );

    decoder decoder_1 (
        //Input
        .if_packet(if_id_packet_in[1]),	 
        // Outputs
        .sign(sign_out[1]),
        .memory_size(id_packet_out[1].mem_size),
        .opa_select(id_packet_out[1].opa_select),
        .opb_select(id_packet_out[1].opb_select),
        .alu_func(id_packet_out[1].alu_func),
        .has_dest(has_dest[1]),
        .rd_mem(id_packet_out[1].rd_mem),
        .wr_mem(id_packet_out[1].wr_mem),
        .cond_branch(id_packet_out[1].cond_branch),
        .uncond_branch(id_packet_out[1].uncond_branch),
        .uncond_jal(id_packet_out[1].uncond_jal),
        .uncond_jalr(id_packet_out[1].uncond_jalr),
        .csr_op(id_packet_out[1].csr_op),
        .halt(id_packet_out[1].halt),
        .illegal(id_packet_out[1].illegal),
        .valid_inst(inst_valid_tmp[1])
    );


    logic [1:0]	         branch_inst;
    logic [1:0]          is_call;
    logic [1:0]          is_return;
    logic [31:0]    branch_PC;
    logic [31:0]    return_PC;

    assign branch_inst[0] = (COND_BRANCH[0] | UNCOND_BRANCH[0]) & inst_valid_tmp[0];
    assign branch_inst[1] = (COND_BRANCH[1] | UNCOND_BRANCH[1]) & inst_valid_tmp[1];
    assign is_call[0]     = JAL[0] & inst_valid_tmp[0];
    assign is_call[1]     = JAL[1] & inst_valid_tmp[1];
    assign is_return[0]   = JALR[0] & inst_valid_tmp[0];
    assign is_return[1]   = JALR[1] & inst_valid_tmp[1];

    //branch predictor
    branch_predictor #(
        .SIZE(128),         //Size of BHT
        .P_SIZE(128),       //Size of PHT
        .BTB_SET(32),       //Num of set of BTB
        .BTB_WAY(4))
    predictor (
        .clock(clock),
        .reset(reset),

        .PC(if_id_packet_in[0].PC),
        .is_branch({branch_inst[1], branch_inst[0]}),
        .is_valid(inst_valid_tmp),

        .PC_update(PC_update),
        .direction_update(direction_update),

        .target_update(target_update),
        .valid_update(valid_update),

        .next_PC(branch_PC),
        .prediction(predictions)
    );

    RAS #(
        .STACK_SIZE(8))
    ras (
        .clock(clock),
        .reset(reset),
        .PC({(if_id_packet_in[0].PC + 4), if_id_packet_in[0].PC}),
        .is_call({is_call[1], is_call[0]}),
        .is_return({is_return[1], is_return[0]}),
        .is_valid(inst_valid_tmp),

        .return_PC(return_PC)
    );

    always_comb begin
        if(reset)begin
            next_PC = 0;
        end
        else begin
            if(is_return[0]) begin
                next_PC = return_PC;
            end
            if(branch_inst[0]) begin
                next_PC = branch_PC;
            end
            else if(is_return[1]) begin
                next_PC = return_PC;
            end
            else if(branch_inst[1]) begin
                next_PC = branch_PC;
            end
            else begin
                next_PC = branch_PC;
            end
        end
    end

    logic branch;

    always_comb begin
        branch = 0;
        for(int i = 0; i < 2 ; i = i + 1) begin
            id_packet_out[i].valid = branch ? 0 : inst_valid_tmp[i];
            if(((branch == 0) && (predictions[i] == 1)) || ((is_return[i] == 1) && (branch == 0)))   // 如果上一個 instruction 有 branch 發生, 下一個 valid 直接設為 0
                branch = 1;
        end
    end

    // decoder 會送出 dest_reg_select 信號，若當前的 instruction 需要 renaming
    // 則從 freelist(在 RAT_RRAT 裡面) 送出的 free physical register 會透過 id_packet_out 送出去
    always_comb begin
        for(int i = 0; i < 2 ; i++) begin
            case (has_dest[i])
                `TRUE:      id_packet_out[i].dest_PRF_idx = dest_PRF[i]; // 進行 instruction destination register 的 register renaming
                `FALSE:     id_packet_out[i].dest_PRF_idx = `ZERO_REG;
                default:    id_packet_out[i].dest_PRF_idx = `ZERO_REG; 
            endcase
        end
    end

    PRF prf(
        .clock(clock),
        .reset(reset),
        .rda_idx(rs1_prn),
        .rdb_idx(rs2_prn),
        .wr_idx(CDB_write_idx),         // 要 write 的 data 的 index
        .wr_data(CDB_write_data),       // 要 write 的 data
        .wr_en(CDB_write_en),           // CDB enable
        .dest_PRN_out(dest_PRN_out),
        .valid_out(retired),
        .rda_data(rs1_value),		
        .rdb_data(rs2_value),
        .committed_data(committed_data)
    );

    map_arch_packet [1:0] map_arch_in;

    assign map_arch_in[0].rs1_idx           = rs1_arn[0];
    assign map_arch_in[0].rs2_idx           = rs2_arn[0];
    assign map_arch_in[0].ARN_dest_idx      = dest_arn[0];
    assign map_arch_in[0].CDB_wr_reg_idx    = CDB_write_idx[0];
    assign map_arch_in[0].CDB_wr_en         = CDB_write_en[0];
    assign map_arch_in[0].ARF_reg_idx       = ARCH_ARF_idx[0];
    assign map_arch_in[0].rob_retire        = rob_retire[0];
    assign map_arch_in[0].PRN_idx_old       = ARCH_PRF_idx[0];

    assign map_arch_in[1].rs1_idx           = rs1_arn[1];
    assign map_arch_in[1].rs2_idx           = rs2_arn[1];
    assign map_arch_in[1].ARN_dest_idx      = dest_arn[1];
    assign map_arch_in[1].CDB_wr_reg_idx    = CDB_write_idx[1];
    assign map_arch_in[1].CDB_wr_en         = CDB_write_en[1];
    assign map_arch_in[1].ARF_reg_idx       = ARCH_ARF_idx[1];
    assign map_arch_in[1].rob_retire        = rob_retire[1];
    assign map_arch_in[1].PRN_idx_old       = ARCH_PRF_idx[1];

    Map_Table renaming_machine(
        .clock(clock),
        .reset(reset),
        .squash(squash),
        .map_arch_in(map_arch_in),
        .rename_valid(dest_arn_valid),       	// valid renaming instruction number
        .rename_result(dest_PRF),               // renaming result PRN
        .rename_result_valid(dest_PRF_valid),   // renaming result valid signal

        .rs1_idx_out(rs1_prn),                  // PRN for rs1
        .rs2_idx_out(rs2_prn),                  // PRN for rs2
        .rs1_valid(rs1_valid_tmp),
        .rs2_valid(rs2_valid_tmp)
    );
        
    always_comb begin
        if(id_packet_out[0].opa_select == OPA_IS_RS1 | COND_BRANCH[0]) begin
            if(rs1_arn[0] == 0) begin
                opa_valid[0]                = 1;
                id_packet_out[0].rs1_value  = 0;
            end
            else begin
                opa_valid[0]                = rs1_valid_tmp[0];
                id_packet_out[0].rs1_value  = opa_valid[0] ? rs1_value[0] : rs1_prn[0];
            end
        end
        else begin
            opa_valid[0]                    = 1;
            id_packet_out[0].rs1_value      = 0;
        end
    end

    always_comb begin
        if(id_packet_out[1].opa_select == OPA_IS_RS1 | COND_BRANCH[1]) begin
            if(rs1_arn[1] == 0) begin
                opa_valid[1]                = 1;
                id_packet_out[1].rs1_value  = 0;
            end
            else begin
                opa_valid[1]                = (dest_arn_valid[0] && dest_arn[0] == rs1_arn[1]) ? 0 : rs1_valid_tmp[1];
                id_packet_out[1].rs1_value  = (dest_arn_valid[0] && dest_arn[0] == rs1_arn[1]) ? dest_PRF[0] : (opa_valid[1] ? rs1_value[1] : rs1_prn[1]);
            end
        end
        else begin
            opa_valid[1]                    = 1;
            id_packet_out[1].rs1_value      = 0;
        end
    end	

    always_comb begin
        if(id_packet_out[0].opb_select == OPB_IS_RS2 | id_packet_out[0].wr_mem | COND_BRANCH[0]) begin
            if(rs2_arn[0] == 0) begin
                opb_valid[0]                = 1;
                id_packet_out[0].rs2_value  = 0;
            end
            else begin
                opb_valid[0]                = rs2_valid_tmp[0];
                id_packet_out[0].rs2_value  = opb_valid[0] ? rs2_value[0] : rs2_prn[0];
            end
        end
        else begin
            opb_valid[0]                    = 1;
            id_packet_out[0].rs2_value      = 0;
        end
    end

    always_comb begin
        if(id_packet_out[1].opb_select == OPB_IS_RS2 | id_packet_out[1].wr_mem | COND_BRANCH[1]) begin
            if(rs2_arn[1] == 0) begin
                opb_valid[1]                = 1;
                id_packet_out[1].rs2_value  = 0;
            end
            else begin
                opb_valid[1]                = (dest_arn_valid[0] && dest_arn[0] == rs2_arn[1]) ? 0 : rs2_valid_tmp[1];
                id_packet_out[1].rs2_value  = (dest_arn_valid[0] && dest_arn[0] == rs2_arn[1]) ? dest_PRF[0] : (opb_valid[1] ? rs2_value[1] : rs2_prn[1]);
            end
        end
        else begin
            opb_valid[1]                    = 1;
            id_packet_out[1].rs2_value      = 0;
        end
    end
endmodule
