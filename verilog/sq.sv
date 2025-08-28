`include "sys_defs.svh"

module store_queue(
    input                                           clock,
    input                                           reset,
    input                                           squash,
    input                                           store_retire,

    input sq_input_packet [1:0]                     sq_input,

    // To debug
    output reg [$clog2(`LSQSZ)-1:0]                 sq_head,
    output reg [$clog2(`LSQSZ)-1:0]                 sq_tail,

    output logic                                    sq_head_output_valid,
    output logic [31:0]                             sq_head_output_data,    
    output logic [15:0]                             sq_head_output_address,
    output logic [1:0]                              sq_head_output_size,
    
    output sq_entry [`LSQSZ-1:0]                    sq_out,

    output logic [$clog2(`LSQSZ):0]                 num_free
);
    // dispatch的訊號
    logic [1:0] [1:0]                               store_size;
    logic [1:0] [31:0]                              store_data;
    logic [1:0]                                     store_data_valid;
    logic [1:0] [$clog2(`ROB)-1:0]                  store_ROB_idx;
    logic [1:0]                                     store_enable;

    // CDB的訊號
    logic [1:0] [31:0]                              CDB_Data;
    logic [1:0] [$clog2(`PRF)-1:0]                  CDB_PRF_idx;
    logic [1:0]                                     CDB_valid;

    // ALU的訊號
    logic [1:0] [$clog2(`ROB)-1:0]                  ALU_ROB_idx;
    logic [1:0]                                     ALU_is_valid;
    logic [1:0] [15:0]                              ALU_data;


    generate
        for(genvar i = 0; i < 2; i++) begin
            assign store_size[i]       = sq_input[i].store_size;
            assign store_data[i]       = sq_input[i].store_data;
            assign store_data_valid[i] = sq_input[i].store_data_valid;
            assign store_ROB_idx[i]    = sq_input[i].store_ROB_idx;
            assign store_enable[i]     = sq_input[i].store_enable;

            assign CDB_Data[i]         = sq_input[i].CDB_Data;
            assign CDB_PRF_idx[i]      = sq_input[i].CDB_PRF_idx;
            assign CDB_valid[i]        = sq_input[i].CDB_valid;

            assign ALU_ROB_idx[i]      = sq_input[i].ALU_ROB_idx;
            assign ALU_is_valid[i]     = sq_input[i].ALU_is_valid;
            assign ALU_data[i]         = sq_input[i].ALU_data;        
        end
    endgenerate


    logic [`LSQSZ-1:0] [1:0]                        sq_size_output;
    logic [`LSQSZ-1:0] [31:0]                       sq_data_output;
    logic [`LSQSZ-1:0]                              sq_data_valid_output;
    logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0]           sq_ROB_idx_output;

    logic [`LSQSZ-1:0] [15:0]                       sq_address_output;
    logic [`LSQSZ-1:0]                              sq_address_valid_output;

    logic [`LSQSZ-1:0]                              sq_valid_output;
    logic [$clog2(`LSQSZ):0]                        sq_free_number;

    genvar gi, gj;


    generate;
        for (genvar i = 0; i < `LSQSZ; i++) begin
            assign sq_out[i].addr       = sq_address_output[i];
            assign sq_out[i].addr_valid = sq_address_valid_output[i];
            assign sq_out[i].data       = sq_data_output[i];
            assign sq_out[i].data_valid = sq_data_valid_output[i];
            assign sq_out[i].size       = sq_size_output[i];
            assign sq_out[i].valid      = sq_valid_output[i];
            assign sq_out[i].ROB_idx    = sq_ROB_idx_output[i];
        end
    endgenerate

    // head and tail in store queue
    logic [`LSQSZ-1:0] sq_head_update;
    logic [`LSQSZ-1:0] sq_tail_update;
    logic [`LSQSZ-1:0] sq_head_update_next;
    logic [`LSQSZ-1:0] sq_head_shift;
    assign sq_head_shift = {sq_head_update[`LSQSZ-2:0], sq_head_update[`LSQSZ-1]};

    logic [`LSQSZ-1:0] sq_tail_update_next;
    logic [2:0] [`LSQSZ-1:0] sq_tail_sequentially_update;

    logic [$clog2(`LSQSZ)-1:0] sq_head_next;
    logic [$clog2(`LSQSZ)-1:0] sq_tail_next;

    wor [$clog2(`LSQSZ)-1:0] location_head;
    wor [$clog2(`LSQSZ)-1:0] location_tail;

    // 如果store指令在ROB被retire, 移動head(一次retire一個store)
    // 利用shifter 來控制head 的移動
    // 例如： retire時 0001-> 0010
    assign sq_head_update_next = store_retire ? sq_head_shift : sq_head_update;  
    
    assign sq_tail_sequentially_update[0]   = sq_tail_update;
    assign sq_tail_sequentially_update[1]   = (store_enable[0] == 1) ? {sq_tail_sequentially_update[0][`LSQSZ-2:0], sq_tail_sequentially_update[0][`LSQSZ-1]} : sq_tail_sequentially_update[0];
    assign sq_tail_sequentially_update[2]   = (store_enable[1] == 1) ? {sq_tail_sequentially_update[1][`LSQSZ-2:0], sq_tail_sequentially_update[1][`LSQSZ-1]} : sq_tail_sequentially_update[1];
    assign sq_tail_update_next              = sq_tail_sequentially_update[2];

    
    wor   [$clog2(`LSQSZ)-1:0]    sq_head_pos;
    logic [`LSQSZ-1:0]            sq_head_valid;

    wor   [$clog2(`LSQSZ)-1:0]    sq_tail_pos;
    logic [`LSQSZ-1:0]            sq_tail_valid;


    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign sq_head_pos      = (sq_head_update_next[i] == 1) ? i    : 0;
            assign sq_head_valid[i] = (sq_head_update_next[i] == 1) ? 1'b1 : 0;
        end
    endgenerate


    assign sq_head_next = (sq_head_valid[sq_head_pos] == 1) ? sq_head_pos : 0;


    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign sq_tail_pos      = (sq_tail_update_next[i] == 1) ? i    : 0;
            assign sq_tail_valid[i] = (sq_tail_update_next[i] == 1) ? 1'b1 : 0;
        end
    endgenerate

    assign sq_tail_next = (sq_tail_valid[sq_tail_pos] == 1) ? sq_tail_pos : 0;
    

    always_ff @(posedge clock) begin
        if (reset | squash) begin
            sq_head <= 0;
            sq_tail <= 0;
        end
        else begin
            sq_head <= sq_head_next;
            sq_tail <= sq_tail_next;
        end
    end


    always_ff @(posedge clock) begin
        if (reset | squash) begin
            sq_head_update <= `LSQSZ'b1;
            sq_tail_update <= `LSQSZ'b1;
        end
        else begin
            sq_head_update <= sq_head_update_next;
            sq_tail_update <= sq_tail_update_next;
        end        
    end

    // 檢查CBD/ALU有沒有hit
    logic [1:0] [`LSQSZ-1:0] CDB_data_hit;
    logic [1:0] [`LSQSZ-1:0] ALU_address_hit;


    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign CDB_data_hit[0][i] = CDB_valid[0] && sq_valid_output[i] && (CDB_PRF_idx[0] == sq_data_output[i]) && (!sq_data_valid_output[i]);
            assign CDB_data_hit[1][i] = CDB_valid[1] && sq_valid_output[i] && (CDB_PRF_idx[1] == sq_data_output[i]) && (!sq_data_valid_output[i]);
        end
    endgenerate


    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign ALU_address_hit[0][i] = ALU_is_valid[0] && sq_valid_output[i] && (ALU_ROB_idx[0] == sq_ROB_idx_output[i]) && (!sq_address_valid_output[i]);
            assign ALU_address_hit[1][i] = ALU_is_valid[1] && sq_valid_output[i] && (ALU_ROB_idx[1] == sq_ROB_idx_output[i]) && (!sq_address_valid_output[i]);
        end
    endgenerate


    logic [`LSQSZ-1:0]          head_clear;
    logic [1:0] [`LSQSZ-1:0]    tail_clear;

    logic [`LSQSZ-1:0]          sq_current_entries;
    logic [`LSQSZ-1:0]          sq_CDB_ready_entires;
    logic [`LSQSZ-1:0]          sq_ALU_ready_entries;


    always_comb begin
        if(store_retire)
            head_clear = ~sq_head_update;
        else
            head_clear = ~(`LSQSZ'b0);
    end


    assign tail_clear[0] = ~(store_enable[0] ? sq_tail_sequentially_update[0] : `LSQSZ'b0);
    assign tail_clear[1] = ~(store_enable[1] ? sq_tail_sequentially_update[1] : `LSQSZ'b0);

    assign sq_current_entries   = head_clear & tail_clear[0] & tail_clear[1];
    assign sq_CDB_ready_entires = sq_current_entries & ~CDB_data_hit[0] & ~CDB_data_hit[1];
    assign sq_ALU_ready_entries = sq_current_entries & ~ALU_address_hit[0] & ~ALU_address_hit[1];
    

    logic [1:0] [31:0]                              sq_data_update;
    logic [1:0]                                     sq_data_valid_update;

    logic [1:0] [1:0]                               sq_size_update;
    logic [1:0] [$clog2(`ROB)-1:0]                  sq_ROB_idx_update;
    logic [1:0] [1:0]                               CDB_dispatch_hit; // 當dispatch的時候，檢查CBD是不是ready

    assign CDB_dispatch_hit[0][0] = store_enable[0] && CDB_valid[0] && (store_data_valid[0] == 0) && (store_data[0] == CDB_PRF_idx[0]);
    assign CDB_dispatch_hit[0][1] = store_enable[0] && CDB_valid[1] && (store_data_valid[0] == 0) && (store_data[0] == CDB_PRF_idx[1]);
    assign CDB_dispatch_hit[1][0] = store_enable[1] && CDB_valid[0] && (store_data_valid[1] == 0) && (store_data[1] == CDB_PRF_idx[0]);
    assign CDB_dispatch_hit[1][1] = store_enable[1] && CDB_valid[1] && (store_data_valid[1] == 0) && (store_data[1] == CDB_PRF_idx[1]);


    assign sq_size_update[0] = store_enable[0] ? store_size[0] : 0;
    assign sq_size_update[1] = store_enable[1] ? store_size[1] : 0;
    
    assign sq_ROB_idx_update[0] = store_enable[0] ? store_ROB_idx[0] : 0;
    assign sq_ROB_idx_update[1] = store_enable[1] ? store_ROB_idx[1] : 0;


    always_comb begin
        sq_data_update[0] = 0;
        if(CDB_dispatch_hit[0][0]) begin
            sq_data_update[0] = CDB_Data[0];
        end
        else if(CDB_dispatch_hit[0][1]) begin
            sq_data_update[0] = CDB_Data[1];
        end
        else if(store_enable[0] && (CDB_dispatch_hit[0] == 0)) begin
            sq_data_update[0] = store_data[0];
        end
    end

    always_comb begin
        sq_data_update[1] = 0;
        if(CDB_dispatch_hit[1][0]) begin
            sq_data_update[1] = CDB_Data[0];
        end
        else if(CDB_dispatch_hit[1][1]) begin
            sq_data_update[1] = CDB_Data[1];
        end
        else if(store_enable[1] && (CDB_dispatch_hit[1] == 0)) begin
            sq_data_update[1] = store_data[1];
        end
    end

    always_comb begin
        sq_data_valid_update[0] = 0;
        if(CDB_dispatch_hit[0][0]) begin
            sq_data_valid_update[0] = 1'b1;
        end
        else if(CDB_dispatch_hit[0][1]) begin
            sq_data_valid_update[0] = 1'b1;
        end
        else if(store_enable[0] && (CDB_dispatch_hit[0] == 0)) begin
            sq_data_valid_update[0] = store_data_valid[0];
        end
    end

    always_comb begin
        sq_data_valid_update[1] = 0;
        if(CDB_dispatch_hit[1][0]) begin
            sq_data_valid_update[1] = 1'b1;
        end
        else if(CDB_dispatch_hit[1][1]) begin
            sq_data_valid_update[1] = 1'b1;
        end
        else if(store_enable[1] && (CDB_dispatch_hit[1] == 0)) begin
            sq_data_valid_update[1] = store_data_valid[1];
        end
    end

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

    // store queue size update
    logic [`LSQSZ-1:0] [1:0] size_next;
    logic [`LSQSZ-1:0] [1:0] size_next_current;
    logic [`LSQSZ-1:0] [1:0] size_next_tail_one;
    logic [`LSQSZ-1:0] [1:0] size_next_tail_two;


    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign size_next_current[i]     = sq_current_entries[i] ? sq_size_output[i] : 0;
            assign size_next_tail_one[i]    = sq_tail_sequentially_update[0][i] ? sq_size_update[0] : 0;
            assign size_next_tail_two[i]    = sq_tail_sequentially_update[1][i] ? sq_size_update[1] : 0;
        end
    endgenerate

    assign size_next = size_next_current | size_next_tail_one | size_next_tail_two;


    logic [`LSQSZ-1:0]  valid_next;
    logic [`LSQSZ-1:0]  valid_next_current;
    logic [`LSQSZ-1:0]  valid_next_tail_one;
    logic [`LSQSZ-1:0]  valid_next_tail_two;

    // store qeue valid bit update
    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign valid_next_current[i]    = sq_current_entries[i] ? sq_valid_output[i] : 0;
            assign valid_next_tail_one[i]   = sq_tail_sequentially_update[0][i] ? store_enable[0] : 0;
            assign valid_next_tail_two[i]   = sq_tail_sequentially_update[1][i] ? store_enable[1] : 0;
        end
    endgenerate

    assign valid_next = valid_next_current | valid_next_tail_one | valid_next_tail_two;

    logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0] ROB_idx_next;
    logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0] ROB_idx_next_current;
    logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0] ROB_idx_next_tail_one;
    logic [`LSQSZ-1:0] [$clog2(`ROB)-1:0] ROB_idx_next_tail_two;

    // store queue rob index update
    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign ROB_idx_next_current[i]  = sq_current_entries[i] ? sq_ROB_idx_output[i] : 0;
            assign ROB_idx_next_tail_one[i] = sq_tail_sequentially_update[0][i] ? sq_ROB_idx_update[0] : 0;
            assign ROB_idx_next_tail_two[i] = sq_tail_sequentially_update[1][i] ? sq_ROB_idx_update[1] : 0;
        end
    endgenerate

    assign ROB_idx_next = ROB_idx_next_current | ROB_idx_next_tail_one | ROB_idx_next_tail_two;

    always_ff @(posedge clock) begin
        if (reset | squash) begin
            sq_size_output    <= 0;
            sq_ROB_idx_output <= 0;
            sq_valid_output   <= 0;
        end
        else begin
            sq_size_output    <= size_next;
            sq_ROB_idx_output <= ROB_idx_next;
            sq_valid_output   <= valid_next;
        end
    end

    logic [`LSQSZ-1:0] [15:0]                         address_next;
    logic [`LSQSZ-1:0] [15:0]                         address_next_current;
    logic [`LSQSZ-1:0] [15:0]                         address_next_hit_one;
    logic [`LSQSZ-1:0] [15:0]                         address_next_hit_two;

    logic [`LSQSZ-1:0]                                address_valid_next;
    logic [`LSQSZ-1:0]                                address_valid_next_current;
    logic [`LSQSZ-1:0]                                address_valid_next_one;
    logic [`LSQSZ-1:0]                                address_valid_next_two;


    // store queue update from ALU
    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign address_next_current[i] = sq_ALU_ready_entries[i] ? sq_address_output[i] : 0;
            assign address_next_hit_one[i] = ALU_address_hit[0][i] ? ALU_data[0] : 0;
            assign address_next_hit_two[i] = ALU_address_hit[1][i] ? ALU_data[1]: 0;
        end
    endgenerate

    assign address_next = address_next_current | address_next_hit_one | address_next_hit_two;

    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign address_valid_next_current[i] = sq_ALU_ready_entries[i] ? sq_address_valid_output[i] : 0;
            assign address_valid_next_one[i] = ALU_address_hit[0][i] ? 1 : 0;
            assign address_valid_next_two[i] = ALU_address_hit[1][i] ? 1 : 0;
        end
    endgenerate

    assign address_valid_next = address_valid_next_current | address_valid_next_one | address_valid_next_two;

    always_ff @(posedge clock) begin
        if (reset | squash) begin
            sq_address_output       <= 0;
            sq_address_valid_output <= 0;
        end
        else begin
            sq_address_output       <= address_next;
            sq_address_valid_output <= address_valid_next;
        end
    end

    wor [`LSQSZ-1:0] [31:0]                         data_next;
    wor [`LSQSZ-1:0]                                data_valid_next;
    
    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign data_next[i] = sq_CDB_ready_entires[i] ? sq_data_output[i] : 0;
            assign data_next[i] = sq_tail_sequentially_update[0][i] ? sq_data_update[0] : 0;
            assign data_next[i] = sq_tail_sequentially_update[1][i] ? sq_data_update[1] : 0;
            assign data_next[i] = CDB_data_hit[0][i] ? CDB_Data[0] : 0;
            assign data_next[i] = CDB_data_hit[1][i] ? CDB_Data[1] : 0;
        end
    endgenerate

    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign data_valid_next[i] = sq_CDB_ready_entires[i] ? sq_data_valid_output[i] : 0;
            assign data_valid_next[i] = sq_tail_sequentially_update[0][i] ? sq_data_valid_update[0] : 0;
            assign data_valid_next[i] = sq_tail_sequentially_update[1][i] ? sq_data_valid_update[1] : 0;
            assign data_valid_next[i] = CDB_data_hit[0][i] ? 1 : 0;
            assign data_valid_next[i] = CDB_data_hit[1][i] ? 1 : 0;
        end
    endgenerate

    always_ff @(posedge clock) begin
        if (reset | squash) begin
            sq_data_output        <= 0;
            sq_data_valid_output  <= 0;
        end
        else begin
            sq_data_output        <= data_next;
            sq_data_valid_output  <= data_valid_next;
        end
    end


    logic [$clog2(`ROB)-1:0]                    sq_head_output_ROB_idx;
    logic                                       sq_head_output_data_valid;
    logic                                       sq_head_output_address_valid;

    logic [1:0]                                 sq_head_output_size_next;
    logic [$clog2(`ROB)-1:0]                    sq_head_output_ROB_idx_next;
    logic                                       sq_head_output_valid_next;

    logic [31:0]                                sq_head_output_data_next;
    logic                                       sq_head_outout_data_valid_next;

    logic [15:0]                                sq_head_output_address_next;
    logic                                       sq_head_output_address_valid_next;



    wor   [$clog2(`LSQSZ)-1:0]                  head_update_location;

    logic [`LSQSZ-1:0] [$clog2(`LSQSZ)-1:0]     head_update_valid;


    generate
        for(genvar i = 0; i < `LSQSZ; i++) begin
            assign head_update_location         = (sq_head_update_next[i]) ? i : 0;
            assign head_update_valid[i]         = (sq_head_update_next[i]) ? 1 : 0;
        end
    endgenerate


    always_comb begin
        sq_head_output_size_next            = (head_update_valid[head_update_location] == 1) ? size_next[head_update_location] : 0;
        sq_head_output_data_next            = (head_update_valid[head_update_location] == 1) ? data_next[head_update_location] : 0;
        sq_head_outout_data_valid_next      = (head_update_valid[head_update_location] == 1) ? data_valid_next[head_update_location] : 0;
        sq_head_output_address_next         = (head_update_valid[head_update_location] == 1) ? address_next[head_update_location] : 0;
        sq_head_output_address_valid_next   = (head_update_valid[head_update_location] == 1) ? address_valid_next[head_update_location] : 0;
        sq_head_output_ROB_idx_next         = (head_update_valid[head_update_location] == 1) ? ROB_idx_next[head_update_location] : 0;
        sq_head_output_valid_next           = (head_update_valid[head_update_location] == 1) ? valid_next[head_update_location] : 0;
    end


    always_ff @(posedge clock) begin
        if (reset | squash) begin
            sq_head_output_data             <= 0;
            sq_head_output_data_valid       <= 0;
            sq_head_output_address          <= 0;
            sq_head_output_address_valid    <= 0;
            sq_head_output_ROB_idx          <= 0;
            sq_head_output_valid            <= 0;
            sq_head_output_size             <= 0;
        end else begin
            sq_head_output_data             <= sq_head_output_data_next;
            sq_head_output_data_valid       <= sq_head_outout_data_valid_next;
            sq_head_output_address          <= sq_head_output_address_next;
            sq_head_output_address_valid    <= sq_head_output_address_valid_next;
            sq_head_output_ROB_idx          <= sq_head_output_ROB_idx_next;
            sq_head_output_valid            <= sq_head_output_valid_next;
            sq_head_output_size             <= sq_head_output_size_next;
        end
    end


    // number of free
    logic [$clog2(2):0] sq_dispatched_number;
    logic [$clog2(`LSQSZ):0] sq_free_number_next;

    assign sq_free_number_next      = (sq_free_number - sq_dispatched_number) + store_retire;
    assign num_free                 = sq_free_number_next;

    
    always_comb begin
        case(store_enable)
            2'b00: begin
                sq_dispatched_number = 0;
            end

            2'b01: begin
                sq_dispatched_number = 1;
            end

            2'b10: begin
                sq_dispatched_number = 1;
            end

            2'b11: begin
                sq_dispatched_number = 2;
            end

            default: begin
                sq_dispatched_number = 0;
            end
        endcase
    end

    always_ff @(posedge clock) begin
        if (reset | squash) begin
            sq_free_number <= `LSQSZ;
        end
        else begin
            sq_free_number <= sq_free_number_next;
        end
    end
endmodule