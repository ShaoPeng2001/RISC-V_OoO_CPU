// optimized non-blocking icache with prefetch enabled
`include "sys_defs.svh"

module icache(
    input                           clock,
    input                           reset,

    // from instruction memory to icache
    input MEM_TAG                   Imem2proc_transaction_tag,
    input MEM_TAG                   Imem2proc_data_tag,
    
    
    input Icache_packet [`N-1:0]    icache_packet_in,
    // from icache to instruction memory
    output MEM_COMMAND              proc2Imem_command, 
    output ADDR                     proc2Imem_addr,

    // from icache to processor
    output logic [`N-1:0][63:0]     Icache_data_out,       // value is memory[proc2Icache_addr]
    output logic [`N-1:0]           Icache_valid_out,      // when this is high

    // from icache to icache_mem
    output logic [`N-1:0] [4:0]     rd_idx,
    output logic  [4:0]             current_index,
    output logic                    data_write_enable
);

logic [15:0]                    fetch_addr;
logic [2:0]                     miss_outstanding;

logic [2:0]                     prefetch_num;
logic [2:0]                     prefetch_num_next;
logic [15:0]                    prefetch_addr;
logic [15:0]                    prefetch_addr_next;

logic [15:0] [12:0]             tag_list;
logic [15:0] [12:0]             tag_list_next;  
logic [15:0]                    tag_valid;
logic [15:0]                    tag_valid_next;

logic [31:0] [7:0]              waiting_tags;
logic [31:0] [7:0]              waiting_tags_next;
logic [31:0]                    waiting_valid;
logic [31:0]                    waiting_valid_next;
logic [`N-1:0]                  hit_waiting;

logic [`N-1:0] [31:0]           proc2Icache_addr;
logic [`N-1:0]                  proc2Icache_en;

logic [`N-1:0] [7:0]            rd_tag;
logic  [7:0]                    current_tag;

logic [`N-1:0] [63:0]           cachemem_data;  // read an insn if it's not in the $, put it in.
logic [`N-1:0]                  cachemem_valid; // for prefectching

logic [31:0] [7:0]              cache_mem_tags;
logic [31:0]                    cache_mem_valid;
logic [1:0]                     cache_read_valid;

assign proc2Imem_command        = (miss_outstanding || prefetch_num) ? (~reset ? MEM_LOAD : MEM_NONE) : MEM_NONE;
assign proc2Imem_addr           = (miss_outstanding & ~hit_waiting) ? fetch_addr : prefetch_addr;
assign prefetch_addr_next       = (Imem2proc_transaction_tag != 0) ? (proc2Imem_addr + 8) : proc2Imem_addr;

assign Icache_data_out          = cachemem_data;
assign Icache_valid_out         = cachemem_valid;

assign current_index            = tag_list[Imem2proc_data_tag][4:0];
assign current_tag              = tag_list[Imem2proc_data_tag][12:5];

assign data_write_enable        = tag_valid[Imem2proc_data_tag];
assign miss_outstanding         = proc2Icache_en & ~cachemem_valid;


assign proc2Icache_addr[0] = icache_packet_in[0].proc2Icache_addr;
assign proc2Icache_addr[1] = icache_packet_in[1].proc2Icache_addr;

assign proc2Icache_en[0]   = icache_packet_in[0].proc2Icache_en;
assign proc2Icache_en[1]   = icache_packet_in[1].proc2Icache_en;

assign cachemem_data[0]    = icache_packet_in[0].cachemem_data;
assign cachemem_data[1]    = icache_packet_in[1].cachemem_data;



assign cachemem_valid[0] = cache_read_valid[0];
assign cachemem_valid[1] = cache_read_valid[1];



// fetch icache addr
// only when no hit waiting, then we fetch insn, or keep prefetch
always_comb begin
    if(miss_outstanding[0] && !hit_waiting[0]) begin
        fetch_addr = {proc2Icache_addr[0][15:3], 3'b0};
    end
    else if(miss_outstanding[1] && !hit_waiting[1]) begin
        fetch_addr = {proc2Icache_addr[1][15:3], 3'b0};
    end
    else begin 
        fetch_addr = 0;
    end
end


// prefetch setting
always_comb begin
    if(miss_outstanding)
        prefetch_num_next = 1;
    else
        prefetch_num_next = 0;
end

always_ff @(posedge clock) begin
    if(reset) begin
        prefetch_addr   <= 0;
        prefetch_num    <= 0;
    end

    else begin
        prefetch_addr   <= prefetch_addr_next;
        prefetch_num    <= prefetch_num_next;
    end

end

assign rd_idx[0] = proc2Icache_addr[0][7:3];
assign rd_idx[1] = proc2Icache_addr[1][7:3];
assign rd_tag[0] = proc2Icache_addr[0][15:8];
assign rd_tag[1] = proc2Icache_addr[1][15:8];


assign hit_waiting[0] = waiting_valid[rd_idx[0]] && (waiting_tags[rd_idx[0]] == rd_tag[0]);
assign hit_waiting[1] = waiting_valid[rd_idx[1]] && (waiting_tags[rd_idx[1]] == rd_tag[1]);


always_ff @(posedge clock) begin
    if(reset) begin
        tag_list        <= 0;
        tag_valid       <= 0;
    end

    else begin
        tag_list        <= tag_list_next;
        tag_valid       <= tag_valid_next;
    end

end

logic valid_data_tag;
logic valid_transaction;

assign valid_data_tag = (Imem2proc_data_tag != 0) ? 1 : 0;
assign valid_transaction = (Imem2proc_transaction_tag && (proc2Imem_command != MEM_NONE)) ? 1 : 0;

always_comb begin
        tag_list_next = tag_list;
        tag_valid_next = tag_valid;
    case({valid_data_tag, valid_transaction})
        2'b01: begin
            tag_list_next[Imem2proc_transaction_tag]    = proc2Imem_addr[15:3];     // store current address with its transaction tag
            tag_valid_next[Imem2proc_transaction_tag]   = 1'b1;                     // mark current transaction tag as valid
        end

        2'b10: begin
            tag_list_next[Imem2proc_data_tag]           = 0;                        // if tag back again, clear correspond tag position
            tag_valid_next[Imem2proc_data_tag]          = 0;

        end

        2'b11: begin
            tag_list_next[Imem2proc_data_tag]           = 0;                        // if tag back again, clear correspond tag position
            tag_valid_next[Imem2proc_data_tag]          = 0;
            tag_list_next[Imem2proc_transaction_tag]    = proc2Imem_addr[15:3];     // store current address with its transaction tag
            tag_valid_next[Imem2proc_transaction_tag]   = 1'b1;                     // mark current transaction tag as valid   
        end

        default: begin
            tag_list_next = tag_list;
            tag_valid_next = tag_valid;
        end
    endcase
end

always_ff @(posedge clock) begin
    if(reset) begin
        waiting_tags    <= 0;
        waiting_valid   <= 0;
    end

    else begin
        waiting_tags    <= waiting_tags_next;
        waiting_valid   <= waiting_valid_next;
    end
end

always_comb begin
    waiting_tags_next                               = waiting_tags;
    waiting_valid_next                              = waiting_valid;

    case(valid_transaction)

        1'b0: begin
            waiting_tags_next[current_index]        = 0;
            waiting_tags_next[current_index]        = 0;
        end

        1'b1: begin
            waiting_tags_next[current_index]        = 0;
            waiting_tags_next[current_index]        = 0;
            waiting_tags_next[proc2Imem_addr[7:3]]  = proc2Imem_addr[15:8];
            waiting_valid_next[proc2Imem_addr[7:3]] = 1'b1;

        end

        default: begin
            waiting_tags_next[current_index]        = 0;
            waiting_tags_next[current_index]        = 0;
        end

    endcase
end


assign cache_read_valid[0] = cache_mem_valid[rd_idx[0]] & (cache_mem_tags[rd_idx[0]] == rd_tag[0]);
assign cache_read_valid[1] = cache_mem_valid[rd_idx[1]] & (cache_mem_tags[rd_idx[1]] == rd_tag[1]);

always_ff @(posedge clock) begin
    if (reset) begin
        cache_mem_tags                  <= '0;
    end 
    else if (data_write_enable) begin
        cache_mem_tags[current_index]   <= current_tag;
    end
end


always_ff @(posedge clock) begin
    if(reset)
        cache_mem_valid                 <= 31'd0;
    else if(data_write_enable)
        cache_mem_valid[current_index]  <= 1'b1;
end



endmodule

