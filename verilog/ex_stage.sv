`include "sys_defs.svh"
`include "ISA.svh"

typedef enum logic[1:0] {INITIAL,  MULT_WAITING, CDB_HAZARD } alu_state;

module ex_mult(
    input                       clock,
    input                       reset,
    input                       valid_in,
    input                       CDB_hazard,

    input [31:0]                rs1,                // rs1_value
    input [31:0]                rs2,                // rs2_value
    ALU_FUNC                    func,               // 從 decoder 送來的 ALU_FUNC
    input                       start_mult,

    output logic                in_usage,       	// structural hazard for FU
    output logic                valid_out,      	// 當前的計算結果是有效的
    output logic [31:0]         mult_result         // ALU result
    );

    alu_state                   state, next_state;  // FSM state for Multiplier
    logic                       start;    


    logic                       mult_result_range, mult_result_range_reg;   	// 1 if [63:32]   
    logic [63:0]                product; 
    logic [1:0]                 sign;

    mult mult_0 (
        .clock(clock),
        .reset(reset),
        .start(start),
        .sign(sign),
        .mcand(rs1),
        .mplier(rs2),
        .product(product),  // multiplier 送出的結果
        .done(mult_done)    // 在 multiplier 送出結果的同時也會是 1
    );

    always_ff @(posedge clock) begin
        if(reset) begin
            state <= INITIAL; 
        end 
        
        else begin
            state <= next_state;
            if(start_mult)
                mult_result_range_reg <= mult_result_range;
        end	
    end

    assign in_usage = (state != INITIAL);

    assign mult_result = (mult_result_range_reg) ? product[63:32] : product[31:0];

    always_comb begin
        sign                = 0;
        mult_result_range   = 0;
        case(func)
            ALU_MUL: begin
                sign                = 2'b11;
                mult_result_range   = 0;          // 拿 lower 32 bits
            end
            ALU_MULH: begin
                sign                = 2'b11;
                mult_result_range   = 1;          // 拿 higher 32 bits
            end
            ALU_MULHSU: begin
                sign                = 2'b01;
                mult_result_range   = 1;          // 拿 higher 32 bits
            end
            ALU_MULHU: begin
                sign                = 2'b00;
                mult_result_range   = 1;          // 拿 higher 32 bits
            end
            default: begin
                sign                = 0;
                mult_result_range   = 0;
            end
        endcase
    end

    always_comb begin
        valid_out = 0;
        start = 0;
        case (state)
            INITIAL: begin
                if(~valid_in | CDB_hazard) begin            // 沒有東西進入, next_state 繼續留在 INITIAL
                    next_state = INITIAL;
                end
                else if(~start_mult) begin                  // 如果不是需要用 multiplier 的 instruction
                    valid_out = 1;                          // valid_out 直接設為 1
                    next_state = INITIAL;                   // next_state 繼續留在 INITIAL
                end	
                else begin 
                    start = 1;                              // valid_in == 1 && MULT -> start = 1 (開始乘法計算)
                    next_state = MULT_WAITING;              // next_state 進入到 multipler not done 階段
                end
            end
            MULT_WAITING: begin
                if(mult_done & ~CDB_hazard) begin           // 如果 multiplier 計算完成且 CDB 沒有 structural hazard
                    valid_out = 1;                          // valid_out = 1, next_state = INITIAL
                    next_state = INITIAL;
                end
                else if(mult_done & CDB_hazard) begin       // multiplier 計算完成但因為 CDB 有 structural hazard,
                    next_state = CDB_HAZARD;                // 所以 next_state 進入 CDB_HAZARD
                end                                         
                else begin                                  // 如果沒有接收到 multiplier 的 done signal, 代表 multiplier 還在進行計算
                    next_state = MULT_WAITING;              // next_state 繼續留在 MULT_WAITING
                end                                         
            end
            CDB_HAZARD: begin                   
                if(CDB_hazard) begin                        // 如果 CDB structural hazard 持續存在
                    next_state = CDB_HAZARD;                // 繼續留在此狀態
                end 
                else begin
                    valid_out = 1;                          // 如果 CDB structural hazard 已經消失
                    next_state = INITIAL;                   // next_state 回到 INITIAL, 代表可以接受新的 instruction
                end
            end
            default: next_state = INITIAL;                  // default next_state = INITIAL
        endcase
    end
endmodule

module alu(
    input                   clock,
    input                   reset,
    input                   valid_in,
    input                   CDB_hazard,

    input [31:0]            rs1,                // rs1_value
    input [31:0]            rs2,                // rs2_value
    ALU_FUNC                func,               // 從 decoder 送來的 ALU_FUNC

    output logic            in_usage,           // structural hazard for FU
    output logic            valid_out,          // 當前的計算結果是有效的
    output logic [31:0]     FU_result           // ALU result
    );
        
    logic                       MULT;
    logic [31:0]                mult_result; 
    logic [31:0]                alu_result;

    logic signed [31:0]         sign_rs1;
    logic signed [31:0]         sign_rs2;

    // 這是用來判斷 multiplier 現在是否被占用
    // 如果 multiplier 因為 CDB structural hazard 被 stall 住
    // 後面要進入 multiplier 的 instruction 也不能使用 multiplier
    // 只有在 state 為 INITIAL，也就是 multiplier 未被占用時，需要使用 multiplier 的 instruction 才能進入
    // assign in_usage = (state != INITIAL);
    assign sign_rs1  = rs1;
    assign sign_rs2  = rs2;

    // 判斷 instruction 是否需要進入 multiplier 處理, 原本在 decoder 處理
    assign MULT = (func == ALU_MUL)       |
                  (func == ALU_MULH)      |
                  (func == ALU_MULHSU)    |
                  (func == ALU_MULHU);

    assign FU_result = MULT ? mult_result: alu_result;

    ex_mult ex_mult0 (
        .clock(clock),
        .reset(reset),
        .valid_in(valid_in),
        .CDB_hazard(CDB_hazard),

        .rs1(rs1),                 // rs1_value
        .rs2(rs2),                 // rs2_value
        .func(func),               // 從 decoder 送來的 ALU_FUNC
        .start_mult(MULT),

        .in_usage(in_usage),       // structural hazard for FU
        .valid_out(valid_out),     // 當前的計算結果是有效的
        .mult_result(mult_result)  // ALU result
    );

    always_comb begin
        alu_result               = 0;

        case (func)
            ALU_ADD:  alu_result = rs1 + rs2;
            ALU_SUB:  alu_result = rs1 - rs2;
            ALU_AND:  alu_result = rs1 & rs2;
            ALU_SLT:  alu_result = sign_rs1 < sign_rs2;
            ALU_SLTU: alu_result = rs1 < rs2;
            ALU_OR:   alu_result = rs1 | rs2;
            ALU_XOR:  alu_result = rs1 ^ rs2;
            ALU_SRL:  alu_result = rs1 >> rs2[4:0];
            ALU_SLL:  alu_result = rs1 << rs2[4:0];
            ALU_SRA:  alu_result = sign_rs1 >>> rs2[4:0]; // arithmetic shift !!!
            default: alu_result = 32'hfacebeec;        // default value
        endcase
    end
endmodule

module brcond(
    // Inputs
    input [31:0]    rs1,    // Value to check against condition
    input [31:0]    rs2,
    input [2:0]     func,   // Specifies which condition to check

    // outputs
    output logic    cond    // 0/1 condition result (False/True)
    );

    logic signed [31:0] signed_rs1; 
    logic signed [31:0] signed_rs2;

    assign signed_rs1 = rs1;        // 考慮正負號
    assign signed_rs2 = rs2;        // 考慮正負號

    always_comb begin
        case (func)
            3'b000: cond = signed_rs1 == signed_rs2;  // BEQ
            3'b001: cond = signed_rs1 != signed_rs2;  // BNE
            3'b100: cond = signed_rs1 <  signed_rs2;  // BLT
            3'b101: cond = signed_rs1 >= signed_rs2;  // BGE
            3'b110: cond = rs1 < rs2;                 // BLTU
            3'b111: cond = rs1 >= rs2;                // BGEU
            default: cond = 0;
        endcase
    end
endmodule

module ex_stage(
    input                                clock,
    input                                reset,
    input                [1:0]           CDB_hazard,
    input  ID_EX_PACKET  [1:0]           id_ex_packet_in,
    output EX_MEM_PACKET [1:0]           ex_packet_out,
    output [1:0]                         FU_in_usage,       // status shows whether multipliers are occupied
    output [1:0]                         ex_branch_out    
    );

    logic [1:0] [31:0]                   opa_mux_out; 
    logic [1:0] [31:0]                   opb_mux_out;
    logic [1:0]                          brcond_result;
    logic [1:0]                          UN_BRANCH, BRANCH;

    generate
        for(genvar i = 0; i < 2; i++) begin
            assign BRANCH[i]     = id_ex_packet_in[i].cond_branch;
            assign UN_BRANCH[i]  = id_ex_packet_in[i].uncond_branch;
        end
    endgenerate

    generate
        for (genvar i = 0; i < 2; i++) begin
            assign ex_packet_out[i].NPC             = id_ex_packet_in[i].NPC;
            assign ex_packet_out[i].rs2_value       = id_ex_packet_in[i].rs2_value;
            assign ex_packet_out[i].rd_mem          = id_ex_packet_in[i].rd_mem;
            assign ex_packet_out[i].wr_mem          = id_ex_packet_in[i].wr_mem;
            assign ex_packet_out[i].dest_PRF_idx    = id_ex_packet_in[i].dest_PRF_idx;
            assign ex_packet_out[i].rob_idx         = id_ex_packet_in[i].rob_idx;
            assign ex_packet_out[i].halt            = id_ex_packet_in[i].halt;
            assign ex_packet_out[i].illegal         = id_ex_packet_in[i].illegal;
            assign ex_packet_out[i].csr_op          = id_ex_packet_in[i].csr_op;
            assign ex_packet_out[i].mem_size        = id_ex_packet_in[i].mem_size;
            assign ex_packet_out[i].reg_write       = id_ex_packet_in[i].reg_write;
            assign ex_branch_out[i]                 = (UN_BRANCH[i] | BRANCH[i]) & ~CDB_hazard;

            assign ex_packet_out[i].take_branch = UN_BRANCH[i] | (BRANCH[i] & brcond_result[i]);
        end
    endgenerate

    // ALU opA mux
    always_comb begin
        for( int i = 0; i < 2; i++) begin
            case (id_ex_packet_in[i].opa_select)
                OPA_IS_RS1:  opa_mux_out[i] = id_ex_packet_in[i].rs1_value;
                OPA_IS_NPC:  opa_mux_out[i] = id_ex_packet_in[i].NPC;
                OPA_IS_PC:   opa_mux_out[i] = id_ex_packet_in[i].PC;
                OPA_IS_ZERO: opa_mux_out[i] = 0;
                default:	 opa_mux_out[i] = 32'hdeadface;
            endcase
        end
    end

    // ALU opB mux
    always_comb begin
        for( int i = 0; i < 2; i++) begin
            case (id_ex_packet_in[i].opb_select)
                OPB_IS_RS2:   opb_mux_out[i] = id_ex_packet_in[i].rs2_value;
                OPB_IS_I_IMM: opb_mux_out[i] = `RV32_signext_Iimm(id_ex_packet_in[i].inst);
                OPB_IS_S_IMM: opb_mux_out[i] = `RV32_signext_Simm(id_ex_packet_in[i].inst);
                OPB_IS_B_IMM: opb_mux_out[i] = `RV32_signext_Bimm(id_ex_packet_in[i].inst);
                OPB_IS_U_IMM: opb_mux_out[i] = `RV32_signext_Uimm(id_ex_packet_in[i].inst);
                OPB_IS_J_IMM: opb_mux_out[i] = `RV32_signext_Jimm(id_ex_packet_in[i].inst);
                default:	  opb_mux_out[i] = 32'hfacefeed;
            endcase
        end
    end

    // the ALU
    generate
        genvar i;
        for (i = 0; i < 2; i++) begin
            alu alu_0(
                // Inputs
                .clock(clock),
                .reset(reset),
                .valid_in(id_ex_packet_in[i].valid),
                .CDB_hazard(CDB_hazard[i]),

                .rs1(opa_mux_out[i]),
                .rs2(opb_mux_out[i]),
                .func(id_ex_packet_in[i].alu_func),

                // outputs
                .in_usage(FU_in_usage[i]),             // 如果 multiplier 被 occupied
                .valid_out(ex_packet_out[i].valid),
                .FU_result(ex_packet_out[i].alu_result)
            );

            brcond brcond_0(
                // Inputs
                .rs1(id_ex_packet_in[i].rs1_value), 
                .rs2(id_ex_packet_in[i].rs2_value),
                .func(id_ex_packet_in[i].inst.b.funct3), // inst bits to determine check

                // Output
                .cond(brcond_result[i])
            );
        end
    endgenerate
endmodule 
