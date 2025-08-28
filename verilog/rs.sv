`include "sys_defs.svh"

module RS(
    input                                       clock,
    input                                       reset,
    input                                       load, 			   
    input [`N-1:0]                              ALU_in_usage,		// ALU function unit 是否被占用
    input RS_packet [`N-1:0]                    rs_packet_in,

    output ID_EX_PACKET [`N-1:0]                rs_packet_out,
    output logic [$clog2(`RS):0]                free_rs_space,		// 目前 RS 當中空閒的數量
    output logic [$clog2(`RS):0]                free_rs_space_next

);

    logic [`RS-1:0]                             load_waiting;
    logic [`RS-1:0]                             free_waiting;
    logic [`RS-1:0]                             ready_waiting;
    logic [`N-1:0] [$clog2(`PRF)-1:0]           RS1;
    logic [`N-1:0] [$clog2(`PRF)-1:0]           RS2;

    // Debug signals
    logic [$clog2(`N):0]                        rs_value_number;
    logic [$clog2(`N):0]                        rs_free_space_decrease;
    logic [$clog2(`N):0]                        rs_free_space_increase;
    logic [`RS-1:0]                             reset_space;
    logic [`RS-1:0]                             reset_space_tmp;

    // Input hubs
    logic [$clog2(`N):0]                        ALU_used;
    logic [`RS-1:0]                             rs1_valid_one_hot;		// one hot signal
    logic [`RS-1:0]                             rs2_valid_one_hot;		// one hot signal

    ID_EX_PACKET [`RS-1:0]                      id_rs_packet_in_slot;	// 準備進入 RS 的 instruction
    ID_EX_PACKET [`RS-1:0]                      rs_packet_out_tmp;		// 準備離開 RS 的 output

    // Output hubs
    logic [`N-1:0] [31:0]                       rs1_in_waiting;
    logic [`N-1:0] [31:0]                       rs2_in_waiting;

    logic [`N-1:0] [`N-1:0]                     rs1_forward_from_CDB;
    logic [`N-1:0] [`N-1:0]                     rs2_forward_from_CDB;

    logic [`N-1:0]                              rs1_valid_waiting;
    logic [`N-1:0]                              rs2_valid_waiting;

    // For input selector
    // 由於 load_waiting 和 reset_space_tmp 是 wor, 因此對其多個 drive 的值將被 or 起來
    logic [`RS*`N-1:0]                          rs_in_gnt_bus;
    logic [`RS*`N-1:0]                          rs_out_gnt_bus;
    logic                                       has_match;		// 用於指示是否找到匹配的 ALU

    logic [`N-1:0] [31:0]                       CDB_Data;
    logic [`N-1:0] [$clog2(`PRF)-1:0]           CDB_PRF_idx;
    logic [`N-1:0]                              CDB_valid;   		 // 始終從 LSB 開始，例如 1、11、111、1111

    logic [`N-1:0]                              rs1_valid_in; 		 // 決定是data還是PRN: 1: data 0: PRN
    logic [`N-1:0]                              rs2_valid_in;

    ID_EX_PACKET [`N-1:0]                       id_rs_packet_in;

    assign CDB_Data[0]        = rs_packet_in[0].CDB_Data;
    assign CDB_PRF_idx[0]     = rs_packet_in[0].CDB_PRF_idx;
    assign CDB_valid[0]       = rs_packet_in[0].CDB_valid;
    assign rs1_valid_in[0]    = rs_packet_in[0].rs1_valid_in;
    assign rs2_valid_in[0]    = rs_packet_in[0].rs2_valid_in;
    assign id_rs_packet_in[0] = rs_packet_in[0].id_rs_packet_in;
    assign RS1[0]             = id_rs_packet_in[0].rs1_value;
    assign RS2[0]             = id_rs_packet_in[0].rs2_value;

    assign CDB_Data[1]        = rs_packet_in[1].CDB_Data;
    assign CDB_PRF_idx[1]     = rs_packet_in[1].CDB_PRF_idx;
    assign CDB_valid[1]       = rs_packet_in[1].CDB_valid;
    assign rs1_valid_in[1]    = rs_packet_in[1].rs1_valid_in;
    assign rs2_valid_in[1]    = rs_packet_in[1].rs2_valid_in;
    assign id_rs_packet_in[1] = rs_packet_in[1].id_rs_packet_in;
    assign RS1[1]             = id_rs_packet_in[1].rs1_value;
    assign RS2[1]             = id_rs_packet_in[1].rs2_value;



// 追蹤 RS 的空間, 根據增減的情況來更新 RS 的空間數目
    assign free_rs_space_next = (free_rs_space - rs_free_space_decrease + rs_free_space_increase);
   // CDB broadcast
    generate
        // debug signal
        for (genvar i = 0; i < 2; i++) begin
            for (genvar j = 0; j < 2; j++) begin
                assign rs1_forward_from_CDB[i][j] = CDB_valid[j] && !rs1_valid_in[i] && (CDB_PRF_idx[j] == RS1[i]);
                assign rs2_forward_from_CDB[i][j] = CDB_valid[j] && !rs2_valid_in[i] && (CDB_PRF_idx[j] == RS2[i]);
            end
        end
    endgenerate

    assign load_waiting     = rs_in_gnt_bus[((`RS * 2) - 1) : `RS] | rs_in_gnt_bus[((`RS * 1) - 1) : 0];
    assign reset_space_tmp  = rs_out_gnt_bus[((`RS * 2) - 1) : `RS] | rs_out_gnt_bus[((`RS * 1) - 1) : 0];

    always_comb begin
        for(int i = 0; i < 2; i++) begin
            rs1_in_waiting[i]               = id_rs_packet_in[i].rs1_value;
            rs1_valid_waiting[i]            = rs1_valid_in[i];
            for(int j = 0; j < 2; j++) begin
                if (rs1_forward_from_CDB[i][j]) begin
                    rs1_in_waiting[i]       = CDB_Data[j];
                    rs1_valid_waiting[i]    = 1'b1;
                end            

            end
        end
    end

    always_comb begin
        for(int i = 0; i < 2; i++) begin
            rs2_in_waiting[i]               = id_rs_packet_in[i].rs2_value;
            rs2_valid_waiting[i]            = rs2_valid_in[i];
            for(int j = 0; j < 2; j++) begin
                if (rs2_forward_from_CDB[i][j]) begin
                    rs2_in_waiting[i]       = CDB_Data[j];
                    rs2_valid_waiting[i]    = 1'b1;
                end
            end
        end
    end

// load_in 是代表準備 dispatch instruction 進入 RS slot
// 把目前 RS 有空閒的 slot 送給 PS，其送出的 gnt 代表可以被 dispatch 的位置
// rs_in_gnt_bus 就是指準備要 dispatch 進入 RS slot 的 signal


    rs_psel_gen #(2,`RS) input_selector(
        .en(load), 
        .reset(1'b0), 
        .req(free_waiting | reset_space), 
        .gnt_bus(rs_in_gnt_bus)
        );

// 遍歷所有 RS slot, 若是該 RS slot 當中有 load_in, 則代表該 RS slot 即將被放進 instruction
// 針對找到的 RS slot, 先用 hub 暫存要放進去的資訊
// rs_free_space_decrease 可以確保一次最多載入 WAYS 個 instruction

    always_comb begin
        id_rs_packet_in_slot   = 0;
        rs_free_space_decrease = 0;

        for(int i = 0; i < `RS; i++) begin
            if(load_waiting[i] == 1 && (rs_free_space_decrease < 2)) begin
                if(rs_free_space_decrease == 0) begin
                    id_rs_packet_in_slot[i]             = id_rs_packet_in[0];
                    id_rs_packet_in_slot[i].rs1_value   = rs1_in_waiting[0];
                    id_rs_packet_in_slot[i].rs2_value   = rs2_in_waiting[0];
                    rs_free_space_decrease = (id_rs_packet_in[0].valid) ? (rs_free_space_decrease + 1) : 0;
                end
                else if(rs_free_space_decrease == 1) begin
                    id_rs_packet_in_slot[i]             = id_rs_packet_in[1];
                    id_rs_packet_in_slot[i].rs1_value   = rs1_in_waiting[1];
                    id_rs_packet_in_slot[i].rs2_value   = rs2_in_waiting[1];
                    rs_free_space_decrease = (id_rs_packet_in[1].valid) ? (rs_free_space_decrease + 1) : 0;
                end
            end
        end
    end

    always_comb begin
        rs1_valid_one_hot = 0;
        rs2_valid_one_hot = 0;
        rs_value_number   = 0;

        for(int i = 0; i < `RS; i++) begin
            if(load_waiting[i] && rs_value_number < 2) begin
                if(rs_value_number == 0) begin
                    rs1_valid_one_hot[i] = rs1_valid_waiting[0];
                    rs2_valid_one_hot[i] = rs2_valid_waiting[0];
                    rs_value_number = (id_rs_packet_in[0].valid) ? (rs_value_number + 1) : 0;
                end
                else if(rs_value_number == 1) begin
                    rs1_valid_one_hot[i] = rs1_valid_waiting[1];
                    rs2_valid_one_hot[i] = rs2_valid_waiting[1];
                    rs_value_number = (id_rs_packet_in[1].valid) ? (rs_value_number + 1) : 0;                
                end
            end
        end
    end


    always_ff @(posedge clock) begin
        if (reset) begin
            free_rs_space <= `RS;
        end 
        else begin
            free_rs_space <= free_rs_space_next;
        end
    end

    RS_entry rs_entries [`RS-1:0] (
        .clock(clock),
        .slot_clear(reset_space),

        .CDB_Data(CDB_Data),
        .CDB_PRF_idx(CDB_PRF_idx),
        .CDB_valid(CDB_valid),
        
        .rs1_valid_in(rs1_valid_one_hot),
        .rs2_valid_in(rs2_valid_one_hot),

        .rs_load_in(load_waiting),
        .id_rs_packet_in(id_rs_packet_in_slot),

        .rs_packet_out(rs_packet_out_tmp),
        .ready(ready_waiting),
        .rs_slot_free(free_waiting)
    );

    rs_psel_gen #(2,`RS) output_selector(
        .en(1'b1), 
        .reset(reset), 
        .req(ready_waiting), 
        .gnt_bus(rs_out_gnt_bus)
        );

    // RS issue 的邏輯
    always_comb begin
        if (reset) begin
            rs_free_space_increase  = '0;
            rs_packet_out           = '0;
            reset_space             = reset_space_tmp;
            ALU_used                = '0;                // 計算issue的數量
        end 
        else begin
            rs_free_space_increase  = '0;
            rs_packet_out           = '0;
            reset_space             = '0;
            ALU_used                = '0;                // 計算issue的數量

            for (int i = 0; i < `RS; i++) begin
                if (reset_space_tmp[i] && (ALU_used < 2)) begin
                    if ((0 >= ALU_used) && !ALU_in_usage[0]) begin
                        rs_packet_out[0]        = rs_packet_out_tmp[i];
                        rs_free_space_increase  = rs_free_space_increase + 1;
                        ALU_used                = 1;
                        reset_space[i]          = 1;
                    end 
                    else if ((1 >= ALU_used) && !ALU_in_usage[1]) begin
                        rs_packet_out[1]        = rs_packet_out_tmp[i];
                        rs_free_space_increase  = rs_free_space_increase + 1;
                        ALU_used                = 2;
                        reset_space[i]          = 1;
                    end
                end
            end
        end
    end

endmodule

module RS_entry(
    input                                       clock,
    input                                       slot_clear,

    input  [`N-1:0] [31:0]              	    CDB_Data,
    input  [`N-1:0] [$clog2(`PRF)-1:0]       	CDB_PRF_idx,
    input  [`N-1:0]                          	CDB_valid,

    input                                       rs1_valid_in, 	// 決定是data還是PRN: 1: data 0: PRN
    input                                       rs2_valid_in, 	// 如果en == 0, 則 operation a 和 b 的 valid 訊號會是0


    input                                       rs_load_in, 
    input  ID_EX_PACKET                         id_rs_packet_in,

    output ID_EX_PACKET                         rs_packet_out,
    output logic                                ready,			// 準備issue
    output logic                                rs_slot_free

);

    logic										VALID;
    logic [$clog2(`PRF)-1:0] 					RS1;
    logic [$clog2(`PRF)-1:0]					RS2;

    logic [`N-1:0]								rs1_forward_from_CDB;
    logic [`N-1:0]                       		rs2_forward_from_CDB;

    logic                                   	rs1_valid_reg;
    logic                                   	rs2_valid_reg;
    logic                                   	rs1_valid_tmp;
    logic                                   	rs2_valid_tmp;

    logic [31:0]                            	rs1_reg_tmp;
    logic [31:0]                            	rs2_reg_tmp;



    // 若是 opa 以及 opb 的 valid 已經準備好，代表此 rs slot 已經準備 issue
    assign ready = rs1_valid_reg && rs2_valid_reg;
    assign VALID = id_rs_packet_in.valid;
    assign RS1   = rs_packet_out.rs1_value;
    assign RS2   = rs_packet_out.rs2_value;

    // watching CDB for broadcasting!!!
    // 檢查是否此 RS slot 當中有跟 CDB 對應的 tag
    // 有對應的話, 就從 CDB 拿值

    assign rs1_forward_from_CDB[0] = CDB_valid[0] && ~rs1_valid_reg && (CDB_PRF_idx[0] == RS1);
    assign rs1_forward_from_CDB[1] = CDB_valid[1] && ~rs1_valid_reg && (CDB_PRF_idx[1] == RS1);
    assign rs2_forward_from_CDB[0] = CDB_valid[0] && ~rs2_valid_reg && (CDB_PRF_idx[0] == RS2);
    assign rs2_forward_from_CDB[1] = CDB_valid[1] && ~rs2_valid_reg && (CDB_PRF_idx[1] == RS2);

    // 給定 default value, 避免 latch
    // 若 RS slot 裡面有東西, 且 source register not ready, 持續追蹤 CDB 的信號, 等到 CDB 有和 slot 當中相符的資訊, 就更新為 valid

    always_comb begin
        if(rs1_forward_from_CDB[0] && !rs_slot_free) begin
            rs1_reg_tmp     = CDB_Data[0];
            rs1_valid_tmp   = 1'b1;
        end else if(rs1_forward_from_CDB[1] && !rs_slot_free) begin
            rs1_reg_tmp     = CDB_Data[1];
            rs1_valid_tmp   = 1'b1;
        end else begin
            rs1_reg_tmp     = rs_packet_out.rs1_value;
            rs1_valid_tmp   = rs1_valid_reg;			
        end
    end


    always_comb begin
        if(rs2_forward_from_CDB[0] && !rs_slot_free) begin
            rs2_reg_tmp     = CDB_Data[0];
            rs2_valid_tmp   = 1'b1;
        end else if(rs2_forward_from_CDB[1] && !rs_slot_free) begin
            rs2_reg_tmp     = CDB_Data[1];
            rs2_valid_tmp   = 1'b1;					
        end else begin
            rs2_reg_tmp     = rs_packet_out.rs2_value;
            rs2_valid_tmp   = rs2_valid_reg;
        end
    end

    always_ff @(posedge clock) begin
        // 正常 dispatch 進入 RS slot, 並向外 output rs_slot_free = 1, 代表 RS slot 被佔據
        if(rs_load_in && VALID) begin
            rs1_valid_reg       <= rs1_valid_in;
            rs2_valid_reg       <= rs2_valid_in;
        end
        // 若是在 dispatch 時發生 input instruction 為 invalid 時，則不 dispatch 進入 RS slot
        else if (slot_clear || (!VALID && rs_load_in)) begin
            rs1_valid_reg       <= 0;
            rs2_valid_reg       <= 0;
        end else begin
            rs1_valid_reg       <= rs1_valid_tmp;
            rs2_valid_reg       <= rs2_valid_tmp;
        end
    end

    always_ff @(posedge clock) begin
        if(rs_load_in && VALID) begin
            rs_slot_free       	<= 0;
        end else if(slot_clear || (!VALID && rs_load_in)) begin
            rs_slot_free       	<= 1;
        end else begin
			rs_slot_free		<= rs_slot_free;
		end
	end


    always_ff @(posedge clock) begin
        // dispatch 時, 將 instruction 拿進來
        if (rs_load_in && VALID) begin
            rs_packet_out 		<= id_rs_packet_in;
        end 

        // 如果 dispatch 時 instruction 並沒有 valid, 則不拿 instruction
        else if (slot_clear || (!VALID && rs_load_in)) begin
            rs_packet_out 		<= 0;
        end 
        
        // 如果 opa 與 opb 有從 cdb 當中拿到東西，則更新
        else begin
            rs_packet_out.rs1_value <= rs1_reg_tmp;
            rs_packet_out.rs2_value <= rs2_reg_tmp;
        end
    end

    endmodule
