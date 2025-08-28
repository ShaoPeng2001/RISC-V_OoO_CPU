`include "sys_defs.svh"
`include "ISA.svh"

module decoder(

    input IF_ID_PACKET          if_packet,

    output logic                sign,
    output logic [1:0]          memory_size,
    output ALU_OPA_SELECT       opa_select,
    output ALU_OPB_SELECT       opb_select,
    output logic                has_dest,
    output ALU_FUNC             alu_func,
    output logic                rd_mem,
    output logic                wr_mem,
    output logic                cond_branch, 
    output logic                uncond_branch, 
    output logic                uncond_jal, 
    output logic                uncond_jalr,
    output logic                csr_op,
    output logic                halt,
    output logic                illegal,
    output logic                valid_inst
);

    logic valid;

    assign valid        = if_packet.valid;  // 原本 decoder valid input
    assign valid_inst   = valid & ~illegal; // output valid instruction signal

    always_comb begin
        opa_select      = OPA_IS_RS1;
        opb_select      = OPB_IS_RS2;
        alu_func        = ALU_ADD;
        has_dest        = `FALSE;
        csr_op          = `FALSE;
        rd_mem          = `FALSE;
        wr_mem          = `FALSE;
        cond_branch     = `FALSE;
        uncond_branch   = `FALSE;
        uncond_jal      = `FALSE;
        uncond_jalr     = `FALSE;
        halt            = `FALSE;
        illegal         = `FALSE;

        if(valid) begin                          // 如果進來 decoder 的 instruction 為 valid 才需要 decode
            casez (if_packet.inst) 
                `RV32_LUI: begin
                    has_dest   = `TRUE;
                    opa_select = OPA_IS_ZERO;
                    opb_select = OPB_IS_U_IMM;
                end
                `RV32_AUIPC: begin
                    has_dest   = `TRUE;
                    opa_select = OPA_IS_PC;
                    opb_select = OPB_IS_U_IMM;
                end
                `RV32_JAL: begin
                    has_dest      = `TRUE;
                    opa_select    = OPA_IS_PC;
                    opb_select    = OPB_IS_J_IMM;
                    uncond_branch = `TRUE;
                    uncond_jal = `TRUE;
                end
                `RV32_JALR: begin
                    has_dest      = `TRUE;
                    opa_select    = OPA_IS_RS1;
                    opb_select    = OPB_IS_I_IMM;
                    uncond_branch = `TRUE;
                    uncond_jalr = `TRUE;
                end
                `RV32_BEQ, `RV32_BNE, `RV32_BLT, `RV32_BGE,
                `RV32_BLTU, `RV32_BGEU: begin
                    opa_select  = OPA_IS_PC;
                    opb_select  = OPB_IS_B_IMM;
                    cond_branch = `TRUE;
                end
                `RV32_LB, `RV32_LH, `RV32_LW,
                `RV32_LBU, `RV32_LHU: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    rd_mem     = `TRUE;
                end
                `RV32_SB, `RV32_SH, `RV32_SW: begin
                    opb_select = OPB_IS_S_IMM;
                    wr_mem     = `TRUE;
                end
                `RV32_ADDI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                end
                `RV32_SLTI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLT;
                end
                `RV32_SLTIU: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLTU;
                end
                `RV32_ANDI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_AND;
                end
                `RV32_ORI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_OR;
                end
                `RV32_XORI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_XOR;
                end
                `RV32_SLLI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SLL;
                end
                `RV32_SRLI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SRL;
                end
                `RV32_SRAI: begin
                    has_dest   = `TRUE;
                    opb_select = OPB_IS_I_IMM;
                    alu_func   = ALU_SRA;
                end
                `RV32_ADD: begin
                    has_dest   = `TRUE;
                end
                `RV32_SUB: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SUB;
                end
                `RV32_SLT: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLT;
                end
                `RV32_SLTU: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLTU;
                end
                `RV32_AND: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_AND;
                end
                `RV32_OR: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_OR;
                end
                `RV32_XOR: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_XOR;
                end
                `RV32_SLL: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SLL;
                end
                `RV32_SRL: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SRL;
                end
                `RV32_SRA: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_SRA;
                end
                `RV32_MUL: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_MUL;
                end
                `RV32_MULH: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_MULH;
                end
                `RV32_MULHSU: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_MULHSU;
                end
                `RV32_MULHU: begin
                    has_dest   = `TRUE;
                    alu_func   = ALU_MULHU;
                end
                `RV32_CSRRW, `RV32_CSRRS, `RV32_CSRRC: begin
                    csr_op = `TRUE;
                end
                `WFI: begin
                    halt = `TRUE;
                end
                default:  begin
                    illegal = `TRUE;
                end
            endcase 
        end
    end 

    // decoder logic for load-store queue, 注意此處 logic 有正負號區別
    always_comb begin
        memory_size     = DOUBLE;
        sign            = 0;

        casez (if_packet.inst) 
            `RV32_LB: begin
                memory_size = BYTE;
                sign        = 1;
            end
            `RV32_SB, `RV32_LBU: begin
                memory_size = BYTE;
            end
            `RV32_LH: begin
                memory_size = HALF;
                sign        = 1;
            end
            `RV32_LHU, `RV32_SH: begin
                memory_size = HALF;
            end
            `RV32_LW, `RV32_SW: begin
                memory_size = WORD;
            end
            default: begin
                sign        = 0;
                memory_size = DOUBLE;
            end
        endcase
    end

endmodule 
