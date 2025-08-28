// 1. 根據 instruction 的 rda_idx 與 rdb_idx, 也就是 source register 的 idx, 從
// freelist 當中找可以 renaming 的 physical register, 同時 RAT_RRAT 有支援 Forwarding
// 的功能
// 2. RAT_dest_idx 與 RAT_idx_valid 可以讓 RAT_RRAT 知道目前 dispatch 的 instruction 能不能被 renaming
// 同時提供 freelist 當中標示為 free 的 physical register
// 3. 從 CDB 來的 enable signal 可以讓 valid bit 更新，同時 valid list 也會知道
// 離開 freelist 的 physical register number, 並將其更新為 not valid
// 4. RRAT_ARF_idx 與 RRAT_PRF_idx 是用來決定 ROB retire 時，要寫回 RRAT 的 physical 
// register(Told) 以及其對應的 architectural register
// 5. 根據 dispatch instruction 的 renaming request, RAT_RRAT module 會 output
// 所需要的 rename_result 以及 rename_reuslt_valid
// 6. 根據 dispatch instruction 的 source register， RAT_RRAT 會 output source register
// 所對應的 idx 以及 valid bit
`include "sys_defs.svh"

module Map_Table(
    input                                       clock,
    input                                       reset,
    input                                       squash,
    input map_arch_packet [`N-1:0]              map_arch_in,
    input [`N-1:0]                              rename_valid,
    /*
    input [`N-1:0] [4:0]                        rs1_idx,            // rename query 1
    input [`N-1:0] [4:0]                        rs2_idx,            // rename query 2
    input [`N-1:0] [4:0]                        ARN_dest_idx,       // ARF # to be renamed
    input [`N-1:0]                              rename_valid,      // how many ARF # to rename?

    input [`N-1:0] [$clog2(`PRF)-1:0]           CDB_wr_reg_idx,     // From CDB, these are now valid
    input [`N-1:0]                              CDB_wr_en,

    input [`N-1:0] [4:0]                        ARF_reg_idx,       // ARF # to be renamed, from ROB
    input [`N-1:0]                              rob_retire, 
    input [`N-1:0] [$clog2(`PRF)-1:0]           PRN_idx_old,       // PRF # 
    */

    output logic [`N-1:0] [$clog2(`PRF)-1:0]    rename_result,      // New PRF # renamed to
    output logic [`N-1:0]                       rename_result_valid,

    output logic [`N-1:0] [$clog2(`PRF)-1:0]    rs1_idx_out,        // PRF # 
    output logic [`N-1:0] [$clog2(`PRF)-1:0]    rs2_idx_out,        // PRF #
    output logic [`N-1:0]                       rs1_valid,
    output logic [`N-1:0]                       rs2_valid
);

    // internal buses
    logic [`N-1:0] [$clog2(`PRF)-1:0]           PRN_old;            // rat bcasts
    logic [`N-1:0] [$clog2(`PRF)-1:0]           free_PRN;         
    logic [`N-1:0]                              free_PRN_valid;   
    logic [`N-1:0]                              is_renamed;

    assign rename_result        = free_PRN;
    assign rename_result_valid  = free_PRN_valid;
    assign is_renamed           = free_PRN_valid & rename_valid;

    renaming_packet [`N-1:0] renaming_in;
    
    genvar i;
    generate
        for(i = 0; i < `N; i = i + 1) begin
            assign renaming_in[i].rs1_idx    = map_arch_in[i].rs1_idx;
            assign renaming_in[i].rs2_idx    = map_arch_in[i].rs2_idx;
            assign renaming_in[i].dest_idx   = map_arch_in[i].ARN_dest_idx;
            assign renaming_in[i].ARF_idx    = map_arch_in[i].ARF_reg_idx;
            assign renaming_in[i].rob_retire = map_arch_in[i].rob_retire;
            assign renaming_in[i].PRF_idx    = map_arch_in[i].PRN_idx_old;
            assign renaming_in[i].free_idx   = free_PRN[i];
        end
    endgenerate

    Map_Table_internal map_table_internal(
        // inputs
        .clock(clock),
        .reset(reset),
        .squash(squash),
        .renaming_signal(renaming_in),
        .dest_idx_valid(rename_valid),
        .free_idx_valid(free_PRN_valid),

        // outputs
        .free_idx_old(PRN_old),   // to free/valid list
        .rs1_idx_out(rs1_idx_out),              // PRF num
        .rs2_idx_out(rs2_idx_out)               // PRF num
    );

    freelist_packet [`N-1:0]    freelist_packet_in;
    generate
        for(i = 0; i < `N; i = i + 1) begin
            assign freelist_packet_in[i].rob_retire_en      = map_arch_in[i].rob_retire;
            assign freelist_packet_in[i].rename_request     = rename_valid[i];
            assign freelist_packet_in[i].arch_idx_entering  = map_arch_in[i].PRN_idx_old;
            assign freelist_packet_in[i].arch_idx_leaving   = PRN_old[i];
        end
    endgenerate

    free_list freelist(
        // inputs
        .clock(clock),
        .reset(reset),
        .squash(squash),
        .freelist_packet_in(freelist_packet_in),

        // outputs
        .free_idx_out(free_PRN),
        .free_idx_out_valid(free_PRN_valid)  // if only partially valid, upper bit -> 1, lower bit -> 0
    );

    valid_packet [`N-1:0]   valid_packet_in;
    generate
        for(i = 0; i < `N; i = i + 1) begin
            assign valid_packet_in[i].rs1_index        = rs1_idx_out[i];
            assign valid_packet_in[i].rs2_index        = rs2_idx_out[i];
            assign valid_packet_in[i].dest_index       = free_PRN[i];
            assign valid_packet_in[i].rename_request   = is_renamed[i];
            assign valid_packet_in[i].CDB_reg_idx      = map_arch_in[i].CDB_wr_reg_idx;
            assign valid_packet_in[i].CDB_enable       = map_arch_in[i].CDB_wr_en;
            assign valid_packet_in[i].arch_reg_new     = map_arch_in[i].PRN_idx_old;
            assign valid_packet_in[i].rob_retire_en    = map_arch_in[i].rob_retire;
            assign valid_packet_in[i].arch_reg_old     = PRN_old[i];
        end
    endgenerate

    valid_bit validbit(
        // input
        .clock(clock),
        .reset(reset),
        .squash(squash),
        .valid_packet_in(valid_packet_in),
        
        // outputs
        .rs1_valid(rs1_valid),
        .rs2_valid(rs2_valid)

    );

endmodule


module Map_Table_internal(
    input                                    clock,
    input                                    reset,
    input                                    squash,
    input renaming_packet [`N-1:0]           renaming_signal,
    input [`N-1:0]                           dest_idx_valid,
    input [`N-1:0]                           free_idx_valid,   // from freelist

    output logic [`N-1:0] [$clog2(`PRF)-1:0] free_idx_old,       // to free/valid list, 從 RRAT 要 retire 掉的 old tag, 送到 freelist
    output logic [`N-1:0] [$clog2(`PRF)-1:0] rs1_idx_out,        // PRF # , source register 的 physical register number
    output logic [`N-1:0] [$clog2(`PRF)-1:0] rs2_idx_out         // PRF # , source register 的 physical register number

);
    logic [`N-1:0] [4:0]                        rs1_index;
    logic [`N-1:0] [4:0]                        rs2_index;
    logic [`N-1:0] [4:0]                        dest_index;
    logic [`N-1:0] [4:0]                        arch_index; 
    logic [`N-1:0] [$clog2(`PRF)-1:0]           phys_index;

    logic  [31:0] [$clog2(`PRF)-1:0]            map_reg;
    logic  [31:0] [$clog2(`PRF)-1:0]            map_reg_next;
    logic  [31:0] [$clog2(`PRF)-1:0]            arch_reg;
    logic  [31:0] [$clog2(`PRF)-1:0]            arch_reg_next;
    logic  [31:0] [$clog2(`PRF)-1:0]            reset_value;
    logic  [`N-1:0]                             is_renamed;
    logic  [`N-1:0]                             rob_retire;

    logic  [`N:0]   [31:0] [$clog2(`PRF)-1:0]   map_reg_update;
    logic  [`N-1:0] [31:0]                      map_reg_overwrite_one_hot;

    assign rs1_index[0] = renaming_signal[0].rs1_idx;
    assign rs1_index[1] = renaming_signal[1].rs1_idx;
    assign rs2_index[0] = renaming_signal[0].rs2_idx;
    assign rs2_index[1] = renaming_signal[1].rs2_idx;

    assign dest_index[0] = renaming_signal[0].dest_idx;
    assign dest_index[1] = renaming_signal[1].dest_idx;

    assign arch_index[0] = renaming_signal[0].ARF_idx;
    assign arch_index[1] = renaming_signal[1].ARF_idx;

    assign phys_index[0] = renaming_signal[0].PRF_idx;
    assign phys_index[1] = renaming_signal[1].PRF_idx;

    assign rob_retire[0] = renaming_signal[0].rob_retire;
    assign rob_retire[1] = renaming_signal[1].rob_retire;

    always_ff @ (posedge clock) begin
        if (reset) begin
            map_reg     <= reset_value;
            arch_reg    <= reset_value;
        end
        else if (squash) begin
            map_reg     <= arch_reg_next;
            arch_reg    <= arch_reg_next;
        end
        else begin
            map_reg     <= map_reg_next;
            arch_reg    <= arch_reg_next;
        end
    end 

    // 若 RAT 需要 renaming 且 freelist 當中有可以命名的 physical register
    // 則設 is_renamed 為 1
    assign is_renamed = dest_idx_valid & free_idx_valid;
   
    assign rs1_idx_out[0] = map_reg_update[0][rs1_index[0]];
    assign rs1_idx_out[1] = map_reg_update[1][rs1_index[1]];
    assign rs2_idx_out[0] = map_reg_update[0][rs2_index[0]];
    assign rs2_idx_out[1] = map_reg_update[1][rs2_index[1]];

    // reset values
    // reset 時 architectural register 依序對應到 physical register (0 ~ 31)
    always_comb begin
        for(int i = 0; i < 32; i = i + 1) begin
            reset_value[i] = i;
        end    
    end    


    always_comb begin
        case(is_renamed)
            2'b00: begin
                map_reg_overwrite_one_hot[0] = 32'h0;
                map_reg_overwrite_one_hot[1] = 32'h0;
            end

            2'b01: begin
                map_reg_overwrite_one_hot[0] = {32'h1 << dest_index[0]};
                map_reg_overwrite_one_hot[1] = 32'h0;                    
            end

            2'b10: begin
                map_reg_overwrite_one_hot[0] = 32'h0;
                map_reg_overwrite_one_hot[1] = {32'h1 << dest_index[1]};                

            end

            2'b11: begin
                map_reg_overwrite_one_hot[0] = {32'h1 << dest_index[0]};
                map_reg_overwrite_one_hot[1] = {32'h1 << dest_index[1]};

            end

            default: begin
                map_reg_overwrite_one_hot[0] = 32'h0;
                map_reg_overwrite_one_hot[1] = 32'h0;

            end

        endcase
    end

    always_comb begin
        map_reg_update[0] = map_reg;
        for(int i = 0; i < 32; i = i + 1) begin
            map_reg_update[1][i] = map_reg_overwrite_one_hot[0][i] ? renaming_signal[0].free_idx : map_reg_update[0][i];
        end
        for(int i = 0; i < 32; i = i + 1) begin
            map_reg_update[2][i] = map_reg_overwrite_one_hot[1][i] ? renaming_signal[1].free_idx : map_reg_update[1][i];
        end
    end

    assign map_reg_next = map_reg_update[`N];

    // Forwarding performed here !!
    // 重點在於，若是在更新 RRAT 時，如果有同樣的 architectural register 會被更新
    // 只有第一次更新是去 RRAT 拿舊的 physical register
    // 後續就不去 RRAT 裡面拿，而是直接拿 input 進 RRAT 的 physical register
    // 可以避免拿到舊的 physical register, 也實現所謂 RAT_RRAT Forwarding
    
    always_comb begin
        free_idx_old[0] = arch_reg[arch_index[0]];
        free_idx_old[1] = (rob_retire[0] && (arch_index[1] == arch_index[0])) ? phys_index[0] : arch_reg[arch_index[1]];
    end


    // arch_reg_next
    // 根據 ROB retire 的 architectural register 去更新 RRAT 所對應的 physical register
    always_comb begin
        arch_reg_next = arch_reg;
        for (int i = 0; i < 2; ++i) begin
            if (rob_retire[i]) begin
                arch_reg_next[arch_index[i]] = phys_index[i];
            end
        end
    end
    
endmodule

// freelist 重點是考慮 branch misprediction 時
// 可以把 freelist rollback 成 misprediction 前發生的狀態
// 基本上 freelist 的功能是，根據 instruction 的要求去提供 freelist 當中 valid 的 physical register 
// 可以提供的 physical register 可以分成一般狀態下以及 misprediction 狀態

module free_list(
    input                                       clock,
    input                                       reset,
    input                                       squash,
    /*
    input [`N-1:0]                              rename_request,         // RAT 所需要的 freelist 個數

    input [`N-1:0] [$clog2(`PRF)-1:0]           arch_idx_entering,      // From RRAT, these are entering RRAT
    input [`N-1:0]                              rob_retire_en,          // REQUIRES: en bits after mis-branch are low
    input [`N-1:0] [$clog2(`PRF)-1:0]           arch_idx_leaving,       // From RRAT, these are leaving RRAT
    */
    input freelist_packet [1:0]                 freelist_packet_in,

    output reg [1:0] [$clog2(`PRF)-1:0]         free_idx_out,			// 分配給 RAT 可用的 physical register index
    output reg [1:0]                            free_idx_out_valid      // 分配給 RAT 的 physical register 是否是 valid 的

);

logic [1:0]                         ROB_RETIRE;
logic [1:0] [$clog2(`PRF)-1:0]      ARCH_NEW;                          // From RRAT, these are entering RRAT      
logic [1:0] [$clog2(`PRF)-1:0]      ARCH_OLD;
logic [1:0]                         RENAME_REQ;
logic [1:0]                         valid_rename_request;

logic [1:0] [$clog2(`PRF)-1:0]      free_idx;
logic [1:0]                         free_idx_valid;
logic [`PRF-1:0]                    freelist_reset_value;             //所有大於或等於 32 的暫存器被標記為1(空閒可用）。

logic [`PRF-1:0]                    free_rename_reg;
logic [`PRF-1:0]                    free_rename_reg_next;
logic [`PRF-1:0]                    free_rename_reg_next_decreased;   //將被分配的暫存器標記為非空閒 0 (next)
logic [`PRF-1:0]                    free_rename_reg_next_increased;

logic [`PRF-1:0]                    free_arch_reg;
logic [`PRF-1:0]                    free_arch_next;	                 // combinational logic, 用以計算 next cycle freelist 中的 physical register, 為 one-hot signal
logic [`PRF-1:0]                    free_arch_next_decreased;
logic [`PRF-1:0]                    free_arch_next_increased;


logic [1:0] [$clog2(`PRF)-1:0]      rollback_idx;
logic [1:0]                         rollback_idx_valid;

generate
    for(genvar i = 0; i < 2; i = i + 1) begin
        assign ROB_RETIRE[i] = freelist_packet_in[i].rob_retire_en;
        assign ARCH_NEW[i]   = freelist_packet_in[i].arch_idx_entering;
        assign ARCH_OLD[i]   = freelist_packet_in[i].arch_idx_leaving;
        assign RENAME_REQ[i] = freelist_packet_in[i].rename_request;
    end
endgenerate



always_ff @ (posedge clock) begin
    if (reset) begin    
        free_rename_reg <= freelist_reset_value;
        free_arch_reg   <= freelist_reset_value;
    end
    else if (squash) begin  
        free_arch_reg   <= free_arch_next;
        free_rename_reg <= free_arch_next;
    end
    else begin  
        free_rename_reg <= free_rename_reg_next;		// 正常狀態下，可以提供給 RAT 使用的 freelist 中的 physical register
        free_arch_reg   <= free_arch_next;
    end
end


logic [(2 *`PRF)-1:0] rename_gnt_bus;

freelist_psel_gen_v2 free_rename_reg_selector(
    .req(free_rename_reg_next),
    .gnt_bus(rename_gnt_bus)
);

always_comb begin
    for(int i = 0; i < 2; i = i + 1) begin
        free_idx[i]                 = 0;
        free_idx_valid[i]           = 1'b0;
        for(int j = i * `PRF; j < (i + 1) * `PRF; j = j + 1) begin
            if(rename_gnt_bus[j]) begin
                free_idx[i]         = j;
                free_idx_valid[i]   = 1'b1;
            end
        end
    end
end

// free_arch_next; optimized
// 在 RRAT 也另外追蹤 freelist 的變化，當 branch misprediction 發生時，才能


always_comb begin
    free_arch_next_increased        = 0;
    free_arch_next_decreased        = {`PRF{1'b1}};
    free_rename_reg_next_increased  = 0;

    case(ROB_RETIRE)
        2'b00: begin
            free_arch_next_increased[ARCH_OLD[0]]       = 1'b0;
            free_arch_next_increased[ARCH_OLD[1]]       = 1'b0;
            free_arch_next_decreased[ARCH_NEW[0]]       = 1'b1;
            free_arch_next_decreased[ARCH_NEW[1]]       = 1'b1;
            free_rename_reg_next_increased[ARCH_OLD[0]] = 1'b0;
            free_rename_reg_next_increased[ARCH_OLD[1]] = 1'b0;

        end

        2'b01: begin
            free_arch_next_increased[ARCH_OLD[0]]       = 1'b1;
            free_arch_next_increased[ARCH_OLD[1]]       = 1'b0;
            free_arch_next_decreased[ARCH_NEW[0]]       = 1'b0;
            free_arch_next_decreased[ARCH_NEW[1]]       = 1'b1;
            free_rename_reg_next_increased[ARCH_OLD[0]] = 1'b1;
            free_rename_reg_next_increased[ARCH_OLD[1]] = 1'b0;

        end

        2'b10: begin
            free_arch_next_increased[ARCH_OLD[0]]       = 1'b0;
            free_arch_next_increased[ARCH_OLD[1]]       = 1'b1;
            free_arch_next_decreased[ARCH_NEW[0]]       = 1'b1;
            free_arch_next_decreased[ARCH_NEW[1]]       = 1'b0;
            free_rename_reg_next_increased[ARCH_OLD[0]] = 1'b0;
            free_rename_reg_next_increased[ARCH_OLD[1]] = 1'b1;

        end

        2'b11: begin
            free_arch_next_increased[ARCH_OLD[0]]       = 1'b1;
            free_arch_next_increased[ARCH_OLD[1]]       = 1'b1;
            free_arch_next_decreased[ARCH_NEW[0]]       = 1'b0;
            free_arch_next_decreased[ARCH_NEW[1]]       = 1'b0;
            free_rename_reg_next_increased[ARCH_OLD[0]] = 1'b1;
            free_rename_reg_next_increased[ARCH_OLD[1]] = 1'b1;

        end

        default: begin
            free_arch_next_increased[ARCH_OLD[0]]       = 1'b0;
            free_arch_next_increased[ARCH_OLD[1]]       = 1'b0;
            free_arch_next_decreased[ARCH_NEW[0]]       = 1'b1;
            free_arch_next_decreased[ARCH_NEW[1]]       = 1'b1;
            free_rename_reg_next_increased[ARCH_OLD[0]] = 1'b0;
            free_rename_reg_next_increased[ARCH_OLD[1]] = 1'b0;

        end


    endcase
end



assign free_arch_next = (free_arch_reg & free_arch_next_decreased) | free_arch_next_increased; //哪些暫存器被分配（從 freelist 中移除）and 哪些暫存器被釋放（加入 freelist）

logic [(2*`PRF)-1:0] rollback_gnt_bus;

freelist_psel_gen_v2 rollback_selector(
    .req(free_arch_next),
    .gnt_bus(rollback_gnt_bus)
);

always_comb begin
    for(int i = 0; i < 2; i = i + 1) begin
        rollback_idx[i]                 = 0;
        rollback_idx_valid[i]           = 1'b0;
        for(int j = i * `PRF; j < (i + 1) * `PRF; j = j + 1) begin
            if(rollback_gnt_bus[j]) begin
                rollback_idx[i]         = j;
                rollback_idx_valid[i]   = 1'b1;
            end
        end
    end
end

// freelist 的選擇邏輯
// 若是在沒有 squashion 的情況下，輸出的 physical register 來自 priority selector 所選中的 PRN
// 只要寫進 RRAT 的 physical register 就是還沒釋放到 freelist
genvar i;
generate;
    for (i = 0; i < 2; i = i + 1) begin
        always_ff @ (posedge clock) begin
            if (reset) begin
                free_idx_out[i]          <= 0;
                free_idx_out_valid[i]    <= 0;
            end
            else if (squash) begin
                free_idx_out[i]          <= rollback_idx[i];
                free_idx_out_valid[i]    <= rollback_idx_valid[i];
            end
            else begin
                free_idx_out[i]          <= free_idx[i];
                free_idx_out_valid[i]    <= free_idx_valid[i];
            end
        end
    end
endgenerate


assign free_rename_reg_next = (free_rename_reg & free_rename_reg_next_decreased) | free_rename_reg_next_increased;

assign valid_rename_request[0] = free_idx_out_valid[0] & freelist_packet_in[0].rename_request;
assign valid_rename_request[1] = free_idx_out_valid[1] & freelist_packet_in[1].rename_request;

// free_rename_reg_next
// 如果目前有 instruction 向 freelist 拿 physical register
// 則將拿走的 physical register 在 next cycle 中標為 non-valid
always_comb begin
    free_rename_reg_next_decreased = {`PRF{1'b1}};  // 初始化，默認所有位都是有效的

    case(valid_rename_request)
        2'b00: begin 
            free_rename_reg_next_decreased[free_idx_out[0]] = 1'b1;
            free_rename_reg_next_decreased[free_idx_out[1]] = 1'b1;
        end
        2'b01: begin
            free_rename_reg_next_decreased[free_idx_out[0]] = 1'b0; //第 1 個暫存器被分配, free_idx_out[x]）在下一個時鐘週期將被標記為 非空閒（0）
            free_rename_reg_next_decreased[free_idx_out[1]] = 1'b1;            
        end
        2'b10: begin
            free_rename_reg_next_decreased[free_idx_out[0]] = 1'b1;
            free_rename_reg_next_decreased[free_idx_out[1]] = 1'b0;
        end
        2'b11: begin
            free_rename_reg_next_decreased[free_idx_out[0]] = 1'b0;
            free_rename_reg_next_decreased[free_idx_out[1]] = 1'b0;
        end
        default: begin
            free_rename_reg_next_decreased[free_idx_out[0]] = 1'b1;
            free_rename_reg_next_decreased[free_idx_out[1]] = 1'b1;
        end
    endcase

end

// reset values
// 在 reset 時，freelist 會將 32 以上的 physical register 標為 free
always_comb begin
    for (int i = 0; i < `PRF; i = i + 1) begin
        freelist_reset_value[i] = (i >= 32) ? 1 : 0;
    end
end


endmodule


module freelist_psel_gen_v2 #(parameter REQS = 2, WIDTH = `PRF)         // 總請求數 & 每個請求的位寬
( 
    input wire [WIDTH-1:0]                        req,                     // 請求向量
    //output logic [REQS-1:0] [$clog2(`PRF)-1:0]  free_list_result,        // 選擇結果
    //output logic [REQS-1:0]                     free_list_result_valid   // 有效性標誌
    output wand [WIDTH*REQS-1:0]                  gnt_bus                  // 儲存所有的授權結果
);

    
    wire                   empty;                                         // 判斷是否所有請求為空


    wire  [WIDTH*REQS-1:0]  tmp_reqs;                                     // 中間請求向量
    wire  [WIDTH*REQS-1:0]  tmp_reqs_rev; 
    wire  [WIDTH*REQS-1:0]  tmp_gnts;                                     // 中間授權向量
    wire  [WIDTH*REQS-1:0]  tmp_gnts_rev;                                 // 翻轉後的授權向量


    assign empty = ~(|req);   //當請求信號為空時，empty 為高。
    
    genvar j, k;

    for (j = 0; j < REQS; j++) begin  // request_processing
        //初始請求和授權
        if (j == 0) begin
        assign tmp_reqs[WIDTH-1:0]  = req[WIDTH-1:0];
        assign gnt_bus[WIDTH-1:0]   = tmp_gnts[WIDTH-1:0];

        // 第一請求翻轉處理
        end else if (j == 1) begin
        for (k=0; k<WIDTH; k=k+1) begin  //reverse_first_request
            assign tmp_reqs[2*WIDTH-1-k] = req[k];
        end

        assign gnt_bus[2*WIDTH-1 -: WIDTH] = tmp_gnts_rev[2*WIDTH-1 -: WIDTH] & ~tmp_gnts[WIDTH-1:0];

        // 其他請求
        end else begin    // mask out gnt from req[j-2]
        assign tmp_reqs[(j+1)*WIDTH-1 -: WIDTH] = tmp_reqs[(j-1)*WIDTH-1 -: WIDTH] &
                                                    ~tmp_gnts[(j-1)*WIDTH-1 -: WIDTH];
        
        if (j % 2 == 0)
            assign gnt_bus[(j+1)*WIDTH-1 -: WIDTH] = tmp_gnts[(j+1)*WIDTH-1 -: WIDTH];
        else
            assign gnt_bus[(j+1)*WIDTH-1 -: WIDTH] = tmp_gnts_rev[(j+1)*WIDTH-1 -: WIDTH];

        end

        // 優先選擇器實例化
        wand_sel #(WIDTH) psel (.req(tmp_reqs[(j+1)*WIDTH-1 -: WIDTH]), .gnt(tmp_gnts[(j+1)*WIDTH-1 -: WIDTH]));

        // 翻轉授權
        for (k = 0; k < WIDTH; k++) begin
            assign tmp_gnts_rev[(j+1)*WIDTH-1-k] = tmp_gnts[(j)*WIDTH+k];
        end

        for (k = j + 1; k < REQS; k = k + 2) begin
            assign gnt_bus[(k+1)*WIDTH-1 -: WIDTH] = ~gnt_bus[(j+1)*WIDTH-1 -: WIDTH];
        end
    end

    // 計算最終授權結果
    for(k = 0; k < REQS; k++) begin
        assign gnt = gnt_bus[(k+1)*WIDTH-1 -: WIDTH];
    end

endmodule


module valid_bit(
    input                                    clock,
    input                                    reset,
    input                                    squash,
    input valid_packet [`N-1:0]              valid_packet_in,

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
        if (reset) begin   
            valid_rename_reg    <= reset_value;
            valid_arch_reg 	    <= reset_value;
        end
        else if (squash) begin    // rollback if branch mispredicted
            valid_rename_reg    <= valid_arch_next;
            valid_arch_reg      <= valid_arch_next;
        end
        // in the normal situation
        else begin
            valid_rename_reg    <= valid_rename_next;
            valid_arch_reg      <= valid_arch_next;
        end
    end


endmodule
